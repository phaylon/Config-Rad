use strictures 1;

package Config::Rad::Parser;
use Moo;
use Config::Rad::Util qw( fail );

use namespace::clean;

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

sub inflate {
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
    fail($loc, "Unclosed $mode reached end of input");
}

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
        $done = $self->inflate('hash', $loc, $stream, 'hash_close');
    }
    elsif ($type eq 'array_open') {
        $done = $self->inflate('array', $loc, $stream, 'array_close');
    }
    elsif ($_closer{$type}) {
        fail(
            $loc,
            "Unexpected closing '",
            $next->[1],
            "'",
        );
    }
    elsif ($type eq 'call_open') {
        fail($loc, "Unexpected opening '('");
    }
    elsif ($type eq 'bareword') {
        my $peek = $stream->[0];
        if ($peek and $peek->[0] eq 'call_open') {
            shift @$stream;
            $done = $self->inflate(
                'call',
                [@$loc],
                $stream,
                'call_close',
            );
            $done = [$done->[0], [$next, $done->[1]], $done->[2]];
        }
    }
    elsif ($type eq 'topic') {
        fail($loc, "Unexpected topicalization");
    }
    $done ||= $next;
    if (@$stream and $stream->[0][0] eq 'topic') {
        my $topic = shift @$stream;
        fail($topic->[2], "Missing topicalized value")
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

1;
