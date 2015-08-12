#line 1
package Test::Builder;

use 5.006;
use strict;
use warnings;

our $VERSION = '0.98';
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
        # occasionally forget the contents of the variable when sharing it.
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

our $Test = Test::Builder->new;

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

#line 168

sub child {
    my( $self, $name ) = @_;

    if( $self->{Child_Name} ) {
        $self->croak("You already have a child named ($self->{Child_Name}) running");
    }

    my $parent_in_todo = $self->in_todo;

    # Clear $TODO for the child.
    my $orig_TODO = $self->find_TODO(undef, 1, undef);

    my $child = bless {}, ref $self;
    $child->reset;

    # Add to our indentation
    $child->_indent( $self->_indent . '    ' );
    
    $child->{$_} = $self->{$_} foreach qw{Out_FH Todo_FH Fail_FH};
    if ($parent_in_todo) {
        $child->{Fail_FH} = $self->{Todo_FH};
    }

    # This will be reset in finalize. We do this here lest one child failure
    # cause all children to fail.
    $child->{Child_Error} = $?;
    $?                    = 0;
    $child->{Parent}      = $self;
    $child->{Parent_TODO} = $orig_TODO;
    $child->{Name}        = $name || "Child of " . $self->name;
    $self->{Child_Name}   = $child->name;
    return $child;
}


#line 211

sub subtest {
    my $self = shift;
    my($name, $subtests) = @_;

    if ('CODE' ne ref $subtests) {
        $self->croak("subtest()'s second argument must be a code ref");
    }

    # Turn the child into the parent so anyone who has stored a copy of
    # the Test::Builder singleton will get the child.
    my($error, $child, %parent);
    {
        # child() calls reset() which sets $Level to 1, so we localize
        # $Level first to limit the scope of the reset to the subtest.
        local $Test::Builder::Level = $Test::Builder::Level + 1;

        $child  = $self->child($name);
        %parent = %$self;
        %$self  = %$child;

        my $run_the_subtests = sub {
            $subtests->();
            $self->done_testing unless $self->_plan_handled;
            1;
        };

        if( !eval { $run_the_subtests->() } ) {
            $error = $@;
        }
    }

    # Restore the parent and the copied child.
    %$child = %$self;
    %$self = %parent;

    # Restore the parent's $TODO
    $self->find_TODO(undef, 1, $child->{Parent_TODO});

    # Die *after* we restore the parent.
    die $error if $error and !eval { $error->isa('Test::Builder::Exception') };

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    return $child->finalize;
}

#line 281

sub _plan_handled {
    my $self = shift;
    return $self->{Have_Plan} || $self->{No_Plan} || $self->{Skip_All};
}


#line 306

sub finalize {
    my $self = shift;

    return unless $self->parent;
    if( $self->{Child_Name} ) {
        $self->croak("Can't call finalize() with child ($self->{Child_Name}) active");
    }

    local $? = 0;     # don't fail if $subtests happened to set $? nonzero
    $self->_ending;

    # XXX This will only be necessary for TAP envelopes (we think)
    #$self->_print( $self->is_passing ? "PASS\n" : "FAIL\n" );

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $ok = 1;
    $self->parent->{Child_Name} = undef;
    if ( $self->{Skip_All} ) {
        $self->parent->skip($self->{Skip_All});
    }
    elsif ( not @{ $self->{Test_Results} } ) {
        $self->parent->ok( 0, sprintf q[No tests run for subtest "%s"], $self->name );
    }
    else {
        $self->parent->ok( $self->is_passing, $self->name );
    }
    $? = $self->{Child_Error};
    delete $self->{Parent};

    return $self->is_passing;
}

sub _indent      {
    my $self = shift;

    if( @_ ) {
        $self->{Indent} = shift;
    }

    return $self->{Indent};
}

#line 359

sub parent { shift->{Parent} }

#line 371

sub name { shift->{Name} }

sub DESTROY {
    my $self = shift;
    if ( $self->parent and $$ == $self->{Original_Pid} ) {
        my $name = $self->name;
        $self->diag(<<"FAIL");
Child ($name) exited without calling finalize()
FAIL
        $self->parent->{In_Destroy} = 1;
        $self->parent->ok(0, $name);
    }
}

#line 395

our $Level;

sub reset {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my($self) = @_;

    # We leave this a global because it has to be localized and localizing
    # hash keys is just asking for pain.  Also, it was documented.
    $Level = 1;

    $self->{Name}         = $0;
    $self->is_passing(1);
    $self->{Ending}       = 0;
    $self->{Have_Plan}    = 0;
    $self->{No_Plan}      = 0;
    $self->{Have_Output_Plan} = 0;
    $self->{Done_Testing} = 0;

    $self->{Original_Pid} = $$;
    $self->{Child_Name}   = undef;
    $self->{Indent}     ||= '';

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

#line 474

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

#line 529

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

#line 553

sub no_plan {
    my($self, $arg) = @_;

    $self->carp("no_plan takes no arguments") if $arg;

    $self->{No_Plan}   = 1;
    $self->{Have_Plan} = 1;

    return 1;
}

#line 586

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


#line 638

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

    # The wrong number of tests were run
    $self->is_passing(0) if $self->{Expected_Tests} != $self->{Curr_Test};

    # No tests were run
    $self->is_passing(0) if $self->{Curr_Test} == 0;

    return 1;
}


#line 689

sub has_plan {
    my $self = shift;

    return( $self->{Expected_Tests} ) if $self->{Expected_Tests};
    return('no_plan') if $self->{No_Plan};
    return(undef);
}

#line 706

sub skip_all {
    my( $self, $reason ) = @_;

    $self->{Skip_All} = $self->parent ? $reason : 1;

    $self->_output_plan(0, "SKIP", $reason) unless $self->no_header;
    if ( $self->parent ) {
        die bless {} => 'Test::Builder::Exception';
    }
    exit(0);
}

#line 731

sub exported_to {
    my( $self, $pack ) = @_;

    if( defined $pack ) {
        $self->{Exported_To} = $pack;
    }
    return $self->{Exported_To};
}

#line 761

sub ok {
    my( $self, $test, $name ) = @_;

    if ( $self->{Child_Name} and not $self->{In_Destroy} ) {
        $name = 'unnamed test' unless defined $name;
        $self->is_passing(0);
        $self->croak("Cannot run test ($name) with active children");
    }
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

    $self->is_passing(0) unless $test || $self->in_todo;

    # Check that we haven't violated the plan
    $self->_check_is_passing_plan();

    return $test ? 1 : 0;
}


# Check that we haven't yet violated the plan and set
# is_passing() accordingly
sub _check_is_passing_plan {
    my $self = shift;

    my $plan = $self->has_plan;
    return unless defined $plan;        # no plan yet defined
    return unless $plan !~ /\D/;        # no numeric plan
    $self->is_passing(0) if $plan < $self->{Curr_Test};
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

#line 939

sub is_eq {
    my( $self, $got, $expect, $name ) = @_;
    local $Level = $Level + 1;

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

#line 1032

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

#line 1081

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

#line 1105

my %numeric_cmps = map { ( $_, 1 ) } ( "<", "<=", ">", ">=", "==", "!=", "<=>" );

sub cmp_ok {
    my( $self, $got, $type, $expect, $name ) = @_;

    my $test;
    my $error;
    {
        ## no critic (BuiltinFunctions::ProhibitStringyEval)

        local( $@, $!, $SIG{__DIE__} );    # isolate eval

        my($pack, $file, $line) = $self->caller();

        # This is so that warnings come out at the caller's level
        $test = eval qq[
#line $line "(eval in cmp_ok) $file"
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

#line 1205

sub BAIL_OUT {
    my( $self, $reason ) = @_;

    $self->{Bailed_Out} = 1;
    $self->_print("Bail out!  $reason");
    exit 255;
}

#line 1218

{
    no warnings 'once';
    *BAILOUT = \&BAIL_OUT;
}

#line 1232

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

#line 1273

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

#line 1353

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
        my $context = $self->_caller_context;

        local( $@, $!, $SIG{__DIE__} );    # isolate eval

        $test = eval $context . q{$test = $this =~ /$usable_regex/ ? 1 : 0};

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

#line 1449

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

#line 1478

sub is_fh {
    my $self     = shift;
    my $maybe_fh = shift;
    return 0 unless defined $maybe_fh;

    return 1 if ref $maybe_fh  eq 'GLOB';    # its a glob ref
    return 1 if ref \$maybe_fh eq 'GLOB';    # its a glob

    return eval { $maybe_fh->isa("IO::Handle") } ||
           eval { tied($maybe_fh)->can('TIEHANDLE') };
}

#line 1521

sub level {
    my( $self, $level ) = @_;

    if( defined $level ) {
        $Level = $level;
    }
    return $Level;
}

#line 1553

sub use_numbers {
    my( $self, $use_nums ) = @_;

    if( defined $use_nums ) {
        $self->{Use_Nums} = $use_nums;
    }
    return $self->{Use_Nums};
}

#line 1586

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

#line 1639

sub diag {
    my $self = shift;

    $self->_print_comment( $self->_diag_fh, @_ );
}

#line 1654

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

#line 1704

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

#line 1733

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
    my $indent = $self->_indent;

    local( $\, $", $, ) = ( undef, ' ', '' );

    # Escape each line after the first with a # so we don't
    # confuse Test::Harness.
    $msg =~ s{\n(?!\z)}{\n$indent# }sg;

    # Stick a newline on the end if it needs it.
    $msg .= "\n" unless $msg =~ /\n\z/;

    return print $fh $indent, $msg;
}

#line 1793

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

    $self->_copy_io_layers( \*STDOUT, $Testout );
    $self->_copy_io_layers( \*STDERR, $Testerr );

    $self->{Opened_Testhandles} = 1;

    return;
}

sub _copy_io_layers {
    my( $self, $src, $dst ) = @_;

    $self->_try(
        sub {
            require PerlIO;
            my @src_layers = PerlIO::get_layers($src);

            _apply_layers($dst, @src_layers) if @src_layers;
        }
    );

    return;
}

sub _apply_layers {
    my ($fh, @layers) = @_;
    my %seen;
    my @unique = grep { $_ ne 'unix' and !$seen{$_}++ } @layers;
    binmode($fh, join(":", "", "raw", @unique));
}


#line 1926

sub reset_outputs {
    my $self = shift;

    $self->output        ($Testout);
    $self->failure_output($Testerr);
    $self->todo_output   ($Testout);

    return;
}

#line 1952

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


#line 1992

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

#line 2040

sub is_passing {
    my $self = shift;

    if( @_ ) {
        $self->{Is_Passing} = shift;
    }

    return $self->{Is_Passing};
}


#line 2062

sub summary {
    my($self) = shift;

    return map { $_->{'ok'} } @{ $self->{Test_Results} };
}

#line 2117

sub details {
    my $self = shift;
    return @{ $self->{Test_Results} };
}

#line 2146

sub todo {
    my( $self, $pack ) = @_;

    return $self->{Todo} if defined $self->{Todo};

    local $Level = $Level + 1;
    my $todo = $self->find_TODO($pack);
    return $todo if defined $todo;

    return '';
}

#line 2173

sub find_TODO {
    my( $self, $pack, $set, $new_value ) = @_;

    $pack = $pack || $self->caller(1) || $self->exported_to;
    return unless $pack;

    no strict 'refs';    ## no critic
    my $old_value = ${ $pack . '::TODO' };
    $set and ${ $pack . '::TODO' } = $new_value;
    return $old_value;
}

#line 2193

sub in_todo {
    my $self = shift;

    local $Level = $Level + 1;
    return( defined $self->{Todo} || $self->find_TODO ) ? 1 : 0;
}

#line 2243

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

#line 2265

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

#line 2298

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

#line 2315

#line 2329

#'#
sub _sanity_check {
    my $self = shift;

    $self->_whoa( $self->{Curr_Test} < 0, 'Says here you ran a negative number of tests!' );
    $self->_whoa( $self->{Curr_Test} != @{ $self->{Test_Results} },
        'Somehow you got a different number of results than tests ran!' );

    return;
}

#line 2350

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

#line 2374

sub _my_exit {
    $? = $_[0];    ## no critic (Variables::RequireLocalizedPunctuationVars)

    return 1;
}

#line 2386

sub _ending {
    my $self = shift;
    return if $self->no_ending;
    return if $self->{Ending}++;

    my $real_exit_code = $?;

    # Don't bother with an ending if this is a forked copy.  Only the parent
    # should do the ending.
    if( $self->{Original_Pid} != $$ ) {
        return;
    }

    # Ran tests but never declared a plan or hit done_testing
    if( !$self->{Have_Plan} and $self->{Curr_Test} ) {
        $self->is_passing(0);
        $self->diag("Tests were run but no plan was declared and done_testing() was not seen.");
    }

    # Exit if plan() was never called.  This is so "require Test::Simple"
    # doesn't puke.
    if( !$self->{Have_Plan} ) {
        return;
    }

    # Don't do an ending if we bailed out.
    if( $self->{Bailed_Out} ) {
        $self->is_passing(0);
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
            $self->is_passing(0);
        }

        if($num_failed) {
            my $num_tests = $self->{Curr_Test};
            my $s = $num_failed == 1 ? '' : 's';

            my $qualifier = $num_extra == 0 ? '' : ' run';

            $self->diag(<<"FAIL");
Looks like you failed $num_failed test$s of $num_tests$qualifier.
FAIL
            $self->is_passing(0);
        }

        if($real_exit_code) {
            $self->diag(<<"FAIL");
Looks like your test exited with $real_exit_code just after $self->{Curr_Test}.
FAIL
            $self->is_passing(0);
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
        $self->is_passing(0);
        _my_exit($real_exit_code) && return;
    }
    else {
        $self->diag("No tests run!\n");
        $self->is_passing(0);
        _my_exit(255) && return;
    }

    $self->is_passing(0);
    $self->_whoa( 1, "We fell off the end of _ending()" );
}

END {
    $Test->_ending if defined $Test;
}

#line 2574

1;

