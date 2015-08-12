#line 1
package Module::Install::AutoInstall;

use strict;
use Module::Install::Base ();

use vars qw{$VERSION @ISA $ISCORE};
BEGIN {
	$VERSION = '1.06';
	@ISA     = 'Module::Install::Base';
	$ISCORE  = 1;
}

sub AutoInstall { $_[0] }

sub run {
    my $self = shift;
    $self->auto_install_now(@_);
}

sub write {
    my $self = shift;
    $self->auto_install(@_);
}

sub auto_install {
    my $self = shift;
    return if $self->{done}++;

    # Flatten array of arrays into a single array
    my @core = map @$_, map @$_, grep ref,
               $self->build_requires, $self->requires;

    my @config = @_;

    # We'll need Module::AutoInstall
    $self->include('Module::AutoInstall');
    require Module::AutoInstall;

    my @features_require = Module::AutoInstall->import(
        (@config ? (-config => \@config) : ()),
        (@core   ? (-core   => \@core)   : ()),
        $self->features,
    );

    my %seen;
    my @requires = map @$_, map @$_, grep ref, $self->requires;
    while (my ($mod, $ver) = splice(@requires, 0, 2)) {
        $seen{$mod}{$ver}++;
    }
    my @build_requires = map @$_, map @$_, grep ref, $self->build_requires;
    while (my ($mod, $ver) = splice(@build_requires, 0, 2)) {
        $seen{$mod}{$ver}++;
    }
    my @configure_requires = map @$_, map @$_, grep ref, $self->configure_requires;
    while (my ($mod, $ver) = splice(@configure_requires, 0, 2)) {
        $seen{$mod}{$ver}++;
    }

    my @deduped;
    while (my ($mod, $ver) = splice(@features_require, 0, 2)) {
        push @deduped, $mod => $ver unless $seen{$mod}{$ver}++;
    }

    $self->requires(@deduped);

    $self->makemaker_args( Module::AutoInstall::_make_args() );

    my $class = ref($self);
    $self->postamble(
        "# --- $class section:\n" .
        Module::AutoInstall::postamble()
    );
}

sub installdeps_target {
    my ($self, @args) = @_;

    $self->include('Module::AutoInstall');
    require Module::AutoInstall;

    Module::AutoInstall::_installdeps_target(1);

    $self->auto_install(@args);
}

sub auto_install_now {
    my $self = shift;
    $self->auto_install(@_);
    Module::AutoInstall::do_install();
}

1;
