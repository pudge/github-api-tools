# github-api-tools

These are command-line utilities, and a Perl library, for dealing with the [GitHub API](https://developer.github.com/v3/).  The tools work with both GitHub.com, and GitHub Enterprise.
* github_api - use the GitHub API
* github_approve_pr - set status for pull request from the command line
* github_protect_branch - set up protected branch rules on an existing repo
* github_search - search GitHub code


## OPTIONS

For all the programs, you must set a host and authorization token.

The host can be passed in with the `-H` flag, or can be set with the `GITHUB_HOST` environment variable.  For public GitHub.com, use `github.com`.

The token -- which can be created on your GitHub instance at `/settings/tokens`, with whatever permissions are required for what you're using it for -- can be passed in with the `-t` flag, or set with the `GITHUB_TOKEN` environment variable.

Use the `-h` flag to read the documentation for the program, and `-V` for the version (which is shared by all the tools, and read from the library).


## INSTALL
* perl Makefile.PL
* make
* make test
* make install


## PREREQUISITES
There are several perl module prereqs for this, all listed in Makefile.PL, but most are included with perl.  You likely only need to get, at most `JSON::XS`.  You can install this from the CPAN, or you can try installing them with your package manager:

* libjson-xs-perl

You may also need:

* libwww-perl

If you choose to build your own Perl modules from source, or using a CPAN tool, you will need the perl build tools for your platform.


## COPYRIGHT AND LICENSE
Copyright 2016, Marchex.

This library is free software; you may redistribute it and/or modify it under the same terms as Perl itself.
