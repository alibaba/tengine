#line 1
package Spiffy;
use strict;
use 5.006001;
use warnings;
use Carp;
require Exporter;
our $VERSION = '0.30';
our @EXPORT = ();
our @EXPORT_BASE = qw(field const stub super);
our @EXPORT_OK = (@EXPORT_BASE, qw(id WWW XXX YYY ZZZ));
our %EXPORT_TAGS = (XXX => [qw(WWW XXX YYY ZZZ)]);

my $stack_frame = 0; 
my $dump = 'yaml';
my $bases_map = {};

sub WWW; sub XXX; sub YYY; sub ZZZ;

# This line is here to convince "autouse" into believing we are autousable.
sub can {
    ($_[1] eq 'import' and caller()->isa('autouse'))
        ? \&Exporter::import        # pacify autouse's equality test
        : $_[0]->SUPER::can($_[1])  # normal case
}

# TODO
#
# Exported functions like field and super should be hidden so as not to
# be confused with methods that can be inherited.
#

sub new {
    my $class = shift;
    $class = ref($class) || $class;
    my $self = bless {}, $class;
    while (@_) {
        my $method = shift;
        $self->$method(shift);
    }
    return $self;    
}

my $filtered_files = {};
my $filter_dump = 0;
my $filter_save = 0;
our $filter_result = '';
sub import {
    no strict 'refs'; 
    no warnings;
    my $self_package = shift;

    # XXX Using parse_arguments here might cause confusion, because the
    # subclass's boolean_arguments and paired_arguments can conflict, causing
    # difficult debugging. Consider using something truly local.
    my ($args, @export_list) = do {
        local *boolean_arguments = sub { 
            qw(
                -base -Base -mixin -selfless 
                -XXX -dumper -yaml 
                -filter_dump -filter_save
            ) 
        };
        local *paired_arguments = sub { qw(-package) };
        $self_package->parse_arguments(@_);
    };
    return spiffy_mixin_import(scalar(caller(0)), $self_package, @export_list)
      if $args->{-mixin};

    $filter_dump = 1 if $args->{-filter_dump};
    $filter_save = 1 if $args->{-filter_save};
    $dump = 'yaml' if $args->{-yaml};
    $dump = 'dumper' if $args->{-dumper};

    local @EXPORT_BASE = @EXPORT_BASE;

    if ($args->{-XXX}) {
        push @EXPORT_BASE, @{$EXPORT_TAGS{XXX}}
          unless grep /^XXX$/, @EXPORT_BASE;
    }

    spiffy_filter() 
      if ($args->{-selfless} or $args->{-Base}) and 
         not $filtered_files->{(caller($stack_frame))[1]}++;

    my $caller_package = $args->{-package} || caller($stack_frame);
    push @{"$caller_package\::ISA"}, $self_package
      if $args->{-Base} or $args->{-base};

    for my $class (@{all_my_bases($self_package)}) {
        next unless $class->isa('Spiffy');
        my @export = grep {
            not defined &{"$caller_package\::$_"};
        } ( @{"$class\::EXPORT"}, 
            ($args->{-Base} or $args->{-base})
              ? @{"$class\::EXPORT_BASE"} : (),
          );
        my @export_ok = grep {
            not defined &{"$caller_package\::$_"};
        } @{"$class\::EXPORT_OK"};

        # Avoid calling the expensive Exporter::export 
        # if there is nothing to do (optimization)
        my %exportable = map { ($_, 1) } @export, @export_ok;
        next unless keys %exportable;

        my @export_save = @{"$class\::EXPORT"};
        my @export_ok_save = @{"$class\::EXPORT_OK"};
        @{"$class\::EXPORT"} = @export;
        @{"$class\::EXPORT_OK"} = @export_ok;
        my @list = grep {
            (my $v = $_) =~ s/^[\!\:]//;
            $exportable{$v} or ${"$class\::EXPORT_TAGS"}{$v};
        } @export_list;
        Exporter::export($class, $caller_package, @list);
        @{"$class\::EXPORT"} = @export_save;
        @{"$class\::EXPORT_OK"} = @export_ok_save;
    }
}

sub spiffy_filter {
    require Filter::Util::Call;
    my $done = 0;
    Filter::Util::Call::filter_add(
        sub {
            return 0 if $done;
            my ($data, $end) = ('', '');
            while (my $status = Filter::Util::Call::filter_read()) {
                return $status if $status < 0;
                if (/^__(?:END|DATA)__\r?$/) {
                    $end = $_;
                    last;
                }
                $data .= $_;
                $_ = '';
            }
            $_ = $data;
            my @my_subs;
            s[^(sub\s+\w+\s+\{)(.*\n)]
             [${1}my \$self = shift;$2]gm;
            s[^(sub\s+\w+)\s*\(\s*\)(\s+\{.*\n)]
             [${1}${2}]gm;
            s[^my\s+sub\s+(\w+)(\s+\{)(.*)((?s:.*?\n))\}\n]
             [push @my_subs, $1; "\$$1 = sub$2my \$self = shift;$3$4\};\n"]gem;
            my $preclare = '';
            if (@my_subs) {
                $preclare = join ',', map "\$$_", @my_subs;
                $preclare = "my($preclare);";
            }
            $_ = "use strict;use warnings;$preclare${_};1;\n$end";
            if ($filter_dump) { print; exit }
            if ($filter_save) { $filter_result = $_; $_ = $filter_result; }
            $done = 1;
        }
    );
}

sub base {
    push @_, -base;
    goto &import;
}

sub all_my_bases {
    my $class = shift;

    return $bases_map->{$class} 
      if defined $bases_map->{$class};

    my @bases = ($class);
    no strict 'refs';
    for my $base_class (@{"${class}::ISA"}) {
        push @bases, @{all_my_bases($base_class)};
    }
    my $used = {};
    $bases_map->{$class} = [grep {not $used->{$_}++} @bases];
}

my %code = ( 
    sub_start => 
      "sub {\n",
    set_default => 
      "  \$_[0]->{%s} = %s\n    unless exists \$_[0]->{%s};\n",
    init =>
      "  return \$_[0]->{%s} = do { my \$self = \$_[0]; %s }\n" .
      "    unless \$#_ > 0 or defined \$_[0]->{%s};\n",
    weak_init =>
      "  return do {\n" .
      "    \$_[0]->{%s} = do { my \$self = \$_[0]; %s };\n" .
      "    Scalar::Util::weaken(\$_[0]->{%s}) if ref \$_[0]->{%s};\n" .
      "    \$_[0]->{%s};\n" .
      "  } unless \$#_ > 0 or defined \$_[0]->{%s};\n",
    return_if_get => 
      "  return \$_[0]->{%s} unless \$#_ > 0;\n",
    set => 
      "  \$_[0]->{%s} = \$_[1];\n",
    weaken => 
      "  Scalar::Util::weaken(\$_[0]->{%s}) if ref \$_[0]->{%s};\n",
    sub_end => 
      "  return \$_[0]->{%s};\n}\n",
);

sub field {
    my $package = caller;
    my ($args, @values) = do {
        no warnings;
        local *boolean_arguments = sub { (qw(-weak)) };
        local *paired_arguments = sub { (qw(-package -init)) };
        Spiffy->parse_arguments(@_);
    };
    my ($field, $default) = @values;
    $package = $args->{-package} if defined $args->{-package};
    die "Cannot have a default for a weakened field ($field)"
        if defined $default && $args->{-weak};
    return if defined &{"${package}::$field"};
    require Scalar::Util if $args->{-weak};
    my $default_string =
        ( ref($default) eq 'ARRAY' and not @$default )
        ? '[]'
        : (ref($default) eq 'HASH' and not keys %$default )
          ? '{}'
          : default_as_code($default);

    my $code = $code{sub_start};
    if ($args->{-init}) {
        my $fragment = $args->{-weak} ? $code{weak_init} : $code{init};
        $code .= sprintf $fragment, $field, $args->{-init}, ($field) x 4;
    }
    $code .= sprintf $code{set_default}, $field, $default_string, $field
      if defined $default;
    $code .= sprintf $code{return_if_get}, $field;
    $code .= sprintf $code{set}, $field;
    $code .= sprintf $code{weaken}, $field, $field 
      if $args->{-weak};
    $code .= sprintf $code{sub_end}, $field;

    my $sub = eval $code;
    die $@ if $@;
    no strict 'refs';
    *{"${package}::$field"} = $sub;
    return $code if defined wantarray;
}

sub default_as_code {
    require Data::Dumper;
    local $Data::Dumper::Sortkeys = 1;
    my $code = Data::Dumper::Dumper(shift);
    $code =~ s/^\$VAR1 = //;
    $code =~ s/;$//;
    return $code;
}

sub const {
    my $package = caller;
    my ($args, @values) = do {
        no warnings;
        local *paired_arguments = sub { (qw(-package)) };
        Spiffy->parse_arguments(@_);
    };
    my ($field, $default) = @values;
    $package = $args->{-package} if defined $args->{-package};
    no strict 'refs';
    return if defined &{"${package}::$field"};
    *{"${package}::$field"} = sub { $default }
}

sub stub {
    my $package = caller;
    my ($args, @values) = do {
        no warnings;
        local *paired_arguments = sub { (qw(-package)) };
        Spiffy->parse_arguments(@_);
    };
    my ($field, $default) = @values;
    $package = $args->{-package} if defined $args->{-package};
    no strict 'refs';
    return if defined &{"${package}::$field"};
    *{"${package}::$field"} = 
    sub { 
        require Carp;
        Carp::confess 
          "Method $field in package $package must be subclassed";
    }
}

sub parse_arguments {
    my $class = shift;
    my ($args, @values) = ({}, ());
    my %booleans = map { ($_, 1) } $class->boolean_arguments;
    my %pairs = map { ($_, 1) } $class->paired_arguments;
    while (@_) {
        my $elem = shift;
        if (defined $elem and defined $booleans{$elem}) {
            $args->{$elem} = (@_ and $_[0] =~ /^[01]$/)
            ? shift
            : 1;
        }
        elsif (defined $elem and defined $pairs{$elem} and @_) {
            $args->{$elem} = shift;
        }
        else {
            push @values, $elem;
        }
    }
    return wantarray ? ($args, @values) : $args;        
}

sub boolean_arguments { () }
sub paired_arguments { () }

# get a unique id for any node
sub id {
    if (not ref $_[0]) {
        return 'undef' if not defined $_[0];
        \$_[0] =~ /\((\w+)\)$/o or die;
        return "$1-S";
    }
    require overload;
    overload::StrVal($_[0]) =~ /\((\w+)\)$/o or die;
    return $1;
}

#===============================================================================
# It's super, man.
#===============================================================================
package DB;
{
    no warnings 'redefine';
    sub super_args { 
        my @dummy = caller(@_ ? $_[0] : 2); 
        return @DB::args;
    }
}

package Spiffy;
sub super {
    my $method;
    my $frame = 1;
    while ($method = (caller($frame++))[3]) {
        $method =~ s/.*::// and last;
    }
    my @args = DB::super_args($frame);
    @_ = @_ ? ($args[0], @_) : @args;
    my $class = ref $_[0] ? ref $_[0] : $_[0];
    my $caller_class = caller;
    my $seen = 0;
    my @super_classes = reverse grep {
        ($seen or $seen = ($_ eq $caller_class)) ? 0 : 1;
    } reverse @{all_my_bases($class)};
    for my $super_class (@super_classes) {
        no strict 'refs';
        next if $super_class eq $class;
        if (defined &{"${super_class}::$method"}) {
            ${"$super_class\::AUTOLOAD"} = ${"$class\::AUTOLOAD"}
              if $method eq 'AUTOLOAD';
            return &{"${super_class}::$method"};
        }
    }
    return;
}

#===============================================================================
# This code deserves a spanking, because it is being very naughty.
# It is exchanging base.pm's import() for its own, so that people
# can use base.pm with Spiffy modules, without being the wiser.
#===============================================================================
my $real_base_import;
my $real_mixin_import;

BEGIN {
    require base unless defined $INC{'base.pm'};
    $INC{'mixin.pm'} ||= 'Spiffy/mixin.pm';
    $real_base_import = \&base::import;
    $real_mixin_import = \&mixin::import;
    no warnings;
    *base::import = \&spiffy_base_import;
    *mixin::import = \&spiffy_mixin_import;
}

# my $i = 0;
# while (my $caller = caller($i++)) {
#     next unless $caller eq 'base' or $caller eq 'mixin';
#     croak <<END;
# Spiffy.pm must be loaded before calling 'use base' or 'use mixin' with a
# Spiffy module. See the documentation of Spiffy.pm for details.
# END
# }

sub spiffy_base_import {
    my @base_classes = @_;
    shift @base_classes;
    no strict 'refs';
    goto &$real_base_import
      unless grep {
          eval "require $_" unless %{"$_\::"};
          $_->isa('Spiffy');
      } @base_classes;
    my $inheritor = caller(0);
    for my $base_class (@base_classes) {
        next if $inheritor->isa($base_class);
        croak "Can't mix Spiffy and non-Spiffy classes in 'use base'.\n", 
              "See the documentation of Spiffy.pm for details\n  "
          unless $base_class->isa('Spiffy');
        $stack_frame = 1; # tell import to use different caller
        import($base_class, '-base');
        $stack_frame = 0;
    }
}

sub mixin {
    my $self = shift;
    my $target_class = ref($self);
    spiffy_mixin_import($target_class, @_)
}

sub spiffy_mixin_import {
    my $target_class = shift;
    $target_class = caller(0)
      if $target_class eq 'mixin';
    my $mixin_class = shift
      or die "Nothing to mixin";
    eval "require $mixin_class";
    my @roles = @_;
    my $pseudo_class = join '-', $target_class, $mixin_class, @roles;
    my %methods = spiffy_mixin_methods($mixin_class, @roles);
    no strict 'refs';
    no warnings;
    @{"$pseudo_class\::ISA"} = @{"$target_class\::ISA"};
    @{"$target_class\::ISA"} = ($pseudo_class);
    for (keys %methods) {
        *{"$pseudo_class\::$_"} = $methods{$_};
    }
}

sub spiffy_mixin_methods {
    my $mixin_class = shift;
    no strict 'refs';
    my %methods = spiffy_all_methods($mixin_class);
    map {
        $methods{$_}
          ? ($_, \ &{"$methods{$_}\::$_"})
          : ($_, \ &{"$mixin_class\::$_"})
    } @_ 
      ? (get_roles($mixin_class, @_))
      : (keys %methods);
}

sub get_roles {
    my $mixin_class = shift;
    my @roles = @_;
    while (grep /^!*:/, @roles) {
        @roles = map {
            s/!!//g;
            /^!:(.*)/ ? do { 
                my $m = "_role_$1"; 
                map("!$_", $mixin_class->$m);
            } :
            /^:(.*)/ ? do {
                my $m = "_role_$1"; 
                ($mixin_class->$m);
            } :
            ($_)
        } @roles;
    }
    if (@roles and $roles[0] =~ /^!/) {
        my %methods = spiffy_all_methods($mixin_class);
        unshift @roles, keys(%methods);
    }
    my %roles;
    for (@roles) {
        s/!!//g;
        delete $roles{$1}, next
          if /^!(.*)/;
        $roles{$_} = 1;
    }
    keys %roles;
}

sub spiffy_all_methods {
    no strict 'refs';
    my $class = shift;
    return if $class eq 'Spiffy';
    my %methods = map {
        ($_, $class)
    } grep {
        defined &{"$class\::$_"} and not /^_/
    } keys %{"$class\::"};
    my %super_methods;
    %super_methods = spiffy_all_methods(${"$class\::ISA"}[0])
      if @{"$class\::ISA"};
    %{{%super_methods, %methods}};
}


# END of naughty code.
#===============================================================================
# Debugging support
#===============================================================================
sub spiffy_dump {
    no warnings;
    if ($dump eq 'dumper') {
        require Data::Dumper;
        $Data::Dumper::Sortkeys = 1;
        $Data::Dumper::Indent = 1;
        return Data::Dumper::Dumper(@_);
    }
    require YAML;
    $YAML::UseVersion = 0;
    return YAML::Dump(@_) . "...\n";
}

sub at_line_number {
    my ($file_path, $line_number) = (caller(1))[1,2];
    "  at $file_path line $line_number\n";
}

sub WWW {
    warn spiffy_dump(@_) . at_line_number;
    return wantarray ? @_ : $_[0];
}

sub XXX {
    die spiffy_dump(@_) . at_line_number;
}

sub YYY {
    print spiffy_dump(@_) . at_line_number;
    return wantarray ? @_ : $_[0];
}

sub ZZZ {
    require Carp;
    Carp::confess spiffy_dump(@_);
}

1;

__END__

#line 1066
