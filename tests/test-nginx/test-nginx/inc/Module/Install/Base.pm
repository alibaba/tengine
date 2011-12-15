#line 1
package Module::Install::Base;

use strict 'vars';
use vars qw{$VERSION};
BEGIN {
	$VERSION = '1.01';
}

# Suspend handler for "redefined" warnings
BEGIN {
	my $w = $SIG{__WARN__};
	$SIG{__WARN__} = sub { $w };
}

#line 42

sub new {
	my $class = shift;
	unless ( defined &{"${class}::call"} ) {
		*{"${class}::call"} = sub { shift->_top->call(@_) };
	}
	unless ( defined &{"${class}::load"} ) {
		*{"${class}::load"} = sub { shift->_top->load(@_) };
	}
	bless { @_ }, $class;
}

#line 61

sub AUTOLOAD {
	local $@;
	my $func = eval { shift->_top->autoload } or return;
	goto &$func;
}

#line 75

sub _top {
	$_[0]->{_top};
}

#line 90

sub admin {
	$_[0]->_top->{admin}
	or
	Module::Install::Base::FakeAdmin->new;
}

#line 106

sub is_admin {
	! $_[0]->admin->isa('Module::Install::Base::FakeAdmin');
}

sub DESTROY {}

package Module::Install::Base::FakeAdmin;

use vars qw{$VERSION};
BEGIN {
	$VERSION = $Module::Install::Base::VERSION;
}

my $fake;

sub new {
	$fake ||= bless(\@_, $_[0]);
}

sub AUTOLOAD {}

sub DESTROY {}

# Restore warning handler
BEGIN {
	$SIG{__WARN__} = $SIG{__WARN__}->();
}

1;

#line 159
