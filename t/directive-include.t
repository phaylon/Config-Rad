use strictures 1;
use Test::More;
use Config::Rad::Test;

test_ok(RAD_DEFAULT, 'include',
    [q!foo { bar 23; @include 'include-test-hash.conf'; baz 17 }!,
        { foo => { bar => 23, baz => 17, incval => 99 } },
        'simple hash include'],
    [q!foo [23; @include 'include-test-array.conf'; 17 ]!,
        { foo => [23, 99, 100, 101, 17] },
        'simple array include'],
);

test_for_cycles;

done_testing;
