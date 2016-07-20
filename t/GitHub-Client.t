use strict;
use warnings;

use Test::More;

uses();
check_env() or finish();

# TODO:
# other tests ... ?  or just this sanity check?

my @tests = (
    'user',
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
}

sub check_env {
    pass(); # succeed one test, whether we can continue or not, as
            # lack of env must not be a test failure

    unless ($ENV{GITHUB_HOST} && $ENV{GITHUB_TOKEN}) {
        note 'Must have $GITHUB_HOST and $GITHUB_TOKEN set in environment to continue tests';
        return 0;
    }

    return 1;
}

sub _init {
    Marchex::Client::GitHub->new;
}

sub _cli {
    my(@args) = @_;
    my $args = join ' ', map { quotemeta } @args;
    my $output = eval { `./blib/script/github_api $args` };
    ok(!$@, sprintf("no error %s", $@//''));

    my $obj = JSON::XS::decode_json($output);
    ok($obj, "API call '$args[0]' successful");
    $obj;
}

sub _cmd {
    my($gh, @args) = @_;
    my $obj = eval { $gh->command(@args) };
    ok(!$@, sprintf("no error %s", $@//''));
    ok($obj, "API call '$args[1]' successful");
    $obj;
}

sub user {
    my $gh = _init();

    ## get the current user, and test that the user has some required attributes
    my $user = _cmd($gh, GET => 'user');
    return unless $user;
    ok($user->{login}, sprintf("found login '%s'", $user->{login}//''));
    ok($user->{repos_url}, sprintf("found repos_url '%s'", $user->{repos_url}//''));

    ## get the repos for the current user, using a full URL, and test that a
    ## repo has some required attributes (if there are any repos)
    my $repos = _cmd($gh, GET => $user->{repos_url});
    ok((ref($repos) eq 'ARRAY'), sprintf('repo count: %d', scalar @$repos));
    if (@$repos) {
        ok($repos->[0]{name}, sprintf("found repo '%s'", $repos->[0]{name}//''));
        ok($repos->[0]{git_url}, sprintf("found git_url '%s'", $repos->[0]->{git_url}//''));
    }

    ## get user and repos via cmd line tool, and verify output is the same
    ## as through the API
    my $c_user = _cli('user');
    is_deeply($user, $c_user, 'compare CLI to API output');

    my $c_repos = _cli( $user->{repos_url} );
    is_deeply($repos, $c_repos, 'compare CLI to API output');
}

