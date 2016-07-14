package Marchex::Client::GitHub;

use warnings;
use strict;

use Data::Dumper; $Data::Dumper::Sortkeys=1;
use HTTP::Request;
use JSON::XS qw(decode_json encode_json);
use LWP;
use URI::Escape 'uri_escape';
use Carp;
use File::Temp 'tempfile';
use WWW::Mechanize;

use base 'Class::Accessor';
__PACKAGE__->mk_ro_accessors(qw(mech));

sub new {
    my($class, @opts) = @_;
    my %opts = @opts;
    $opts{verbose} ||= 0;

    my $self = bless \%opts, $class;

    $self->_init_mech if $self->{mech};

    $self->{ua}       = LWP::UserAgent->new;
    $self->{token}  //= $ENV{GITHUB_TOKEN};

    $self->{host} = $ENV{GITHUB_HOST};
    if ($self->{host} eq 'github.com') {
        $self->{uri}  = 'https://api.github.com';
        $self->{base} = $self->{uri};
    }
    else {
        $self->{uri}    //= "https://" . $self->{host};
        $self->{base}   //= $self->{uri} . '/api/v3';
    }

    return $self;
}


# $data can be a query-string for GET, and JSON for other HTTP methods
sub command {
    my($self, $method, $api, $data, $options) = @_;

    delete $self->{links};
    $api =~ s/^\///;

    my $url = "$self->{base}/$api";

    if (!$options->{link} && $method eq 'GET' && $data) {
        my $query = ref $data ? (
            join '&', map { sprintf '%s=%s', $_, $data->{$_} } sort keys %$data
        ) : $data;
        $url .= '?' . $query if $query && length($query);
    }

    # allow passing in a "link" option to override the URL
    my $req = HTTP::Request->new($method => ($options->{link} || $url));

    if (!$options->{link} && $method ne 'GET' && $data) {
        my $content = ref $data ? encode_json($data) : $data;
        if ($content && length($content)) {
            $req->content_type('application/json');
            $req->content($content);
        }
    }

    $req->header(Authorization => 'token ' . uri_escape($self->{token}));
    $req->header(Accept => $options->{accept_type} || 'application/vnd.github.v3+json');

    if ($self->{verbose}) {
        my $req_str = $self->_prep_str($req->as_string, '> ');
        $req_str =~ s/^(> Authorization: token) .+$/$1 PRIVATE/m;
        print STDERR $req_str, "--\n";
    }

    my $res = $self->{ua}->request($req);
    if ($self->{verbose}) {
        my $res_str = $self->_prep_str($res->as_string, '< ');
        print STDERR $res_str, "--\n";
    }

    unless ($res->is_success) {
        die sprintf "%s:\n%s\n",
            $res->status_line,
            $self->pretty($res->content);
    }

    my $content = eval { decode_json($res->content) } // $res->content;
    if ($res->header('Link') && $content && ref($content)) {
        my %links = reverse split /\s*[,;]\s*/, $res->header('Link');
        if ($links{'rel="next"'}) {
            (my $link = $links{'rel="next"'}) =~ s/^<(.+?)>$/$1/;
            $self->{links}{next} = $link;
            if (!$options->{no_follow}) {
                my $next = $self->command($method, $api, $data, { %$options, link => $link });
                my $ref = ref $content;
                if ($ref eq 'ARRAY') {
                    push @$content, @$next;
                }
                elsif ($ref eq 'HASH' && $content->{items} && $next->{items}) {
                    push @{$content->{items}}, @{$next->{items}};
                }
            }
        }
    }

    return $content;
}

sub _prompt_for_credentials {
    my($self, $type, $prefix, $key) = @_;

    $self->{user} //= $ENV{USER} // '';
    $self->{pass} //= '';

    my $username = prompt_for("Username for [$self->{user}]");
    $self->{user} = $username if $username;

    $self->{pass} = prompt_for("Password", 1);
}

sub prompt_for {
    my($prompt, $is_pass) = @_;
    local $\;
    local $| = 1;

    # Disable displaying password when it's typed
    qx(stty -echo) if $is_pass;
    print "$prompt: ";

    chomp(my $input = <STDIN>);
    if ($is_pass) {
        qx(stty echo);
        print "\n";
    }

    return $input;
}

sub _prep_str {
    my($self, $str, $prefix) = @_;
    $str =~ s/\n\n.+?$//m if $self->{verbose} == 1;  # strip off content for low verbosity
    1 while chomp($str);
    $str =~ s/^/$prefix/mg if $prefix;
    $str . "\n";
}

sub pretty {
    my($self, $content) = @_;
    my $content_str = ref $content ? $content : eval { decode_json($content) } // $content;
    return eval { JSON::XS->new->pretty(1)->encode( $content_str ) } // $content_str;
}

1;
