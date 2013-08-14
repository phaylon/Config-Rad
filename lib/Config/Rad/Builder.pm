use strictures 1;

package Config::Rad::Builder;
use Moo;
use Try::Tiny;
use Config::Rad::Util qw( fail isa_hash );

use namespace::clean;

has functions => (is => 'ro', required => 1, isa => \&isa_hash);
has constants => (is => 'ro', required => 1, isa => \&isa_hash);

my %_builtin_const = (
    true => 1,
    false => 0,
    undef => undef,
);

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

sub construct {
    my ($self, $tree, $env) = @_;
    my ($type, $value, $loc) = @$tree;
    my $method = "_construct_$type";
    fail($loc, "Unexpected $type token")
        unless $self->can($method);
    return $self->$method($tree, {%$env});
}

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
        fail($loc, 'Arrays cannot contain keyed values')
            if @$part > 1;
        push @$struct, $self->construct($part->[0], $env);
    }
    return $struct;
}

sub _construct_topicalized {
    my ($self, $tree, $env) = @_;
    my ($type, $pair, $loc) = @$tree;
    my ($topic, $hash) = @$pair;
    my $val_hash = $self->construct($hash, $env);
    fail($loc, 'Can only topicalize hash references')
        unless ref($val_hash) eq 'HASH';
    return {
        _ => $self->_construct_auto_string($topic, $env),
        %$val_hash,
    };
}

sub _construct_bareword {
    my ($self, $tree) = @_;
    my $const = $tree->[1];
    my $value =
        exists($self->constants->{$const}) ? $self->constants->{$const}
      : exists($_builtin_const{$const}) ? $_builtin_const{$const}
      : fail($tree->[2], "Unknown constant '$const'");
    return $value;
}

sub _construct_call {
    my ($self, $tree, $env) = @_;
    my ($type, $call, $loc) = @$tree;
    my ($name, $parts) = @$call;
    my $name_str = $name->[1];
    my $callback = $self->functions->{$name_str}
        || $_builtin_fun{$name_str}
        or fail($loc, "Unknown function '$name_str'");
    my $args_ref = $self->construct(['array', $parts, $loc], $env);
    my $result;
    try {
        $result = $callback->(@$args_ref);
    }
    catch {
        chomp $_;
        fail($loc, "Error in '$name_str' callback: $_\n");
    };
    return $result;
}

sub _construct_string {
    my ($self, $tree, $env) = @_;
    my ($type, $items, $loc) = @$tree;
    return join '', map {
        my $item = $_;
        ref($item) ? $self->construct($item, $env) : $item;
    } @$items;
}

sub _construct_auto_string {
    my ($self, $tree, $env) = @_;
    return $tree->[1]
        if $tree->[0] eq 'bareword';
    return $self->construct($tree, $env);
}

sub _construct_variable {
    my ($self, $tree, $env) = @_;
    my ($type, $name, $loc) = @$tree;
    fail($loc, "Unknown variable '$name'")
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
    fail($loc, 'Left side of assignment has to be variable')
        unless @before == 1
            and $before[0][0] eq 'variable';
    fail($loc, 'Right side of assignment has to be single value')
        unless @after == 1;
    $env->{ $before[0][1] } = $self->construct($after[0], $env);
    return 1;
}

sub _handle_directive {
    my ($self, $part, $env) = @_;
    #use Data::Dump qw( pp );
    #pp $part;
    return 1
        if $part->[0] and $part->[0][0] eq 'item_comment';
    return 0;
}

sub _construct_hash {
    my ($self, $tree, $env) = @_;
    my ($type, $parts, $loc) = @$tree;
    my $struct = {};
    PART: for my $part (@$parts) {
        my @left = @$part;
        next PART
            if $self->_handle_directive($part, $env);
        next PART
            if $self->_variable_set($part, $env);
        my $value = pop @left;
        fail($loc, "Missing hash key names")
            unless @left;
        my $curr = $struct;
        while (my $key = shift @left) {
            my $str = $self->_construct_auto_string($key, $env);
            fail($loc, "Hash key is not a string")
                if ref $str or not defined $str;
            if (@left) {
                fail(
                    $loc,
                    "Key '$str' exists but is not a hash reference",
                ) if exists($curr->{$str})
                    and ref($curr->{$str}) ne 'HASH';
                $curr = $curr->{$str} ||= {};
            }
            else {
                fail($loc, "Value '$str' is already set")
                    if exists $curr->{$str};
                $curr->{$str} = $self->construct($value, $env);
            }
        }
    }
    return $struct;
}

1;
