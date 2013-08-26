use strictures 1;

package Config::Rad::Lexer;
use Moo;
use Config::Rad::Util qw( fail );

use namespace::clean;

my $_rx_ident = qr{ [a-z_] [a-z0-9_]* }ix;
my $_rx_int = qr { [0-9]+ (?: _ [0-9]+ )* }x;

my @_tokens = (
    map {
        ref($_->[1])
        ? $_ 
        : [$_->[0], qr{\Q$_->[1]\E}, @{$_}[2 .. $#$_]]
    }
    ['item_comment', '@@'],
    ['directive', qr{ \@ $_rx_ident }x],
    ['line_comment', qr{^\#[^\n]*}, discard => 1],
    ['whitespace', qr{\s|\n}, discard => 1],
    ['string', "'", descend => '_tokenize_string_q'],
    ['string', '"', descend => '_tokenize_string_qq'],
    ['hash_open', '{'],
    ['hash_close', '}'],
    ['array_open', '['],
    ['array_close', ']'],
    ['call_open', '('],
    ['call_close', ')'],
    ['separator', qr{,|;}],
    ['topic', ':'],
    ['assign', '='],
    ['bareword', $_rx_ident],
    ['variable', qr{ \$ $_rx_ident }x],
    ['number', qr{ -? $_rx_int (?: \. $_rx_int )? }x],
);

my %_escape_q = (
    "\\" => "\\",
    "'" => "'",
);

my %_escape_qq = (
    'n' => "\n",
    't' => "\t",
    'r' => "\r",
    "\\" => "\\",
    '"' => '"',
    '$' => '$',
);

sub _tokenize_string_q {
    my ($self, $source, $loc) = @_;
    my $done;
    while (length $$source) {
        if ($$source =~ s{^'}{}) {
            return [$done];
        }
        elsif ($$source =~ s{^\\(.)}{}) {
            if (exists $_escape_q{$1}) {
                $done .= $_escape_q{$1};
            }
            else {
                $done .= "\\$1";
            }
        }
        elsif ($$source =~ s{^\n}{}) {
            last;
        }
        else {
            $$source =~ s{^(.)}{}
                or die "Unable to advance string parse\n";
            $done .= $1;
        }
    }
    fail(
        $loc,
        'Single quoted string reached end of line without termination',
    );
}

sub _tokenize_string_qq {
    my ($self, $source, $loc) = @_;
    my @items = ('');
    my $push = sub {
        my ($item) = @_;
        if (ref $item) {
            push @items, $item;
        }
        else {
            if (ref $items[-1]) {
                push @items, $item;
            }
            else {
                $items[-1] .= $item;
            }
        }
    };
    while (length $$source) {
        if ($$source =~ s{^"}{}) {
            return \@items;
        }
        elsif ($$source =~ s{^\\(.)}{}) {
            if (exists $_escape_qq{$1}) {
                $push->($_escape_qq{$1});
            }
            else {
                fail($loc, "Unknown escape sequence '\\$1'");
            }
        }
        elsif ($$source =~ s{^\$\{($_rx_ident)\}}{}) {
            $push->(['variable', "\$$1", $loc]);
        }
        elsif ($$source =~ s{^\n}{}) {
            last;
        }
        else {
            $$source =~ s{^(.)}{}
                or die "Unable to advance string parse\n";
            $push->($1);
        }
    }
    fail(
        $loc,
        'Double quoted string reached end of line without termination',
    );
}

sub tokenize {
    my ($self, $source, $source_name) = @_;
    my $orig = $source;
    my $get_location = sub {
        my $done = substr $orig, 0, length($orig) - length($source);
        my @lines = length($done) ? (split m{\n}, $done, -1) : 1;
        my $line_num = @lines;
        return [$source_name, $line_num];
    };
    my @found;
    PARSE: while (length $source) {
        my $loc = $get_location->();
        TOKEN: for my $token (@_tokens) {
            my ($type, $rx, %arg) = @$token;
            if ($source =~ s{\A($rx)}{}) {
                next PARSE
                    if $arg{discard};
                if (my $method = $arg{descend}) {
                    push @found, [
                        $type,
                        $self->$method(\$source, $loc),
                        $loc,
                    ];
                }
                else {
                    push @found, [$type, $1, $loc];
                }
                next PARSE;
            }
        }
        my ($last_line) = split m{\n}, $source, -1;
        fail($loc, "Unable to parse: `$last_line`");
    }
    return @found;
}

1;
