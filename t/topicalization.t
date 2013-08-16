use strictures 1;
use Test::More;
use Config::Rad::Test;

test_ok(RAD_DEFAULT, 'topicalization',
    ['foo bar: {}',
        { foo => { _ => 'bar' } }, 'empty'],
    ['foo bar : {}',
        { foo => { _ => 'bar' } }, 'with spacing'],
    ['foo bar: { x 23 }',
        { foo => { _ => 'bar', x => 23 } }, 'simple'],
    ['foo 23: { x 17 }',
        { foo => { _ => 23, x => 17 } }, 'number topic'],
    ['$foo = 23; bar $foo: { x 17 }',
        { bar => { _ => 23, x => 17 } }, 'variable topic'],
    ['foo [23]: { x 17 }',
        { foo => { _ => [23], x => 17 } }, 'array topic'],
    ['a { href "/" }: { content "foo" }',
        { a => { _ => { href => '/' }, content => 'foo' } },
        'hash topic'],
    ['$foo = { x 23 }; foo bar: $foo',
        { foo => { _ => 'bar', x => 23 } },
        'topicalized variable'],
    ['foo bar: passthrough({ x 23 })',
        { foo => { _ => 'bar', x => 23 } },
        'topicalized call'],
    ['foo bar: somehash',
        { foo => { _ => 'bar', x => 23 } },
        'topicalized constant'],
    ['foo a bar: somehash; foo b baz: somehash',
        { foo => {
            a => { _ => 'bar', x => 23 },
            b => { _ => 'baz', x => 23 },
        } },
        'topicalized constant unchanged'],
    ['$foo = { x 23 }; foo a bar: $foo; foo b baz: $foo',
        { foo => {
            a => { _ => 'bar', x => 23 },
            b => { _ => 'baz', x => 23 },
        } },
        'topicalized variable unchanged'],
    ['foo [bar: { x 23 }, baz: { x 17 }]',
        { foo => [
            { _ => 'bar', x => 23 },
            { _ => 'baz', x => 17 },
        ] },
        'in array'],
);

test_err(RAD_DEFAULT, 'topicalization errors',
    (map {
        ["foo bar: $_",
            qr{Can only topicalize hash references},
            "topic on `$_`"],
    } '23', '[]', 'undef'),
    ['foo {:}', qr{Unexpected topicalization}, 'operator only'],
    ['foo {: {} }', qr{Unexpected topicalization}, 'missing topic'],
    ['foo 23:', qr{Missing topicalized value}, 'missing value'],
);

done_testing;
