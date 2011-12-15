#line 1
package Module::Install::Makefile;

use strict 'vars';
use ExtUtils::MakeMaker   ();
use Module::Install::Base ();
use Fcntl qw/:flock :seek/;

use vars qw{$VERSION @ISA $ISCORE};
BEGIN {
	$VERSION = '1.01';
	@ISA     = 'Module::Install::Base';
	$ISCORE  = 1;
}

sub Makefile { $_[0] }

my %seen = ();

sub prompt {
	shift;

	# Infinite loop protection
	my @c = caller();
	if ( ++$seen{"$c[1]|$c[2]|$_[0]"} > 3 ) {
		die "Caught an potential prompt infinite loop ($c[1]|$c[2]|$_[0])";
	}

	# In automated testing or non-interactive session, always use defaults
	if ( ($ENV{AUTOMATED_TESTING} or -! -t STDIN) and ! $ENV{PERL_MM_USE_DEFAULT} ) {
		local $ENV{PERL_MM_USE_DEFAULT} = 1;
		goto &ExtUtils::MakeMaker::prompt;
	} else {
		goto &ExtUtils::MakeMaker::prompt;
	}
}

# Store a cleaned up version of the MakeMaker version,
# since we need to behave differently in a variety of
# ways based on the MM version.
my $makemaker = eval $ExtUtils::MakeMaker::VERSION;

# If we are passed a param, do a "newer than" comparison.
# Otherwise, just return the MakeMaker version.
sub makemaker {
	( @_ < 2 or $makemaker >= eval($_[1]) ) ? $makemaker : 0
}

# Ripped from ExtUtils::MakeMaker 6.56, and slightly modified
# as we only need to know here whether the attribute is an array
# or a hash or something else (which may or may not be appendable).
my %makemaker_argtype = (
 C                  => 'ARRAY',
 CONFIG             => 'ARRAY',
# CONFIGURE          => 'CODE', # ignore
 DIR                => 'ARRAY',
 DL_FUNCS           => 'HASH',
 DL_VARS            => 'ARRAY',
 EXCLUDE_EXT        => 'ARRAY',
 EXE_FILES          => 'ARRAY',
 FUNCLIST           => 'ARRAY',
 H                  => 'ARRAY',
 IMPORTS            => 'HASH',
 INCLUDE_EXT        => 'ARRAY',
 LIBS               => 'ARRAY', # ignore ''
 MAN1PODS           => 'HASH',
 MAN3PODS           => 'HASH',
 META_ADD           => 'HASH',
 META_MERGE         => 'HASH',
 PL_FILES           => 'HASH',
 PM                 => 'HASH',
 PMLIBDIRS          => 'ARRAY',
 PMLIBPARENTDIRS    => 'ARRAY',
 PREREQ_PM          => 'HASH',
 CONFIGURE_REQUIRES => 'HASH',
 SKIP               => 'ARRAY',
 TYPEMAPS           => 'ARRAY',
 XS                 => 'HASH',
# VERSION            => ['version',''],  # ignore
# _KEEP_AFTER_FLUSH  => '',

 clean      => 'HASH',
 depend     => 'HASH',
 dist       => 'HASH',
 dynamic_lib=> 'HASH',
 linkext    => 'HASH',
 macro      => 'HASH',
 postamble  => 'HASH',
 realclean  => 'HASH',
 test       => 'HASH',
 tool_autosplit => 'HASH',

 # special cases where you can use makemaker_append
 CCFLAGS   => 'APPENDABLE',
 DEFINE    => 'APPENDABLE',
 INC       => 'APPENDABLE',
 LDDLFLAGS => 'APPENDABLE',
 LDFROM    => 'APPENDABLE',
);

sub makemaker_args {
	my ($self, %new_args) = @_;
	my $args = ( $self->{makemaker_args} ||= {} );
	foreach my $key (keys %new_args) {
		if ($makemaker_argtype{$key}) {
			if ($makemaker_argtype{$key} eq 'ARRAY') {
				$args->{$key} = [] unless defined $args->{$key};
				unless (ref $args->{$key} eq 'ARRAY') {
					$args->{$key} = [$args->{$key}]
				}
				push @{$args->{$key}},
					ref $new_args{$key} eq 'ARRAY'
						? @{$new_args{$key}}
						: $new_args{$key};
			}
			elsif ($makemaker_argtype{$key} eq 'HASH') {
				$args->{$key} = {} unless defined $args->{$key};
				foreach my $skey (keys %{ $new_args{$key} }) {
					$args->{$key}{$skey} = $new_args{$key}{$skey};
				}
			}
			elsif ($makemaker_argtype{$key} eq 'APPENDABLE') {
				$self->makemaker_append($key => $new_args{$key});
			}
		}
		else {
			if (defined $args->{$key}) {
				warn qq{MakeMaker attribute "$key" is overriden; use "makemaker_append" to append values\n};
			}
			$args->{$key} = $new_args{$key};
		}
	}
	return $args;
}

# For mm args that take multiple space-seperated args,
# append an argument to the current list.
sub makemaker_append {
	my $self = shift;
	my $name = shift;
	my $args = $self->makemaker_args;
	$args->{$name} = defined $args->{$name}
		? join( ' ', $args->{$name}, @_ )
		: join( ' ', @_ );
}

sub build_subdirs {
	my $self    = shift;
	my $subdirs = $self->makemaker_args->{DIR} ||= [];
	for my $subdir (@_) {
		push @$subdirs, $subdir;
	}
}

sub clean_files {
	my $self  = shift;
	my $clean = $self->makemaker_args->{clean} ||= {};
	  %$clean = (
		%$clean,
		FILES => join ' ', grep { length $_ } ($clean->{FILES} || (), @_),
	);
}

sub realclean_files {
	my $self      = shift;
	my $realclean = $self->makemaker_args->{realclean} ||= {};
	  %$realclean = (
		%$realclean,
		FILES => join ' ', grep { length $_ } ($realclean->{FILES} || (), @_),
	);
}

sub libs {
	my $self = shift;
	my $libs = ref $_[0] ? shift : [ shift ];
	$self->makemaker_args( LIBS => $libs );
}

sub inc {
	my $self = shift;
	$self->makemaker_args( INC => shift );
}

sub _wanted_t {
}

sub tests_recursive {
	my $self = shift;
	my $dir = shift || 't';
	unless ( -d $dir ) {
		die "tests_recursive dir '$dir' does not exist";
	}
	my %tests = map { $_ => 1 } split / /, ($self->tests || '');
	require File::Find;
	File::Find::find(
        sub { /\.t$/ and -f $_ and $tests{"$File::Find::dir/*.t"} = 1 },
        $dir
    );
	$self->tests( join ' ', sort keys %tests );
}

sub write {
	my $self = shift;
	die "&Makefile->write() takes no arguments\n" if @_;

	# Check the current Perl version
	my $perl_version = $self->perl_version;
	if ( $perl_version ) {
		eval "use $perl_version; 1"
			or die "ERROR: perl: Version $] is installed, "
			. "but we need version >= $perl_version";
	}

	# Make sure we have a new enough MakeMaker
	require ExtUtils::MakeMaker;

	if ( $perl_version and $self->_cmp($perl_version, '5.006') >= 0 ) {
		# MakeMaker can complain about module versions that include
		# an underscore, even though its own version may contain one!
		# Hence the funny regexp to get rid of it.  See RT #35800
		# for details.
		my $v = $ExtUtils::MakeMaker::VERSION =~ /^(\d+\.\d+)/;
		$self->build_requires(     'ExtUtils::MakeMaker' => $v );
		$self->configure_requires( 'ExtUtils::MakeMaker' => $v );
	} else {
		# Allow legacy-compatibility with 5.005 by depending on the
		# most recent EU:MM that supported 5.005.
		$self->build_requires(     'ExtUtils::MakeMaker' => 6.42 );
		$self->configure_requires( 'ExtUtils::MakeMaker' => 6.42 );
	}

	# Generate the MakeMaker params
	my $args = $self->makemaker_args;
	$args->{DISTNAME} = $self->name;
	$args->{NAME}     = $self->module_name || $self->name;
	$args->{NAME}     =~ s/-/::/g;
	$args->{VERSION}  = $self->version or die <<'EOT';
ERROR: Can't determine distribution version. Please specify it
explicitly via 'version' in Makefile.PL, or set a valid $VERSION
in a module, and provide its file path via 'version_from' (or
'all_from' if you prefer) in Makefile.PL.
EOT

	$DB::single = 1;
	if ( $self->tests ) {
		my @tests = split ' ', $self->tests;
		my %seen;
		$args->{test} = {
			TESTS => (join ' ', grep {!$seen{$_}++} @tests),
		};
    } elsif ( $Module::Install::ExtraTests::use_extratests ) {
        # Module::Install::ExtraTests doesn't set $self->tests and does its own tests via harness.
        # So, just ignore our xt tests here.
	} elsif ( -d 'xt' and ($Module::Install::AUTHOR or $ENV{RELEASE_TESTING}) ) {
		$args->{test} = {
			TESTS => join( ' ', map { "$_/*.t" } grep { -d $_ } qw{ t xt } ),
		};
	}
	if ( $] >= 5.005 ) {
		$args->{ABSTRACT} = $self->abstract;
		$args->{AUTHOR}   = join ', ', @{$self->author || []};
	}
	if ( $self->makemaker(6.10) ) {
		$args->{NO_META}   = 1;
		#$args->{NO_MYMETA} = 1;
	}
	if ( $self->makemaker(6.17) and $self->sign ) {
		$args->{SIGN} = 1;
	}
	unless ( $self->is_admin ) {
		delete $args->{SIGN};
	}
	if ( $self->makemaker(6.31) and $self->license ) {
		$args->{LICENSE} = $self->license;
	}

	my $prereq = ($args->{PREREQ_PM} ||= {});
	%$prereq = ( %$prereq,
		map { @$_ } # flatten [module => version]
		map { @$_ }
		grep $_,
		($self->requires)
	);

	# Remove any reference to perl, PREREQ_PM doesn't support it
	delete $args->{PREREQ_PM}->{perl};

	# Merge both kinds of requires into BUILD_REQUIRES
	my $build_prereq = ($args->{BUILD_REQUIRES} ||= {});
	%$build_prereq = ( %$build_prereq,
		map { @$_ } # flatten [module => version]
		map { @$_ }
		grep $_,
		($self->configure_requires, $self->build_requires)
	);

	# Remove any reference to perl, BUILD_REQUIRES doesn't support it
	delete $args->{BUILD_REQUIRES}->{perl};

	# Delete bundled dists from prereq_pm, add it to Makefile DIR
	my $subdirs = ($args->{DIR} || []);
	if ($self->bundles) {
		my %processed;
		foreach my $bundle (@{ $self->bundles }) {
			my ($mod_name, $dist_dir) = @$bundle;
			delete $prereq->{$mod_name};
			$dist_dir = File::Basename::basename($dist_dir); # dir for building this module
			if (not exists $processed{$dist_dir}) {
				if (-d $dist_dir) {
					# List as sub-directory to be processed by make
					push @$subdirs, $dist_dir;
				}
				# Else do nothing: the module is already present on the system
				$processed{$dist_dir} = undef;
			}
		}
	}

	unless ( $self->makemaker('6.55_03') ) {
		%$prereq = (%$prereq,%$build_prereq);
		delete $args->{BUILD_REQUIRES};
	}

	if ( my $perl_version = $self->perl_version ) {
		eval "use $perl_version; 1"
			or die "ERROR: perl: Version $] is installed, "
			. "but we need version >= $perl_version";

		if ( $self->makemaker(6.48) ) {
			$args->{MIN_PERL_VERSION} = $perl_version;
		}
	}

	if ($self->installdirs) {
		warn qq{old INSTALLDIRS (probably set by makemaker_args) is overriden by installdirs\n} if $args->{INSTALLDIRS};
		$args->{INSTALLDIRS} = $self->installdirs;
	}

	my %args = map {
		( $_ => $args->{$_} ) } grep {defined($args->{$_} )
	} keys %$args;

	my $user_preop = delete $args{dist}->{PREOP};
	if ( my $preop = $self->admin->preop($user_preop) ) {
		foreach my $key ( keys %$preop ) {
			$args{dist}->{$key} = $preop->{$key};
		}
	}

	my $mm = ExtUtils::MakeMaker::WriteMakefile(%args);
	$self->fix_up_makefile($mm->{FIRST_MAKEFILE} || 'Makefile');
}

sub fix_up_makefile {
	my $self          = shift;
	my $makefile_name = shift;
	my $top_class     = ref($self->_top) || '';
	my $top_version   = $self->_top->VERSION || '';

	my $preamble = $self->preamble
		? "# Preamble by $top_class $top_version\n"
			. $self->preamble
		: '';
	my $postamble = "# Postamble by $top_class $top_version\n"
		. ($self->postamble || '');

	local *MAKEFILE;
	open MAKEFILE, "+< $makefile_name" or die "fix_up_makefile: Couldn't open $makefile_name: $!";
	eval { flock MAKEFILE, LOCK_EX };
	my $makefile = do { local $/; <MAKEFILE> };

	$makefile =~ s/\b(test_harness\(\$\(TEST_VERBOSE\), )/$1'inc', /;
	$makefile =~ s/( -I\$\(INST_ARCHLIB\))/ -Iinc$1/g;
	$makefile =~ s/( "-I\$\(INST_LIB\)")/ "-Iinc"$1/g;
	$makefile =~ s/^(FULLPERL = .*)/$1 "-Iinc"/m;
	$makefile =~ s/^(PERL = .*)/$1 "-Iinc"/m;

	# Module::Install will never be used to build the Core Perl
	# Sometimes PERL_LIB and PERL_ARCHLIB get written anyway, which breaks
	# PREFIX/PERL5LIB, and thus, install_share. Blank them if they exist
	$makefile =~ s/^PERL_LIB = .+/PERL_LIB =/m;
	#$makefile =~ s/^PERL_ARCHLIB = .+/PERL_ARCHLIB =/m;

	# Perl 5.005 mentions PERL_LIB explicitly, so we have to remove that as well.
	$makefile =~ s/(\"?)-I\$\(PERL_LIB\)\1//g;

	# XXX - This is currently unused; not sure if it breaks other MM-users
	# $makefile =~ s/^pm_to_blib\s+:\s+/pm_to_blib :: /mg;

	seek MAKEFILE, 0, SEEK_SET;
	truncate MAKEFILE, 0;
	print MAKEFILE  "$preamble$makefile$postamble" or die $!;
	close MAKEFILE  or die $!;

	1;
}

sub preamble {
	my ($self, $text) = @_;
	$self->{preamble} = $text . $self->{preamble} if defined $text;
	$self->{preamble};
}

sub postamble {
	my ($self, $text) = @_;
	$self->{postamble} ||= $self->admin->postamble;
	$self->{postamble} .= $text if defined $text;
	$self->{postamble}
}

1;

__END__

#line 541
