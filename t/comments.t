use strictures 1;
use Test::More;
use Config::Rad::Test;

test_ok(RAD_DEFAULT, 'line comments',
    ['# foo', {}, 'comment at start'],
    [' # foo', {}, 'comment after whitespace'],
    ["foo 23; # bar\nbaz 17",
        { foo => 23, baz => 17 }, 'comment ends at line end'],
    ["# foo\nbar 23", { bar => 23 }, 'data after comment'],
);

test_ok(RAD_DEFAULT, 'item comments',
    ['@@ 23; foo 17', { foo => 17 }, 'simple'],
    ["foo 23, @# bar {\nbaz 17\n};\nqux 99",
        { foo => 23, qux => 99 }, 'multiline item comment'],
);

test_err(RAD_DEFAULT, 'item comment errors',
    ['foo @@ 23', qr{Unexpected item_comment token}, 'misplaced'],
);

done_testing;
