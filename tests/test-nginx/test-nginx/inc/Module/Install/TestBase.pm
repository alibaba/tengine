#line 1
package Module::Install::TestBase;
use strict;
use warnings;

use Module::Install::Base;

use vars qw($VERSION @ISA);
BEGIN {
    $VERSION = '0.60';
    @ISA     = 'Module::Install::Base';
}

sub use_test_base {
    my $self = shift;
    $self->include('Test::Base');
    $self->include('Test::Base::Filter');
    $self->include('Spiffy');
    $self->include('Test::More');
    $self->include('Test::Builder');
    $self->include('Test::Builder::Module');
    $self->requires('Filter::Util::Call');
}

1;

=encoding utf8

#line 70
