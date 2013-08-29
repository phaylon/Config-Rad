use strictures 1;
use Test::More;
use Config::Rad::Test;

test_ok(RAD_DEFAULT, 'loading',
    ['@load "load-test.conf"; foo $testfoo',
        { foo => 23 }, 'variable access'],
    ['@load "load-test.conf"; foo testfunc(23)',
        { foo => { testresult => 23 } }, 'function access'],
    ['@load "load-test-rtvar.conf"; foo rtvar()',
        { foo => 99 },
        'runtime variable access',
        { variables => { rtvar => 99 } }],
    ['@load "load-test.conf"; foo level2def()',
        { foo => 99 },
        'second level include access and definition',
        { variables => { rtvar => 99 } }],
);

test_err(RAD_DEFAULT_NOINC, 'loading errors without include paths',
    ['@load "load-test.conf"',
        qr{Unable to reference.+ 'load-test.conf' without include_paths},
        'cannot load without paths'],
);

test_err(RAD_DEFAULT, 'loading errors with include paths',
    ['@load "nofile.conf"',
        qr{Unable to find file 'nofile.conf' in include_paths},
        'unknown file'],
);

test_err(RAD_DEFAULT, 'errors in loaded file',
    ['@load "load-test-fail-withdata.conf"',
        [qr{Cannot construct data in data-less environment},
            1, qr{conf/load-test-fail-withdata\.conf}],
        'data in loaded file'],
    ['@define outerfoo($n) $n; @load "load-test-fail-outerenv.conf"',
        [qr{Unknown function 'outerfoo'},
            1, qr{conf/load-test-fail-outerenv\.conf}],
        'loading env not available'],
    ['$outervar = 99; @load "load-test-fail-outervar.conf"; x foo()',
        [qr{Unknown variable '\$outervar'},
            1, qr{conf/load-test-fail-outervar\.conf}],
        'var in loading env not available'],
);

test_for_cycles;

done_testing;
