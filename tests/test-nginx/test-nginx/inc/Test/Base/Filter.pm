#line 1
#===============================================================================
# This is the default class for handling Test::Base data filtering.
#===============================================================================
package Test::Base::Filter;
use Spiffy -Base;
use Spiffy ':XXX';

field 'current_block';

our $arguments;
sub current_arguments {
    return undef unless defined $arguments;
    my $args = $arguments;
    $args =~ s/(\\s)/ /g;
    $args =~ s/(\\[a-z])/'"' . $1 . '"'/gee;
    return $args;
}

sub assert_scalar {
    return if @_ == 1;
    require Carp;
    my $filter = (caller(1))[3];
    $filter =~ s/.*:://;
    Carp::croak "Input to the '$filter' filter must be a scalar, not a list";
}

sub _apply_deepest {
    my $method = shift;
    return () unless @_;
    if (ref $_[0] eq 'ARRAY') {
        for my $aref (@_) {
            @$aref = $self->_apply_deepest($method, @$aref);
        }
        return @_;
    }
    $self->$method(@_);
}

sub _split_array {
    map {
        [$self->split($_)];
    } @_;
}

sub _peel_deepest {
    return () unless @_;
    if (ref $_[0] eq 'ARRAY') {
        if (ref $_[0]->[0] eq 'ARRAY') {
            for my $aref (@_) {
                @$aref = $self->_peel_deepest(@$aref);
            }
            return @_;
        }
        return map { $_->[0] } @_;
    }
    return @_;
}

#===============================================================================
# these filters work on the leaves of nested arrays
#===============================================================================
sub Join { $self->_peel_deepest($self->_apply_deepest(join => @_)) }
sub Reverse { $self->_apply_deepest(reverse => @_) }
sub Split { $self->_apply_deepest(_split_array => @_) }
sub Sort { $self->_apply_deepest(sort => @_) }


sub append {
    my $suffix = $self->current_arguments;
    map { $_ . $suffix } @_;
}

sub array {
    return [@_];
}

sub base64_decode {
    $self->assert_scalar(@_);
    require MIME::Base64;
    MIME::Base64::decode_base64(shift);
}

sub base64_encode {
    $self->assert_scalar(@_);
    require MIME::Base64;
    MIME::Base64::encode_base64(shift);
}

sub chomp {
    map { CORE::chomp; $_ } @_;
}

sub chop {
    map { CORE::chop; $_ } @_;
}

sub dumper {
    no warnings 'once';
    require Data::Dumper;
    local $Data::Dumper::Sortkeys = 1;
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Terse = 1;
    Data::Dumper::Dumper(@_);
}

sub escape {
    $self->assert_scalar(@_);
    my $text = shift;
    $text =~ s/(\\.)/eval "qq{$1}"/ge;
    return $text;
}

sub eval {
    $self->assert_scalar(@_);
    my @return = CORE::eval(shift);
    return $@ if $@;
    return @return;
}

sub eval_all {
    $self->assert_scalar(@_);
    my $out = '';
    my $err = '';
    Test::Base::tie_output(*STDOUT, $out);
    Test::Base::tie_output(*STDERR, $err);
    my $return = CORE::eval(shift);
    no warnings;
    untie *STDOUT;
    untie *STDERR;
    return $return, $@, $out, $err;
}

sub eval_stderr {
    $self->assert_scalar(@_);
    my $output = '';
    Test::Base::tie_output(*STDERR, $output);
    CORE::eval(shift);
    no warnings;
    untie *STDERR;
    return $output;
}

sub eval_stdout {
    $self->assert_scalar(@_);
    my $output = '';
    Test::Base::tie_output(*STDOUT, $output);
    CORE::eval(shift);
    no warnings;
    untie *STDOUT;
    return $output;
}

sub exec_perl_stdout {
    my $tmpfile = "/tmp/test-blocks-$$";
    $self->_write_to($tmpfile, @_);
    open my $execution, "$^X $tmpfile 2>&1 |"
      or die "Couldn't open subprocess: $!\n";
    local $/;
    my $output = <$execution>;
    close $execution;
    unlink($tmpfile)
      or die "Couldn't unlink $tmpfile: $!\n";
    return $output;
}

sub flatten {
    $self->assert_scalar(@_);
    my $ref = shift;
    if (ref($ref) eq 'HASH') {
        return map {
            ($_, $ref->{$_});
        } sort keys %$ref;
    }
    if (ref($ref) eq 'ARRAY') {
        return @$ref;
    }
    die "Can only flatten a hash or array ref";
}

sub get_url {
    $self->assert_scalar(@_);
    my $url = shift;
    CORE::chomp($url);
    require LWP::Simple;
    LWP::Simple::get($url);
}

sub hash {
    return +{ @_ };
}

sub head {
    my $size = $self->current_arguments || 1;
    return splice(@_, 0, $size);
}

sub join {
    my $string = $self->current_arguments;
    $string = '' unless defined $string;
    CORE::join $string, @_;
}

sub lines {
    $self->assert_scalar(@_);
    my $text = shift;
    return () unless length $text;
    my @lines = ($text =~ /^(.*\n?)/gm);
    return @lines;
}

sub norm {
    $self->assert_scalar(@_);
    my $text = shift;
    $text = '' unless defined $text;
    $text =~ s/\015\012/\n/g;
    $text =~ s/\r/\n/g;
    return $text;
}

sub prepend {
    my $prefix = $self->current_arguments;
    map { $prefix . $_ } @_;
}

sub read_file {
    $self->assert_scalar(@_);
    my $file = shift;
    CORE::chomp $file;
    open my $fh, $file
      or die "Can't open '$file' for input:\n$!";
    CORE::join '', <$fh>;
}

sub regexp {
    $self->assert_scalar(@_);
    my $text = shift;
    my $flags = $self->current_arguments;
    if ($text =~ /\n.*?\n/s) {
        $flags = 'xism'
          unless defined $flags;
    }
    else {
        CORE::chomp($text);
    }
    $flags ||= '';
    my $regexp = eval "qr{$text}$flags";
    die $@ if $@;
    return $regexp;
}

sub reverse {
    CORE::reverse(@_);
}

sub slice {
    die "Invalid args for slice"
      unless $self->current_arguments =~ /^(\d+)(?:,(\d))?$/;
    my ($x, $y) = ($1, $2);
    $y = $x if not defined $y;
    die "Invalid args for slice"
      if $x > $y;
    return splice(@_, $x, 1 + $y - $x);
}

sub sort {
    CORE::sort(@_);
}

sub split {
    $self->assert_scalar(@_);
    my $separator = $self->current_arguments;
    if (defined $separator and $separator =~ s{^/(.*)/$}{$1}) {
        my $regexp = $1;
        $separator = qr{$regexp};
    }
    $separator = qr/\s+/ unless $separator;
    CORE::split $separator, shift;
}

sub strict {
    $self->assert_scalar(@_);
    <<'...' . shift;
use strict;
use warnings;
...
}

sub tail {
    my $size = $self->current_arguments || 1;
    return splice(@_, @_ - $size, $size);
}

sub trim {
    map {
        s/\A([ \t]*\n)+//;
        s/(?<=\n)\s*\z//g;
        $_;
    } @_;
}

sub unchomp {
    map { $_ . "\n" } @_;
}

sub write_file {
    my $file = $self->current_arguments
      or die "No file specified for write_file filter";
    if ($file =~ /(.*)[\\\/]/) {
        my $dir = $1;
        if (not -e $dir) {
            require File::Path;
            File::Path::mkpath($dir)
              or die "Can't create $dir";
        }
    }
    open my $fh, ">$file"
      or die "Can't open '$file' for output\n:$!";
    print $fh @_;
    close $fh;
    return $file;
}

sub yaml {
    $self->assert_scalar(@_);
    require YAML;
    return YAML::Load(shift);
}

sub _write_to {
    my $filename = shift;
    open my $script, ">$filename"
      or die "Couldn't open $filename: $!\n";
    print $script @_;
    close $script
      or die "Couldn't close $filename: $!\n";
}

__DATA__

#line 636
