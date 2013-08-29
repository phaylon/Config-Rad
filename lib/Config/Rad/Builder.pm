use strictures 1;

package Config::Rad::Builder;
use Moo;
use Try::Tiny;
use Config::Rad::Util qw( fail fail_nested isa_hash isa_array );
use Scalar::Util qw( weaken );

use namespace::clean;

has functions => (is => 'ro', required => 1, isa => \&isa_hash);
has constants => (is => 'ro', required => 1, isa => \&isa_hash);
has loader => (is => 'ro', required => 1);

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

sub _child_env {
    my ($self, $env) = @_;
    return {
        %$env,
        func => { %{ $env->{func} || {} } },
        const => { %{ $env->{const} || {} } },
        template => { %{ $env->{template} || {} } },
        var => { %{ $env->{var} || {} } },
    };
}

sub _child_root_env {
    my ($self, $env) = @_;
    return $self->_child_env({ %{ $env->{root} }, root => $env->{root} });
}

sub construct {
    my ($self, $tree, $env, %arg) = @_;
    my ($type, $value, $loc) = @$tree;
    my $method = "_construct_$type";
    unless ($self->can($method)) {
        fail($loc,
            "Unexpected $type token",
            (defined($value) and not ref($value))
                ? " `$value`"
                : '',
        );
    }
    return $self->$method($tree, $env, %arg);
}

sub _construct_number {
    my ($self, $item) = @_;
    my $value = $item->[1];
    $value =~ s{_}{}g;
    return 0+$value;
}

sub _construct_nodata {
    my ($self, $tree, $env, %arg) = @_;
    my ($type, $parts, $loc) = @$tree;
    PART: for my $part (@$parts) {
        next PART if $self
            ->_handle_directive('nodata', $part, undef, $env);
        next PART
            if $self->_variable_set($part, $env);
        fail($loc, 'Cannot construct data in data-less environment');
    }
    return undef;
}

sub _construct_array {
    my ($self, $tree, $env, %arg) = @_;
    my ($type, $parts, $loc) = @$tree;
    my $struct = $arg{_topstruct} || [];
    my $child_env = $self->_child_env($env);
    PART: for my $part (@$parts) {
        next PART if $self
            ->_handle_directive('array', $part, $struct, $child_env);
        next PART
            if $self->_variable_set($part, $child_env);
        fail($loc, 'Arrays cannot contain keyed values')
            if @$part > 1;
        push @$struct, $self->construct($part->[0], $child_env);
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
        $env->{topic} => $self->_construct_auto_string($topic, $env),
        %$val_hash,
    };
}

sub _construct_bareword {
    my ($self, $tree, $env) = @_;
    my $const = $tree->[1];
    my $value =
        exists($env->{const}{$const}) ? $env->{const}{$const}
      : exists($self->constants->{$const}) ? $self->constants->{$const}
      : exists($_builtin_const{$const}) ? $_builtin_const{$const}
      : fail($tree->[2], "Unknown constant '$const'");
    return $value;
}

sub _construct_call {
    my ($self, $tree, $env) = @_;
    my ($type, $call, $loc) = @$tree;
    my ($name, $parts) = @$call;
    my $name_str = $name->[1];
    my $args_env = $self->_child_env($env);
    my $get_args = sub {
        my $args = $self->construct(['array', $parts, $loc], $args_env);
        return @$args;
    };
    if (my $template_def = $env->{template}{$name_str}) {
        my ($vars, $template, $sub_env) = @$template_def;
        my @args = $get_args->();
        fail($loc, "Too many arguments for '$name_str'")
            if @args > @$vars;
        my $call_env = $self->_child_env($sub_env);
        my $num = 0;
        for my $var_def (@$vars) {
            $num++;
            my ($var, $default) = @$var_def;
            my $arg = @args
                ? shift(@args)
                : defined($default)
                ? $self->construct($default, $call_env)
                : fail($loc,
                    "Missing required argument $num",
                    " (`$var`) for '$name_str'",
                );
            $call_env->{var}{$var} = $arg;
        }
        return $self->construct($template, $call_env);
    }
    my $callback = $env->{func}{$name_str}
        || $self->functions->{$name_str}
        || $_builtin_fun{$name_str}
        or fail($loc, "Unknown function '$name_str'");
    my $result;
    my @args = $get_args->();
    try {
        $result = $callback->(@args);
    }
    catch {
        chomp $_;
        fail_nested($loc, "Error in '$name_str' callback", $_);
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
        unless exists $env->{var}{$name};
    return $env->{var}{$name};
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
    my $var_name = $before[0][1];
    $env->{var}{ $var_name } = $self->construct($after[0], $env);
    return 1;
}

sub _handle_directive {
    my ($self, $mode, $part, $struct, $env) = @_;
    return 1
        if $part->[0] and $part->[0][0] eq 'item_comment';
    if ($part->[0] and $part->[0][0] eq 'directive') {
        my ($directive, @args) = @$part;
        my ($type, $value, $loc) = @$directive;
        (my $name = $value) =~ s{^\@}{};
        my $method = "_handle_${name}_directive";
        fail($loc, "Invalid directive `$value`")
            unless $self->can($method);
        $self->$method($mode, $struct, $env, $loc, @args);
        return 1;
    }
    return 0;
}

my @_seq_assign = qw( variable assign ? );

sub _destruct_signature {
    my ($self, $outer_loc, $env, $signature) = @_;
    fail($outer_loc, 'Signature needs to be in form of a call')
        unless $signature->[0] eq 'call';
    my (undef, $call, $loc) = @$signature;
    my ($name, $params) = @$call;
    $name = $name->[1];
    my @vars;
    my $in_optional;
    for my $param_idx (0 .. $#$params) {
        my $param_parts = $params->[$param_idx];
        if ($self->_match_sequence($param_parts, @_seq_assign)) {
            push @vars, [$param_parts->[0][1], $param_parts->[2]];
            $in_optional = 1;
        }
        elsif ($self->_match_sequence($param_parts, 'variable')) {
            my $var_name = $param_parts->[0][1];
            fail($loc,
                "Required parameter `$var_name` can not come after",
                ' optional parameters',
            ) if $in_optional;
            push @vars, [$var_name];
        }
        else {
            fail($loc,
                'Parameter specification in signature can only contain',
                ' variables and default assignments',
            );
        }
    }
    return $name, \@vars;
}

sub _match_sequence {
    my ($self, $parts, @types) = @_;
    for my $type_idx (0 .. $#types) {
        my $type = $types[ $type_idx ];
        last if $type eq '*';
        return 0 if @$parts < ($type_idx + 1);
        next if $type eq '?';
        return 0 if $parts->[$type_idx][0] ne $type;
    }
    return @$parts == @types ? 1 : 0;
}

sub _handle_topic_directive {
    my ($self, $mode, $struct, $env, $loc, $expr, @rest) = @_;
    fail($loc, 'Too many expressions for `@topic` directive')
        if @rest;
    fail($loc, 'Missing expression for `@topic` directive')
        unless $expr;
    my $topic = $self->construct($expr, $env);
    fail($loc, 'Value for `@topic` directive must be defined')
        unless defined $topic;
    $env->{topic} = $topic;
    return 1;
}

sub _handle_do_directive {
    my ($self, $mode, undef, $env, $loc, $expr, @rest) = @_;
    fail($loc, 'Too many expressions for `@do` directive')
        if @rest;
    fail($loc, 'Missing expression for `@do` directive')
        unless $expr;
    $self->construct($expr, $env);
    return 1;
}

sub _handle_define_directive {
    my ($self, $mode, undef, $env, $loc, $signature, $template, @rest) = @_;
    fail($loc, 'Too many expressions for `@define` directive')
        if @rest;
    fail($loc, 'Missing call signature for `@define`')
        unless $signature;
    my ($name, $var) = $self->_destruct_signature($loc, $env, $signature);
    fail($loc, 'Missing call definition template for `@define`')
        unless $template;
    my $sub_env = $self->_child_env($env);
    $env->{template}{$name} = [$var, $template, $sub_env];
    return 1;
}

my @_load_merge = (
    ['func', 'function'],
    ['template', 'defined function'],
    ['var', 'variable'],
);

sub _handle_load_directive {
    my ($self, $mode, undef, $env, $loc, $file, $args, @rest) = @_;
    fail($loc, 'Too many expressions for `@load` directive')
        if @rest;
    fail($loc, 'Missing path to file for `@load` directive')
        unless defined $file and length $file;
    my $file_path = $self->construct($file, $env);
    fail($loc, 'Path to file for `@load` directive must be defined')
        unless defined $file_path;
    my $load_env = $self->_child_root_env($env);
    $args = (defined($args) ? $self->construct($args, $env) : {});
    fail($loc, 'Arguments for loaded file have to be in a hash')
        unless ref $args eq 'HASH';
    $load_env->{var}{ '$' . $_ } = $args->{$_}
        for keys %$args;
    $self->loader->('nodata', undef, $load_env, $loc, $file_path, $args);
    for my $merge (@_load_merge) {
        my ($type, $title) = @$merge;
        for my $name (keys %{ $load_env->{$type} || {} }) {
            if ($type eq 'var') {
                (my $varname = $name) =~ s{^\$}{};
                next if exists $args->{$varname};
            }
            $env->{$type}{$name} = $load_env->{$type}{$name};
        }
    }
    return 1;
}

sub _construct_hash {
    my ($self, $tree, $env, %arg) = @_;
    my ($type, $parts, $loc) = @$tree;
    my $struct = $arg{_topstruct} || {};
    my $child_env = $self->_child_env($env);
    PART: for my $part (@$parts) {
        my @left = @$part;
        next PART if $self
            ->_handle_directive('hash', $part, $struct, $child_env);
        next PART
            if $self->_variable_set($part, $child_env);
        my $value = pop @left;
        fail($loc, "Missing hash key names")
            unless @left;
        my $curr = $struct;
        while (my $key = shift @left) {
            my $str = $self->_construct_auto_string($key, $child_env);
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
                $curr->{$str} = $self->construct($value, $child_env);
            }
        }
    }
    return $struct;
}

1;
