use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

(do 'maint/Makefile.PL.include' or die $@) unless -f 'META.yml';

my %_deps_runtime = (
    'Moo' => '1.003',
    'Try::Tiny' => '0.12',
    'strictures' => 1,
    'namespace::clean' => '0.24',
    'List::Util' => 0,
    'Scalar::Util' => 0,
    'Path::Tiny' => '0.021',
);

my %_deps_tests = (
    'Test::More' => '0.98',
    'Test::Fatal' => '0.010',
);

WriteMakefile(
    NAME => 'Config::Rad',
    VERSION_FROM => 'lib/Config/Rad.pm',
    PREREQ_PM => { %_deps_runtime },
    BUILD_REQUIRES => { %_deps_tests },
    LICENSE => 'perl',
);
