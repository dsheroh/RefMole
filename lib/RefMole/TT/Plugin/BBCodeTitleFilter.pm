package RefMole::TT::Plugin::BBCodeTitleFilter;

use strict;
use warnings;

use base qw(Template::Plugin::Filter);

use RefMole::BBCode;

sub init {
    my $self = shift;

    my $name = $self->{_CONFIG}->{name} || 'bbtitle';
    $self->install_filter($name);

    return $self;
}

sub filter { return RefMole::BBCode::render_bbtitle($_[1]) }


1;

