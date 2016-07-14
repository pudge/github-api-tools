package Marchex::OpenURL;

use warnings;
use strict;

# if OPEN_URL_SSH is true, and you're logged in via SSH, will attempt to
# open a connection back to your host and open the URL there.  otherwise,
# will attempt to open the URL locally.

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
