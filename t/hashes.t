use strictures 1;
use Test::More;
use Config::Rad::Test;

my @_hash_topmodes = (
    [RAD_DEFAULT, 'default topmode (hash)'],
    [RAD_HASH, 'hash topmode'],
    [RAD_RT_HASH, 'runtime hash topmode'],
);

for my $top (@_hash_topmodes) {
    my ($rad, $title) = @$top;
    test_ok($rad, $title,
        ['', {}, 'empty'],
        ['foo 23',
            { foo => 23 }, 'single value'],
        ['foo 23; bar 17',
            { foo => 23, bar => 17 }, 'semicolon separation'],
        ['; ;; ;foo 23; ;; ;',
            { foo => 23 }, 'extra semicolon separators'],
        ['foo 23, bar 17',
            { foo => 23, bar => 17 }, 'comma separation'],
        [', ,, ,foo 23, ,, ,',
            { foo => 23 }, 'extra comma separators'],
        ['foo bar 23, foo baz 17',
            { foo => { bar => 23, baz => 17 } }, 'descending keys'],
        ['foo bar: { baz 23 }',
            { foo => { _ => 'bar', baz => 23 } }, 'topicalization'],
    );
    test_err($rad, "$title errors",
        ['foo', qr{Missing hash key names}, 'unkeyed value'],
        ['23, 17', qr{Missing hash key names}, 'unkeyed values'],
        (map {
            ["$_ 23",
                qr{Hash key is not a string},
                "key `$_` failure"],
        } '[]', '$noval'),
    );
}

test_ok(RAD_DEFAULT, 'hash containers',
    ['foo { }',
        { foo => {} }, 'empty'],
    ['foo { bar 17 }',
        { foo => { bar => 17 } }, 'simple'],
    ['foo bar { baz qux { x 23 } }',
        { foo => { bar => { baz => { qux => { x => 23 } } } } },
        'nested'],
    ['foo getkey("bar", { bar 23 })',
        { foo => 23 }, 'in call arguments'],
    ['foo [23, { bar 17 }, 99]',
        { foo => [23, { bar => 17 }, 99] }, 'in array'],
    ['foo { x 23 }; foo bar 17',
        { foo => { x => 23, bar => 17 } },
        'extension of existing hash'],
    ['"foo" "bar"', { foo => 'bar' }, 'as hash key'],
);

test_err(RAD_DEFAULT, 'hash container errors',
    ['foo { 23 }', qr{Missing hash key names}, 'unkeyed value'],
    ['foo { 23, 17 }', qr{Missing hash key names}, 'unkeyed values'],
    (map {
        ["foo { $_ 23 }",
            qr{Hash key is not a string},
            "key `$_` failure"],
    } '[]', '$noval'),
    (map {
        ["foo $_; foo bar 23",
            qr{Key 'foo' exists but is not a hash reference},
            "top set in `$_` instead of hash failure"],
        ["foo bar $_; foo bar baz 23",
            qr{Key 'bar' exists but is not a hash reference},
            "deep set in `$_` instead of hash failure"],
        ["foo bar $_; foo bar baz qux 23",
            qr{Key 'bar' exists but is not a hash reference},
            "deeper set in `$_` instead of hash failure"],
    } '[]', 'undef', '23', '$strobj'),
    (map {
        ["foo $_; foo 23",
            qr{Value 'foo' is already set},
            "simple existing `$_` value failure"],
        ["foo $_; foo undef",
            qr{Value 'foo' is already set},
            "undefining existing `$_` value failure"],
    } '[]', 'undef', '23', '$strobj'),
    ['foo { bar 23 }}', qr{Unexpected closing '\}'}, 'unopened hash'],
    ['foo { bar 23',
        qr{Unclosed hash reached end of input}, 'unclosed hash'],
);

done_testing;
