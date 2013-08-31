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

test_ok(RAD_DEFAULT, 'default assignment',
    ['$foo //= 23; bar $foo',
        { bar => 23 }, 'lexical creation'],
    (map {
        my ($val, $exp, $title) = @$_;
        [qq!\$foo = $val; \$foo //= 23; bar \$foo!,
            { bar => $exp },
            "default assignment with $title value"],
    } ['17', 17, 'defined'],
      ['0', 0, 'false'],
      ['undef', 23, 'undefined'],
    ),
);

test_err(RAD_DEFAULT, 'variable errors',
    ['foo $novar',
        qr{Unknown variable '\$novar'}, 'unknown variable'],
    (map {
        my ($ops, $title) = @$_;
        ["\$foo $ops 23",
            qr{Invalid assignment operator position},
            "invalid $title"],
    } ['= =', 'double assign'],
      ['==', 'unspaced double assign'],
      ['//= //=', 'double default'],
      ['//==', 'default and assign'],
      ['=//=', 'assign and default'],
    ),
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
);

test_for_cycles;

done_testing;
