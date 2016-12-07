use strict;
use warnings;

use Test::More;
use JSON::XS qw(decode_json encode_json);
use Scalar::Util 'blessed';

uses();

my @tests = (
    'new_empty',
    'new_example',
    'new_github_com',
    'command_url',
    'command_url_fqbase',
    'command_req',
);

for (@tests) {
    no strict 'refs';
    subtest $_ => \&$_;
}

finish();

sub finish {
    done_testing();
    exit;
}

sub uses {
    use_ok('Marchex::Client::GitHub');
    use_ok('Marchex::Color');
    use_ok('Marchex::OpenURL');
}

sub _init {
    my(@args) = @_;
    my $gh = eval { Marchex::Client::GitHub->new(@args) };
    my $err = $@;
    ok($gh, "object returned");
    like($err, qr/^$/, "no error returned");
    $gh;
}

sub new_empty {
    my $gh = eval { Marchex::Client::GitHub->new(host => '', token => '0') };
    my $err = $@;
    ok(!$gh, "no object returned without 'host' and 'token' set");
    like($err, qr/Must have host and credentials set/i, "error returned");
}

sub new_example {
    my $host = 'github.example.com';
    my $token = '1';

    # 'host' and 'token' set explicitly
    my $gh = _init(host => $host, token => $token) or return;

    is(blessed($gh->{ua}), 'LWP::UserAgent', "'ua' object defined");
    is($gh->{token}, $token, "'token' is set properly");
    is($gh->{host}, $host, "'host' is set properly");
    is($gh->{uri}, "https://$host", "'uri' is set properly");
    is($gh->{base}, "https://$host/api/v3", "'base' is set properly");
}

sub new_github_com {
    my $host = local $ENV{GITHUB_HOST} = 'github.com';
    my $token = local $ENV{GITHUB_TOKEN} = 'aa';

    # 'host' and 'token' set via environment
    my $gh = _init() or return;

    is(blessed($gh->{ua}), 'LWP::UserAgent', "'ua' object defined");
    is($gh->{token}, $token, "'token' is set properly");
    is($gh->{host}, $host, "'host' is set properly");
    is($gh->{uri}, "https://api.$host", "'uri' is set properly");
    is($gh->{base}, "https://api.$host", "'base' is set properly");
}

sub command_url {
    local $ENV{GITHUB_HOST} = 'github.com';
    local $ENV{GITHUB_TOKEN} = 'aa';

    my $gh = _init() or return;

    my $base = $gh->{base};

    is($gh->_url(GET => 'user'), "$base/user", 'verify normal API URL');
    is($gh->_url(GET => '/user'), "$base/user", 'verify normal API URL');
    is($gh->_url(GET => 'user/repos'), "$base/user/repos", 'verify normal API URL');
    is($gh->_url(GET => '/user/repos'), "$base/user/repos", 'verify normal API URL');

    is($gh->_url(GET => 'user', 'bar=baz'), "$base/user?bar=baz", 'verify preformatted URL data');
    is($gh->_url(GET => 'user', { bar => 'baz' }), "$base/user?bar=baz", 'verify simple URL data');
    is($gh->_url(GET => 'user', { bar => 'baz', buz => 'biz' }), "$base/user?bar=baz&buz=biz", 'verify more complex URL data');

    is($gh->_url(POST => 'user', 'bar=baz'), "$base/user", 'verify no URL data in POST');
    is($gh->_url(POST => 'user', { bar => 'baz' }), "$base/user", 'verify no URL data in POST');

    is($gh->_url(GET => 'user', 'bar=baz', { link => 1 }), "$base/user", 'verify no URL data with "link"');
    is($gh->_url(GET => 'user', { bar => 'baz' }, { link => 1 }), "$base/user", 'verify no URL data with "link"');
}

sub command_url_fqbase {
    local $ENV{GITHUB_HOST} = 'github.com';
    local $ENV{GITHUB_TOKEN} = 'aa';

    my $gh = _init() or return;

    my $base = 'https://foo/user';

    is($gh->_url(GET => $base), $base, 'verify FQ URL');

    is($gh->_url(GET => $base, 'bar=baz'), "$base?bar=baz", 'verify preformatted URL data');
    is($gh->_url(GET => $base, { bar => 'baz' }), "$base?bar=baz", 'verify simple URL data');
    is($gh->_url(GET => $base, { bar => 'baz', buz => 'biz' }), "$base?bar=baz&buz=biz", 'verify more complex URL data');

    is($gh->_url(POST => $base, 'bar=baz'), $base, 'verify no URL data in POST');
    is($gh->_url(POST => $base, { bar => 'baz' }), $base, 'verify no URL data in POST');
    is($gh->_url(POST => $base, { bar => ['baz', 'quux'], buz => 'biz' }), $base, 'verify no URL data in POST');

    is($gh->_url(GET => $base, 'bar=baz', { link => 1 }), $base, 'verify no URL data with "link"');
    is($gh->_url(GET => $base, { bar => 'baz' }, { link => 1 }), $base, 'verify no URL data with "link"');
    is($gh->_url(GET => $base, { bar => ['baz', 'quux'], buz => 'biz' }, { link => 1 }), $base, 'verify no URL data with "link"');
}


sub command_req {
    local $ENV{GITHUB_HOST} = 'github.com';
    local $ENV{GITHUB_TOKEN} = 'aa';

    my $gh = _init() or return;

    my @tests = (
        { data => 'bar=baz' },
        { data => { bar => 'baz' }, content => '{"bar":"baz"}', query_string => 'bar=baz' },
        { data => { bar => ['baz', {'buz' => 'biz'}] },
            content => '{"bar":["baz",{"buz":"biz"}]}',
            get_fail => qr/data in GET request cannot contain complex data structure/
        },
    );

    for my $method (qw(GET POST PATCH PUT DELETE)) {
        my $i = 0;
        for my $content_type (undef, 'text/plain') {
      	    for my $accept_type (undef, 'application/vnd.github.loki-preview+json') {
                for my $link (undef, 'foo') {
                    for my $test (@tests) {
                        subtest "command_req_\L${method}\E_$i" => sub {
                            $test->{options}{content_type} = $content_type;
                            $test->{options}{accept_type} = $accept_type;
                            $test->{options}{link} = $link;

                            my $url = eval { $gh->_url($method => 'user', $test->{data}, $test->{options}) };
                            my $err = $@;
                            if ($method eq 'GET' && !$link && $test->{get_fail}) {
                                like($err, $test->{get_fail}, 'verify error when using complex data in GET request');
                                return;
                            }
                            my $req = $gh->_req($method => $url, $test->{data}, $test->{options});

                            is(blessed($req), 'HTTP::Request', 'verify request object');
                            is($req->method, $method, "method is '$method'");
                            if ($method eq 'GET' || $link) {
                                is($req->content, '', 'content is empty');
                                is($req->content_type, '', 'content type is empty');
                                if ($link) {
                                    is($req->uri, $link, "uri is '$link'");
                                }
                                else {
                                    my $query_string = $test->{query_string} // $test->{data};
                                    is($req->uri, "$gh->{base}/user?$query_string", "uri is '$gh->{base}/user?$query_string'");
                                }
                            }
                            else {
                                my $content_t = $test->{content} // $test->{data};
                                is($req->content, $content_t, "content is '$content_t'" );
                                my $content_type_t = $content_type // 'application/json';
                                is($req->content_type, $content_type_t, "content type is '$content_type_t'");
                                is($req->uri, "$gh->{base}/user", "uri is '$gh->{base}/user'");
                            }
                            my $accept_type_t = $accept_type // 'application/vnd.github.v3+json';
                            is($req->header('Accept'), $accept_type_t, "accept type is '$accept_type_t'");
                        };
                        $i++;
                    }
                }
            }
        }
    }
}

