use strictures 1;
use Test::More;
use Config::Rad::Test;

test_ok(RAD_DEFAULT, 'numbers',
    ['foo 23', { foo => 23 }, 'integer'],
    ['foo 23_500', { foo => 23500 }, 'integer with separator'],
    ['foo -23', { foo => -23 }, 'negative integer'],
    ['foo 23.57', { foo => 23.57 }, 'float'],
    ['foo 2_3.5_7', { foo => 23.57 }, 'float with separators'],
    ['foo -23.57', { foo => -23.57 }, 'negative float'],
    ['foo 0', { foo => 0 }, 'zero'],
    ['foo 0.0', { foo => 0 }, 'zero float'],
    ['foo -0', { foo => 0 }, 'negative zero'],
);

test_err(RAD_DEFAULT, 'number errors',
    ['foo 0755',
        qr{Numbers cannot start with 0},
        'octal'],
    ['foo 0_755',
        qr{Numbers cannot start with 0},
        'octal with delimiter'],
    ['foo -0755',
        qr{Numbers cannot start with 0},
        'negative octal'],
    ['foo 0755.23',
        qr{Numbers cannot start with 0},
        'octal float'],
    ['foo -0755.23',
        qr{Numbers cannot start with 0},
        'negative octal float'],
);

test_for_cycles;

done_testing;
