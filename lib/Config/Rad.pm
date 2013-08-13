use strictures 1;

package Config::Rad;
use Moo;
use Carp qw( croak );
use Try::Tiny;

use namespace::clean;

our $VERSION = '0.001';
$VERSION = eval $VERSION;

my $_is_mode = sub {
    defined($_[0]) and ($_[0] eq 'hash' or $_[0] eq 'array');
};

my $_isa_hash = sub {
    die "Not a hash reference\n"
        unless ref $_[0] eq 'HASH';
};

has topmode => (
    is => 'ro',
    default => sub { 'hash' },
    isa => sub {
        die "Must be either 'hash' or 'array'\n"
            unless $_[0]->$_is_mode;
    },
);

has functions => (is => 'ro', default => sub { {} }, isa => $_isa_hash);
has constants => (is => 'ro', default => sub { {} }, isa => $_isa_hash);
has variables => (is => 'ro', default => sub { {} }, isa => $_isa_hash);

my $_rx_ident = qr{ [a-z_] [a-z0-9_]* }ix;
my $_rx_int = qr { [0-9]+ (?: _ [0-9]+ )* }x;

sub parse_file {
    my ($self, $file, %arg) = @_;
    open my $fh, '<:utf8', $file
        or croak qq{Unable to open '$file': $!};
    my $string = do { local $/; <$fh> };
    return $self->parse_string($string, $file, %arg);
}

sub parse_string {
    my ($self, $source, $source_name, %arg) = @_;
    $source_name ||= join ':', (caller)[1, 2];
    my @tokens = $self->_tokenize($source, $source_name);
    my $mode = $arg{topmode} || $self->topmode;
    croak q{Invalid topmode: Must be 'hash' or 'array'}
        unless $mode->$_is_mode;
    my $tree = $self->_inflate($mode, [$source_name, 1], \@tokens);
    my $struct = $self->_construct($tree, $self->_prefixed_variables);
    return $struct;
}

sub _prefixed_variables {
    my ($self) = @_;
    my $vars = $self->variables;
    return {
        map { (join('', '$', $_), $vars->{$_}) }
        keys %$vars,
    };
}

sub _construct {
    my ($self, $tree, $env) = @_;
    my ($type, $value, $loc) = @$tree;
    my $method = "_construct_$type";
    $self->_fail($loc, "Unexpected $type token")
        unless $self->can($method);
    return $self->$method($tree, {%$env});
}

my %_key_type = map { ($_, 1) } qw(
    bareword
    string
    number
);

sub _construct_number {
    my ($self, $item) = @_;
    return 0 + $item->[1];
}

sub _construct_array {
    my ($self, $tree, $env) = @_;
    my ($type, $parts, $loc) = @$tree;
    my $struct = [];
    PART: for my $part (@$parts) {
        next PART
            if $self->_variable_set($part, $env);
        $self->_fail($loc, 'Arrays cannot contain keyed values')
            if @$part > 1;
        push @$struct, $self->_construct($part->[0], $env);
    }
    return $struct;
}

sub _construct_topicalized {
    my ($self, $tree, $env) = @_;
    my ($type, $pair, $loc) = @$tree;
    my ($topic, $hash) = @$pair;
    my $val_hash = $self->_construct($hash, $env);
    $self->_fail($loc, 'Can only topicalize hash references')
        unless ref($val_hash) eq 'HASH';
    return {
        _ => $self->_construct_auto_string($topic, $env),
        %$val_hash,
    };
}

my %_builtin_const = (
    true => 1,
    false => 0,
    undef => undef,
);

sub _construct_bareword {
    my ($self, $tree) = @_;
    my $const = $tree->[1];
    my $value =
        exists($self->constants->{$const}) ? $self->constants->{$const}
      : exists($_builtin_const{$const}) ? $_builtin_const{$const}
      : $self->_fail($tree->[2], "Unknown constant '$const'");
    return $value;
}

my %_builtin_fun = (
    str => sub {
        die "Unable to stringify undefined value\n"
            if grep { not defined } @_;
        return join '', @_;
    },
    env => sub {
        die "Missing variable name argument\n"
            unless @_;
        die "Variable name argument is undefined\n"
            unless defined $_[0];
        die "Too many arguments\n"
            if @_ > 1;
        return $ENV{$_[0]};
    },
);

sub _construct_call {
    my ($self, $tree, $env) = @_;
    my ($type, $call, $loc) = @$tree;
    my ($name, $parts) = @$call;
    my $name_str = $name->[1];
    my $callback = $self->functions->{$name_str}
        || $_builtin_fun{$name_str}
        or $self->_fail($loc, "Unknown function '$name_str'");
    my $args_ref = $self->_construct(['array', $parts, $loc], $env);
    my $result;
    try {
        $result = $callback->(@$args_ref);
    }
    catch {
        chomp $_;
        $self->_fail($loc, "Error in '$name_str' callback: $_\n");
    };
    return $result;
}

sub _construct_string {
    my ($self, $tree, $env) = @_;
    my ($type, $items, $loc) = @$tree;
    return join '', map {
        my $item = $_;
        ref($item) ? $self->_construct($item, $env) : $item;
    } @$items;
}

sub _construct_auto_string {
    my ($self, $tree, $env) = @_;
    return $tree->[1]
        if $tree->[0] eq 'bareword';
    return $self->_construct($tree, $env);
}

sub _construct_variable {
    my ($self, $tree, $env) = @_;
    my ($type, $name, $loc) = @$tree;
    $self->_fail($loc, "Unknown variable '$name'")
        unless exists $env->{$name};
    return $env->{$name};
}

sub _variable_set {
    my ($self, $items, $env) = @_;
    my (@before, $assign, @after);
    for my $item (@$items) {
        if ($item->[0] eq 'assign') {
            $assign = $item;
        }
        else {
            if ($assign) {
                push @after, $item;
            }
            else {
                push @before, $item;
            }
        }
    }
    return 0
        unless $assign;
    my $loc = $assign->[2];
    $self->_fail($loc, 'Left side of assignment has to be variable')
        unless @before == 1
            and $before[0][0] eq 'variable';
    $self->_fail($loc, 'Right side of assignment has to be single value')
        unless @after == 1;
    $env->{ $before[0][1] } = $self->_construct($after[0], $env);
    return 1;
}

sub _construct_hash {
    my ($self, $tree, $env) = @_;
    my ($type, $parts, $loc) = @$tree;
    my $struct = {};
    PART: for my $part (@$parts) {
        my @left = @$part;
        next PART
            if $self->_variable_set($part, $env);
        my $value = pop @left;
        $self->_fail($loc, "Missing hash key names")
            unless @left;
        my $curr = $struct;
        while (my $key = shift @left) {
            my $str = $self->_construct_auto_string($key, $env);
            $self->_fail($loc, "Hash key is not a string")
                if ref $str or not defined $str;
            if (@left) {
                $self->_fail(
                    $loc,
                    "Key '$str' exists but is not a hash reference",
                ) if exists($curr->{$str})
                    and ref($curr->{$str}) ne 'HASH';
                $curr = $curr->{$str} ||= {};
            }
            else {
                $self->_fail($loc, "Value '$str' is already set")
                    if exists $curr->{$str};
                $curr->{$str} = $self->_construct($value, $env);
            }
        }
    }
    return $struct;
}

sub _fail {
    my ($self, $loc, @msg) = @_;
    die sprintf "Config Error: %s at %s line %s.\n",
        join('', @msg),
        @$loc;
}

sub _partition {
    my ($self, @items) = @_;
    my @parts;
    my @buffer;
    for my $item (@items) {
        if ($item->[0] eq 'separator') {
            push @parts, [@buffer]
                if @buffer;
            @buffer = ();
        }
        else {
            push @buffer, $item;
        }
    }
    push @parts, [@buffer]
        if @buffer;
    return @parts;
}

my %_primitive = map { ($_ => 1) } qw(
    bareword
    string
    number
);

my %_closer = map { ($_ => 1) } qw(
    array_close
    hash_close
    call_close
);

sub _inflate_element {
    my ($self, @items) = @_;
    my @parts = $self->_partition(@items);
    return @parts;
}

sub _inflate_next {
    my ($self, $stream) = @_;
    my $next = shift @$stream;
    my $type = $next->[0];
    my $loc = $next->[2];
    my $done;
    if ($type eq 'hash_open') {
        $done = $self->_inflate('hash', $loc, $stream, 'hash_close');
    }
    elsif ($type eq 'array_open') {
        $done = $self->_inflate('array', $loc, $stream, 'array_close');
    }
    elsif ($_closer{$type}) {
        $self->_fail(
            $loc,
            "Unexpected closing '",
            $next->[1],
            "'",
        );
    }
    elsif ($type eq 'call_open') {
        $self->_fail($loc, "Unexpected opening '('");
    }
    elsif ($type eq 'bareword') {
        my $peek = $stream->[0];
        if ($peek and $peek->[0] eq 'call_open') {
            shift @$stream;
            $done = $self->_inflate(
                'call',
                [@$loc],
                $stream,
                'call_close',
            );
            $done = [$done->[0], [$next, $done->[1]], $done->[2]];
        }
    }
    elsif ($type eq 'topic') {
        $self->_fail($loc, "Unexpected topicalization");
    }
    $done ||= $next;
    if (@$stream and $stream->[0][0] eq 'topic') {
        my $topic = shift @$stream;
        $self->_fail($topic->[2], "Missing topicalized value")
            unless @$stream;
        my $topicalized = $self->_inflate_next($stream);
        return [
            'topicalized',
            [$done, $topicalized],
            [@$loc],
        ];
    }
    return $done;
}

sub _inflate {
    my ($self, $mode, $loc, $stream, $closer) = @_;
    my @done;
    while (@$stream) {
        my $item = $stream->[0];
        if ($closer and $item->[0] eq $closer) {
            shift @$stream;
            return [$mode, [$self->_inflate_element(@done)], [@$loc]];
        }
        push @done, $self->_inflate_next($stream);
    }
    unless ($closer) {
        return [$mode, [$self->_inflate_element(@done)], $loc];
    }
    $self->_fail($loc, "Unclosed $mode reached end of input");
}

my @_tokens = (
    map {
        ref($_->[1])
        ? $_ 
        : [$_->[0], qr{\Q$_->[1]\E}, @{$_}[2 .. $#$_]]
    }
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
    $self->_fail(
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
                $self->_fail($loc, "Unknown escape sequence '\\$1'");
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
    $self->_fail(
        $loc,
        'Double quoted string reached end of line without termination',
    );
}

sub _tokenize {
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
        $self->_fail($loc, "Unable to parse: `$last_line`");
    }
    return @found;
}

1;

__END__

=head1 NAME

Config::Rad - Flexible Configurations

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 CONFIGURATION SYNTAX

=head2 Topmodes

=head2 Hashes

=head2 Arrays

=head2 Values

=head2 Function Calls

=head2 Constants

=head2 Variables

=head1 METHODS

=head1 ATTRIBUTES

=head1 EXAMPLES

=head1 AUTHOR

 Robert Sedlacek <rs@474.at>

=head1 CONTRIBUTORS

None yet

=head1 COPYRIGHT

Copyright (c) 2013 the Config::Rad L</AUTHOR> and L</CONTRIBUTORS>
as listed above.

=head1 LICENSE

This library is free software and may be distributed under the same terms
as perl itself.

=cut
