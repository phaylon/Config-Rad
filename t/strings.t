use strictures 1;
use Test::More;
use Config::Rad::Test;

test_ok(RAD_DEFAULT, 'single quoted strings',
    ["foo 'bar'",
        { foo => 'bar' }, 'simple'],
    ["foo 'bar \\' baz'",
        { foo => "bar ' baz" }, 'escaped delimiter'],
    ["foo 'bar \\\\ baz'",
        { foo => "bar \\ baz" }, 'escaped backslash'],
    ["foo 'bar \\n baz'",
        { foo => q{bar \n baz} }, 'escaped qq known letter'],
    ["foo 'bar \\? baz'",
        { foo => q{bar \? baz} }, 'escaped random letter'],
    ["foo 'bar \${foo} baz'",
        { foo => q!bar ${foo} baz! }, 'sigil'],
    [q{foo 'bar \\\\'},
        { foo => 'bar \\' }, 'backslash escape at end'],
);

test_err(RAD_DEFAULT, 'single quoted string errors',
    [q{foo 'bar},
        qr{Single quoted string reached end of line without termination},
        'unclosed string'],
    [qq{foo 'bar\nbaz'},
        qr{Single quoted string reached end of line without termination},
        'multiline string'],
);

test_ok(RAD_DEFAULT, 'double quoted strings',
    ['foo "bar"',
        { foo => 'bar' }, 'simple'],
    ['foo "bar\n\tbaz\n\tqux"',
        { foo => "bar\n\tbaz\n\tqux" }, 'interpolated chars'],
    ['$baz = 23; foo "bar${baz}qux"',
        { foo => 'bar23qux' }, 'variable interpolation'],
    ['foo "bar \${baz} qux"',
        { foo => 'bar ${baz} qux' }, 'escaped interpolation'],
);

test_err(RAD_DEFAULT, 'double quoted string errors',
    [q{foo "bar},
        qr{Double quoted string reached end of line without termination},
        'unclosed string'],
    [qq{foo "bar\nbaz"},
        qr{Double quoted string reached end of line without termination},
        'multiline string'],
    [qq{foo "bar \\?"},
        qr{Unknown escape sequence '\\\?'},
        'invalid escape'],
);

done_testing;
