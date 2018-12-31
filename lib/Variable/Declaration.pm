package Variable::Declaration;
use v5.12.0;
use strict;
use warnings;

our $VERSION = "0.01";

use Keyword::Simple;
use PPR;
use Carp ();
use Import::Into;
use Data::Lock ();
use Type::Tie ();

our $LEVEL;
our $DEFAULT_LEVEL = 2;

sub import {
    shift;
    my %args = @_;
    my $caller = caller;

    $LEVEL = exists $args{level} ? $args{level}
           : exists $ENV{'Variable::Declaration::LEVEL'} ? $ENV{'Variable::Declaration::LEVEL'}
           : $DEFAULT_LEVEL;

    feature->import::into($caller, 'state');
    Type::Tie->import::into($caller, 'ttie');
    Data::Lock->import::into($caller, 'dlock');

    Keyword::Simple::define 'let'    => \&define_let;
    Keyword::Simple::define 'static' => \&define_static;
    Keyword::Simple::define 'const'  => \&define_const;
}

sub unimport {
    Keyword::Simple::undefine 'let';
    Keyword::Simple::undefine 'static';
    Keyword::Simple::undefine 'const';
}

sub define_let    { define_declaration(let => 'my', @_) }
sub define_static { define_declaration(static => 'state', @_) }
sub define_const  { define_declaration(const => 'my', @_) }

sub define_declaration {
    my ($declaration, $perl_declaration, $ref) = @_;

    my $match = _valid($declaration => _parse($$ref));
    my $tv    = _parse_type_varlist($match->{type_varlist});
    my $args  = +{ declaration => $declaration, perl_declaration => $perl_declaration, %$match, %$tv, level => $LEVEL };

    substr($$ref, 0, length $match->{statement}) = _render_declaration($args);
}

sub _croak { Carp::croak @_ }

sub _valid {
    my ($declaration, $match) = @_;

    _croak "variable declaration is required'"
        unless $match->{type_varlist};

    my ($eq, $assign) = ($match->{eq}, $match->{assign});
    if ($declaration eq 'const') {
        _croak "'const' declaration must be assigned"
            unless defined $eq && defined $assign;
    }
    else {
        _croak "illegal expression"
            unless (defined $eq && defined $assign) or (!defined $eq && !defined $assign);
    }

    return $match;
}

sub _render_declaration {
    my $args = shift;
    my @lines;
    push @lines => _lines_declaration($args);
    push @lines => _lines_type_check($args) if $args->{level} >= 1;
    push @lines => _lines_type_tie($args)   if $args->{level} == 2;
    push @lines => _lines_data_lock($args)  if $args->{declaration} eq 'const';
    return join ";", @lines;
}

sub _lines_declaration {
    my $args = shift;
    my $s = $args->{perl_declaration};
    $s .= do {
        my $s = join ', ', map { $_->{var} } @{$args->{type_vars}};
        $args->{is_list_context} ? " ($s)" : " $s";
    };
    $s .= $args->{attributes} if $args->{attributes};
    $s .= " = @{[$args->{assign}]}" if defined $args->{assign};
    return ($s);
}

sub _lines_type_tie {
    my $args = shift;
    my @lines;
    for (@{$args->{type_vars}}) {
        my ($type, $var) = ($_->{type}, $_->{var});
        next unless $type;
        push @lines => sprintf('ttie %s, %s', $var, $type);
    }
    return @lines;
}

sub _lines_type_check {
    my $args = shift;
    my @lines;
    for (@{$args->{type_vars}}) {
        my ($type, $var) = ($_->{type}, $_->{var});
        next unless $type;
        push @lines => sprintf('Variable::Declaration::_croak(%s->get_message(%s)) unless %s->check(%s)', $type, $var, $type, $var)
    }
    return @lines;
}

sub _lines_data_lock {
    my $args = shift;
    my @lines;
    for my $type_var (@{$args->{type_vars}}) {
        push @lines => "dlock($type_var->{var})";
    }
    return @lines;
}

sub _parse {
    my $src = shift;

    return unless $src =~ m{
        \A
        (?<statement>
            (?&PerlOWS)
            (?<assign_to>
                (?<type_varlist>
                    (?&PerlIdentifier)? (?&PerlOWS)
                    (?&PerlVariable)
                |   (?&PerlParenthesesList)
                ) (?&PerlOWS)
                (?<attributes>(?&PerlAttributes))? (?&PerlOWS)
            )
            (?<eq>=)? (?&PerlOWS)
            (?<assign>(?&PerlConditionalExpression))?
        ) $PPR::GRAMMAR }x;

    return +{
        statement       => $+{statement},
        type_varlist    => $+{type_varlist},
        assign_to       => $+{assign_to},
        eq              => $+{eq},
        assign          => $+{assign},
        attributes      => $+{attributes},
    }
}

sub _parse_type_varlist {
    my $expression = shift;

    if ($expression =~ m{ (?<list>(?&PerlParenthesesList)) $PPR::GRAMMAR }x) {
        my ($type_vars) = $+{list} =~ m/\A\((.+)\)\Z/;
        my @list = split ',', $type_vars;
        return +{
            is_list_context => 1,
            type_vars       => [ map { _parse_type_var($_) } @list ],
        }
    }
    elsif (my $type_var = _parse_type_var($expression)) {
        return +{
            is_list_context => 0,
            type_vars       => [ $type_var ],
        }
    }
    else {
        return;
    }
}

sub _parse_type_var {
    my $expression = shift;

    return unless $expression =~ m{
        \A
        (?&PerlOWS)
        (?<type>(?&PerlIdentifier))? (?&PerlOWS)
        (?<var>(?:(?&PerlVariable)))
        \Z
        $PPR::GRAMMAR
    }x;

    return +{
        type => $+{type},
        var  => $+{var},
    }
}

1;
__END__

=encoding utf-8

=head1 NAME

Variable::Declaration - declare with type constraint

=head1 SYNOPSIS

    use Variable::Declaration;
    use Types::Standard '-all';

    # variable declaration
    let $foo;      # is equivalent to `my $foo`
    static $bar;   # is equivalent to `state $bar`
    const $baz;    # is equivalent to `my $baz;dlock($baz)`

    # with type constraint

    # init case
    let Str $foo = {}; # => Reference {} did not pass type constraint "Str"

    # store case
    let Str $foo = 'foo';
    $foo = {}; # => Reference {} did not pass type constraint "Str"

=head1 DESCRIPTION

Warning: This module is still new and experimental. The API may change in future versions. The code may be buggy.

Variable::Declaration provides new variable declarations, i.e. `let`, `static`, and `const`.

`let` is equivalent to `my` with type constraint.
`static` is equivalent to `state` with type constraint.
`const` is equivalent to `let` with data lock.

=head1 LICENSE

Copyright (C) Kenta, Kobayashi.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Kenta, Kobayashi E<lt>kentafly88@gmail.comE<gt>

=cut

