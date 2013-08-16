use strictures 1;
use Test::More;
use Test::Fatal;
use Config::Rad;
use File::Temp;

do {
    package TestStringify;
    use overload '""' => sub { $_[0]->{value} }, fallback => 1;
    sub new { shift; bless { value => shift } }
};
do {
    package TestRuntimeMode;
    sub new { shift; bless { obj => $_[0], mode => $_[1] } }
    sub parse_string {
        my $self = shift;
        return $self->{obj}->parse_string(@_, topmode => $self->{mode});
    }
};

my $functions = {
    foo => sub { join '', 'foo', @_ },
    getkey => sub { $_[1]->{$_[0]} },
    passthrough => sub { shift },
    ns => sub { 'FUN' },
    throw => sub { die "THROWN\n" },
    somearray => sub { my @foo = (8..11); @foo },
};
my $variables = {
    strobj => TestStringify->new('STROBJ'),
    noval => undef,
};
my $constants = {
    bazqux => 23,
    somehash => { x => 23 },
    ns => 'CONST',
};
my %common = (
    functions => $functions,
    variables => $variables,
    constants => $constants,
);

my $rad_default = Config::Rad->new(%common);
my $rad_hash = Config::Rad->new(%common, topmode => 'hash');
my $rad_array = Config::Rad->new(%common, topmode => 'array');
my $rad_rt_hash = TestRuntimeMode->new($rad_array, 'hash');
my $rad_rt_array = TestRuntimeMode->new($rad_hash, 'array');

subtest 'topmode errors' => sub {
    like exception { Config::Rad->new(topmode => 'list') },
        qr{Must be either 'hash' or 'array'},
        'invalid topmode attribute value';

    for my $arg (qw( variables constants functions )) {
        like exception { Config::Rad->new($arg => []) },
            qr{Not a hash reference},
            "invaild $arg argument";
    }

    like exception {
        $rad_default->parse_string('', 'test config', topmode => 'list');
    }, qr{Invalid topmode: Must be 'hash' or 'array'},
        'invalid runtime topmode';
};

subtest 'file loading' => sub {
    do {
        my $tmp = File::Temp->new;
        print $tmp 'foo 23';
        close $tmp;
        my $data = $rad_default->parse_file($tmp->filename);
        is_deeply $data, { foo => 23 }, 'config loaded from file';
    };
    like exception {
        $rad_default->parse_file('_CONFIG_RAD_THISFILESHOULDNTEXIST');
    }, qr{Unable to open '_CONFIG_RAD_THISFILESHOULDNTEXIST':},
        'invalid file source';
    do {
        my $tmp = File::Temp->new;
        print $tmp 'foo $novar';
        close $tmp;
        my $fname = $tmp->filename;
        like exception { $rad_default->parse_file($fname) },
            qr{Unknown variable '\$novar' at $fname line 1.},
            'file source name';
    };
};

subtest 'caching' => sub {
    my $rad = Config::Rad->new(cache => 1);
    my ($name, $first_load, $second_load);
    do {
        my $tmp = File::Temp->new;
        $name = $tmp->filename;
        print $tmp 'foo 23';
        close $tmp;
        $first_load = $rad->parse_file($name);
    };
    ok not(-e $name), 'file no longer exists';
    $second_load = $rad->parse_file($name);
    is_deeply $first_load, { foo => 23 }, 'config file was valid';
    is_deeply $second_load, $first_load, 'second load is equal';
};

test_ok($rad_default, 'runtime elements',
    ['foo rtconst', { foo => 23 }, 'runtime constant', {
        constants => { rtconst => 23 },
    }],
    ['foo $rtvar', { foo => 23 }, 'runtime variable', {
        variables => { rtvar => 23 },
    }],
    ['foo rtfunc()', { foo => 23 }, 'runtime function', {
        functions => { rtfunc => sub { 23 } },
    }],
);

test_ok($rad_default, 'line comments',
    ['# foo', {}, 'comment at start'],
    [' # foo', {}, 'comment after whitespace'],
    ["foo 23; # bar\nbaz 17",
        { foo => 23, baz => 17 }, 'comment ends at line end'],
    ["# foo\nbar 23", { bar => 23 }, 'data after comment'],
);

test_ok($rad_default, 'item comments',
    ['@# 23; foo 17', { foo => 17 }, 'simple'],
    ["foo 23, @# bar {\nbaz 17\n};\nqux 99",
        { foo => 23, qux => 99 }, 'multiline item comment'],
);

test_err($rad_default, 'item comment errors',
    ['foo @# 23', qr{Unexpected item_comment token}, 'misplaced'],
);

my @_hash_topmodes = (
    [$rad_default, 'default topmode (hash)'],
    [$rad_hash, 'hash topmode'],
    [$rad_rt_hash, 'runtime hash topmode'],
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

my @_array_topmodes = (
    [$rad_array, 'array topmode'],
    [$rad_rt_array, 'runtime array topmode'],
);

for my $top (@_array_topmodes) {
    my ($rad, $title) = @$top;
    test_ok($rad, $title,
        ['', [], 'empty'],
        ['23', [23], 'simple'],
        ['23; 17', [23, 17], 'semicolon separation'],
        ['23, 17', [23, 17], 'comma separation'],
        ['foo: { x 17 }', [{ _ => 'foo', x => 17 }], 'topicalization'],
    );
}

test_err($rad_array, 'array topmode errors',
    ['foo 23', qr{Arrays cannot contain keyed values}, 'keyed value'],
    ['a b 23', qr{Arrays cannot contain keyed values}, 'keyed values'],
);

test_err($rad_default, 'generic errors',
    ['foo bar:= {}',
        qr{Unexpected assign token}, 'unexpected token'],
    ["foo\nbar\n:\n=\n{}",
        [qr{Unexpected assign token}, 4], 'unexpected multiline'],
    ['? 23', qr{Unable to parse: `\? 23`}, 'unknown char'],
);

test_ok($rad_default, 'single quoted strings',
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

test_err($rad_default, 'single quoted string errors',
    [q{foo 'bar},
        qr{Single quoted string reached end of line without termination},
        'unclosed string'],
    [qq{foo 'bar\nbaz'},
        qr{Single quoted string reached end of line without termination},
        'multiline string'],
);

test_ok($rad_default, 'double quoted strings',
    ['foo "bar"',
        { foo => 'bar' }, 'simple'],
    ['foo "bar\n\tbaz\n\tqux"',
        { foo => "bar\n\tbaz\n\tqux" }, 'interpolated chars'],
    ['$baz = 23; foo "bar${baz}qux"',
        { foo => 'bar23qux' }, 'variable interpolation'],
    ['foo "bar \${baz} qux"',
        { foo => 'bar ${baz} qux' }, 'escaped interpolation'],
);

test_err($rad_default, 'double quoted string errors',
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

test_ok($rad_default, 'variables',
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
);

test_err($rad_default, 'variable errors',
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
);

subtest 'functions' => sub {
    test_ok($rad_default, 'syntax',
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
    test_ok($rad_default, 'predeclared',
        ['foo foo("bar")',
            { foo => 'foobar' }, 'with argument'],
        ['foo foo()',
            { foo => 'foo' }, 'without arguments'],
    );
    local $ENV{TESTVALUE} = 'ENVVALUE';
    test_ok($rad_default, 'builtin',
        ['foo str()',
            { foo => '' }, 'str()'],
        ['foo str($strobj)',
            { foo => 'STROBJ' }, 'str(object)'],
        ['foo str(2, 3, 4)',
            { foo => '234' }, 'str(...)'],
        ['foo env("TESTVALUE")',
            { foo => 'ENVVALUE' }, 'env(name)'],
    );
    test_err($rad_default, 'builtin errors',
        ['foo str(23, undef, 17)',
            qr{Error in 'str' callback: Unable to stringify undef},
            'str(..., undef, ...)'],
        ['foo env()',
            qr{Error in 'env' callback: Missing variable name argument},
            'env()'],
        ['foo env(undef)',
            qr{Error in 'env' callback: Variable name argument is undef},
            'env(undef)'],
        ['foo env(2, 3)',
            qr{Error in 'env' callback: Too many arguments},
            'env(...)'],
    );
    test_ok($rad_default, 'usage',
        ['foo ns()',
            { foo => 'FUN' }, 'separate from const namespace'],
        ['foo somearray()',
            { foo => 4 }, 'called in scalar context'],
    );
    test_err($rad_default, 'errors',
        ['foo nofunc()',
            qr{Unknown function 'nofunc'}, 'unknown function'],
        ['foo throw()',
            qr{Error in 'throw' callback: THROWN\n}, 'callback error'],
        ['foo throw())',
            qr{Unexpected closing '\)'}, 'unopened arguments'],
        ['foo 23(17)',
            qr{Unexpected opening '\('}, 'invalid arguments'],
        ['foo throw(23, ',
            qr{Unclosed call reached end of input},
            'unclosed arguments'],
    );
};

test_ok($rad_default, 'hash containers',
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

test_err($rad_default, 'hash container errors',
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

test_ok($rad_default, 'array containers',
    ['foo []',
        { foo => [] }, 'empty'],
    ['foo [23]',
        { foo => [23] }, 'simple'],
    ['foo [23, 17]',
        { foo => [23, 17] }, 'comma separated'],
    ['foo [23; 17]',
        { foo => [23, 17] }, 'semicolon separated'],
    ['foo [23, [17, 99]]',
        { foo => [23, [17, 99]] }, 'nested'],
);

test_err($rad_default, 'array container errors',
    ['foo [bar 23]',
        qr{Arrays cannot contain keyed values}, 'keyed value'],
    ['foo [23, 17]]',
        qr{Unexpected closing '\]'}, 'unopened array'],
    ['foo [23,',
        qr{Unclosed array reached end of input}, 'unclosed array'],
);

test_ok($rad_default, 'topicalization',
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

test_err($rad_default, 'topicalization errors',
    (map {
        ["foo bar: $_",
            qr{Can only topicalize hash references},
            "topic on `$_`"],
    } '23', '[]', 'undef'),
    ['foo {:}', qr{Unexpected topicalization}, 'operator only'],
    ['foo {: {} }', qr{Unexpected topicalization}, 'missing topic'],
    ['foo 23:', qr{Missing topicalized value}, 'missing value'],
);

subtest 'constants' => sub {
    test_ok($rad_default, 'builtin',
        ['foo true', { foo => 1 }, 'true'],
        ['foo false', { foo => 0 }, 'false'],
        ['foo undef', { foo => undef }, 'null'],
    );
    test_ok($rad_default, 'predeclared',
        ['foo bazqux', { foo => 23 }, 'simple'],
    );
    test_ok($rad_default, 'usage',
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
    test_err($rad_default, 'errors',
        ['foo noconst',
            qr{Unknown constant 'noconst'},
            'unknown constant'],
    );
};

done_testing;

sub test_err {
    my ($rad, $group_title, @tests) = @_;
    subtest $group_title => sub {
        for my $test (@tests) {
            my ($body, $error, $title) = @$test;
            my $caught = exception {
                $rad->parse_string($body, 'test config');
            };
            my ($error_rx, $error_ln);
            if (ref($error) eq 'ARRAY') {
                ($error_rx, $error_ln) = @$error;
            }
            else {
                ($error_rx, $error_ln) = ($error, 1);
            }
            ok $caught, "$title was thrown" and do {
                like $caught,
                    qr{^Config Error: $error_rx},
                    "$title message";
                like $caught,
                    qr{ at test config line \Q$error_ln\E\.$},
                    "$title line number";
            };
        }
    };
}

sub test_ok {
    my ($rad, $group_title, @tests) = @_;
    subtest $group_title => sub {
        for my $test (@tests) {
            my ($body, $expected, $title, $args) = @$test;
            $args ||= {};
            my $struct = $rad->parse_string($body, "test config", %$args);
            is_deeply $struct, $expected, $title;
        }
    };
}
