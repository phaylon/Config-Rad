use strictures 1;

package Config::Rad;
use Moo;
use Carp qw( croak );
use Config::Rad::Util qw( isa_hash isa_array fail );
use Path::Tiny;
use Scalar::Util qw( weaken );

use Config::Rad::Lexer;
use Config::Rad::Parser;
use Config::Rad::Builder;

use namespace::clean;

our $VERSION = '0.001';
$VERSION = eval $VERSION;

my %_valid_mode = map { ($_, 1) } qw( hash array nodata );

my $_is_mode = sub {
    defined($_[0]) and $_valid_mode{$_[0]};
};

has _topmode => (
    is => 'ro',
    default => sub { 'hash' },
    init_arg => 'topmode',
    isa => sub {
        die "Must be either 'hash' or 'array'\n"
            unless $_[0]->$_is_mode;
    },
);

has _include_paths => (
    is => 'ro',
    default => sub { [] },
    isa => \&isa_array,
    init_arg => 'include_paths',
);

has _lexer => (is => 'lazy', init_arg => undef);
has _parser => (is => 'lazy', init_arg => undef);
has _builder => (is => 'lazy', init_arg => undef);

has _functions => (
    is => 'ro',
    default => sub { {} },
    isa => \&isa_hash,
    init_arg => 'functions',
);

has _constants => (
    is => 'ro',
    default => sub { {} },
    isa => \&isa_hash,
    init_arg => 'constants',
);

has _variables => (
    is => 'ro',
    default => sub { {} },
    isa => \&isa_hash,
    init_arg => 'variables',
);

has _cache => (is => 'ro', init_arg => 'cache');
has _cache_store => (is => 'ro', default => sub { {} }, init_arg => undef);

sub _build__parser { Config::Rad::Parser->new }
sub _build__lexer { Config::Rad::Lexer->new }

sub _build__builder {
    my ($self) = @_;
    return Config::Rad::Builder->new(
        functions => $self->_functions,
        constants => $self->_constants,
        loader => do {
            my $wself = $self;
            weaken $wself;
            sub {
                my ($mode, $struct, $env, $loc, $file) = @_;
                my $path = $wself->_find_include_file($loc, $file);
                return $wself->parse_file(
                    $path,
                    topmode => $mode,
                    _topenv => $env,
                    _topstruct => $struct,
                );
            };
        },
    );
}

sub _find_include_file {
    my ($self, $loc, $file) = @_;
    my @roots = @{ $self->_include_paths };
    fail($loc, qq{Unable to reference file '$file' without include_paths})
        unless @roots;
    for my $root (@roots) {
        my $path = path($root)->child($file);
        if (-e $path) {
            return $path;
        }
    }
    fail($loc, qq{Unable to find file '$file' in include_paths});
}

sub parse_file {
    my ($self, $file, %arg) = @_;
    my $string;
    unless ($self->_cache_store->{$file}) {
        open my $fh, '<:utf8', $file
            or croak qq{Unable to open '$file': $!};
        $string = do { local $/; <$fh> };
    }
    return $self->parse_string($string, $file, %arg);
}

sub parse_string {
    my ($self, $source, $source_name, %arg) = @_;
    $source_name = join ':', (caller)[1, 2]
        unless defined $source_name;
    return $self->_construct($source, $source_name, %arg);
}

sub _tokenize {
    my ($self, $source, $source_name, %arg) = @_;
    return [$self->_lexer->tokenize($source, $source_name)];
}

sub _parse {
    my ($self, $source, $source_name, %arg) = @_;
    my $tokens = $self->_tokenize($source, $source_name, %arg);
    my $mode = $arg{topmode} || $self->_topmode;
    croak q{Invalid topmode: Must be 'hash' or 'array'}
        unless $mode->$_is_mode;
    my $tree = $self->_parser
        ->inflate($mode, [$source_name, 1], $tokens);
    return $tree;
}

sub _construct {
    my ($self, $source, $source_name, %arg) = @_;
    my $tree;
    if ($self->_cache) {
        $tree = $self->_cache_store->{$source_name};
    }
    unless ($tree) {
        $tree = $self->_parse($source, $source_name, %arg);
    }
    if ($self->_cache) {
        $self->_cache_store->{$source_name} = $tree;
    }
    my $struct = $self->_builder->construct(
        $tree,
        $self->_make_root_env(%arg),
        _topstruct => $arg{_topstruct},
    );
    return $struct;
}

sub _make_root_env {
    my ($self, %arg) = @_;
    return $arg{_topenv}
        if defined $arg{_topenv};
    my $rt_func = $arg{functions};
    my $rt_const = $arg{constants};
    my $rt_var = $arg{variables};
    my $env = {
        var => {
            %{ $self->_prefixed_variables($self->_variables) },
            %{ $self->_prefixed_variables($rt_var || {}) },
        },
        func => $rt_func || {},
        const => $rt_const || {},
        topic => '_',
    };
    return {
        %$env,
        root => $env,
        var => { %{ $env->{var} } },
        func => { %{ $env->{func} } },
        const => { %{ $env->{const} } },
        templates => {},
    };
}

sub _prefixed_variables {
    my ($self, $vars) = @_;
    return {
        map { (join('', '$', $_), $vars->{$_}) }
        keys %$vars,
    };
}

1;

__END__

=head1 NAME

Config::Rad - Flexible Configurations

=head1 SYNOPSIS

    use Config::Rad;

    my $rad = Config::Rad->new(
        variables => { foo => 23 },
        functions => { debug => sub { warn "DEBUG: @_\n" } },
    );

    my $data = $rad->parse_file('foo.conf');

=head1 DESCRIPTION

This module provides a configuration description language that is
optimized for loading complex, custom data structures.

=head1 CONFIGURATION SYNTAX

The syntax is heavily inspired by Perl's own syntax. Different elements
are separated by semicolons (C<;>) or commas (C<,>). You can use either
at any level to separate different data elements.

Example:

    # with semicolons
    foo 23;
    bar 17;

    # with commas
    foo 23,
    bar 17,

Directives are special elements that are prefixed with a C<@>. These
can have various effects on the produced data.

=head2 Topmodes

Every configuration must have a topmode. This determines what kind of
data structure the configuration will be at its top level. The default
is C<hash>. You can set it to C<array> if you want the top level to be
treated like an array.

The rules for the top level syntax are the same as the rules for the
contents of L</Arrays> and L</Hashes>.

You can set a default topmode by giving the L</new> constructor a
C<topmode> argument or by passing a C<topmode> value to one of the
C<parse_*> methods.

=head2 Hashes

Hashes are delimited by C<{> and C<}>. Hash values are declared with
a set of keys followed by a value. If the keys are barewords, they will
be autoquoted and not interpreted as constants.

Examples:

    # $data->{point} = { x => 23, y => 17 }
    point {
        x 23;
        y 17;
    };

    # $data->{limit} = 23
    limit 23;

    # $data->{option}{show} = 1
    option show true;

    # $data->{ $key }{ subkey() } = 99
    $key subkey() 99;

=head2 Hash Topicalization

Hashes can be created in a topicalized manner. You can prefix the
hash with a value and a double colon (C<:>) to set that value as topic
key in the hash.

Examples:

    # without topicalization
    directory {
        path '/foo/bar';
        handler 'Foo::Bar';
    };

    # with topicalization
    @topic 'path';
    directory '/foo/bar': {
        handler 'Foo::Bar';
    };

The default topic is C<_>. The L</@topic> value is lexically
available in all lower topicalizations. The directive can also appear
anywhere, not only in hash contexts.

=head2 Arrays

Arrays are delimited with C<[> and C<]>. The elements are specified
as single values. Trying to specify keys will result in an error.

Examples:

    # using semicolons as separators
    arguments [
        23;
        bar();
        $baz;
    ];

    # using commas
    arguments [23, bar(), $baz];

=head2 Variables

You can declare lexical variables in any scope. The declaration
consists of a variable name, an assignment operator C<=> and the
value to be assigned. You cannot change a variable once it has been
declared. If you redeclare it, you will generate a new variable
shadowing the old one.

Example:

    $key = 'somekey';
    foo {
        $val = 'someval';
        $key $val;
    };

=head2 Strings

=over

=item Single quoted/Single line

A single quoted single line string is delimited by C<'> on both ends.
It cannot be broken across multiple lines. Special characters and
variables will not be interpolated. You can only escape backslashes
(C<\\>) and single quotes (C<\'>).

Examples:

    # simple
    foo 'bar';

    # escaped backslash and single quotes
    bar '\\baz \'x\'';

=item Double quoted/Single line

A double quoted single line string is delimited by C<"> on both ends.
It cannot be broken across multiple lines. You can interpolate the
special characters C<\n>, C<\t>, C<\r>. You can escape double quotes
(C<\">), backslashes (C<\\>) and variable sigils (C<\$>)

You can interpolate variables by delimiting them with C<${> and C<}>.

Examples:

    # simple
    foo "bar";

    # interpolation
    bar "foo\n${bar}\t\"baz\"";

=item Multi line Variants

The multiline variants are delimited by C<'''> for single quoted strings
and C<"""> for double quoted strings. The interpolation rules are the
same as for the single line variants.

Additionally, certain whitespace cleanups will be performed. Trailing
and tailing whitespace will be removed. The first line will be removed
if it is empty. The text will also be de-indented based on the line
with the least indentation (ignoring empty lines).

Examples:

    # "bar\n    baz\nqux\n"
    foo '''
        bar
            baz
        qux
    ''';

    # "bar\n    $baz1\n$baz2\nqux\n"
    foo """
        bar
            ${baz1}\n${baz2}
        qux
    """;

=back

=head2 Numbers

Integers are composed of digits, optionally separated by underscores
(C<_>). Floating point numbers use C<.>. Only decimal numbers are
allowed. Negative numbers are prefixed with C<->.

Examples:

    foo 23;
    bar 23.17;
    baz -0.5;
    qux 23_500_000;


=head2 Function Calls

Functions are called with an identifier followed by an argument list
delimited by C<(> and C<)>.

Examples:

    foo func();
    bar func(23, 17);
    baz func(23; 17);
    qux func(23, {
        x 17;
    });

=head2 Builtin Functions

The following functions are always available:

=over

=item str

    str($arg1, $arg2, ...)

Concatenates all arguments into a single string.

=item env

    env($key)

Accesses the environment variable C<$key>.

=back

=head2 Constants

Any identifier that is not auto-quoted or part of other syntax (like
function calls) is regarded as a constant.

=head2 Builtin Constants

The following constants are always available:

=over

=item true

Returns a numeric C<1>.

=item false

Returns a numeric C<0>.

=item undef

Returns an undefined value.

=back

=head2 Comments

All content after a number sign (C<#>) is ignored, just like in Perl.

Additionally, you can use the item comment directive C<@@> to ignore
a full element, possible spanning multiple lines.

Examples:

    # this is a comment
    ### this is also a comment

    # the following element will be ignored, only C<bar> will exist
    @@ foo {
        x 23;
    };
    bar {
        y 17;
    };

=head2 Templates

You can define reusable data templates with the C<@define> directive.
They are declared with a call signature containg names and parameters.
Parameters are specified as lexical variables, or variable declarations
if a default should be available.

You can invoke a defined template just like you would with a function.
The environment of the definition will be captured and used when the
template is evaluated.

Examples:

    # hash template
    @define foo($n) {
        foo bar $n;
    };
    value foo(23);

    # function call template with default
    @define foo($n = 23) func($n);
    bar foo();
    baz foo(17);

=head2 Loading External Definitions

You can use the C<@load> directive to load definitions (but not data)
from a different file. If the external file contains data definitions,
an error will be thrown. This is useful for shared libraries of
variables and templates.

You will need to pass C<include_paths> to L</new> to be able to load
external definitions.

Example:

    # inc.conf
    @define foo($n) [$n, bar($n)];
    $bar = 23;

    # main.conf
    @load 'inc.conf';
    value foo($bar);

=head2 Ignoring Data

If you want to just evaluate an expression (usually a function call)
without putting the value somewhere in the data structure, you can use
the C<@do> directive.

Example:

    @do register($someobj);

=head1 METHODS

=head2 new

    my $rad = Config::Rad->new(%arguments);

Constructs a new instance. Possible arguments are:

=over

=item topmode

Specifies the data mode the topmost level should be in. Can be either
C<hash> or C<array>. Defaults to C<hash>.

=item include_paths

An array reference of directories that should be searched when trying
to include other files.

=item functions

A hash reference containing functions that should be available.

=item constants

A hash reference containing constants that should be available.

=item variables

A hash reference containing variables that should be available.

=item cache

A boolean indicating whether abstract trees used to generate the data
should be cached. Defaults to false.

=back

=head2 parse_file

    my $data = $rad->parse_file($path, %arguments);

Loads the configuration file specified by C<$path>.

The C<%arguments> can contain C<topmode>, C<constants>, C<functions> and
C<variables> values as specified for L</new>.

=head2 parse_string

    my $data = $rad->parse_string($config, $name, %arguments);

Loads the configuration in the string C<$config>. The C<$name> argument
will be used for error messages. It defaults to the caller C<$file:$line>
if it's not defined.

The C<%arguments> can contain C<topmode>, C<constants>, C<functions> and
C<variables> values as specified for L</new>.

=head1 EXAMPLES

=head2 A Catalyst model

Demonstrating a generic hash structure and a function call.

    'Model::DB' {
        schema_class 'MyApp::Schema';
        connect_info {
            $HOME = env('HOME');
            dsn "dbi:SQLite:dbname=${HOME}/myapp/storage.db";
        };
    };

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
