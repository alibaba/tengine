#line 1
package Test::Base;
use 5.006001;
use Spiffy 0.30 -Base;
use Spiffy ':XXX';
our $VERSION = '0.60';

my @test_more_exports;
BEGIN {
    @test_more_exports = qw(
        ok isnt like unlike is_deeply cmp_ok
        skip todo_skip pass fail
        eq_array eq_hash eq_set
        plan can_ok isa_ok diag
        use_ok
        $TODO
    );
}

use Test::More import => \@test_more_exports;
use Carp;

our @EXPORT = (@test_more_exports, qw(
    is no_diff

    blocks next_block first_block
    delimiters spec_file spec_string 
    filters filters_delay filter_arguments
    run run_compare run_is run_is_deeply run_like run_unlike 
    skip_all_unless_require is_deep run_is_deep
    WWW XXX YYY ZZZ
    tie_output no_diag_on_only

    find_my_self default_object

    croak carp cluck confess
));

field '_spec_file';
field '_spec_string';
field _filters => [qw(norm trim)];
field _filters_map => {};
field spec =>
      -init => '$self->_spec_init';
field block_list =>
      -init => '$self->_block_list_init';
field _next_list => [];
field block_delim =>
      -init => '$self->block_delim_default';
field data_delim =>
      -init => '$self->data_delim_default';
field _filters_delay => 0;
field _no_diag_on_only => 0;

field block_delim_default => '===';
field data_delim_default => '---';

my $default_class;
my $default_object;
my $reserved_section_names = {};

sub default_object { 
    $default_object ||= $default_class->new;
    return $default_object;
}

my $import_called = 0;
sub import() {
    $import_called = 1;
    my $class = (grep /^-base$/i, @_) 
    ? scalar(caller)
    : $_[0];
    if (not defined $default_class) {
        $default_class = $class;
    }
#     else {
#         croak "Can't use $class after using $default_class"
#           unless $default_class->isa($class);
#     }

    unless (grep /^-base$/i, @_) {
        my @args;
        for (my $ii = 1; $ii <= $#_; ++$ii) {
            if ($_[$ii] eq '-package') {
                ++$ii;
            } else {
                push @args, $_[$ii];
            }
        }
        Test::More->import(import => \@test_more_exports, @args)
            if @args;
     }
    
    _strict_warnings();
    goto &Spiffy::import;
}

# Wrap Test::Builder::plan
my $plan_code = \&Test::Builder::plan;
my $Have_Plan = 0;
{
    no warnings 'redefine';
    *Test::Builder::plan = sub {
        $Have_Plan = 1;
        goto &$plan_code;
    };
}

my $DIED = 0;
$SIG{__DIE__} = sub { $DIED = 1; die @_ };

sub block_class  { $self->find_class('Block') }
sub filter_class { $self->find_class('Filter') }

sub find_class {
    my $suffix = shift;
    my $class = ref($self) . "::$suffix";
    return $class if $class->can('new');
    $class = __PACKAGE__ . "::$suffix";
    return $class if $class->can('new');
    eval "require $class";
    return $class if $class->can('new');
    die "Can't find a class for $suffix";
}

sub check_late {
    if ($self->{block_list}) {
        my $caller = (caller(1))[3];
        $caller =~ s/.*:://;
        croak "Too late to call $caller()"
    }
}

sub find_my_self() {
    my $self = ref($_[0]) eq $default_class
    ? splice(@_, 0, 1)
    : default_object();
    return $self, @_;
}

sub blocks() {
    (my ($self), @_) = find_my_self(@_);

    croak "Invalid arguments passed to 'blocks'"
      if @_ > 1;
    croak sprintf("'%s' is invalid argument to blocks()", shift(@_))
      if @_ && $_[0] !~ /^[a-zA-Z]\w*$/;

    my $blocks = $self->block_list;
    
    my $section_name = shift || '';
    my @blocks = $section_name
    ? (grep { exists $_->{$section_name} } @$blocks)
    : (@$blocks);

    return scalar(@blocks) unless wantarray;
    
    return (@blocks) if $self->_filters_delay;

    for my $block (@blocks) {
        $block->run_filters
          unless $block->is_filtered;
    }

    return (@blocks);
}

sub next_block() {
    (my ($self), @_) = find_my_self(@_);
    my $list = $self->_next_list;
    if (@$list == 0) {
        $list = [@{$self->block_list}, undef];
        $self->_next_list($list);
    }
    my $block = shift @$list;
    if (defined $block and not $block->is_filtered) {
        $block->run_filters;
    }
    return $block;
}

sub first_block() {
    (my ($self), @_) = find_my_self(@_);
    $self->_next_list([]);
    $self->next_block;
}

sub filters_delay() {
    (my ($self), @_) = find_my_self(@_);
    $self->_filters_delay(defined $_[0] ? shift : 1);
}

sub no_diag_on_only() {
    (my ($self), @_) = find_my_self(@_);
    $self->_no_diag_on_only(defined $_[0] ? shift : 1);
}

sub delimiters() {
    (my ($self), @_) = find_my_self(@_);
    $self->check_late;
    my ($block_delimiter, $data_delimiter) = @_;
    $block_delimiter ||= $self->block_delim_default;
    $data_delimiter ||= $self->data_delim_default;
    $self->block_delim($block_delimiter);
    $self->data_delim($data_delimiter);
    return $self;
}

sub spec_file() {
    (my ($self), @_) = find_my_self(@_);
    $self->check_late;
    $self->_spec_file(shift);
    return $self;
}

sub spec_string() {
    (my ($self), @_) = find_my_self(@_);
    $self->check_late;
    $self->_spec_string(shift);
    return $self;
}

sub filters() {
    (my ($self), @_) = find_my_self(@_);
    if (ref($_[0]) eq 'HASH') {
        $self->_filters_map(shift);
    }
    else {    
        my $filters = $self->_filters;
        push @$filters, @_;
    }
    return $self;
}

sub filter_arguments() {
    $Test::Base::Filter::arguments;
}

sub have_text_diff {
    eval { require Text::Diff; 1 } &&
        $Text::Diff::VERSION >= 0.35 &&
        $Algorithm::Diff::VERSION >= 1.15;
}

sub is($$;$) {
    (my ($self), @_) = find_my_self(@_);
    my ($actual, $expected, $name) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    if ($ENV{TEST_SHOW_NO_DIFFS} or
         not defined $actual or
         not defined $expected or
         $actual eq $expected or 
         not($self->have_text_diff) or 
         $expected !~ /\n./s
    ) {
        Test::More::is($actual, $expected, $name);
    }
    else {
        $name = '' unless defined $name;
        ok $actual eq $expected,
           $name . "\n" . Text::Diff::diff(\$expected, \$actual);
    }
}

sub run(&;$) {
    (my ($self), @_) = find_my_self(@_);
    my $callback = shift;
    for my $block (@{$self->block_list}) {
        $block->run_filters unless $block->is_filtered;
        &{$callback}($block);
    }
}

my $name_error = "Can't determine section names";
sub _section_names {
    return @_ if @_ == 2;
    my $block = $self->first_block
      or croak $name_error;
    my @names = grep {
        $_ !~ /^(ONLY|LAST|SKIP)$/;
    } @{$block->{_section_order}[0] || []};
    croak "$name_error. Need two sections in first block"
      unless @names == 2;
    return @names;
}

sub _assert_plan {
    plan('no_plan') unless $Have_Plan;
}

sub END {
    run_compare() unless $Have_Plan or $DIED or not $import_called;
}

sub run_compare() {
    (my ($self), @_) = find_my_self(@_);
    $self->_assert_plan;
    my ($x, $y) = $self->_section_names(@_);
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    for my $block (@{$self->block_list}) {
        next unless exists($block->{$x}) and exists($block->{$y});
        $block->run_filters unless $block->is_filtered;
        if (ref $block->$x) {
            is_deeply($block->$x, $block->$y,
                $block->name ? $block->name : ());
        }
        elsif (ref $block->$y eq 'Regexp') {
            my $regexp = ref $y ? $y : $block->$y;
            like($block->$x, $regexp, $block->name ? $block->name : ());
        }
        else {
            is($block->$x, $block->$y, $block->name ? $block->name : ());
        }
    }
}

sub run_is() {
    (my ($self), @_) = find_my_self(@_);
    $self->_assert_plan;
    my ($x, $y) = $self->_section_names(@_);
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    for my $block (@{$self->block_list}) {
        next unless exists($block->{$x}) and exists($block->{$y});
        $block->run_filters unless $block->is_filtered;
        is($block->$x, $block->$y, 
           $block->name ? $block->name : ()
          );
    }
}

sub run_is_deeply() {
    (my ($self), @_) = find_my_self(@_);
    $self->_assert_plan;
    my ($x, $y) = $self->_section_names(@_);
    for my $block (@{$self->block_list}) {
        next unless exists($block->{$x}) and exists($block->{$y});
        $block->run_filters unless $block->is_filtered;
        is_deeply($block->$x, $block->$y, 
           $block->name ? $block->name : ()
          );
    }
}

sub run_like() {
    (my ($self), @_) = find_my_self(@_);
    $self->_assert_plan;
    my ($x, $y) = $self->_section_names(@_);
    for my $block (@{$self->block_list}) {
        next unless exists($block->{$x}) and defined($y);
        $block->run_filters unless $block->is_filtered;
        my $regexp = ref $y ? $y : $block->$y;
        like($block->$x, $regexp,
             $block->name ? $block->name : ()
            );
    }
}

sub run_unlike() {
    (my ($self), @_) = find_my_self(@_);
    $self->_assert_plan;
    my ($x, $y) = $self->_section_names(@_);
    for my $block (@{$self->block_list}) {
        next unless exists($block->{$x}) and defined($y);
        $block->run_filters unless $block->is_filtered;
        my $regexp = ref $y ? $y : $block->$y;
        unlike($block->$x, $regexp,
               $block->name ? $block->name : ()
              );
    }
}

sub skip_all_unless_require() {
    (my ($self), @_) = find_my_self(@_);
    my $module = shift;
    eval "require $module; 1"
        or Test::More::plan(
            skip_all => "$module failed to load"
        );
}

sub is_deep() {
    (my ($self), @_) = find_my_self(@_);
    require Test::Deep;
    Test::Deep::cmp_deeply(@_);
}

sub run_is_deep() {
    (my ($self), @_) = find_my_self(@_);
    $self->_assert_plan;
    my ($x, $y) = $self->_section_names(@_);
    for my $block (@{$self->block_list}) {
        next unless exists($block->{$x}) and exists($block->{$y});
        $block->run_filters unless $block->is_filtered;
        is_deep($block->$x, $block->$y, 
           $block->name ? $block->name : ()
          );
    }
}

sub _pre_eval {
    my $spec = shift;
    return $spec unless $spec =~
      s/\A\s*<<<(.*?)>>>\s*$//sm;
    my $eval_code = $1;
    eval "package main; $eval_code";
    croak $@ if $@;
    return $spec;
}

sub _block_list_init {
    my $spec = $self->spec;
    $spec = $self->_pre_eval($spec);
    my $cd = $self->block_delim;
    my @hunks = ($spec =~ /^(\Q${cd}\E.*?(?=^\Q${cd}\E|\z))/msg);
    my $blocks = $self->_choose_blocks(@hunks);
    $self->block_list($blocks); # Need to set early for possible filter use
    my $seq = 1;
    for my $block (@$blocks) {
        $block->blocks_object($self);
        $block->seq_num($seq++);
    }
    return $blocks;
}

sub _choose_blocks {
    my $blocks = [];
    for my $hunk (@_) {
        my $block = $self->_make_block($hunk);
        if (exists $block->{ONLY}) {
            diag "I found ONLY: maybe you're debugging?"
                unless $self->_no_diag_on_only;
            return [$block];
        }
        next if exists $block->{SKIP};
        push @$blocks, $block;
        if (exists $block->{LAST}) {
            return $blocks;
        }
    }
    return $blocks;
}

sub _check_reserved {
    my $id = shift;
    croak "'$id' is a reserved name. Use something else.\n"
      if $reserved_section_names->{$id} or
         $id =~ /^_/;
}

sub _make_block {
    my $hunk = shift;
    my $cd = $self->block_delim;
    my $dd = $self->data_delim;
    my $block = $self->block_class->new;
    $hunk =~ s/\A\Q${cd}\E[ \t]*(.*)\s+// or die;
    my $name = $1;
    my @parts = split /^\Q${dd}\E +\(?(\w+)\)? *(.*)?\n/m, $hunk;
    my $description = shift @parts;
    $description ||= '';
    unless ($description =~ /\S/) {
        $description = $name;
    }
    $description =~ s/\s*\z//;
    $block->set_value(description => $description);
    
    my $section_map = {};
    my $section_order = [];
    while (@parts) {
        my ($type, $filters, $value) = splice(@parts, 0, 3);
        $self->_check_reserved($type);
        $value = '' unless defined $value;
        $filters = '' unless defined $filters;
        if ($filters =~ /:(\s|\z)/) {
            croak "Extra lines not allowed in '$type' section"
              if $value =~ /\S/;
            ($filters, $value) = split /\s*:(?:\s+|\z)/, $filters, 2;
            $value = '' unless defined $value;
            $value =~ s/^\s*(.*?)\s*$/$1/;
        }
        $section_map->{$type} = {
            filters => $filters,
        };
        push @$section_order, $type;
        $block->set_value($type, $value);
    }
    $block->set_value(name => $name);
    $block->set_value(_section_map => $section_map);
    $block->set_value(_section_order => $section_order);
    return $block;
}

sub _spec_init {
    return $self->_spec_string
      if $self->_spec_string;
    local $/;
    my $spec;
    if (my $spec_file = $self->_spec_file) {
        open FILE, $spec_file or die $!;
        $spec = <FILE>;
        close FILE;
    }
    else {    
        $spec = do { 
            package main; 
            no warnings 'once';
            <DATA>;
        };
    }
    return $spec;
}

sub _strict_warnings() {
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
            $_ = "use strict;use warnings;$data$end";
            $done = 1;
        }
    );
}

sub tie_output() {
    my $handle = shift;
    die "No buffer to tie" unless @_;
    tie *$handle, 'Test::Base::Handle', $_[0];
}

sub no_diff {
    $ENV{TEST_SHOW_NO_DIFFS} = 1;
}

package Test::Base::Handle;

sub TIEHANDLE() {
    my $class = shift;
    bless \ $_[0], $class;
}

sub PRINT {
    $$self .= $_ for @_;
}

#===============================================================================
# Test::Base::Block
#
# This is the default class for accessing a Test::Base block object.
#===============================================================================
package Test::Base::Block;
our @ISA = qw(Spiffy);

our @EXPORT = qw(block_accessor);

sub AUTOLOAD {
    return;
}

sub block_accessor() {
    my $accessor = shift;
    no strict 'refs';
    return if defined &$accessor;
    *$accessor = sub {
        my $self = shift;
        if (@_) {
            Carp::croak "Not allowed to set values for '$accessor'";
        }
        my @list = @{$self->{$accessor} || []};
        return wantarray
        ? (@list)
        : $list[0];
    };
}

block_accessor 'name';
block_accessor 'description';
Spiffy::field 'seq_num';
Spiffy::field 'is_filtered';
Spiffy::field 'blocks_object';
Spiffy::field 'original_values' => {};

sub set_value {
    no strict 'refs';
    my $accessor = shift;
    block_accessor $accessor
      unless defined &$accessor;
    $self->{$accessor} = [@_];
}

sub run_filters {
    my $map = $self->_section_map;
    my $order = $self->_section_order;
    Carp::croak "Attempt to filter a block twice"
      if $self->is_filtered;
    for my $type (@$order) {
        my $filters = $map->{$type}{filters};
        my @value = $self->$type;
        $self->original_values->{$type} = $value[0];
        for my $filter ($self->_get_filters($type, $filters)) {
            $Test::Base::Filter::arguments =
              $filter =~ s/=(.*)$// ? $1 : undef;
            my $function = "main::$filter";
            no strict 'refs';
            if (defined &$function) {
                local $_ =
                    (@value == 1 and not defined($value[0])) ? undef :
                        join '', @value;
                my $old = $_;
                @value = &$function(@value);
                if (not(@value) or 
                    @value == 1 and defined($value[0]) and $value[0] =~ /\A(\d+|)\z/
                ) {
                    if ($value[0] && $_ eq $old) {
                        Test::Base::diag("Filters returning numbers are supposed to do munging \$_: your filter '$function' apparently doesn't.");
                    }
                    @value = ($_);
                }
            }
            else {
                my $filter_object = $self->blocks_object->filter_class->new;
                die "Can't find a function or method for '$filter' filter\n"
                  unless $filter_object->can($filter);
                $filter_object->current_block($self);
                @value = $filter_object->$filter(@value);
            }
            # Set the value after each filter since other filters may be
            # introspecting.
            $self->set_value($type, @value);
        }
    }
    $self->is_filtered(1);
}

sub _get_filters {
    my $type = shift;
    my $string = shift || '';
    $string =~ s/\s*(.*?)\s*/$1/;
    my @filters = ();
    my $map_filters = $self->blocks_object->_filters_map->{$type} || [];
    $map_filters = [ $map_filters ] unless ref $map_filters;
    my @append = ();
    for (
        @{$self->blocks_object->_filters}, 
        @$map_filters,
        split(/\s+/, $string),
    ) {
        my $filter = $_;
        last unless length $filter;
        if ($filter =~ s/^-//) {
            @filters = grep { $_ ne $filter } @filters;
        }
        elsif ($filter =~ s/^\+//) {
            push @append, $filter;
        }
        else {
            push @filters, $filter;
        }
    }
    return @filters, @append;
}

{
    %$reserved_section_names = map {
        ($_, 1);
    } keys(%Test::Base::Block::), qw( new DESTROY );
}

__DATA__

=encoding utf8

#line 1374
