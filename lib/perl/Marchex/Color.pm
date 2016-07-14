package Marchex::Color;

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
