package RefMole::TT::Plugin::JSEscapeFilter;

use strict;
use warnings;

use base qw(Template::Plugin::Filter);

use JavaScript::Value::Escape;

sub init {
    my $self = shift;

    my $name = $self->{_CONFIG}->{name} || 'js';
    $self->install_filter($name);

    return $self;
}

sub filter { return JavaScript::Value::Escape::javascript_value_escape($_[1]) }


1;

