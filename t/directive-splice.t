use strictures 1;
use Test::More;
use Config::Rad::Test;

test_ok(RAD_DEFAULT, 'splices',
    ['$s = { n 99 }; foo { x 17; @splice $s; y 23 }',
        { foo => { x => 17, y => 23, n => 99 } },
        'hash splicing'],
    ['$s = [2, 3, 4]; foo [17, @splice $s, 23]',
        { foo => [17, 2, 3, 4, 23] },
        'array splicing'],
    ['$s = [2, 3, 4]; foo str(17, @splice $s, 23)',
        { foo => '1723423' },
        'call argument splicing'],
);

test_ok(RAD_DEFAULT, 'toplevel hash splice',
    ['$s = { n 99 }; x 17; @splice $s; y 23',
        { x => 17, n => 99, y => 23 },
        'variable splice'],
);

test_ok(RAD_ARRAY, 'toplevel array splice',
    ['$s = [2, 3, 4]; 17; @splice $s; 23',
        [17, 2, 3, 4, 23],
        'variable splice'],
);

test_err(RAD_DEFAULT, 'splice errors',
    ['@splice',
        qr{Missing spliced value for `\@splice` directive},
        'missing value'],
    ['@splice {} undef',
        qr{Too many expressions for `\@splice` directive},
        'too many expressions'],
    (map {
        my ($val, $title) = @$_;
        [qq!\$s = $val; foo { \@splice \$s }!,
            qr{Can only splice hash references in hash context},
            "spliced $title"],
    } ['[]', 'array'],
      ['undef', 'undefined value'],
    ),
    (map {
        my ($val, $title) = @$_;
        [qq!\$s = $val; foo [ \@splice \$s ]!,
            qr{Can only splice array references in list context},
            "spliced $title"],
    } ['{}', 'hash'],
      ['undef', 'undefined value'],
    ),
);

test_for_cycles;

done_testing;
