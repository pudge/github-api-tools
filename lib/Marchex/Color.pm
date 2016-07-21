package Marchex::Color;

=pod

=head1 NAME

Marchex::Color - Simple helper for printing ANSI colors

=head1 SYNOPSIS

    use Marchex::Color qw(:colors color_str);
    print color_str("neat!", RED), "\n";

=head1 DESCRIPTION

Just wraps strings in ASNI colors.  It will not color strings if the program not connected to a TTY.

=head1 COPYRIGHT AND LICENSE

Copyright 2016, Marchex.

This library is free software; you may redistribute it and/or modify it under the same terms as Perl itself.

=cut

use warnings;
use strict;

use constant RED     => 31;
use constant GREEN   => 32;
use constant YELLOW  => 33;
use constant BLUE    => 34;
use constant MAGENTA => 35;
use constant CYAN    => 36;

use Exporter;
use base 'Exporter';
my @colors = qw(RED GREEN YELLOW BLUE MAGENTA CYAN);
our @EXPORT_OK = (@colors, 'color_str');
our %EXPORT_TAGS = (colors => \@colors);

sub color_str {
    my($str, $color) = @_;
    return $str unless (-t STDIN && -t STDOUT);
    return $color ? "\e[${color}m${str}\e[0m" : $str;
}

1;
