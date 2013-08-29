use strictures 1;

package Config::Rad::Lexer;
use Moo;
use Config::Rad::Util qw( fail );
use List::Util qw( min );

use namespace::clean;

my $_rx_ident = qr{ [a-z_] [a-z0-9_]* }ix;
my $_rx_int = qr { [0-9]+ (?: _ [0-9]+ )* }x;

my $_is_num = sub {
    my ($value, $loc) = @_;
    fail($loc, 'Numbers cannot start with 0')
        if $value =~ m{^-?0(?:\d|_)};
    return 1;
};

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
    ['string', "'''", descend => '_tokenize_string_q'],
    ['string', "'", descend => '_tokenize_string_q'],
    ['string', '"""', descend => '_tokenize_string_qq'],
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
    ['number', qr{ -? $_rx_int (?: \. $_rx_int )? }x, check => $_is_num],
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

sub _multiline_collapse {
    my ($self, $multi, @lines) = @_;
    return ''
        unless @lines;
    return map { (@$_) } @lines
        unless $multi;
    $lines[0][0] =~ s{^\s*}{};
    splice @{ $lines[0] }, 0, 1
        if @{ $lines[0] } == 1 and $lines[0][0] eq "\n";
    $lines[-1][-1] =~ s{\s*$}{}
        unless ref $lines[-1][-1];
    my $min_indent = min(map {
        (@$_ == 1 and $_->[0] =~ m{^\s*$}) ? () : do {
            $_->[0] =~ m{^(\s*)};
            length($1);
        };
    } @lines);
    return map {
        my $first = $_->[0];
        my @rest = @{ $_ }[1 .. $#$_];
        $first =~ s!^\s{$min_indent}!!;
        ($first, @rest);
    } @lines;
}

sub _tokenize_string_q {
    my ($self, $source, $start_loc, $get_loc, $delim) = @_;
    my @lines;
    my $done = '';
    my $multiline = ($delim eq q('''));
    while (length $$source) {
        if ($$source =~ s{^$delim}{}) {
            push @lines, [$done]
                if length $done;
            return [$self->_multiline_collapse($multiline, @lines)];
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
            if ($multiline) {
                push @lines, ["$done\n"];
                $done = '';
            }
            else {
                last;
            }
        }
        else {
            $$source =~ s{^(.)}{}
                or die "Unable to advance string parse\n";
            $done .= $1;
        }
    }
    my $str_type = $multiline ? 'multiline string' : 'string';
    my $str_end = $multiline ? 'end of input' : 'end of line';
    fail(
        $start_loc,
        "Single quoted $str_type reached $str_end without termination",
    );
}

sub _tokenize_string_qq {
    my ($self, $source, $start_loc, $get_loc, $delim) = @_;
    my @items = ('');
    my @lines;
    my $multiline = ($delim eq q("""));
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
        my $loc = $get_loc->();
        if ($$source =~ s{^$delim}{}) {
            push @lines, [@items]
                if @items;
            return [$self->_multiline_collapse($multiline, @lines)];
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
            if ($multiline) {
                $push->("\n");
                push @lines, [@items];
                @items = ('');
            }
            else {
                last;
            }
        }
        else {
            $$source =~ s{^(.)}{}
                or die "Unable to advance string parse\n";
            $push->($1);
        }
    }
    my $str_type = $multiline ? 'multiline string' : 'string';
    my $str_end = $multiline ? 'end of input' : 'end of line';
    fail(
        $start_loc,
        "Double quoted $str_type reached $str_end without termination",
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
                my $value = $1;
                if (my $check = $arg{check}) {
                    $value->$check($loc);
                }
                next PARSE
                    if $arg{discard};
                if (my $method = $arg{descend}) {
                    push @found, [
                        $type,
                        $self->$method(
                            \$source,
                            $loc,
                            $get_location,
                            $value,
                        ),
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
