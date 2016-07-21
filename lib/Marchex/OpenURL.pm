package Marchex::OpenURL;

=pod

=head1 NAME

Marchex::OpenURL - Simple helper for printing ANSI colors

=head1 SYNOPSIS

    use Marchex::OpenURL qw(open_url open_url_with);
    open_url('http://www.marchex.com/');
    open_url_with('xdg-open', 'http://www.marchex.com/');

=head1 DESCRIPTION

This package attempts to open a URL in your local browser.  If the environment variable C<OPEN_URL_SSH> is true, and you're logged in via SSH, it will attempt to open a connection back to your host and open the URL there.  Otherwise, it will attempt to open the URL on the executing host (which may end up opening it via X11).

If the environment variables C<OPEN_URL_REMOTE_CMD> or C<BROWSER> are set, will attempt (in that order) to use that as the browser instead of the default, which is C<open> on Mac OS X and C<xdg-open> otherwise.


=head1 COPYRIGHT AND LICENSE

Copyright 2016, Marchex.

This library is free software; you may redistribute it and/or modify it under the same terms as Perl itself.

=cut

use warnings;
use strict;

use base 'Exporter';
our @EXPORT_OK = qw(open_url open_url_with);

our $SSH = 'ssh';

sub open_url {
    my($url) = @_;

    my $cmd = $ENV{OPEN_URL_CMD} // $ENV{BROWSER} // (
        $^O eq 'darwin' ? 'open' : 'xdg-open' # modern Linux default
    );
    my $cmd_remote  = $ENV{OPEN_URL_REMOTE_CMD} // 'open'; # Mac OS
    my $ssh_allowed = $ENV{OPEN_URL_SSH}; # boolean, no need to use for X11

    if ($url && $ssh_allowed) {
        my $host = $ENV{SSH_CLIENT} || $ENV{SSH_CONNECTION};
        if ($host) {
            $host =~ s/ .+$//;
            if ($host =~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
                # quote the $url, else '&' characters will still be unhappy
                # on the remote from the ssh cmd
                _open_url($SSH, $host, $cmd_remote, quotemeta($url));
                exit(0);
            }
        }
    }

    _open_url($cmd, $url);
    exit(0);
}

sub open_url_with {
    my($browser, $url) = @_;
    local $ENV{OPEN_URL_CMD} = $browser if defined($browser) && length($browser);
    open_url($url);
}

sub _open_url {
    my(@args) = @_;
    system(@args);
}

1;
