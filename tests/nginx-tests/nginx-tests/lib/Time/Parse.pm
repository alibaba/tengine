# Date::Parse
#
# Copyright (c) 1995 Graham Barr. All rights reserved. This program is free
# software; you can redistribute it and/or modify it under the same terms
# as Perl itself.

package Time::Parse;

=head1 NAME

Date::Parse - Parse date strings into time values

=head1 SYNOPSIS

	use Date::Parse;
	
	$time = str2time($date);
	
	($ss,$mm,$hh,$day,$month,$year,$zone) = strptime($date);

=head1 DESCRIPTION

C<Date::Parse> provides two routines for parsing date strings into time values.

=over 4

=item str2time(DATE [, ZONE])

C<str2time> parses C<DATE> and returns a unix time value, or undef upon failure.
C<ZONE>, if given, specifies the timezone to assume when parsing if the
date string does not specify a timezome.

=item strptime(DATE [, ZONE])

C<strptime> takes the same arguments as str2time but returns an array of
values C<($ss,$mm,$hh,$day,$month,$year,$zone)>. Elements are only defined
if they could be extracted from the date string. The C<$zone> element is
the timezone offset in seconds from GMT. An empty array is returned upon
failure.

=head1 MULTI-LANGUAGE SUPPORT

Date::Parse is capable of parsing dates in several languages, these are
English, French, German and Italian. Changing the language is done via
a static method call, for example

	Date::Parse->language('German');

will cause Date::Parse to attempt to parse any subsequent dates in German.

This is only a first pass, I am considering changing this to be

	$lang = Date::Language->new('German');
	$lang->str2time("25 Jun 1996 21:09:55 +0100");

I am open to suggestions on this.

=head1 AUTHOR

Graham Barr <Graham.Barr@tiuk.ti.com>

=head1 REVISION

$Revision: 2.6 $

=head1 COPYRIGHT

Copyright (c) 1995 Graham Barr. All rights reserved. This program is free
software; you can redistribute it and/or modify it under the same terms
as Perl itself.

=cut

require 5.000;
use strict;
use vars qw($VERSION @ISA @EXPORT);
use Time::Local;
use Carp;
use Time::Zone;
use Exporter;

@ISA = qw(Exporter);
@EXPORT = qw(&strtotime &str2time &strptime);

$VERSION = sprintf("%d.%02d", q$Revision: 2.6 $ =~ m#(\d+)\.(\d+)#);

my %month = (
	january		=> 0,
	february	=> 1,
	march		=> 2,
	april		=> 3,
	may		=> 4,
	june		=> 5,
	july		=> 6,
	august		=> 7,
	september	=> 8,
	sept		=> 8,
	october		=> 9,
	november	=> 10,
	december	=> 11,
	);

my %day = (
	sunday		=> 0,
	monday		=> 1,
	tuesday		=> 2,
	tues		=> 2,
	wednesday	=> 3,
	wednes		=> 3,
	thursday	=> 4,
	thur		=> 4,
	thurs		=> 4,
	friday		=> 5,
	saturday	=> 6,
	);

my @suf = (qw(th st nd rd th th th th th th)) x 3;
@suf[11,12,13] = qw(th th th);

#Abbreviations

map { $month{substr($_,0,3)} = $month{$_} } keys %month;
map { $day{substr($_,0,3)}   = $day{$_} }   keys %day;

my $strptime = <<'ESQ';
 my %month = map { lc $_ } %$mon_ref;
 my $daypat = join("|", map { lc $_ } keys %$day_ref);
 my $monpat = join("|", keys %month);
 my $sufpat = join("|", map { lc $_ } @$suf_ref);

 my %ampm = (
	am => 0,
	pm => 12
	);

 # allow map am +. a.m.
 map { my($z) = $_; $z =~ s#(\w)#$1\.#g; $ampm{$z} = $ampm{$_} } keys %ampm;

 my($AM, $PM) = (0,12);

sub
{

 my $dtstr = lc shift;
 my $merid = 24;

 my($year,$month,$day,$hh,$mm,$ss,$zone) = (undef) x 7;

 $zone = tz_offset(shift)
    if(@_);

 while(1) { last unless($dtstr =~ s#\([^\(\)]*\)# #o) }

 $dtstr =~ s#(\A|\n|\Z)# #sog;

 # ignore day names
 $dtstr =~ s#([\d\w\s])[\.\,]\s#$1 #sog;
 $dtstr =~ s#($daypat)\s*(den\s)?# #o;
 # Time: 12:00 or 12:00:00 with optional am/pm
  
 if($dtstr =~ s#[:\s](\d\d?):(\d\d)(:(\d\d)(?:\.\d+)?)?\s*([ap]\.?m\.?)?\s# #o)
  {
   ($hh,$mm,$ss) = ($1,$2,$4 || 0);
   $merid = $ampm{$5} if($5);
  }

 # Time: 12 am
  
 elsif($dtstr =~ s#\s(\d\d?)\s*([ap]\.?m\.?)\s# #o)
  {
   ($hh,$mm,$ss) = ($1,0,0);
   $merid = $ampm{$2};
  }
  
 # Date: 12-June-96 (using - . or /)
  
 if($dtstr =~ s#\s(\d\d?)([\-\./])($monpat)(\2(\d\d+))?\s# #o)
  {
   ($month,$day) = ($month{$3},$1);
   $year = $5
        if($5);
  }
  
 # Date: 12-12-96 (using '-', '.' or '/' )
  
 elsif($dtstr =~ s#\s(\d\d*)([\-\./])(\d\d?)(\2(\d\d+))?\s# #o)
  {
   ($month,$day) = ($1 - 1,$3);
   if($5)
    {
     $year = $5;
     # Possible match for 1995-01-24 (short mainframe date format);
     ($year,$month,$day) = ($1, $3 - 1, $5)
    	    if($month > 12);
    }
  }
 elsif($dtstr =~ s#\s(\d+)\s*($sufpat)?\s*($monpat)# #o)
  {
   ($month,$day) = ($month{$3},$1);
  }
 elsif($dtstr =~ s#($monpat)\s*(\d+)\s*($sufpat)?\s# #o)
  {
   ($month,$day) = ($month{$1},$2);
  }

 # Date: 961212

 elsif($dtstr =~ s#\s(\d\d)(\d\d)(\d\d)\s# #o)
  {
   ($year,$month,$day) = ($1,$2-1,$3);
  }

 $year = $1
    if(!defined($year) && $dtstr =~ s#\s(\d{2}(\d{2})?)[\s\.,]# #o);

 # Zone

 if($dtstr =~ s#\s"?(\w{3,})\s# #o) 
  {
   $zone = tz_offset($1);
   return ()
    unless(defined $zone);
  }
 elsif($dtstr =~ s#\s(([\-\+])\d\d?)(\d\d)\s# #o)
  {
   my $m = $2 . $3;
   $zone = 60 * ($m + (60 * $1));
  }

 return ()
    if($dtstr =~ /\S/o);

 $hh += 12
	if(defined $hh && $merid == $PM);

 $year -= 1900
	if(defined $year && $year > 1900);

 return ($ss,$mm,$hh,$day,$month,$year,$zone);
}
ESQ

use vars qw($day_ref $mon_ref $suf_ref $obj);

sub gen_parser
{
 local($day_ref,$mon_ref,$suf_ref,$obj) = @_;

 if($obj)
  {
   my $obj_strptime = $strptime;
   substr($obj_strptime,index($strptime,"sub")+6,0) = <<'ESQ';
 shift; # package
ESQ
   return eval "$obj_strptime";
  }

 eval "$strptime";

}

*strptime = gen_parser(\%day,\%month,\@suf);

sub str2time
{
 my @t = strptime(@_);

 return undef
	unless @t;

 my($ss,$mm,$hh,$day,$month,$year,$zone) = @t;
 my @lt  = localtime(time);

 $hh    ||= 0;
 $mm    ||= 0;
 $ss    ||= 0;

 $month = $lt[4]
	unless(defined $month);

 $day  = $lt[3]
	unless(defined $day);

 $year = ($month > $lt[4]) ? ($lt[5] - 1) : $lt[5]
	unless(defined $year);

 return defined $zone ? timegm($ss,$mm,$hh,$day,$month,$year) - $zone
    	    	      : timelocal($ss,$mm,$hh,$day,$month,$year);
}

1;

