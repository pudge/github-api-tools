package Marchex::Client::GitHub;

=pod

=head1 NAME

Marchex::Client::GitHub - Perl framework for using GitHub API

=head1 SYNOPSIS

    use Marchex::Client::GitHub;
    my $gh = Marchex::Client::GitHub->new(
        host    => 'github.com',
        token   => $my_token,
        verbose => 1  # 0=none, 1=HTTP request/response, 2=include response content
    );

    my $user = $gh->command(GET => 'user');
    print $user->{login};

    my $search = $gh->command(GET => 'search/code', {
        q => 'org:github github'
    });

    my $search_lang = $gh->command(GET => 'search/code', {
        q => 'org:github language:perl'
    }, {
        page_limit      => 10, # get no more than 10 pages of results
        content_type    => 'application/json', # default
        accept_type     => 'application/vnd.github.v3+json' # default
    });


=head1 DESCRIPTION

You must use the correct version of the documentation for your GitHub version, which is currently:

    # GitHub.com
    https://developer.github.com/v3/

    # GitHub Enterprise
    https://developer.github.com/enterprise/2.6/v3/

Follow the specific instructions in the GitHub API for each method you want to call.  The API can also be a full URL, instead of the API name, for example:

    my $user = $gh->command(GET => "https://api.github.com/$user");

The return value will be the JSON object, converted to a Perl data structure.

Pagination is automatically followed, and can be controlled with C<page_limit> and C<no_follow> options on the call to C<command>.  When pagination is followed, if the result object is an array, all of the results are put into the array; if it is a hash, then the results are put into C<$obj->{items}>.


=head1 REQUIREMENTS

=over 4

=item * Create personal access token on GitHub with necessary scopes for given endpoints (L<https://github.example.com/settings/tokens>).

You can save the token in the environment variable C<$GITHUB_TOKEN>, or pass it in the command line with C<-t>.

=back


=head1 COPYRIGHT AND LICENSE

Copyright 2016, Marchex.

This library is free software; you may redistribute it and/or modify it under the same terms as Perl itself.

=cut


use warnings;
use strict;

our $VERSION = v0.1.0;

use HTTP::Request;
use JSON::XS qw(decode_json encode_json);
use LWP;
use MIME::Base64 'encode_base64';
use URI::Escape 'uri_escape';

use Pod::Usage;
use Getopt::Long;

sub new {
    my($class, %opts) = @_;
    $opts{verbose} ||= 0;

    my $self = bless \%opts, $class;

    $self->{token}      //= $ENV{GITHUB_TOKEN};
    $self->{host}       //= $ENV{GITHUB_HOST};
    $self->{username}   //= $ENV{USER};
    $self->{ua}           = $self->_ua();

    die 'Must have host and credentials set; please see documentation'
        unless $self->{host} && ($self->{token} || ($self->{password} && $self->{username}));

    # currently only HTTPS supported
    if ($self->{host} eq 'github.com') {
        $self->{uri}  = 'https://api.github.com';
        $self->{base} = $self->{uri};
    }
    else {
        $self->{uri}    //= "https://" . $self->{host};
        $self->{base}   //= $self->{uri} . '/api/v3';
    }

    eval {
        require Marchex::Client::Tiny;
        $self->{tiny} = Marchex::Client::Tiny->new;
    };
    undef $@;

    return $self;
}

sub _ua {
    my($self) = @_;
    my $ua = LWP::UserAgent->new;
    push @{ $ua->requests_redirectable }, 'PUT';

    if ($self->{token}) {
        $self->{auth} = 'token ' . uri_escape($self->{token});
    }
    else {
        $self->prompt_for_credentials;
        $self->{auth} = 'Basic ' . encode_base64($self->{username} . ':' . $self->{password});
    }

    return $ua;
}

# $data can be a query-string for GET, and JSON for other HTTP methods
sub command {
    my($self, $method, $api, $data, $options) = @_;

    my $url = $self->_url($method, $api, $data, $options);
    my $req = $self->_req($method, $url, $data, $options);
    my $res = $self->_res($req);
    my $content = $self->_content($res, $method, $api, $data, $options);

    return $content;
}

sub _url {
    my($self, $method, $api, $data, $options) = @_;

    # leading / is optional
    $api =~ s|^/||;

    # can optionally pass in a full URI instead of just the API method
    my $url = $api =~ /^https?:\/\// ? $api : "$self->{base}/$api";

    # if link, it contains the info needed, we don't re-add the data
    # if not GET, data will be added to request instead of URL
    if (!$options->{link} && $method eq 'GET' && $data) {
        die 'data in GET request cannot contain complex data structures'
            if ref $data && grep { ref } values %$data;
        my $query = ref $data ? (
            join '&', map { sprintf '%s=%s', $_, $data->{$_} } sort keys %$data
        ) : $data;
        $url .= '?' . $query if $query && length($query);
    }

    return $url;
}

sub _req {
    my($self, $method, $url, $data, $options) = @_;
    my $req = HTTP::Request->new($method => ($options->{link} || $url));

    # if link, it contains the info needed, we don't re-add the data
    # if GET, data was added to URL instead of the request
    if (!$options->{link} && $method ne 'GET') {
        $data //= '{}';
        my $content = ref $data ? encode_json($data) : $data;
        if ($content && length($content)) {
            $req->content_type($options->{content_type} || 'application/json');
            $req->content($content);
        }
    }

    $req->header(Authorization => $self->{auth});
    $req->header(Accept => $options->{accept_type} || 'application/vnd.github.v3+json');

    $self->_debug_input($req);

    return $req;
}

sub _res {
    my($self, $req) = @_;
    my $res = $self->{ua}->request($req);
    $self->_debug_output($res);

    unless ($res->is_success) {
        die sprintf "%s:\n%s\n",
            $res->status_line,
            $self->pretty($res->content);
    }

    return $res;
}

sub _follow_links {
    my($self, $res, $content, $method, $api, $data, $options) = @_;

    # in case copied in from previous call
    # if there are links, we always want to set it in the API object
    # even if no_follow is set, so callers could follow it manually
    # if they wanted to
    delete $self->{links};

    # if there's a next "Link" then automatically follow it ...
    if ($res->header('Link') && $content && ref($content)) {
        my %links = reverse split /\s*[,;]\s*/, $res->header('Link');
        if ($links{'rel="next"'}) {
            (my $link = $links{'rel="next"'}) =~ s/^<(.+?)>$/$1/;
            $self->{links}{next} = $link;
            my $no_follow = $options->{no_follow};

            if (!$no_follow && $options->{page_limit}) {
                my($page) = $link =~ /\bpage=(\d+)/;
                if ($page && $page > $options->{page_limit}) {
                    $no_follow = 1;
                }
            }

            # ... unless no_follow is set
            if (!$no_follow) {
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
}

sub _content {
    my($self, $res, $method, $api, $data, $options) = @_;

    my $content = eval { decode_json($res->content) } // $res->content;
    $self->_follow_links($res, $content, $method, $api, $data, $options);

    return $content;
}

sub _debug_input {
    my($self, $req) = @_;
    if ($self->{verbose}) {
        my $req_str = $self->_prep_str($req->as_string, '> ');
        $req_str =~ s/^(> Authorization: \w+) .+$/$1 PRIVATE/m;
        print STDERR $req_str, "--\n";
    }
}

sub _debug_output {
    my($self, $res) = @_;
    if ($self->{verbose}) {
        my $res_str = $self->_prep_str($res->as_string, '< ');
        print STDERR $res_str, "--\n";
    }
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
        'username=s'            => \$opts{username},
        'password'              => \$opts{password},
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
    unless ($opts{token} || defined $opts{password} || defined $opts{create_token}) {
        if (open my $fh, '<', "$ENV{HOME}/.github-api-tools-token") {
            $opts{token} = <$fh>;
        }
    }
    pod2usage(-verbose => 1, -message => "no credentials provided\n")
        unless ($opts{token} || defined $opts{password} || defined $opts{create_token});

    # must use password auth with creating tokens
    if (defined $opts{create_token}) {
        delete $opts{token};
        delete $ENV{GITHUB_TOKEN};
        $opts{password} = 1;
    }

    $opts{api} = Marchex::Client::GitHub->new(
        host        => $opts{host},
        token       => $opts{token},
        username    => $opts{username},
        password    => $opts{password},
        verbose     => $opts{verbose}
    );

    return(\%opts);

}

sub format_url {
    my($self, $url) = @_;
    return $self->{tiny} ? $self->{tiny}->tinify($url) : $url;
}

sub prompt_for_credentials {
    my($self, $opts) = @_;

    $self->{username} //= '';

    my $username  = prompt_for("Username [$self->{username}]");
    $self->{username} = $username if $username;
    $self->{password} = prompt_for("Password", 1);
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

1;
