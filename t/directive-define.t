use strictures 1;
use Test::More;
use Config::Rad::Test;

test_ok(RAD_DEFAULT, 'templates',
    ['@define foo() 23; foo foo()',
        { foo => 23 }, 'no parameters'],
    ['@define foo($x) $x; foo foo(23)',
        { foo => 23 }, 'single parameter'],
    ['@define foo($x, $y) { $x $y }; foo foo(23, 17)',
        { foo => { 23 => 17 } }, 'multiple parameters'],
    ['@define foo($x, $y = 17) { $x $y }; foo foo(23)',
        { foo => { 23 => 17 } }, 'defaulted parameter'],
    ['@define foo($x, $y = undef) { $x $y }; foo foo(23)',
        { foo => { 23 => undef } }, 'undef defaulted parameter'],
    ['@define foo($x, $y = 17) { $x $y }; foo foo(23, undef)',
        { foo => { 23 => undef } }, 'undefined argument with default'],
    ['$x = 23; @define x() $x; foo [$x = 17; x()]',
        { foo => [23] }, 'original definition environment was used'],
    ['@define foo($x, $y = $x) [$x, $y]; foo [foo(23, 17), foo(23)]',
        { foo => [[23, 17], [23, 23]] }, 'accessing earlier arguments'],
);

test_err(RAD_DEFAULT, 'template errors',
    ['@define',
        qr{Missing call signature for `\@define`},
        'no signature'],
    ['@define [23] 23',
        qr{Signature needs to be in form of a call},
        'non-call signature'],
    ['@define foo()',
        qr{Missing call definition template for `\@define`},
        'no template'],
    ['@define foo($x, 23) 17',
        qr{Parameter.+in signature.+can only.+variables and default},
        'invalid parameter'],
    ['@define foo($x = 23, $y)',
        qr{Required parameter `\$y` can not come after optional},
        'required after optional'],
    ['@define foo($x) $x; bar foo(23, 17)',
        qr{Too many arguments for 'foo'},
        'too many arguments'],
    ['@define foo($x) $x; bar foo()',
        qr{Missing required argument 1 \(`\$x`\) for 'foo'},
        'missing required argument'],
    ['@define foo() 23 17',
        qr{Too many expressions for `\@define` directive},
        'too many expressions'],
);

test_for_cycles;

done_testing;
