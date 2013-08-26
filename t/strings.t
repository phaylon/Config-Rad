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

test_ok(RAD_DEFAULT, 'single quoted multiline strings',
    [qq!foo '''\n    23\n        17\n    99\n  '''!,
        { foo => "23\n    17\n99\n" },
        'simple'],
    [qq!foo '''  \n  23\n 17\n   99'''!,
        { foo => " 23\n17\n  99" },
        'whitespace on empty opening line'],
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

test_ok(RAD_DEFAULT, 'single quoted multiline strings',
    [qq!foo """\n    23\n        \${numval}\n    99\n  """!,
        { foo => "23\n    17\n99\n" },
        'simple'],
    [qq!foo """  \n  23\n \${numval}\n   99"""!,
        { foo => " 23\n17\n  99" },
        'whitespace on empty opening line'],
    [q!
        foo """
            foo
                bar\nbaz
                qux
        """
    !, { foo => "foo\n    bar\nbaz\n    qux\n" },
        'inserted newline characters ignored on realignment'],
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
