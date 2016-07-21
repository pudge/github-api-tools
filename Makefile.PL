use 5.010;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Marchex::Client::GitHub',
    VERSION_FROM      => 'lib/Marchex/Client/GitHub.pm', # finds $VERSION
    PREREQ_PM         => {
        'Carp'                  => 0,
        'Class::Accessor'       => 0,
        'Data::Dumper'          => 0,
        'File::Temp'            => 0,
        'Getopt::Long'          => 0,
        'HTTP::Request'         => 0,
        'JSON::XS'              => 0,
        'LWP'                   => 0,
        'LWP::Protocol::https'  => 0,
        'MIME::Base64'          => 0,
        'Pod::Usage'            => 0,
        'URI::Escape'           => 0,
        'WWW::Mechanize'        => 0,
    },
    EXE_FILES         => [<bin/*>]
);
