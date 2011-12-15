#line 1
package Test::Builder;

use 5.006;
use strict;
use warnings;

our $VERSION = '0.92';
$VERSION = eval $VERSION;    ## no critic (BuiltinFunctions::ProhibitStringyEval)

BEGIN {
    if( $] < 5.008 ) {
        require Test::Builder::IO::Scalar;
    }
}


# Make Test::Builder thread-safe for ithreads.
BEGIN {
    use Config;
    # Load threads::shared when threads are turned on.
    # 5.8.0's threads are so busted we no longer support them.
    if( $] >= 5.008001 && $Config{useithreads} && $INC{'threads.pm'} ) {
        require threads::shared;

        # Hack around YET ANOTHER threads::shared bug.  It would
        # occassionally forget the contents of the variable when sharing it.
        # So we first copy the data, then share, then put our copy back.
        *share = sub (\[$@%]) {
            my $type = ref $_[0];
            my $data;

            if( $type eq 'HASH' ) {
                %$data = %{ $_[0] };
            }
            elsif( $type eq 'ARRAY' ) {
                @$data = @{ $_[0] };
            }
            elsif( $type eq 'SCALAR' ) {
                $$data = ${ $_[0] };
            }
            else {
                die( "Unknown type: " . $type );
            }

            $_[0] = &threads::shared::share( $_[0] );

            if( $type eq 'HASH' ) {
                %{ $_[0] } = %$data;
            }
            elsif( $type eq 'ARRAY' ) {
                @{ $_[0] } = @$data;
            }
            elsif( $type eq 'SCALAR' ) {
                ${ $_[0] } = $$data;
            }
            else {
                die( "Unknown type: " . $type );
            }

            return $_[0];
        };
    }
    # 5.8.0's threads::shared is busted when threads are off
    # and earlier Perls just don't have that module at all.
    else {
        *share = sub { return $_[0] };
        *lock  = sub { 0 };
    }
}

#line 117

my $Test = Test::Builder->new;

sub new {
    my($class) = shift;
    $Test ||= $class->create;
    return $Test;
}

#line 139

sub create {
    my $class = shift;

    my $self = bless {}, $class;
    $self->reset;

    return $self;
}

#line 158

our $Level;

sub reset {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my($self) = @_;

    # We leave this a global because it has to be localized and localizing
    # hash keys is just asking for pain.  Also, it was documented.
    $Level = 1;

    $self->{Have_Plan}    = 0;
    $self->{No_Plan}      = 0;
    $self->{Have_Output_Plan} = 0;

    $self->{Original_Pid} = $$;

    share( $self->{Curr_Test} );
    $self->{Curr_Test} = 0;
    $self->{Test_Results} = &share( [] );

    $self->{Exported_To}    = undef;
    $self->{Expected_Tests} = 0;

    $self->{Skip_All} = 0;

    $self->{Use_Nums} = 1;

    $self->{No_Header} = 0;
    $self->{No_Ending} = 0;

    $self->{Todo}       = undef;
    $self->{Todo_Stack} = [];
    $self->{Start_Todo} = 0;
    $self->{Opened_Testhandles} = 0;

    $self->_dup_stdhandles;

    return;
}

#line 219

my %plan_cmds = (
    no_plan     => \&no_plan,
    skip_all    => \&skip_all,
    tests       => \&_plan_tests,
);

sub plan {
    my( $self, $cmd, $arg ) = @_;

    return unless $cmd;

    local $Level = $Level + 1;

    $self->croak("You tried to plan twice") if $self->{Have_Plan};

    if( my $method = $plan_cmds{$cmd} ) {
        local $Level = $Level + 1;
        $self->$method($arg);
    }
    else {
        my @args = grep { defined } ( $cmd, $arg );
        $self->croak("plan() doesn't understand @args");
    }

    return 1;
}


sub _plan_tests {
    my($self, $arg) = @_;

    if($arg) {
        local $Level = $Level + 1;
        return $self->expected_tests($arg);
    }
    elsif( !defined $arg ) {
        $self->croak("Got an undefined number of tests");
    }
    else {
        $self->croak("You said to run 0 tests");
    }

    return;
}


#line 275

sub expected_tests {
    my $self = shift;
    my($max) = @_;

    if(@_) {
        $self->croak("Number of tests must be a positive integer.  You gave it '$max'")
          unless $max =~ /^\+?\d+$/;

        $self->{Expected_Tests} = $max;
        $self->{Have_Plan}      = 1;

        $self->_output_plan($max) unless $self->no_header;
    }
    return $self->{Expected_Tests};
}

#line 299

sub no_plan {
    my($self, $arg) = @_;

    $self->carp("no_plan takes no arguments") if $arg;

    $self->{No_Plan}   = 1;
    $self->{Have_Plan} = 1;

    return 1;
}


#line 333

sub _output_plan {
    my($self, $max, $directive, $reason) = @_;

    $self->carp("The plan was already output") if $self->{Have_Output_Plan};

    my $plan = "1..$max";
    $plan .= " # $directive" if defined $directive;
    $plan .= " $reason"      if defined $reason;

    $self->_print("$plan\n");

    $self->{Have_Output_Plan} = 1;

    return;
}

#line 384

sub done_testing {
    my($self, $num_tests) = @_;

    # If done_testing() specified the number of tests, shut off no_plan.
    if( defined $num_tests ) {
        $self->{No_Plan} = 0;
    }
    else {
        $num_tests = $self->current_test;
    }

    if( $self->{Done_Testing} ) {
        my($file, $line) = @{$self->{Done_Testing}}[1,2];
        $self->ok(0, "done_testing() was already called at $file line $line");
        return;
    }

    $self->{Done_Testing} = [caller];

    if( $self->expected_tests && $num_tests != $self->expected_tests ) {
        $self->ok(0, "planned to run @{[ $self->expected_tests ]} ".
                     "but done_testing() expects $num_tests");
    }
    else {
        $self->{Expected_Tests} = $num_tests;
    }

    $self->_output_plan($num_tests) unless $self->{Have_Output_Plan};

    $self->{Have_Plan} = 1;

    return 1;
}


#line 429

sub has_plan {
    my $self = shift;

    return( $self->{Expected_Tests} ) if $self->{Expected_Tests};
    return('no_plan') if $self->{No_Plan};
    return(undef);
}

#line 446

sub skip_all {
    my( $self, $reason ) = @_;

    $self->{Skip_All} = 1;

    $self->_output_plan(0, "SKIP", $reason) unless $self->no_header;
    exit(0);
}

#line 468

sub exported_to {
    my( $self, $pack ) = @_;

    if( defined $pack ) {
        $self->{Exported_To} = $pack;
    }
    return $self->{Exported_To};
}

#line 498

sub ok {
    my( $self, $test, $name ) = @_;

    # $test might contain an object which we don't want to accidentally
    # store, so we turn it into a boolean.
    $test = $test ? 1 : 0;

    lock $self->{Curr_Test};
    $self->{Curr_Test}++;

    # In case $name is a string overloaded object, force it to stringify.
    $self->_unoverload_str( \$name );

    $self->diag(<<"ERR") if defined $name and $name =~ /^[\d\s]+$/;
    You named your test '$name'.  You shouldn't use numbers for your test names.
    Very confusing.
ERR

    # Capture the value of $TODO for the rest of this ok() call
    # so it can more easily be found by other routines.
    my $todo    = $self->todo();
    my $in_todo = $self->in_todo;
    local $self->{Todo} = $todo if $in_todo;

    $self->_unoverload_str( \$todo );

    my $out;
    my $result = &share( {} );

    unless($test) {
        $out .= "not ";
        @$result{ 'ok', 'actual_ok' } = ( ( $self->in_todo ? 1 : 0 ), 0 );
    }
    else {
        @$result{ 'ok', 'actual_ok' } = ( 1, $test );
    }

    $out .= "ok";
    $out .= " $self->{Curr_Test}" if $self->use_numbers;

    if( defined $name ) {
        $name =~ s|#|\\#|g;    # # in a name can confuse Test::Harness.
        $out .= " - $name";
        $result->{name} = $name;
    }
    else {
        $result->{name} = '';
    }

    if( $self->in_todo ) {
        $out .= " # TODO $todo";
        $result->{reason} = $todo;
        $result->{type}   = 'todo';
    }
    else {
        $result->{reason} = '';
        $result->{type}   = '';
    }

    $self->{Test_Results}[ $self->{Curr_Test} - 1 ] = $result;
    $out .= "\n";

    $self->_print($out);

    unless($test) {
        my $msg = $self->in_todo ? "Failed (TODO)" : "Failed";
        $self->_print_to_fh( $self->_diag_fh, "\n" ) if $ENV{HARNESS_ACTIVE};

        my( undef, $file, $line ) = $self->caller;
        if( defined $name ) {
            $self->diag(qq[  $msg test '$name'\n]);
            $self->diag(qq[  at $file line $line.\n]);
        }
        else {
            $self->diag(qq[  $msg test at $file line $line.\n]);
        }
    }

    return $test ? 1 : 0;
}

sub _unoverload {
    my $self = shift;
    my $type = shift;

    $self->_try(sub { require overload; }, die_on_fail => 1);

    foreach my $thing (@_) {
        if( $self->_is_object($$thing) ) {
            if( my $string_meth = overload::Method( $$thing, $type ) ) {
                $$thing = $$thing->$string_meth();
            }
        }
    }

    return;
}

sub _is_object {
    my( $self, $thing ) = @_;

    return $self->_try( sub { ref $thing && $thing->isa('UNIVERSAL') } ) ? 1 : 0;
}

sub _unoverload_str {
    my $self = shift;

    return $self->_unoverload( q[""], @_ );
}

sub _unoverload_num {
    my $self = shift;

    $self->_unoverload( '0+', @_ );

    for my $val (@_) {
        next unless $self->_is_dualvar($$val);
        $$val = $$val + 0;
    }

    return;
}

# This is a hack to detect a dualvar such as $!
sub _is_dualvar {
    my( $self, $val ) = @_;

    # Objects are not dualvars.
    return 0 if ref $val;

    no warnings 'numeric';
    my $numval = $val + 0;
    return $numval != 0 and $numval ne $val ? 1 : 0;
}

#line 649

sub is_eq {
    my( $self, $got, $expect, $name ) = @_;
    local $Level = $Level + 1;

    $self->_unoverload_str( \$got, \$expect );

    if( !defined $got || !defined $expect ) {
        # undef only matches undef and nothing else
        my $test = !defined $got && !defined $expect;

        $self->ok( $test, $name );
        $self->_is_diag( $got, 'eq', $expect ) unless $test;
        return $test;
    }

    return $self->cmp_ok( $got, 'eq', $expect, $name );
}

sub is_num {
    my( $self, $got, $expect, $name ) = @_;
    local $Level = $Level + 1;

    $self->_unoverload_num( \$got, \$expect );

    if( !defined $got || !defined $expect ) {
        # undef only matches undef and nothing else
        my $test = !defined $got && !defined $expect;

        $self->ok( $test, $name );
        $self->_is_diag( $got, '==', $expect ) unless $test;
        return $test;
    }

    return $self->cmp_ok( $got, '==', $expect, $name );
}

sub _diag_fmt {
    my( $self, $type, $val ) = @_;

    if( defined $$val ) {
        if( $type eq 'eq' or $type eq 'ne' ) {
            # quote and force string context
            $$val = "'$$val'";
        }
        else {
            # force numeric context
            $self->_unoverload_num($val);
        }
    }
    else {
        $$val = 'undef';
    }

    return;
}

sub _is_diag {
    my( $self, $got, $type, $expect ) = @_;

    $self->_diag_fmt( $type, $_ ) for \$got, \$expect;

    local $Level = $Level + 1;
    return $self->diag(<<"DIAGNOSTIC");
         got: $got
    expected: $expect
DIAGNOSTIC

}

sub _isnt_diag {
    my( $self, $got, $type ) = @_;

    $self->_diag_fmt( $type, \$got );

    local $Level = $Level + 1;
    return $self->diag(<<"DIAGNOSTIC");
         got: $got
    expected: anything else
DIAGNOSTIC
}

#line 746

sub isnt_eq {
    my( $self, $got, $dont_expect, $name ) = @_;
    local $Level = $Level + 1;

    if( !defined $got || !defined $dont_expect ) {
        # undef only matches undef and nothing else
        my $test = defined $got || defined $dont_expect;

        $self->ok( $test, $name );
        $self->_isnt_diag( $got, 'ne' ) unless $test;
        return $test;
    }

    return $self->cmp_ok( $got, 'ne', $dont_expect, $name );
}

sub isnt_num {
    my( $self, $got, $dont_expect, $name ) = @_;
    local $Level = $Level + 1;

    if( !defined $got || !defined $dont_expect ) {
        # undef only matches undef and nothing else
        my $test = defined $got || defined $dont_expect;

        $self->ok( $test, $name );
        $self->_isnt_diag( $got, '!=' ) unless $test;
        return $test;
    }

    return $self->cmp_ok( $got, '!=', $dont_expect, $name );
}

#line 797

sub like {
    my( $self, $this, $regex, $name ) = @_;

    local $Level = $Level + 1;
    return $self->_regex_ok( $this, $regex, '=~', $name );
}

sub unlike {
    my( $self, $this, $regex, $name ) = @_;

    local $Level = $Level + 1;
    return $self->_regex_ok( $this, $regex, '!~', $name );
}

#line 821

my %numeric_cmps = map { ( $_, 1 ) } ( "<", "<=", ">", ">=", "==", "!=", "<=>" );

sub cmp_ok {
    my( $self, $got, $type, $expect, $name ) = @_;

    my $test;
    my $error;
    {
        ## no critic (BuiltinFunctions::ProhibitStringyEval)

        local( $@, $!, $SIG{__DIE__} );    # isolate eval

        my($pack, $file, $line) = $self->caller();

        $test = eval qq[
#line 1 "cmp_ok [from $file line $line]"
\$got $type \$expect;
];
        $error = $@;
    }
    local $Level = $Level + 1;
    my $ok = $self->ok( $test, $name );

    # Treat overloaded objects as numbers if we're asked to do a
    # numeric comparison.
    my $unoverload
      = $numeric_cmps{$type}
      ? '_unoverload_num'
      : '_unoverload_str';

    $self->diag(<<"END") if $error;
An error occurred while using $type:
------------------------------------
$error
------------------------------------
END

    unless($ok) {
        $self->$unoverload( \$got, \$expect );

        if( $type =~ /^(eq|==)$/ ) {
            $self->_is_diag( $got, $type, $expect );
        }
        elsif( $type =~ /^(ne|!=)$/ ) {
            $self->_isnt_diag( $got, $type );
        }
        else {
            $self->_cmp_diag( $got, $type, $expect );
        }
    }
    return $ok;
}

sub _cmp_diag {
    my( $self, $got, $type, $expect ) = @_;

    $got    = defined $got    ? "'$got'"    : 'undef';
    $expect = defined $expect ? "'$expect'" : 'undef';

    local $Level = $Level + 1;
    return $self->diag(<<"DIAGNOSTIC");
    $got
        $type
    $expect
DIAGNOSTIC
}

sub _caller_context {
    my $self = shift;

    my( $pack, $file, $line ) = $self->caller(1);

    my $code = '';
    $code .= "#line $line $file\n" if defined $file and defined $line;

    return $code;
}

#line 920

sub BAIL_OUT {
    my( $self, $reason ) = @_;

    $self->{Bailed_Out} = 1;
    $self->_print("Bail out!  $reason");
    exit 255;
}

#line 933

*BAILOUT = \&BAIL_OUT;

#line 944

sub skip {
    my( $self, $why ) = @_;
    $why ||= '';
    $self->_unoverload_str( \$why );

    lock( $self->{Curr_Test} );
    $self->{Curr_Test}++;

    $self->{Test_Results}[ $self->{Curr_Test} - 1 ] = &share(
        {
            'ok'      => 1,
            actual_ok => 1,
            name      => '',
            type      => 'skip',
            reason    => $why,
        }
    );

    my $out = "ok";
    $out .= " $self->{Curr_Test}" if $self->use_numbers;
    $out .= " # skip";
    $out .= " $why"               if length $why;
    $out .= "\n";

    $self->_print($out);

    return 1;
}

#line 985

sub todo_skip {
    my( $self, $why ) = @_;
    $why ||= '';

    lock( $self->{Curr_Test} );
    $self->{Curr_Test}++;

    $self->{Test_Results}[ $self->{Curr_Test} - 1 ] = &share(
        {
            'ok'      => 1,
            actual_ok => 0,
            name      => '',
            type      => 'todo_skip',
            reason    => $why,
        }
    );

    my $out = "not ok";
    $out .= " $self->{Curr_Test}" if $self->use_numbers;
    $out .= " # TODO & SKIP $why\n";

    $self->_print($out);

    return 1;
}

#line 1062

sub maybe_regex {
    my( $self, $regex ) = @_;
    my $usable_regex = undef;

    return $usable_regex unless defined $regex;

    my( $re, $opts );

    # Check for qr/foo/
    if( _is_qr($regex) ) {
        $usable_regex = $regex;
    }
    # Check for '/foo/' or 'm,foo,'
    elsif(( $re, $opts )        = $regex =~ m{^ /(.*)/ (\w*) $ }sx              or
          ( undef, $re, $opts ) = $regex =~ m,^ m([^\w\s]) (.+) \1 (\w*) $,sx
    )
    {
        $usable_regex = length $opts ? "(?$opts)$re" : $re;
    }

    return $usable_regex;
}

sub _is_qr {
    my $regex = shift;

    # is_regexp() checks for regexes in a robust manner, say if they're
    # blessed.
    return re::is_regexp($regex) if defined &re::is_regexp;
    return ref $regex eq 'Regexp';
}

sub _regex_ok {
    my( $self, $this, $regex, $cmp, $name ) = @_;

    my $ok           = 0;
    my $usable_regex = $self->maybe_regex($regex);
    unless( defined $usable_regex ) {
        local $Level = $Level + 1;
        $ok = $self->ok( 0, $name );
        $self->diag("    '$regex' doesn't look much like a regex to me.");
        return $ok;
    }

    {
        ## no critic (BuiltinFunctions::ProhibitStringyEval)

        my $test;
        my $code = $self->_caller_context;

        local( $@, $!, $SIG{__DIE__} );    # isolate eval

        # Yes, it has to look like this or 5.4.5 won't see the #line
        # directive.
        # Don't ask me, man, I just work here.
        $test = eval "
$code" . q{$test = $this =~ /$usable_regex/ ? 1 : 0};

        $test = !$test if $cmp eq '!~';

        local $Level = $Level + 1;
        $ok = $self->ok( $test, $name );
    }

    unless($ok) {
        $this = defined $this ? "'$this'" : 'undef';
        my $match = $cmp eq '=~' ? "doesn't match" : "matches";

        local $Level = $Level + 1;
        $self->diag( sprintf <<'DIAGNOSTIC', $this, $match, $regex );
                  %s
    %13s '%s'
DIAGNOSTIC

    }

    return $ok;
}

# I'm not ready to publish this.  It doesn't deal with array return
# values from the code or context.

#line 1162

sub _try {
    my( $self, $code, %opts ) = @_;

    my $error;
    my $return;
    {
        local $!;               # eval can mess up $!
        local $@;               # don't set $@ in the test
        local $SIG{__DIE__};    # don't trip an outside DIE handler.
        $return = eval { $code->() };
        $error = $@;
    }

    die $error if $error and $opts{die_on_fail};

    return wantarray ? ( $return, $error ) : $return;
}

#line 1191

sub is_fh {
    my $self     = shift;
    my $maybe_fh = shift;
    return 0 unless defined $maybe_fh;

    return 1 if ref $maybe_fh  eq 'GLOB';    # its a glob ref
    return 1 if ref \$maybe_fh eq 'GLOB';    # its a glob

    return eval { $maybe_fh->isa("IO::Handle") } ||
           # 5.5.4's tied() and can() doesn't like getting undef
           eval { ( tied($maybe_fh) || '' )->can('TIEHANDLE') };
}

#line 1235

sub level {
    my( $self, $level ) = @_;

    if( defined $level ) {
        $Level = $level;
    }
    return $Level;
}

#line 1267

sub use_numbers {
    my( $self, $use_nums ) = @_;

    if( defined $use_nums ) {
        $self->{Use_Nums} = $use_nums;
    }
    return $self->{Use_Nums};
}

#line 1300

foreach my $attribute (qw(No_Header No_Ending No_Diag)) {
    my $method = lc $attribute;

    my $code = sub {
        my( $self, $no ) = @_;

        if( defined $no ) {
            $self->{$attribute} = $no;
        }
        return $self->{$attribute};
    };

    no strict 'refs';    ## no critic
    *{ __PACKAGE__ . '::' . $method } = $code;
}

#line 1353

sub diag {
    my $self = shift;

    $self->_print_comment( $self->_diag_fh, @_ );
}

#line 1368

sub note {
    my $self = shift;

    $self->_print_comment( $self->output, @_ );
}

sub _diag_fh {
    my $self = shift;

    local $Level = $Level + 1;
    return $self->in_todo ? $self->todo_output : $self->failure_output;
}

sub _print_comment {
    my( $self, $fh, @msgs ) = @_;

    return if $self->no_diag;
    return unless @msgs;

    # Prevent printing headers when compiling (i.e. -c)
    return if $^C;

    # Smash args together like print does.
    # Convert undef to 'undef' so its readable.
    my $msg = join '', map { defined($_) ? $_ : 'undef' } @msgs;

    # Escape the beginning, _print will take care of the rest.
    $msg =~ s/^/# /;

    local $Level = $Level + 1;
    $self->_print_to_fh( $fh, $msg );

    return 0;
}

#line 1418

sub explain {
    my $self = shift;

    return map {
        ref $_
          ? do {
            $self->_try(sub { require Data::Dumper }, die_on_fail => 1);

            my $dumper = Data::Dumper->new( [$_] );
            $dumper->Indent(1)->Terse(1);
            $dumper->Sortkeys(1) if $dumper->can("Sortkeys");
            $dumper->Dump;
          }
          : $_
    } @_;
}

#line 1447

sub _print {
    my $self = shift;
    return $self->_print_to_fh( $self->output, @_ );
}

sub _print_to_fh {
    my( $self, $fh, @msgs ) = @_;

    # Prevent printing headers when only compiling.  Mostly for when
    # tests are deparsed with B::Deparse
    return if $^C;

    my $msg = join '', @msgs;

    local( $\, $", $, ) = ( undef, ' ', '' );

    # Escape each line after the first with a # so we don't
    # confuse Test::Harness.
    $msg =~ s{\n(?!\z)}{\n# }sg;

    # Stick a newline on the end if it needs it.
    $msg .= "\n" unless $msg =~ /\n\z/;

    return print $fh $msg;
}

#line 1506

sub output {
    my( $self, $fh ) = @_;

    if( defined $fh ) {
        $self->{Out_FH} = $self->_new_fh($fh);
    }
    return $self->{Out_FH};
}

sub failure_output {
    my( $self, $fh ) = @_;

    if( defined $fh ) {
        $self->{Fail_FH} = $self->_new_fh($fh);
    }
    return $self->{Fail_FH};
}

sub todo_output {
    my( $self, $fh ) = @_;

    if( defined $fh ) {
        $self->{Todo_FH} = $self->_new_fh($fh);
    }
    return $self->{Todo_FH};
}

sub _new_fh {
    my $self = shift;
    my($file_or_fh) = shift;

    my $fh;
    if( $self->is_fh($file_or_fh) ) {
        $fh = $file_or_fh;
    }
    elsif( ref $file_or_fh eq 'SCALAR' ) {
        # Scalar refs as filehandles was added in 5.8.
        if( $] >= 5.008 ) {
            open $fh, ">>", $file_or_fh
              or $self->croak("Can't open scalar ref $file_or_fh: $!");
        }
        # Emulate scalar ref filehandles with a tie.
        else {
            $fh = Test::Builder::IO::Scalar->new($file_or_fh)
              or $self->croak("Can't tie scalar ref $file_or_fh");
        }
    }
    else {
        open $fh, ">", $file_or_fh
          or $self->croak("Can't open test output log $file_or_fh: $!");
        _autoflush($fh);
    }

    return $fh;
}

sub _autoflush {
    my($fh) = shift;
    my $old_fh = select $fh;
    $| = 1;
    select $old_fh;

    return;
}

my( $Testout, $Testerr );

sub _dup_stdhandles {
    my $self = shift;

    $self->_open_testhandles;

    # Set everything to unbuffered else plain prints to STDOUT will
    # come out in the wrong order from our own prints.
    _autoflush($Testout);
    _autoflush( \*STDOUT );
    _autoflush($Testerr);
    _autoflush( \*STDERR );

    $self->reset_outputs;

    return;
}

sub _open_testhandles {
    my $self = shift;

    return if $self->{Opened_Testhandles};

    # We dup STDOUT and STDERR so people can change them in their
    # test suites while still getting normal test output.
    open( $Testout, ">&STDOUT" ) or die "Can't dup STDOUT:  $!";
    open( $Testerr, ">&STDERR" ) or die "Can't dup STDERR:  $!";

    #    $self->_copy_io_layers( \*STDOUT, $Testout );
    #    $self->_copy_io_layers( \*STDERR, $Testerr );

    $self->{Opened_Testhandles} = 1;

    return;
}

sub _copy_io_layers {
    my( $self, $src, $dst ) = @_;

    $self->_try(
        sub {
            require PerlIO;
            my @src_layers = PerlIO::get_layers($src);

            binmode $dst, join " ", map ":$_", @src_layers if @src_layers;
        }
    );

    return;
}

#line 1631

sub reset_outputs {
    my $self = shift;

    $self->output        ($Testout);
    $self->failure_output($Testerr);
    $self->todo_output   ($Testout);

    return;
}

#line 1657

sub _message_at_caller {
    my $self = shift;

    local $Level = $Level + 1;
    my( $pack, $file, $line ) = $self->caller;
    return join( "", @_ ) . " at $file line $line.\n";
}

sub carp {
    my $self = shift;
    return warn $self->_message_at_caller(@_);
}

sub croak {
    my $self = shift;
    return die $self->_message_at_caller(@_);
}


#line 1697

sub current_test {
    my( $self, $num ) = @_;

    lock( $self->{Curr_Test} );
    if( defined $num ) {
        $self->{Curr_Test} = $num;

        # If the test counter is being pushed forward fill in the details.
        my $test_results = $self->{Test_Results};
        if( $num > @$test_results ) {
            my $start = @$test_results ? @$test_results : 0;
            for( $start .. $num - 1 ) {
                $test_results->[$_] = &share(
                    {
                        'ok'      => 1,
                        actual_ok => undef,
                        reason    => 'incrementing test number',
                        type      => 'unknown',
                        name      => undef
                    }
                );
            }
        }
        # If backward, wipe history.  Its their funeral.
        elsif( $num < @$test_results ) {
            $#{$test_results} = $num - 1;
        }
    }
    return $self->{Curr_Test};
}

#line 1739

sub summary {
    my($self) = shift;

    return map { $_->{'ok'} } @{ $self->{Test_Results} };
}

#line 1794

sub details {
    my $self = shift;
    return @{ $self->{Test_Results} };
}

#line 1823

sub todo {
    my( $self, $pack ) = @_;

    return $self->{Todo} if defined $self->{Todo};

    local $Level = $Level + 1;
    my $todo = $self->find_TODO($pack);
    return $todo if defined $todo;

    return '';
}

#line 1845

sub find_TODO {
    my( $self, $pack ) = @_;

    $pack = $pack || $self->caller(1) || $self->exported_to;
    return unless $pack;

    no strict 'refs';    ## no critic
    return ${ $pack . '::TODO' };
}

#line 1863

sub in_todo {
    my $self = shift;

    local $Level = $Level + 1;
    return( defined $self->{Todo} || $self->find_TODO ) ? 1 : 0;
}

#line 1913

sub todo_start {
    my $self = shift;
    my $message = @_ ? shift : '';

    $self->{Start_Todo}++;
    if( $self->in_todo ) {
        push @{ $self->{Todo_Stack} } => $self->todo;
    }
    $self->{Todo} = $message;

    return;
}

#line 1935

sub todo_end {
    my $self = shift;

    if( !$self->{Start_Todo} ) {
        $self->croak('todo_end() called without todo_start()');
    }

    $self->{Start_Todo}--;

    if( $self->{Start_Todo} && @{ $self->{Todo_Stack} } ) {
        $self->{Todo} = pop @{ $self->{Todo_Stack} };
    }
    else {
        delete $self->{Todo};
    }

    return;
}

#line 1968

sub caller {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my( $self, $height ) = @_;
    $height ||= 0;

    my $level = $self->level + $height + 1;
    my @caller;
    do {
        @caller = CORE::caller( $level );
        $level--;
    } until @caller;
    return wantarray ? @caller : $caller[0];
}

#line 1985

#line 1999

#'#
sub _sanity_check {
    my $self = shift;

    $self->_whoa( $self->{Curr_Test} < 0, 'Says here you ran a negative number of tests!' );
    $self->_whoa( $self->{Curr_Test} != @{ $self->{Test_Results} },
        'Somehow you got a different number of results than tests ran!' );

    return;
}

#line 2020

sub _whoa {
    my( $self, $check, $desc ) = @_;
    if($check) {
        local $Level = $Level + 1;
        $self->croak(<<"WHOA");
WHOA!  $desc
This should never happen!  Please contact the author immediately!
WHOA
    }

    return;
}

#line 2044

sub _my_exit {
    $? = $_[0];    ## no critic (Variables::RequireLocalizedPunctuationVars)

    return 1;
}

#line 2056

sub _ending {
    my $self = shift;

    my $real_exit_code = $?;

    # Don't bother with an ending if this is a forked copy.  Only the parent
    # should do the ending.
    if( $self->{Original_Pid} != $$ ) {
        return;
    }

    # Ran tests but never declared a plan or hit done_testing
    if( !$self->{Have_Plan} and $self->{Curr_Test} ) {
        $self->diag("Tests were run but no plan was declared and done_testing() was not seen.");
    }

    # Exit if plan() was never called.  This is so "require Test::Simple"
    # doesn't puke.
    if( !$self->{Have_Plan} ) {
        return;
    }

    # Don't do an ending if we bailed out.
    if( $self->{Bailed_Out} ) {
        return;
    }

    # Figure out if we passed or failed and print helpful messages.
    my $test_results = $self->{Test_Results};
    if(@$test_results) {
        # The plan?  We have no plan.
        if( $self->{No_Plan} ) {
            $self->_output_plan($self->{Curr_Test}) unless $self->no_header;
            $self->{Expected_Tests} = $self->{Curr_Test};
        }

        # Auto-extended arrays and elements which aren't explicitly
        # filled in with a shared reference will puke under 5.8.0
        # ithreads.  So we have to fill them in by hand. :(
        my $empty_result = &share( {} );
        for my $idx ( 0 .. $self->{Expected_Tests} - 1 ) {
            $test_results->[$idx] = $empty_result
              unless defined $test_results->[$idx];
        }

        my $num_failed = grep !$_->{'ok'}, @{$test_results}[ 0 .. $self->{Curr_Test} - 1 ];

        my $num_extra = $self->{Curr_Test} - $self->{Expected_Tests};

        if( $num_extra != 0 ) {
            my $s = $self->{Expected_Tests} == 1 ? '' : 's';
            $self->diag(<<"FAIL");
Looks like you planned $self->{Expected_Tests} test$s but ran $self->{Curr_Test}.
FAIL
        }

        if($num_failed) {
            my $num_tests = $self->{Curr_Test};
            my $s = $num_failed == 1 ? '' : 's';

            my $qualifier = $num_extra == 0 ? '' : ' run';

            $self->diag(<<"FAIL");
Looks like you failed $num_failed test$s of $num_tests$qualifier.
FAIL
        }

        if($real_exit_code) {
            $self->diag(<<"FAIL");
Looks like your test exited with $real_exit_code just after $self->{Curr_Test}.
FAIL

            _my_exit($real_exit_code) && return;
        }

        my $exit_code;
        if($num_failed) {
            $exit_code = $num_failed <= 254 ? $num_failed : 254;
        }
        elsif( $num_extra != 0 ) {
            $exit_code = 255;
        }
        else {
            $exit_code = 0;
        }

        _my_exit($exit_code) && return;
    }
    elsif( $self->{Skip_All} ) {
        _my_exit(0) && return;
    }
    elsif($real_exit_code) {
        $self->diag(<<"FAIL");
Looks like your test exited with $real_exit_code before it could output anything.
FAIL
        _my_exit($real_exit_code) && return;
    }
    else {
        $self->diag("No tests run!\n");
        _my_exit(255) && return;
    }

    $self->_whoa( 1, "We fell off the end of _ending()" );
}

END {
    $Test->_ending if defined $Test and !$Test->no_ending;
}

#line 2236

1;

