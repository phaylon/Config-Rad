use strictures 1;

package Config::Rad::Test;
use Config::Rad;
use Test::More ();
use Test::Fatal;
use FindBin;
use Exporter 'import';

our @EXPORT = qw(
    test_err
    test_ok
    RAD_DEFAULT
    RAD_DEFAULT_NOINC
    RAD_HASH
    RAD_ARRAY
    RAD_RT_HASH
    RAD_RT_ARRAY
);

do {
    package TestStringify;
    use overload '""' => sub { $_[0]->{value} }, fallback => 1;
    sub new { shift; bless { value => shift } }
};

do {
    package TestRuntimeMode;
    sub new { shift; bless { obj => $_[0], mode => $_[1] } }
    sub parse_string {
        my $self = shift;
        return $self->{obj}->parse_string(@_, topmode => $self->{mode});
    }
};

my $functions = {
    foo => sub { join '', 'foo', @_ },
    getkey => sub { $_[1]->{$_[0]} },
    passthrough => sub { shift },
    ns => sub { 'FUN' },
    throw => sub { die "THROWN\n" },
    somearray => sub { my @foo = (8..11); @foo },
};
my $variables = {
    strobj => TestStringify->new('STROBJ'),
    noval => undef,
    numval => 17,
};
my $constants = {
    bazqux => 23,
    somehash => { x => 23 },
    ns => 'CONST',
};
my %common = (
    functions => $functions,
    variables => $variables,
    constants => $constants,
    include_paths => ["$FindBin::Bin/conf/"],
);

my $rad_default = Config::Rad->new(%common);
my $rad_default_noinc = Config::Rad->new(%common, include_paths => []);
my $rad_hash = Config::Rad->new(%common, topmode => 'hash');
my $rad_array = Config::Rad->new(%common, topmode => 'array');
my $rad_rt_hash = TestRuntimeMode->new($rad_array, 'hash');
my $rad_rt_array = TestRuntimeMode->new($rad_hash, 'array');

sub RAD_DEFAULT () { $rad_default }
sub RAD_DEFAULT_NOINC () { $rad_default_noinc }
sub RAD_HASH () { $rad_hash }
sub RAD_ARRAY () { $rad_array }
sub RAD_RT_HASH () { $rad_rt_hash }
sub RAD_RT_ARRAY () { $rad_rt_array }

sub test_err {
    my ($rad, $group_title, @tests) = @_;
    Test::More::subtest $group_title => sub {
        for my $test (@tests) {
            my ($body, $error, $title) = @$test;
            my $caught = exception {
                $rad->parse_string($body, 'test config');
            };
            my ($error_rx, $error_ln, $error_src);
            if (ref($error) eq 'ARRAY') {
                ($error_rx, $error_ln, $error_src) = @$error;
            }
            else {
                ($error_rx, $error_ln, $error_src) = ($error, 1);
            }
            $error_src ||= qr{test config};
            Test::More::ok $caught, "$title was thrown" and do {
                Test::More::like $caught,
                    qr{^Config Error: $error_rx},
                    "$title message";
                Test::More::like $caught,
                    qr{at.+$error_src line \Q$error_ln\E},
                    "$title line number";
            };
        }
    };
}

sub test_ok {
    my ($rad, $group_title, @tests) = @_;
    Test::More::subtest $group_title => sub {
        for my $test (@tests) {
            my ($body, $expected, $title, $args) = @$test;
            $args ||= {};
            my $struct = $rad->parse_string($body, "test config", %$args);
            Test::More::is_deeply $struct, $expected, $title;
        }
    };
}

1;
