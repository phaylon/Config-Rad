use strictures 1;
use Test::More;
use Config::Rad::Test;

test_ok(RAD_DEFAULT, 'builtin',
    ['foo true', { foo => 1 }, 'true'],
    ['foo false', { foo => 0 }, 'false'],
    ['foo undef', { foo => undef }, 'null'],
);

test_ok(RAD_DEFAULT, 'predeclared',
    ['foo bazqux', { foo => 23 }, 'simple'],
);

test_ok(RAD_DEFAULT, 'usage',
    ['foo [true, bazqux]',
        { foo => [1, 23] }, 'in array'],
    ['foo foo(bazqux)',
        { foo => 'foo23' }, 'in call'],
    ['foo { bar bazqux }',
        { foo => { bar => 23 } }, 'in hash'],
    ['bazqux bazqux',
        { bazqux => 23 }, 'not in autoquotes'],
    ['foo ns',
        { foo => 'CONST' }, 'separate from function namespace'],
);

test_err(RAD_DEFAULT, 'errors',
    ['foo noconst',
        qr{Unknown constant 'noconst'},
        'unknown constant'],
);

test_for_cycles;

done_testing;
