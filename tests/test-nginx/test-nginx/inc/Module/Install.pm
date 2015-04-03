#line 1
package Module::Install;

# For any maintainers:
# The load order for Module::Install is a bit magic.
# It goes something like this...
#
# IF ( host has Module::Install installed, creating author mode ) {
#     1. Makefile.PL calls "use inc::Module::Install"
#     2. $INC{inc/Module/Install.pm} set to installed version of inc::Module::Install
#     3. The installed version of inc::Module::Install loads
#     4. inc::Module::Install calls "require Module::Install"
#     5. The ./inc/ version of Module::Install loads
# } ELSE {
#     1. Makefile.PL calls "use inc::Module::Install"
#     2. $INC{inc/Module/Install.pm} set to ./inc/ version of Module::Install
#     3. The ./inc/ version of Module::Install loads
# }

use 5.005;
use strict 'vars';
use Cwd        ();
use File::Find ();
use File::Path ();

use vars qw{$VERSION $MAIN};
BEGIN {
	# All Module::Install core packages now require synchronised versions.
	# This will be used to ensure we don't accidentally load old or
	# different versions of modules.
	# This is not enforced yet, but will be some time in the next few
	# releases once we can make sure it won't clash with custom
	# Module::Install extensions.
	$VERSION = '1.06';

	# Storage for the pseudo-singleton
	$MAIN    = undef;

	*inc::Module::Install::VERSION = *VERSION;
	@inc::Module::Install::ISA     = __PACKAGE__;

}

sub import {
	my $class = shift;
	my $self  = $class->new(@_);
	my $who   = $self->_caller;

	#-------------------------------------------------------------
	# all of the following checks should be included in import(),
	# to allow "eval 'require Module::Install; 1' to test
	# installation of Module::Install. (RT #51267)
	#-------------------------------------------------------------

	# Whether or not inc::Module::Install is actually loaded, the
	# $INC{inc/Module/Install.pm} is what will still get set as long as
	# the caller loaded module this in the documented manner.
	# If not set, the caller may NOT have loaded the bundled version, and thus
	# they may not have a MI version that works with the Makefile.PL. This would
	# result in false errors or unexpected behaviour. And we don't want that.
	my $file = join( '/', 'inc', split /::/, __PACKAGE__ ) . '.pm';
	unless ( $INC{$file} ) { die <<"END_DIE" }

Please invoke ${\__PACKAGE__} with:

	use inc::${\__PACKAGE__};

not:

	use ${\__PACKAGE__};

END_DIE

	# This reportedly fixes a rare Win32 UTC file time issue, but
	# as this is a non-cross-platform XS module not in the core,
	# we shouldn't really depend on it. See RT #24194 for detail.
	# (Also, this module only supports Perl 5.6 and above).
	eval "use Win32::UTCFileTime" if $^O eq 'MSWin32' && $] >= 5.006;

	# If the script that is loading Module::Install is from the future,
	# then make will detect this and cause it to re-run over and over
	# again. This is bad. Rather than taking action to touch it (which
	# is unreliable on some platforms and requires write permissions)
	# for now we should catch this and refuse to run.
	if ( -f $0 ) {
		my $s = (stat($0))[9];

		# If the modification time is only slightly in the future,
		# sleep briefly to remove the problem.
		my $a = $s - time;
		if ( $a > 0 and $a < 5 ) { sleep 5 }

		# Too far in the future, throw an error.
		my $t = time;
		if ( $s > $t ) { die <<"END_DIE" }

Your installer $0 has a modification time in the future ($s > $t).

This is known to create infinite loops in make.

Please correct this, then run $0 again.

END_DIE
	}


	# Build.PL was formerly supported, but no longer is due to excessive
	# difficulty in implementing every single feature twice.
	if ( $0 =~ /Build.PL$/i ) { die <<"END_DIE" }

Module::Install no longer supports Build.PL.

It was impossible to maintain duel backends, and has been deprecated.

Please remove all Build.PL files and only use the Makefile.PL installer.

END_DIE

	#-------------------------------------------------------------

	# To save some more typing in Module::Install installers, every...
	# use inc::Module::Install
	# ...also acts as an implicit use strict.
	$^H |= strict::bits(qw(refs subs vars));

	#-------------------------------------------------------------

	unless ( -f $self->{file} ) {
		foreach my $key (keys %INC) {
			delete $INC{$key} if $key =~ /Module\/Install/;
		}

		local $^W;
		require "$self->{path}/$self->{dispatch}.pm";
		File::Path::mkpath("$self->{prefix}/$self->{author}");
		$self->{admin} = "$self->{name}::$self->{dispatch}"->new( _top => $self );
		$self->{admin}->init;
		@_ = ($class, _self => $self);
		goto &{"$self->{name}::import"};
	}

	local $^W;
	*{"${who}::AUTOLOAD"} = $self->autoload;
	$self->preload;

	# Unregister loader and worker packages so subdirs can use them again
	delete $INC{'inc/Module/Install.pm'};
	delete $INC{'Module/Install.pm'};

	# Save to the singleton
	$MAIN = $self;

	return 1;
}

sub autoload {
	my $self = shift;
	my $who  = $self->_caller;
	my $cwd  = Cwd::cwd();
	my $sym  = "${who}::AUTOLOAD";
	$sym->{$cwd} = sub {
		my $pwd = Cwd::cwd();
		if ( my $code = $sym->{$pwd} ) {
			# Delegate back to parent dirs
			goto &$code unless $cwd eq $pwd;
		}
		unless ($$sym =~ s/([^:]+)$//) {
			# XXX: it looks like we can't retrieve the missing function
			# via $$sym (usually $main::AUTOLOAD) in this case.
			# I'm still wondering if we should slurp Makefile.PL to
			# get some context or not ...
			my ($package, $file, $line) = caller;
			die <<"EOT";
Unknown function is found at $file line $line.
Execution of $file aborted due to runtime errors.

If you're a contributor to a project, you may need to install
some Module::Install extensions from CPAN (or other repository).
If you're a user of a module, please contact the author.
EOT
		}
		my $method = $1;
		if ( uc($method) eq $method ) {
			# Do nothing
			return;
		} elsif ( $method =~ /^_/ and $self->can($method) ) {
			# Dispatch to the root M:I class
			return $self->$method(@_);
		}

		# Dispatch to the appropriate plugin
		unshift @_, ( $self, $1 );
		goto &{$self->can('call')};
	};
}

sub preload {
	my $self = shift;
	unless ( $self->{extensions} ) {
		$self->load_extensions(
			"$self->{prefix}/$self->{path}", $self
		);
	}

	my @exts = @{$self->{extensions}};
	unless ( @exts ) {
		@exts = $self->{admin}->load_all_extensions;
	}

	my %seen;
	foreach my $obj ( @exts ) {
		while (my ($method, $glob) = each %{ref($obj) . '::'}) {
			next unless $obj->can($method);
			next if $method =~ /^_/;
			next if $method eq uc($method);
			$seen{$method}++;
		}
	}

	my $who = $self->_caller;
	foreach my $name ( sort keys %seen ) {
		local $^W;
		*{"${who}::$name"} = sub {
			${"${who}::AUTOLOAD"} = "${who}::$name";
			goto &{"${who}::AUTOLOAD"};
		};
	}
}

sub new {
	my ($class, %args) = @_;

	delete $INC{'FindBin.pm'};
	{
		# to suppress the redefine warning
		local $SIG{__WARN__} = sub {};
		require FindBin;
	}

	# ignore the prefix on extension modules built from top level.
	my $base_path = Cwd::abs_path($FindBin::Bin);
	unless ( Cwd::abs_path(Cwd::cwd()) eq $base_path ) {
		delete $args{prefix};
	}
	return $args{_self} if $args{_self};

	$args{dispatch} ||= 'Admin';
	$args{prefix}   ||= 'inc';
	$args{author}   ||= ($^O eq 'VMS' ? '_author' : '.author');
	$args{bundle}   ||= 'inc/BUNDLES';
	$args{base}     ||= $base_path;
	$class =~ s/^\Q$args{prefix}\E:://;
	$args{name}     ||= $class;
	$args{version}  ||= $class->VERSION;
	unless ( $args{path} ) {
		$args{path}  = $args{name};
		$args{path}  =~ s!::!/!g;
	}
	$args{file}     ||= "$args{base}/$args{prefix}/$args{path}.pm";
	$args{wrote}      = 0;

	bless( \%args, $class );
}

sub call {
	my ($self, $method) = @_;
	my $obj = $self->load($method) or return;
        splice(@_, 0, 2, $obj);
	goto &{$obj->can($method)};
}

sub load {
	my ($self, $method) = @_;

	$self->load_extensions(
		"$self->{prefix}/$self->{path}", $self
	) unless $self->{extensions};

	foreach my $obj (@{$self->{extensions}}) {
		return $obj if $obj->can($method);
	}

	my $admin = $self->{admin} or die <<"END_DIE";
The '$method' method does not exist in the '$self->{prefix}' path!
Please remove the '$self->{prefix}' directory and run $0 again to load it.
END_DIE

	my $obj = $admin->load($method, 1);
	push @{$self->{extensions}}, $obj;

	$obj;
}

sub load_extensions {
	my ($self, $path, $top) = @_;

	my $should_reload = 0;
	unless ( grep { ! ref $_ and lc $_ eq lc $self->{prefix} } @INC ) {
		unshift @INC, $self->{prefix};
		$should_reload = 1;
	}

	foreach my $rv ( $self->find_extensions($path) ) {
		my ($file, $pkg) = @{$rv};
		next if $self->{pathnames}{$pkg};

		local $@;
		my $new = eval { local $^W; require $file; $pkg->can('new') };
		unless ( $new ) {
			warn $@ if $@;
			next;
		}
		$self->{pathnames}{$pkg} =
			$should_reload ? delete $INC{$file} : $INC{$file};
		push @{$self->{extensions}}, &{$new}($pkg, _top => $top );
	}

	$self->{extensions} ||= [];
}

sub find_extensions {
	my ($self, $path) = @_;

	my @found;
	File::Find::find( sub {
		my $file = $File::Find::name;
		return unless $file =~ m!^\Q$path\E/(.+)\.pm\Z!is;
		my $subpath = $1;
		return if lc($subpath) eq lc($self->{dispatch});

		$file = "$self->{path}/$subpath.pm";
		my $pkg = "$self->{name}::$subpath";
		$pkg =~ s!/!::!g;

		# If we have a mixed-case package name, assume case has been preserved
		# correctly.  Otherwise, root through the file to locate the case-preserved
		# version of the package name.
		if ( $subpath eq lc($subpath) || $subpath eq uc($subpath) ) {
			my $content = Module::Install::_read($subpath . '.pm');
			my $in_pod  = 0;
			foreach ( split //, $content ) {
				$in_pod = 1 if /^=\w/;
				$in_pod = 0 if /^=cut/;
				next if ($in_pod || /^=cut/);  # skip pod text
				next if /^\s*#/;               # and comments
				if ( m/^\s*package\s+($pkg)\s*;/i ) {
					$pkg = $1;
					last;
				}
			}
		}

		push @found, [ $file, $pkg ];
	}, $path ) if -d $path;

	@found;
}





#####################################################################
# Common Utility Functions

sub _caller {
	my $depth = 0;
	my $call  = caller($depth);
	while ( $call eq __PACKAGE__ ) {
		$depth++;
		$call = caller($depth);
	}
	return $call;
}

# Done in evals to avoid confusing Perl::MinimumVersion
eval( $] >= 5.006 ? <<'END_NEW' : <<'END_OLD' ); die $@ if $@;
sub _read {
	local *FH;
	open( FH, '<', $_[0] ) or die "open($_[0]): $!";
	my $string = do { local $/; <FH> };
	close FH or die "close($_[0]): $!";
	return $string;
}
END_NEW
sub _read {
	local *FH;
	open( FH, "< $_[0]"  ) or die "open($_[0]): $!";
	my $string = do { local $/; <FH> };
	close FH or die "close($_[0]): $!";
	return $string;
}
END_OLD

sub _readperl {
	my $string = Module::Install::_read($_[0]);
	$string =~ s/(?:\015{1,2}\012|\015|\012)/\n/sg;
	$string =~ s/(\n)\n*__(?:DATA|END)__\b.*\z/$1/s;
	$string =~ s/\n\n=\w+.+?\n\n=cut\b.+?\n+/\n\n/sg;
	return $string;
}

sub _readpod {
	my $string = Module::Install::_read($_[0]);
	$string =~ s/(?:\015{1,2}\012|\015|\012)/\n/sg;
	return $string if $_[0] =~ /\.pod\z/;
	$string =~ s/(^|\n=cut\b.+?\n+)[^=\s].+?\n(\n=\w+|\z)/$1$2/sg;
	$string =~ s/\n*=pod\b[^\n]*\n+/\n\n/sg;
	$string =~ s/\n*=cut\b[^\n]*\n+/\n\n/sg;
	$string =~ s/^\n+//s;
	return $string;
}

# Done in evals to avoid confusing Perl::MinimumVersion
eval( $] >= 5.006 ? <<'END_NEW' : <<'END_OLD' ); die $@ if $@;
sub _write {
	local *FH;
	open( FH, '>', $_[0] ) or die "open($_[0]): $!";
	foreach ( 1 .. $#_ ) {
		print FH $_[$_] or die "print($_[0]): $!";
	}
	close FH or die "close($_[0]): $!";
}
END_NEW
sub _write {
	local *FH;
	open( FH, "> $_[0]"  ) or die "open($_[0]): $!";
	foreach ( 1 .. $#_ ) {
		print FH $_[$_] or die "print($_[0]): $!";
	}
	close FH or die "close($_[0]): $!";
}
END_OLD

# _version is for processing module versions (eg, 1.03_05) not
# Perl versions (eg, 5.8.1).
sub _version ($) {
	my $s = shift || 0;
	my $d =()= $s =~ /(\.)/g;
	if ( $d >= 2 ) {
		# Normalise multipart versions
		$s =~ s/(\.)(\d{1,3})/sprintf("$1%03d",$2)/eg;
	}
	$s =~ s/^(\d+)\.?//;
	my $l = $1 || 0;
	my @v = map {
		$_ . '0' x (3 - length $_)
	} $s =~ /(\d{1,3})\D?/g;
	$l = $l . '.' . join '', @v if @v;
	return $l + 0;
}

sub _cmp ($$) {
	_version($_[1]) <=> _version($_[2]);
}

# Cloned from Params::Util::_CLASS
sub _CLASS ($) {
	(
		defined $_[0]
		and
		! ref $_[0]
		and
		$_[0] =~ m/^[^\W\d]\w*(?:::\w+)*\z/s
	) ? $_[0] : undef;
}

1;

# Copyright 2008 - 2012 Adam Kennedy.
