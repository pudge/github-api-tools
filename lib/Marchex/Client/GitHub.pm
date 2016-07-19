package Marchex::Client::GitHub;

use warnings;
use strict;

our $VERSION = v0.1.0;

use HTTP::Request;
use JSON::XS qw(decode_json encode_json);
use LWP;
use URI::Escape 'uri_escape';

use Pod::Usage;
use Getopt::Long;

sub new {
    my($class, @opts) = @_;
    my %opts = @opts;
    $opts{verbose} ||= 0;

    my $self = bless \%opts, $class;

    $self->{ua}       = LWP::UserAgent->new;
    $self->{token}  //= $ENV{GITHUB_TOKEN};
    $self->{host}   //= $ENV{GITHUB_HOST};
    $self->{user}   //= $ENV{USER};

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

    # can optionally pass in a full URI instead of just the API method
    my $url = $api =~ /^https?:\/\// ? $api :"$self->{base}/$api";

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
            $req->content_type($options->{content_type} || 'application/json');
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

    # if there's a next "Link" then automatically follow it ...
    if ($res->header('Link') && $content && ref($content)) {
        my %links = reverse split /\s*[,;]\s*/, $res->header('Link');
        if ($links{'rel="next"'}) {
            (my $link = $links{'rel="next"'}) =~ s/^<(.+?)>$/$1/;
            $self->{links}{next} = $link;
            # ... unless no_follow is set
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

# for initializing a new tool
sub init {
    my($class, %in_opts) = @_;
    my %opts;

    # fix up external options to point to reference in %opts
    for my $o (keys %in_opts) {
        $in_opts{$o} = \$opts{$in_opts{$o}}
    }

    Getopt::Long::Configure('bundling');
    GetOptions(
        'h|help'                => sub { pod2usage(-verbose => 2) },
        't|token=s'             => \$opts{token},
        'H|host=s'              => \$opts{host},
        'V|version'             => \$opts{version},
        'v|verbose+'            => \$opts{verbose},
        %in_opts
    ) or pod2usage(-verbose => 1);

    if ($opts{version}) {
        printf "Marchex-GitHub version v%vd\n", $Marchex::Client::GitHub::VERSION;
        exit;
    }

    $opts{host} //= $ENV{GITHUB_HOST};
    pod2usage(-verbose => 1, -message => "no GitHub host provided\n")
        unless $opts{host};

    $opts{token} //= $ENV{GITHUB_TOKEN};
    pod2usage(-verbose => 1, -message => "no personal token provided\n")
        unless $opts{token};

    $opts{api} = Marchex::Client::GitHub->new(
        host    => $opts{host},
        token   => $opts{token},
        verbose => $opts{verbose}
    );

    return(\%opts);

}

1;
