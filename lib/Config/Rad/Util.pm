use strictures 1;

package Config::Rad::Util;
use Exporter 'import';

our @EXPORT_OK = qw( fail isa_hash );

sub isa_hash {
    die "Not a hash reference\n"
        unless ref $_[0] eq 'HASH';
}

sub fail {
    my ($loc, @msg) = @_;
    die sprintf "Config Error: %s at %s line %s.\n",
        join('', @msg),
        @$loc;
}

1;
