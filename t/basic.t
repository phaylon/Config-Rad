use strictures 1;
use Test::More;
use Test::Fatal;
use File::Temp;
use Config::Rad::Test;

my @_test_cycles;

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
        RAD_DEFAULT->parse_string('', 'test config', topmode => 'list');
    }, qr{Invalid topmode: Must be 'hash' or 'array'},
        'invalid runtime topmode';
};

subtest 'file loading' => sub {
    do {
        my $tmp = File::Temp->new;
        print $tmp 'foo 23';
        close $tmp;
        my $data = RAD_DEFAULT->parse_file($tmp->filename);
        is_deeply $data, { foo => 23 }, 'config loaded from file';
    };
    like exception {
        RAD_DEFAULT->parse_file('_CONFIG_RAD_THISFILESHOULDNTEXIST');
    }, qr{Unable to open '_CONFIG_RAD_THISFILESHOULDNTEXIST':},
        'invalid file source';
    do {
        my $tmp = File::Temp->new;
        print $tmp 'foo $novar';
        close $tmp;
        my $fname = $tmp->filename;
        like exception { RAD_DEFAULT->parse_file($fname) },
            qr{Unknown variable '\$novar' at $fname line 1.},
            'file source name';
    };
};

subtest 'caching' => sub {
    my $rad = Config::Rad->new(cache => 1);
    push @_test_cycles, [$rad, 'caching instance'];
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

test_ok(RAD_DEFAULT, 'runtime elements',
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

test_err(RAD_DEFAULT, 'generic errors',
    ['foo bar:= {}',
        qr{Unexpected assign token `=`}, 'unexpected token'],
    ["foo\nbar\n:\n=\n{}",
        [qr{Unexpected assign token}, 4], 'unexpected multiline'],
    ['? 23', qr{Unable to parse: `\? 23`}, 'unknown char'],
    ['@fnord',
        qr{Invalid directive `\@fnord`}, 'unknown directive'],
);

test_for_cycles(@_test_cycles);

done_testing;
