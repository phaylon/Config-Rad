use strictures 1;

package Config::Rad;
use Moo;
use Carp qw( croak );
use Config::Rad::Util qw( isa_hash );

use Config::Rad::Lexer;
use Config::Rad::Parser;
use Config::Rad::Builder;

use namespace::clean;

our $VERSION = '0.001';
$VERSION = eval $VERSION;

my $_is_mode = sub {
    defined($_[0]) and ($_[0] eq 'hash' or $_[0] eq 'array');
};


has topmode => (
    is => 'ro',
    default => sub { 'hash' },
    isa => sub {
        die "Must be either 'hash' or 'array'\n"
            unless $_[0]->$_is_mode;
    },
);

has lexer => (is => 'lazy', init_arg => undef);
has parser => (is => 'lazy', init_arg => undef);
has builder => (is => 'lazy', init_arg => undef);
has functions => (is => 'ro', default => sub { {} }, isa => \&isa_hash);
has constants => (is => 'ro', default => sub { {} }, isa => \&isa_hash);
has variables => (is => 'ro', default => sub { {} }, isa => \&isa_hash);
has cache => (is => 'ro');
has cache_store => (is => 'ro', default => sub { {} }, init_arg => undef);

sub _build_parser { Config::Rad::Parser->new }
sub _build_lexer { Config::Rad::Lexer->new }

sub _build_builder {
    my ($self) = @_;
    return Config::Rad::Builder->new(
        functions => $self->functions,
        constants => $self->constants,
    );
}

sub parse_file {
    my ($self, $file, %arg) = @_;
    my $string;
    unless ($self->cache_store->{$file}) {
        open my $fh, '<:utf8', $file
            or croak qq{Unable to open '$file': $!};
        $string = do { local $/; <$fh> };
    }
    return $self->parse_string($string, $file, %arg);
}

sub parse_string {
    my ($self, $source, $source_name, %arg) = @_;
    $source_name ||= join ':', (caller)[1, 2];
    return $self->_construct($source, $source_name, %arg);
}

sub _tokenize {
    my ($self, $source, $source_name, %arg) = @_;
    return [$self->lexer->tokenize($source, $source_name)];
}

sub _parse {
    my ($self, $source, $source_name, %arg) = @_;
    my $tokens = $self->_tokenize($source, $source_name, %arg);
    my $mode = $arg{topmode} || $self->topmode;
    croak q{Invalid topmode: Must be 'hash' or 'array'}
        unless $mode->$_is_mode;
    my $tree = $self->parser
        ->inflate($mode, [$source_name, 1], $tokens);
    return $tree;
}

sub _construct {
    my ($self, $source, $source_name, %arg) = @_;
    my $tree;
    if ($self->cache) {
        $tree = $self->cache_store->{$source_name};
    }
    unless ($tree) {
        $tree = $self->_parse($source, $source_name, %arg);
    }
    if ($self->cache) {
        $self->cache_store->{$source_name} = $tree;
    }
    my $struct = $self->builder
        ->construct($tree, $self->_make_root_env(%arg));
    return $struct;
}

sub _make_root_env {
    my ($self, %arg) = @_;
    my $rt_func = $arg{functions};
    my $rt_const = $arg{constants};
    my $rt_var = $arg{variables};
    return {
        %{ $self->_prefixed_variables($self->variables) },
        %{ $self->_prefixed_variables($rt_var || {}) },
        func => $rt_func || {},
        const => $rt_const || {},
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
