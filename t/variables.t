use strictures 1;
use Test::More;
use Config::Rad::Test;

test_ok(RAD_DEFAULT, 'variables',
    ['$foo = 23; bar $foo',
        { bar => 23 }, 'as hash value'],
    ['$foo = 23; bar "[${foo}]"',
        { bar => '[23]' }, 'interpolated in string'],
    ['$foo = 23; bar [$foo]',
        { bar => [23] }, 'as array item'],
    ['$foo = 23; $bar = 17; $foo $bar',
        { 23 => 17 }, 'as hash key and value'],
    ['foo str($strobj)',
        { foo => 'STROBJ' }, 'predeclared'],
    ['foo str($bar = 23, $bar, $bar)',
        { foo => '2323' }, 'in call'],
    ['foo [$bar = 23; [$bar, $bar]; 99]',
        { foo => [[23, 23], 99] }, 'nested access'],
    ['$foo = 23; bar $foo baz 17',
        { bar => { 23 => { baz => 17 } } }, 'in descending keys'],
    ['$foo = bar: { x 23 }; foo $foo',
        { foo => { _ => 'bar', x => 23 } }, 'topicalization value'],
    ['foo [$bar = 23, $bar]; baz [$bar = 17, $bar]',
        { foo => [23], baz => [17] }, 'equally named variables'],
);

test_err(RAD_DEFAULT, 'variable errors',
    ['foo $novar',
        qr{Unknown variable '\$novar'}, 'unknown variable'],
    (map {
        ["$_ = 23",
            qr{Left side of assignment has to be variable},
            "assign to `$_` failure"],
    } 'foo', '23', '[]', '', 'foo bar', 'foo $bar'),
    (map {
        ["\$foo = $_",
            qr{Right side of assignment has to be single value},
            "assigning `$_` failure"],
    } 'foo bar'),
    ['$foo = 23; $foo = 17',
        qr{Variable '\$foo' is already defined},
        'redefined in same scope'],
    ['$foo = 23; bar [$foo = 17]',
        qr{Variable '\$foo' is already defined},
        'redefined in lower scope'],
);

done_testing;
