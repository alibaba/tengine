#line 1
package Module::AutoInstall;

use strict;
use Cwd                 ();
use File::Spec          ();
use ExtUtils::MakeMaker ();

use vars qw{$VERSION};
BEGIN {
	$VERSION = '1.06';
}

# special map on pre-defined feature sets
my %FeatureMap = (
    ''      => 'Core Features',    # XXX: deprecated
    '-core' => 'Core Features',
);

# various lexical flags
my ( @Missing, @Existing,  %DisabledTests, $UnderCPAN, $InstallDepsTarget, $HasCPANPLUS );
my (
    $Config, $CheckOnly, $SkipInstall, $AcceptDefault, $TestOnly, $AllDeps,
    $UpgradeDeps
);
my ( $PostambleActions, $PostambleActionsNoTest, $PostambleActionsUpgradeDeps,
    $PostambleActionsUpgradeDepsNoTest, $PostambleActionsListDeps,
    $PostambleActionsListAllDeps, $PostambleUsed, $NoTest);

# See if it's a testing or non-interactive session
_accept_default( $ENV{AUTOMATED_TESTING} or ! -t STDIN ); 
_init();

sub _accept_default {
    $AcceptDefault = shift;
}

sub _installdeps_target {
    $InstallDepsTarget = shift;
}

sub missing_modules {
    return @Missing;
}

sub do_install {
    __PACKAGE__->install(
        [
            $Config
            ? ( UNIVERSAL::isa( $Config, 'HASH' ) ? %{$Config} : @{$Config} )
            : ()
        ],
        @Missing,
    );
}

# initialize various flags, and/or perform install
sub _init {
    foreach my $arg (
        @ARGV,
        split(
            /[\s\t]+/,
            $ENV{PERL_AUTOINSTALL} || $ENV{PERL_EXTUTILS_AUTOINSTALL} || ''
        )
      )
    {
        if ( $arg =~ /^--config=(.*)$/ ) {
            $Config = [ split( ',', $1 ) ];
        }
        elsif ( $arg =~ /^--installdeps=(.*)$/ ) {
            __PACKAGE__->install( $Config, @Missing = split( /,/, $1 ) );
            exit 0;
        }
	elsif ( $arg =~ /^--upgradedeps=(.*)$/ ) {
	    $UpgradeDeps = 1;
	    __PACKAGE__->install( $Config, @Missing = split( /,/, $1 ) );
	    exit 0;
	}
        elsif ( $arg =~ /^--default(?:deps)?$/ ) {
            $AcceptDefault = 1;
        }
        elsif ( $arg =~ /^--check(?:deps)?$/ ) {
            $CheckOnly = 1;
        }
        elsif ( $arg =~ /^--skip(?:deps)?$/ ) {
            $SkipInstall = 1;
        }
        elsif ( $arg =~ /^--test(?:only)?$/ ) {
            $TestOnly = 1;
        }
        elsif ( $arg =~ /^--all(?:deps)?$/ ) {
            $AllDeps = 1;
        }
    }
}

# overrides MakeMaker's prompt() to automatically accept the default choice
sub _prompt {
    goto &ExtUtils::MakeMaker::prompt unless $AcceptDefault;

    my ( $prompt, $default ) = @_;
    my $y = ( $default =~ /^[Yy]/ );

    print $prompt, ' [', ( $y ? 'Y' : 'y' ), '/', ( $y ? 'n' : 'N' ), '] ';
    print "$default\n";
    return $default;
}

# the workhorse
sub import {
    my $class = shift;
    my @args  = @_ or return;
    my $core_all;

    print "*** $class version " . $class->VERSION . "\n";
    print "*** Checking for Perl dependencies...\n";

    my $cwd = Cwd::cwd();

    $Config = [];

    my $maxlen = length(
        (
            sort   { length($b) <=> length($a) }
              grep { /^[^\-]/ }
              map  {
                ref($_)
                  ? ( ( ref($_) eq 'HASH' ) ? keys(%$_) : @{$_} )
                  : ''
              }
              map { +{@args}->{$_} }
              grep { /^[^\-]/ or /^-core$/i } keys %{ +{@args} }
        )[0]
    );

    # We want to know if we're under CPAN early to avoid prompting, but
    # if we aren't going to try and install anything anyway then skip the
    # check entirely since we don't want to have to load (and configure)
    # an old CPAN just for a cosmetic message

    $UnderCPAN = _check_lock(1) unless $SkipInstall || $InstallDepsTarget;

    while ( my ( $feature, $modules ) = splice( @args, 0, 2 ) ) {
        my ( @required, @tests, @skiptests );
        my $default  = 1;
        my $conflict = 0;

        if ( $feature =~ m/^-(\w+)$/ ) {
            my $option = lc($1);

            # check for a newer version of myself
            _update_to( $modules, @_ ) and return if $option eq 'version';

            # sets CPAN configuration options
            $Config = $modules if $option eq 'config';

            # promote every features to core status
            $core_all = ( $modules =~ /^all$/i ) and next
              if $option eq 'core';

            next unless $option eq 'core';
        }

        print "[" . ( $FeatureMap{ lc($feature) } || $feature ) . "]\n";

        $modules = [ %{$modules} ] if UNIVERSAL::isa( $modules, 'HASH' );

        unshift @$modules, -default => &{ shift(@$modules) }
          if ( ref( $modules->[0] ) eq 'CODE' );    # XXX: bugward combatability

        while ( my ( $mod, $arg ) = splice( @$modules, 0, 2 ) ) {
            if ( $mod =~ m/^-(\w+)$/ ) {
                my $option = lc($1);

                $default   = $arg    if ( $option eq 'default' );
                $conflict  = $arg    if ( $option eq 'conflict' );
                @tests     = @{$arg} if ( $option eq 'tests' );
                @skiptests = @{$arg} if ( $option eq 'skiptests' );

                next;
            }

            printf( "- %-${maxlen}s ...", $mod );

            if ( $arg and $arg =~ /^\D/ ) {
                unshift @$modules, $arg;
                $arg = 0;
            }

            # XXX: check for conflicts and uninstalls(!) them.
            my $cur = _version_of($mod);
            if (_version_cmp ($cur, $arg) >= 0)
            {
                print "loaded. ($cur" . ( $arg ? " >= $arg" : '' ) . ")\n";
                push @Existing, $mod => $arg;
                $DisabledTests{$_} = 1 for map { glob($_) } @skiptests;
            }
            else {
                if (not defined $cur)   # indeed missing
                {
                    print "missing." . ( $arg ? " (would need $arg)" : '' ) . "\n";
                }
                else
                {
                    # no need to check $arg as _version_cmp ($cur, undef) would satisfy >= above
                    print "too old. ($cur < $arg)\n";
                }

                push @required, $mod => $arg;
            }
        }

        next unless @required;

        my $mandatory = ( $feature eq '-core' or $core_all );

        if (
            !$SkipInstall
            and (
                $CheckOnly
                or ($mandatory and $UnderCPAN)
                or $AllDeps
                or $InstallDepsTarget
                or _prompt(
                    qq{==> Auto-install the }
                      . ( @required / 2 )
                      . ( $mandatory ? ' mandatory' : ' optional' )
                      . qq{ module(s) from CPAN?},
                    $default ? 'y' : 'n',
                ) =~ /^[Yy]/
            )
          )
        {
            push( @Missing, @required );
            $DisabledTests{$_} = 1 for map { glob($_) } @skiptests;
        }

        elsif ( !$SkipInstall
            and $default
            and $mandatory
            and
            _prompt( qq{==> The module(s) are mandatory! Really skip?}, 'n', )
            =~ /^[Nn]/ )
        {
            push( @Missing, @required );
            $DisabledTests{$_} = 1 for map { glob($_) } @skiptests;
        }

        else {
            $DisabledTests{$_} = 1 for map { glob($_) } @tests;
        }
    }

    if ( @Missing and not( $CheckOnly or $UnderCPAN) ) {
        require Config;
        my $make = $Config::Config{make};
        if ($InstallDepsTarget) {
            print
"*** To install dependencies type '$make installdeps' or '$make installdeps_notest'.\n";
        }
        else {
            print
"*** Dependencies will be installed the next time you type '$make'.\n";
        }

        # make an educated guess of whether we'll need root permission.
        print "    (You may need to do that as the 'root' user.)\n"
          if eval '$>';
    }
    print "*** $class configuration finished.\n";

    chdir $cwd;

    # import to main::
    no strict 'refs';
    *{'main::WriteMakefile'} = \&Write if caller(0) eq 'main';

    return (@Existing, @Missing);
}

sub _running_under {
    my $thing = shift;
    print <<"END_MESSAGE";
*** Since we're running under ${thing}, I'll just let it take care
    of the dependency's installation later.
END_MESSAGE
    return 1;
}

# Check to see if we are currently running under CPAN.pm and/or CPANPLUS;
# if we are, then we simply let it taking care of our dependencies
sub _check_lock {
    return unless @Missing or @_;

    if ($ENV{PERL5_CPANM_IS_RUNNING}) {
        return _running_under('cpanminus');
    }

    my $cpan_env = $ENV{PERL5_CPAN_IS_RUNNING};

    if ($ENV{PERL5_CPANPLUS_IS_RUNNING}) {
        return _running_under($cpan_env ? 'CPAN' : 'CPANPLUS');
    }

    require CPAN;

    if ($CPAN::VERSION > '1.89') {
        if ($cpan_env) {
            return _running_under('CPAN');
        }
        return; # CPAN.pm new enough, don't need to check further
    }

    # last ditch attempt, this -will- configure CPAN, very sorry

    _load_cpan(1); # force initialize even though it's already loaded

    # Find the CPAN lock-file
    my $lock = MM->catfile( $CPAN::Config->{cpan_home}, ".lock" );
    return unless -f $lock;

    # Check the lock
    local *LOCK;
    return unless open(LOCK, $lock);

    if (
            ( $^O eq 'MSWin32' ? _under_cpan() : <LOCK> == getppid() )
        and ( $CPAN::Config->{prerequisites_policy} || '' ) ne 'ignore'
    ) {
        print <<'END_MESSAGE';

*** Since we're running under CPAN, I'll just let it take care
    of the dependency's installation later.
END_MESSAGE
        return 1;
    }

    close LOCK;
    return;
}

sub install {
    my $class = shift;

    my $i;    # used below to strip leading '-' from config keys
    my @config = ( map { s/^-// if ++$i; $_ } @{ +shift } );

    my ( @modules, @installed );
    while ( my ( $pkg, $ver ) = splice( @_, 0, 2 ) ) {

        # grep out those already installed
        if ( _version_cmp( _version_of($pkg), $ver ) >= 0 ) {
            push @installed, $pkg;
        }
        else {
            push @modules, $pkg, $ver;
        }
    }

    if ($UpgradeDeps) {
        push @modules, @installed;
        @installed = ();
    }

    return @installed unless @modules;  # nothing to do
    return @installed if _check_lock(); # defer to the CPAN shell

    print "*** Installing dependencies...\n";

    return unless _connected_to('cpan.org');

    my %args = @config;
    my %failed;
    local *FAILED;
    if ( $args{do_once} and open( FAILED, '.#autoinstall.failed' ) ) {
        while (<FAILED>) { chomp; $failed{$_}++ }
        close FAILED;

        my @newmod;
        while ( my ( $k, $v ) = splice( @modules, 0, 2 ) ) {
            push @newmod, ( $k => $v ) unless $failed{$k};
        }
        @modules = @newmod;
    }

    if ( _has_cpanplus() and not $ENV{PERL_AUTOINSTALL_PREFER_CPAN} ) {
        _install_cpanplus( \@modules, \@config );
    } else {
        _install_cpan( \@modules, \@config );
    }

    print "*** $class installation finished.\n";

    # see if we have successfully installed them
    while ( my ( $pkg, $ver ) = splice( @modules, 0, 2 ) ) {
        if ( _version_cmp( _version_of($pkg), $ver ) >= 0 ) {
            push @installed, $pkg;
        }
        elsif ( $args{do_once} and open( FAILED, '>> .#autoinstall.failed' ) ) {
            print FAILED "$pkg\n";
        }
    }

    close FAILED if $args{do_once};

    return @installed;
}

sub _install_cpanplus {
    my @modules   = @{ +shift };
    my @config    = _cpanplus_config( @{ +shift } );
    my $installed = 0;

    require CPANPLUS::Backend;
    my $cp   = CPANPLUS::Backend->new;
    my $conf = $cp->configure_object;

    return unless $conf->can('conf') # 0.05x+ with "sudo" support
               or _can_write($conf->_get_build('base'));  # 0.04x

    # if we're root, set UNINST=1 to avoid trouble unless user asked for it.
    my $makeflags = $conf->get_conf('makeflags') || '';
    if ( UNIVERSAL::isa( $makeflags, 'HASH' ) ) {
        # 0.03+ uses a hashref here
        $makeflags->{UNINST} = 1 unless exists $makeflags->{UNINST};

    } else {
        # 0.02 and below uses a scalar
        $makeflags = join( ' ', split( ' ', $makeflags ), 'UNINST=1' )
          if ( $makeflags !~ /\bUNINST\b/ and eval qq{ $> eq '0' } );

    }
    $conf->set_conf( makeflags => $makeflags );
    $conf->set_conf( prereqs   => 1 );

    

    while ( my ( $key, $val ) = splice( @config, 0, 2 ) ) {
        $conf->set_conf( $key, $val );
    }

    my $modtree = $cp->module_tree;
    while ( my ( $pkg, $ver ) = splice( @modules, 0, 2 ) ) {
        print "*** Installing $pkg...\n";

        MY::preinstall( $pkg, $ver ) or next if defined &MY::preinstall;

        my $success;
        my $obj = $modtree->{$pkg};

        if ( $obj and _version_cmp( $obj->{version}, $ver ) >= 0 ) {
            my $pathname = $pkg;
            $pathname =~ s/::/\\W/;

            foreach my $inc ( grep { m/$pathname.pm/i } keys(%INC) ) {
                delete $INC{$inc};
            }

            my $rv = $cp->install( modules => [ $obj->{module} ] );

            if ( $rv and ( $rv->{ $obj->{module} } or $rv->{ok} ) ) {
                print "*** $pkg successfully installed.\n";
                $success = 1;
            } else {
                print "*** $pkg installation cancelled.\n";
                $success = 0;
            }

            $installed += $success;
        } else {
            print << ".";
*** Could not find a version $ver or above for $pkg; skipping.
.
        }

        MY::postinstall( $pkg, $ver, $success ) if defined &MY::postinstall;
    }

    return $installed;
}

sub _cpanplus_config {
	my @config = ();
	while ( @_ ) {
		my ($key, $value) = (shift(), shift());
		if ( $key eq 'prerequisites_policy' ) {
			if ( $value eq 'follow' ) {
				$value = CPANPLUS::Internals::Constants::PREREQ_INSTALL();
			} elsif ( $value eq 'ask' ) {
				$value = CPANPLUS::Internals::Constants::PREREQ_ASK();
			} elsif ( $value eq 'ignore' ) {
				$value = CPANPLUS::Internals::Constants::PREREQ_IGNORE();
			} else {
				die "*** Cannot convert option $key = '$value' to CPANPLUS version.\n";
			}
			push @config, 'prereqs', $value;
		} elsif ( $key eq 'force' ) {
		    push @config, $key, $value;
		} elsif ( $key eq 'notest' ) {
		    push @config, 'skiptest', $value;
		} else {
			die "*** Cannot convert option $key to CPANPLUS version.\n";
		}
	}
	return @config;
}

sub _install_cpan {
    my @modules   = @{ +shift };
    my @config    = @{ +shift };
    my $installed = 0;
    my %args;

    _load_cpan();
    require Config;

    if (CPAN->VERSION < 1.80) {
        # no "sudo" support, probe for writableness
        return unless _can_write( MM->catfile( $CPAN::Config->{cpan_home}, 'sources' ) )
                  and _can_write( $Config::Config{sitelib} );
    }

    # if we're root, set UNINST=1 to avoid trouble unless user asked for it.
    my $makeflags = $CPAN::Config->{make_install_arg} || '';
    $CPAN::Config->{make_install_arg} =
      join( ' ', split( ' ', $makeflags ), 'UNINST=1' )
      if ( $makeflags !~ /\bUNINST\b/ and eval qq{ $> eq '0' } );

    # don't show start-up info
    $CPAN::Config->{inhibit_startup_message} = 1;

    # set additional options
    while ( my ( $opt, $arg ) = splice( @config, 0, 2 ) ) {
        ( $args{$opt} = $arg, next )
          if $opt =~ /^(?:force|notest)$/;    # pseudo-option
        $CPAN::Config->{$opt} = $arg;
    }

    if ($args{notest} && (not CPAN::Shell->can('notest'))) {
	die "Your version of CPAN is too old to support the 'notest' pragma";
    }

    local $CPAN::Config->{prerequisites_policy} = 'follow';

    while ( my ( $pkg, $ver ) = splice( @modules, 0, 2 ) ) {
        MY::preinstall( $pkg, $ver ) or next if defined &MY::preinstall;

        print "*** Installing $pkg...\n";

        my $obj     = CPAN::Shell->expand( Module => $pkg );
        my $success = 0;

        if ( $obj and _version_cmp( $obj->cpan_version, $ver ) >= 0 ) {
            my $pathname = $pkg;
            $pathname =~ s/::/\\W/;

            foreach my $inc ( grep { m/$pathname.pm/i } keys(%INC) ) {
                delete $INC{$inc};
            }

            my $rv = do {
		if ($args{force}) {
		    CPAN::Shell->force( install => $pkg )
		} elsif ($args{notest}) {
		    CPAN::Shell->notest( install => $pkg )
		} else {
		    CPAN::Shell->install($pkg)
		}
	    };

            $rv ||= eval {
                $CPAN::META->instance( 'CPAN::Distribution', $obj->cpan_file, )
                  ->{install}
                  if $CPAN::META;
            };

            if ( $rv eq 'YES' ) {
                print "*** $pkg successfully installed.\n";
                $success = 1;
            }
            else {
                print "*** $pkg installation failed.\n";
                $success = 0;
            }

            $installed += $success;
        }
        else {
            print << ".";
*** Could not find a version $ver or above for $pkg; skipping.
.
        }

        MY::postinstall( $pkg, $ver, $success ) if defined &MY::postinstall;
    }

    return $installed;
}

sub _has_cpanplus {
    return (
        $HasCPANPLUS = (
            $INC{'CPANPLUS/Config.pm'}
              or _load('CPANPLUS::Shell::Default')
        )
    );
}

# make guesses on whether we're under the CPAN installation directory
sub _under_cpan {
    require Cwd;
    require File::Spec;

    my $cwd  = File::Spec->canonpath( Cwd::cwd() );
    my $cpan = File::Spec->canonpath( $CPAN::Config->{cpan_home} );

    return ( index( $cwd, $cpan ) > -1 );
}

sub _update_to {
    my $class = __PACKAGE__;
    my $ver   = shift;

    return
      if _version_cmp( _version_of($class), $ver ) >= 0;  # no need to upgrade

    if (
        _prompt( "==> A newer version of $class ($ver) is required. Install?",
            'y' ) =~ /^[Nn]/
      )
    {
        die "*** Please install $class $ver manually.\n";
    }

    print << ".";
*** Trying to fetch it from CPAN...
.

    # install ourselves
    _load($class) and return $class->import(@_)
      if $class->install( [], $class, $ver );

    print << '.'; exit 1;

*** Cannot bootstrap myself. :-( Installation terminated.
.
}

# check if we're connected to some host, using inet_aton
sub _connected_to {
    my $site = shift;

    return (
        ( _load('Socket') and Socket::inet_aton($site) ) or _prompt(
            qq(
*** Your host cannot resolve the domain name '$site', which
    probably means the Internet connections are unavailable.
==> Should we try to install the required module(s) anyway?), 'n'
          ) =~ /^[Yy]/
    );
}

# check if a directory is writable; may create it on demand
sub _can_write {
    my $path = shift;
    mkdir( $path, 0755 ) unless -e $path;

    return 1 if -w $path;

    print << ".";
*** You are not allowed to write to the directory '$path';
    the installation may fail due to insufficient permissions.
.

    if (
        eval '$>' and lc(`sudo -V`) =~ /version/ and _prompt(
            qq(
==> Should we try to re-execute the autoinstall process with 'sudo'?),
            ((-t STDIN) ? 'y' : 'n')
        ) =~ /^[Yy]/
      )
    {

        # try to bootstrap ourselves from sudo
        print << ".";
*** Trying to re-execute the autoinstall process with 'sudo'...
.
        my $missing = join( ',', @Missing );
        my $config = join( ',',
            UNIVERSAL::isa( $Config, 'HASH' ) ? %{$Config} : @{$Config} )
          if $Config;

        return
          unless system( 'sudo', $^X, $0, "--config=$config",
            "--installdeps=$missing" );

        print << ".";
*** The 'sudo' command exited with error!  Resuming...
.
    }

    return _prompt(
        qq(
==> Should we try to install the required module(s) anyway?), 'n'
    ) =~ /^[Yy]/;
}

# load a module and return the version it reports
sub _load {
    my $mod  = pop; # method/function doesn't matter
    my $file = $mod;
    $file =~ s|::|/|g;
    $file .= '.pm';
    local $@;
    return eval { require $file; $mod->VERSION } || ( $@ ? undef: 0 );
}

# report version without loading a module
sub _version_of {
    my $mod = pop; # method/function doesn't matter
    my $file = $mod;
    $file =~ s|::|/|g;
    $file .= '.pm';
    foreach my $dir ( @INC ) {
        next if ref $dir;
        my $path = File::Spec->catfile($dir, $file);
        next unless -e $path;
        require ExtUtils::MM_Unix;
        return ExtUtils::MM_Unix->parse_version($path);
    }
    return undef;
}

# Load CPAN.pm and it's configuration
sub _load_cpan {
    return if $CPAN::VERSION and $CPAN::Config and not @_;
    require CPAN;

    # CPAN-1.82+ adds CPAN::Config::AUTOLOAD to redirect to
    #    CPAN::HandleConfig->load. CPAN reports that the redirection
    #    is deprecated in a warning printed at the user.

    # CPAN-1.81 expects CPAN::HandleConfig->load, does not have
    #   $CPAN::HandleConfig::VERSION but cannot handle
    #   CPAN::Config->load

    # Which "versions expect CPAN::Config->load?

    if ( $CPAN::HandleConfig::VERSION
        || CPAN::HandleConfig->can('load')
    ) {
        # Newer versions of CPAN have a HandleConfig module
        CPAN::HandleConfig->load;
    } else {
    	# Older versions had the load method in Config directly
        CPAN::Config->load;
    }
}

# compare two versions, either use Sort::Versions or plain comparison
# return values same as <=>
sub _version_cmp {
    my ( $cur, $min ) = @_;
    return -1 unless defined $cur;  # if 0 keep comparing
    return 1 unless $min;

    $cur =~ s/\s+$//;

    # check for version numbers that are not in decimal format
    if ( ref($cur) or ref($min) or $cur =~ /v|\..*\./ or $min =~ /v|\..*\./ ) {
        if ( ( $version::VERSION or defined( _load('version') )) and
             version->can('new') 
            ) {

            # use version.pm if it is installed.
            return version->new($cur) <=> version->new($min);
        }
        elsif ( $Sort::Versions::VERSION or defined( _load('Sort::Versions') ) )
        {

            # use Sort::Versions as the sorting algorithm for a.b.c versions
            return Sort::Versions::versioncmp( $cur, $min );
        }

        warn "Cannot reliably compare non-decimal formatted versions.\n"
          . "Please install version.pm or Sort::Versions.\n";
    }

    # plain comparison
    local $^W = 0;    # shuts off 'not numeric' bugs
    return $cur <=> $min;
}

# nothing; this usage is deprecated.
sub main::PREREQ_PM { return {}; }

sub _make_args {
    my %args = @_;

    $args{PREREQ_PM} = { %{ $args{PREREQ_PM} || {} }, @Existing, @Missing }
      if $UnderCPAN or $TestOnly;

    if ( $args{EXE_FILES} and -e 'MANIFEST' ) {
        require ExtUtils::Manifest;
        my $manifest = ExtUtils::Manifest::maniread('MANIFEST');

        $args{EXE_FILES} =
          [ grep { exists $manifest->{$_} } @{ $args{EXE_FILES} } ];
    }

    $args{test}{TESTS} ||= 't/*.t';
    $args{test}{TESTS} = join( ' ',
        grep { !exists( $DisabledTests{$_} ) }
          map { glob($_) } split( /\s+/, $args{test}{TESTS} ) );

    my $missing = join( ',', @Missing );
    my $config =
      join( ',', UNIVERSAL::isa( $Config, 'HASH' ) ? %{$Config} : @{$Config} )
      if $Config;

    $PostambleActions = (
        ($missing and not $UnderCPAN)
        ? "\$(PERL) $0 --config=$config --installdeps=$missing"
        : "\$(NOECHO) \$(NOOP)"
    );

    my $deps_list = join( ',', @Missing, @Existing );

    $PostambleActionsUpgradeDeps =
        "\$(PERL) $0 --config=$config --upgradedeps=$deps_list";

    my $config_notest =
      join( ',', (UNIVERSAL::isa( $Config, 'HASH' ) ? %{$Config} : @{$Config}),
	  'notest', 1 )
      if $Config;

    $PostambleActionsNoTest = (
        ($missing and not $UnderCPAN)
        ? "\$(PERL) $0 --config=$config_notest --installdeps=$missing"
        : "\$(NOECHO) \$(NOOP)"
    );

    $PostambleActionsUpgradeDepsNoTest =
        "\$(PERL) $0 --config=$config_notest --upgradedeps=$deps_list";

    $PostambleActionsListDeps =
        '@$(PERL) -le "print for @ARGV" '
            . join(' ', map $Missing[$_], grep $_ % 2 == 0, 0..$#Missing);

    my @all = (@Missing, @Existing);

    $PostambleActionsListAllDeps =
        '@$(PERL) -le "print for @ARGV" '
            . join(' ', map $all[$_], grep $_ % 2 == 0, 0..$#all);

    return %args;
}

# a wrapper to ExtUtils::MakeMaker::WriteMakefile
sub Write {
    require Carp;
    Carp::croak "WriteMakefile: Need even number of args" if @_ % 2;

    if ($CheckOnly) {
        print << ".";
*** Makefile not written in check-only mode.
.
        return;
    }

    my %args = _make_args(@_);

    no strict 'refs';

    $PostambleUsed = 0;
    local *MY::postamble = \&postamble unless defined &MY::postamble;
    ExtUtils::MakeMaker::WriteMakefile(%args);

    print << "." unless $PostambleUsed;
*** WARNING: Makefile written with customized MY::postamble() without
    including contents from Module::AutoInstall::postamble() --
    auto installation features disabled.  Please contact the author.
.

    return 1;
}

sub postamble {
    $PostambleUsed = 1;
    my $fragment;

    $fragment .= <<"AUTO_INSTALL" if !$InstallDepsTarget;

config :: installdeps
\t\$(NOECHO) \$(NOOP)
AUTO_INSTALL

    $fragment .= <<"END_MAKE";

checkdeps ::
\t\$(PERL) $0 --checkdeps

installdeps ::
\t$PostambleActions

installdeps_notest ::
\t$PostambleActionsNoTest

upgradedeps ::
\t$PostambleActionsUpgradeDeps

upgradedeps_notest ::
\t$PostambleActionsUpgradeDepsNoTest

listdeps ::
\t$PostambleActionsListDeps

listalldeps ::
\t$PostambleActionsListAllDeps

END_MAKE

    return $fragment;
}

1;

__END__

#line 1193
