use strictures 1;
use Test::More;
use Config::Rad::Test;

my @_array_topmodes = (
    [RAD_ARRAY, 'array topmode'],
    [RAD_RT_ARRAY, 'runtime array topmode'],
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
    test_err($rad, 'array topmode errors',
        ['foo 23',
            qr{Arrays cannot contain keyed values}, 'keyed value'],
        ['a b 23',
            qr{Arrays cannot contain keyed values}, 'keyed values'],
    );
}

test_ok(RAD_DEFAULT, 'array containers',
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

test_err(RAD_DEFAULT, 'array container errors',
    ['foo [bar 23]',
        qr{Arrays cannot contain keyed values}, 'keyed value'],
    ['foo [23, 17]]',
        qr{Unexpected closing '\]'}, 'unopened array'],
    ['foo [23,',
        qr{Unclosed array reached end of input}, 'unclosed array'],
);

test_for_cycles;

done_testing;
