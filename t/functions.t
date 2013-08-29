use strictures 1;
use Test::More;
use Config::Rad::Test;

local $ENV{TESTVALUE} = 'ENVVALUE';

test_ok(RAD_DEFAULT, 'syntax',
    ['foo foo()',
        { foo => 'foo' }, 'without arguments'],
    ['foo foo (23)',
        { foo => 'foo23' }, 'with spacing'],
    ['foo foo(23, 17)',
        { foo => 'foo2317' }, 'with comma separated arguments'],
    ['foo foo(23; 17)',
        { foo => 'foo2317' }, 'with semicolon separated arguments'],
    ['foo foo(23, foo(17))',
        { foo => 'foo23foo17' }, 'nested calls'],
    ['foo(23) foo(17)',
        { foo23 => 'foo17' }, 'as hash key'],
    ['foo foo(23) bar foo(17)',
        { foo => { foo23 => { bar => 'foo17' } } },
        'in descending keys'],
);

test_ok(RAD_DEFAULT, 'predeclared',
    ['foo foo("bar")',
        { foo => 'foobar' }, 'with argument'],
    ['foo foo()',
        { foo => 'foo' }, 'without arguments'],
);

test_ok(RAD_DEFAULT, 'builtin',
    ['foo str()',
        { foo => '' }, 'str()'],
    ['foo str($strobj)',
        { foo => 'STROBJ' }, 'str(object)'],
    ['foo str(2, 3, 4)',
        { foo => '234' }, 'str(...)'],
    ['foo env("TESTVALUE")',
        { foo => 'ENVVALUE' }, 'env(name)'],
);

test_err(RAD_DEFAULT, 'builtin errors',
    ['foo str(23, undef, 17)',
        qr{Error in 'str' callback.+Unable to stringify undef}s,
        'str(..., undef, ...)'],
    ['foo env()',
        qr{Error in 'env' callback.+Missing variable name argument}s,
        'env()'],
    ['foo env(undef)',
        qr{Error in 'env' callback.+Variable name argument is undef}s,
        'env(undef)'],
    ['foo env(2, 3)',
        qr{Error in 'env' callback.+Too many arguments}s,
        'env(...)'],
);

test_ok(RAD_DEFAULT, 'usage',
    ['foo ns()',
        { foo => 'FUN' }, 'separate from const namespace'],
    ['foo somearray()',
        { foo => 4 }, 'called in scalar context'],
);

test_err(RAD_DEFAULT, 'errors',
    ['foo nofunc()',
        qr{Unknown function 'nofunc'}, 'unknown function'],
    ['foo throw()',
        qr{Error in 'throw' callback.+THROWN\n}s, 'callback error'],
    ['foo throw())',
        qr{Unexpected closing '\)'}, 'unopened arguments'],
    ['foo 23(17)',
        qr{Unexpected opening '\('}, 'invalid arguments'],
    ['foo throw(23, ',
        qr{Unclosed call reached end of input},
        'unclosed arguments'],
);

test_for_cycles;

done_testing;
