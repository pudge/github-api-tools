use strict;
use warnings;

use Test::More;

# the API *apparently* returns a maximum of 30 results per page
# and 34 pages of results; subject to change.  due to rate limit,
# we're setting the max pages to 10 and testing with that.
use constant MAX_RESULTS_PER_PAGE => 30;
use constant MAX_PAGES => 10;
use constant MAX_RESULTS => MAX_RESULTS_PER_PAGE * MAX_PAGES;

uses();
check_env() or finish();

my @tests = (
    'user',
    'links'
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
    my $output = eval { `$^X -Mblib ./blib/script/github_api $args` };
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

# we want to test that following links (API pagination) works.
# this is hard to test, since we don't know what the data will look
# like, especially if GITHUB_HOST isn't github.com.  so we end up
# testing search results, and *hoping* that it also tests following links.
sub links {
    my @q;
    my $gh = _init();

    # careful, if you run this too much, you'll error with a rate limit,
    # but we really need to test pagination
    if ($ENV{GITHUB_HOST} eq 'github.com') {
        # we know this, for now, gives dozens of results
        push @q, 'org:github language:perl';
        # 'the' is a pretty common word
        push @q, 'org:github the';
    }
    else {
        my $user = _cmd($gh, GET => 'user');
        # just a guess at what might give a lot of results
        push @q, "org:$user->{login} $user->{login}";
        push @q, "org:$user->{login} the";
    }

    my $i = 0;
    for my $q (@q) {
        subtest "links_q_$i" => sub {
            my $search = _cmd($gh, GET => '/search/code', { 'q' => $q }, { page_limit => MAX_PAGES });
            my $count = scalar @{$search->{items}};
            if ($count >= MAX_RESULTS) {
                is($count, MAX_RESULTS, "total count: $search->{total_count}, but hit max of $count");
            }
            else {
                is($count, $search->{total_count}, "total count: $search->{total_count}");
            }

            # hopefully the total count is great enough that we can test no_follow to see if
            # we get less than MAX_RETURN
            if ($search->{total_count} > MAX_RESULTS_PER_PAGE) {
                my $search_no_follow = _cmd($gh, GET => '/search/code', { 'q' => $q }, { no_follow => 1 });
                my $count_no_follow = scalar @{$search_no_follow->{items}};
                is($count_no_follow, MAX_RESULTS_PER_PAGE,
                    sprintf("total count: %d/%d", MAX_RESULTS_PER_PAGE, $search_no_follow->{total_count})
                );
            }
        };
        $i++;
    }
}
