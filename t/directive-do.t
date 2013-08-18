use strictures 1;
use Test::More;
use Config::Rad::Test;

my @collect;
my $rad = Config::Rad->new(
    functions => {
        collect => sub { push @collect, @_ },
    },
    variables => {
        collected => \@collect,
    },
);

test_ok($rad, 'usage',
    ['@do 23', {}, 'simple'],
    ['@do collect(23); @do collect(17); foo $collected',
        { foo => [23, 17] }, 'order'],
);

test_err(RAD_DEFAULT, 'errors',
    ['@do',
        qr{Missing expression for `\@do` directive},
        'missing expression'],
    ['@do 23 17',
        qr{Too many expressions for `\@do` directive},
        'too many expressions'],
);

done_testing;
