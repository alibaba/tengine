#line 1
package Test::Builder::Module;

use strict;

use Test::Builder;

require Exporter;
our @ISA = qw(Exporter);

our $VERSION = '0.98';
$VERSION = eval $VERSION;      ## no critic (BuiltinFunctions::ProhibitStringyEval)


#line 74

sub import {
    my($class) = shift;

    # Don't run all this when loading ourself.
    return 1 if $class eq 'Test::Builder::Module';

    my $test = $class->builder;

    my $caller = caller;

    $test->exported_to($caller);

    $class->import_extra( \@_ );
    my(@imports) = $class->_strip_imports( \@_ );

    $test->plan(@_);

    $class->export_to_level( 1, $class, @imports );
}

sub _strip_imports {
    my $class = shift;
    my $list  = shift;

    my @imports = ();
    my @other   = ();
    my $idx     = 0;
    while( $idx <= $#{$list} ) {
        my $item = $list->[$idx];

        if( defined $item and $item eq 'import' ) {
            push @imports, @{ $list->[ $idx + 1 ] };
            $idx++;
        }
        else {
            push @other, $item;
        }

        $idx++;
    }

    @$list = @other;

    return @imports;
}

#line 137

sub import_extra { }

#line 167

sub builder {
    return Test::Builder->new;
}

1;
