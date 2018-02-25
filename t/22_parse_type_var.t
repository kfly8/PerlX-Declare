use strict;
use warnings;
use Test::More;
use PerlX::Declare;

my @OK = (
    '$foo'     => [undef, '$foo'],
    '@foo'     => [undef, '@foo'],
    '%foo'     => [undef, '%foo'],
    '  $foo'   => [undef, '$foo'],
    '$foo  '   => [undef, '$foo  '],
    '  $foo  ' => [undef, '$foo  '],

    '$Foo::Bar::foo' => [undef, '$Foo::Bar::foo'],

    'Str $foo'      => ['Str', '$foo'],
    'Int8 $foo'     => ['Int8', '$foo'],

    '  Str $foo'    => ['Str', '$foo'],
    'Str  $foo'     => ['Str', '$foo'],
    'Str $foo  '    => ['Str', '$foo  '],
    '  Str  $foo  ' => ['Str', '$foo  '],

    'Str $Foo::Bar::foo' => ['Str', '$Foo::Bar::foo'],
);

my @NG = (
    'foo',
    'Str Str $foo',
    'Foo::Bar $foo',
    '$str $foo',
);

sub check_ok {
    my ($expression, $expected) = @_;
    my $got = PerlX::Declare::_parse_type_var($expression);

    note "'$expression'";
    is $got->{type}, $expected->[0], "type: '@{[$expected->[0] || '']}'";
    is $got->{var}, $expected->[1], "var: '@{[$expected->[1]]}'";
}

sub check_ng {
    my $expression = shift;
    my $got = PerlX::Declare::_parse_type_var($expression);

    note "'$expression'";
    is $got, undef;
    note explain $got if $got;
}

subtest 'case ok' => sub {
    while (@OK) {
        check_ok(shift @OK, shift @OK)
    }
};

subtest 'case ng' => sub {
    check_ng($_) for @NG;
};

done_testing;
