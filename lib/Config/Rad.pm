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
    open my $fh, '<:utf8', $file
        or croak qq{Unable to open '$file': $!};
    my $string = do { local $/; <$fh> };
    return $self->parse_string($string, $file, %arg);
}

sub parse_string {
    my ($self, $source, $source_name, %arg) = @_;
    $source_name ||= join ':', (caller)[1, 2];
    my @tokens = $self->lexer
        ->tokenize($source, $source_name);
    my $mode = $arg{topmode} || $self->topmode;
    croak q{Invalid topmode: Must be 'hash' or 'array'}
        unless $mode->$_is_mode;
    my $tree = $self->parser
        ->inflate($mode, [$source_name, 1], \@tokens);
    my $struct = $self->builder
        ->construct($tree, $self->_prefixed_variables);
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
