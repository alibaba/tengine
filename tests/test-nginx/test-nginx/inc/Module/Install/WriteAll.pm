#line 1
package Module::Install::WriteAll;

use strict;
use Module::Install::Base ();

use vars qw{$VERSION @ISA $ISCORE};
BEGIN {
	$VERSION = '1.06';
	@ISA     = qw{Module::Install::Base};
	$ISCORE  = 1;
}

sub WriteAll {
	my $self = shift;
	my %args = (
		meta        => 1,
		sign        => 0,
		inline      => 0,
		check_nmake => 1,
		@_,
	);

	$self->sign(1)                if $args{sign};
	$self->admin->WriteAll(%args) if $self->is_admin;

	$self->check_nmake if $args{check_nmake};
	unless ( $self->makemaker_args->{PL_FILES} ) {
		# XXX: This still may be a bit over-defensive...
		unless ($self->makemaker(6.25)) {
			$self->makemaker_args( PL_FILES => {} ) if -f 'Build.PL';
		}
	}

	# Until ExtUtils::MakeMaker support MYMETA.yml, make sure
	# we clean it up properly ourself.
	$self->realclean_files('MYMETA.yml');

	if ( $args{inline} ) {
		$self->Inline->write;
	} else {
		$self->Makefile->write;
	}

	# The Makefile write process adds a couple of dependencies,
	# so write the META.yml files after the Makefile.
	if ( $args{meta} ) {
		$self->Meta->write;
	}

	# Experimental support for MYMETA
	if ( $ENV{X_MYMETA} ) {
		if ( $ENV{X_MYMETA} eq 'JSON' ) {
			$self->Meta->write_mymeta_json;
		} else {
			$self->Meta->write_mymeta_yaml;
		}
	}

	return 1;
}

1;
