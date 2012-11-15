#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Valentin Bartenev

# Tests for nginx ssi module, "if" statement.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http ssi/)->plan(44);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        location / {
            ssi on;
        }
    }
}

EOF


my $if_elif_else =
	'<!--#if expr="$arg_if" -->IF'
	. '<!--#elif expr="$arg_elif" -->ELIF'
	. '<!--#else -->ELSE'
	. '<!--#endif -->';

my $zig = 'GOOD';
my $zag = 'GOOD';

foreach my $i (reverse 1 .. 15) {
	if ($i % 2) {
		$zig =
		"<!--#if expr='\$arg_$i' -->$i<!--#else -->$zig<!--#endif -->";
		$zag =
		"<!--#if expr='\$arg_$i' -->$zag<!--#else -->$i<!--#endif -->";
	} else {
		$zig =
		"<!--#if expr='\$arg_$i' -->$zig<!--#else -->$i<!--#endif -->";
		$zag =
		"<!--#if expr='\$arg_$i' -->$i<!--#else -->$zag<!--#endif -->";
	}
}

$t->run();

###############################################################################

$t->write_file('if_var.html', 'x<!--#if expr="$arg_v" -->OK<!--#endif -->x');

like(http_get('/if_var.html?v=1'), qr/^xOKx$/m, 'if variable exists');
like(http_get('/if_var.html'), qr/^xx$/m, 'if variable not exists');


$t->write_file('if_eq.html',
	'x<!--#if expr="$arg_v = equal" -->OK<!--#endif -->x');

like(http_get('/if_eq.html?v=equal'), qr/^xOKx$/m, 'if var = text');
like(http_get('/if_eq.html?v=notequal'), qr/^xx$/m, 'if var = text (false)');


$t->write_file('if_neq.html',
	'x<!--#if expr="equal != $arg_v" -->OK<!--#endif -->x');

like(http_get('/if_neq.html?v=notequal'), qr/^xOKx$/m, 'if text != var');
like(http_get('/if_neq.html?v=equal'), qr/^xx$/m, 'if text != var (false)');


SKIP: {
	# PCRE may not be available unless we have rewrite module

	skip 'no PCRE', 4 unless $t->has_module('rewrite');

	$t->write_file('if_eq_re.html',
		'x<!--#if expr="$arg_v = /re+gexp?/" -->OK<!--#endif -->x');

	like(http_get('/if_eq_re.html?v=XreeeegexX'), qr/^xOKx$/m,
		'if var = /regex/');
	like(http_get('/if_eq_re.html?v=XrgxX'), qr/^xx$/m,
		'if var = /regex/ (false)');


	$t->write_file('if_neq_re.html',
		'x<!--#if expr="$arg_v != /re+gexp?/" -->OK<!--#endif -->x');

	like(http_get('/if_neq_re.html?v=XrgxX'), qr/^xOKx$/m,
		'if var != /regex/');
	like(http_get('/if_neq_re.html?v=XreeeegexX'), qr/^xx$/m,
		'if var != /regex/ (false)');
}


$t->write_file('if_varvar.html',
	'x<!--#if expr="$arg_v = var$arg_v2" -->OK<!--#endif -->x');

like(http_get('/if_varvar.html?v=varHERE&v2=HERE'), qr/^xOKx$/m,
	'if var = complex');


SKIP: {
	# PCRE may not be available unless we have rewrite module

	skip 'no PCRE', 2 unless $t->has_module('rewrite');

	$t->write_file('if_cap_re.html',
		'x<!--#if expr="$arg_v = /(CAP\d).*(CAP\d)/" -->'
			. '<!--#echo var="1" -->x<!--#echo var="2" -->'
		. '<!--#endif -->x');

	like(http_get('/if_cap_re.html?v=hereCAP1andCAP2'), qr/^xCAP1xCAP2x$/m,
		'if regex with captures');


	$t->write_file('if_ncap_re.html',
		'x<!--#if expr="$arg_v = /(?P<ncap>HERE)/" -->'
			. '<!--#echo var="ncap" -->'
		. '<!--#endif -->x');

	like(http_get('/if_ncap_re.html?v=captureHEREeee'), qr/^xHEREx$/m,
		'if regex with named capture');
}


$t->write_file('if.html', 'x' . $if_elif_else . 'x');

like(http_get('/if.html?if=1'), qr/^xIFx$/m, 'if');
like(http_get('/if.html?if=1&elif=1'), qr/^xIFx$/m, 'if suppresses elif');
like(http_get('/if.html?elif=1'), qr/^xELIFx$/m, 'elif');
like(http_get('/if.html'), qr/^xELSEx$/m, 'else');


$t->write_file('if_multi.html',
	'x<!--#if expr="$arg_1" -->IF1<!--#else -->ELSE1<!--#endif -->'
	. 'x<!--#if expr="$arg_2" -->IF2<!--#else -->ELSE2<!--#endif -->'
	. 'x<!--#if expr="$arg_3" -->IF3<!--#else -->ELSE3<!--#endif -->'
	. 'x<!--#if expr="$arg_4" -->IF4<!--#else -->ELSE4<!--#endif -->'
	. 'x<!--#if expr="$arg_5" -->IF5<!--#else -->ELSE5<!--#endif -->x');

like(http_get('/if_multi.html?1=t&2=t&3=t&4=t&5=t'),
	qr/^xIF1xIF2xIF3xIF4xIF5x$/m, 'multiple if (sequentially)');
like(http_get('/if_multi.html?1=t&3=t&5=t'), qr/^xIF1xELSE2xIF3xELSE4xIF5x$/m,
	'multiple if (interlaced)');
like(http_get('/if_multi.html?2=t&4=t'), qr/^xELSE1xIF2xELSE3xIF4xELSE5x$/m,
	'multiple if (interlaced reversed)');


$t->write_file('if_in_block.html',
	'<!--#block name="one" -->' . $if_elif_else . '<!--#endblock -->'
	. 'x<!--#include virtual="/404?$args" stub="one" -->x');

like(http_get('/if_in_block.html?if=1'), qr/^xIFx$/m, 'if (in block)');
like(http_get('/if_in_block.html?if=1&elif=1'), qr/^xIFx$/m,
	'if suppresses elif (in block)');
like(http_get('/if_in_block.html?elif=1'), qr/^xELIFx$/m, 'elif (in block)');
like(http_get('/if_in_block.html'), qr/^xELSEx$/m, 'else (in block)');


$t->write_file('if_config_set_echo.html',
	'x<!--#if expr="$arg_if" -->'
		. '<!--#config timefmt="IF" -->'
		. '<!--#set var="v" value="$date_gmt" -->'
		. '<!--#echo var="v" -->'
	. '<!--#else -->'
		. '<!--#config timefmt="ELSE" -->'
		. '<!--#set var="v" value="$date_gmt" -->'
		. '<!--#echo var="v" -->'
	. '<!--#endif -->x');

like(http_get('/if_config_set_echo.html?if=1'), qr/^xIFx$/m,
	'if config-set-echo');
like(http_get('/if_config_set_echo.html'), qr/^xELSEx$/m,
	'else config-set-echo');


$t->write_file('if_include.html',
	'x<!--#if expr="$arg_if" -->'
		. '<!--#include virtual="/if.html?if=1" -->'
	. '<!--#else -->'
		. '<!--#include virtual="/if.html" -->'
	. '<!--#endif -->x');

like(http_get('/if_include.html?if=1'), qr/^xxIFxx$/m,
	'if include');
like(http_get('/if_include.html'), qr/^xxELSExx$/m,
	'else include');


$t->write_file('if_block.html',
	'<!--#if expr="$arg_if" -->'
		. '<!--#block name="one" -->IF<!--#endblock -->'
	. '<!--#else -->'
		. '<!--#block name="one" -->ELSE<!--#endblock -->'
	. '<!--#endif -->'
	. 'x<!--#include virtual="/404" stub="one" -->x');

like(http_get('/if_block.html?if=1'), qr/^xIFx$/m, 'if block');
like(http_get('/if_block.html'), qr/^xELSEx$/m, 'else block');


TODO: {
local $TODO = 'support for nested ifs';

$t->write_file('ifif.html',
	'x<!--#if expr="$arg__if" -->IFx' . $if_elif_else
	. '<!--#elif expr="$arg__elif" -->ELIFx' . $if_elif_else
	. '<!--#else -->ELSEx' . $if_elif_else
	. '<!--#endif -->x');

like(http_get('/ifif.html?_if=1&if=1'), qr/^xIFxIFx$/m, 'if if');
like(http_get('/ifif.html?_if=1&elif=1'), qr/^xIFxELIFx$/m, 'if elif');
like(http_get('/ifif.html?_if=1'), qr/^xIFxELSEx$/m, 'if else');

like(http_get('/ifif.html?_elif=1&if=1'), qr/^xELIFxIFx$/m, 'elif if');
like(http_get('/ifif.html?_elif=1&elif=1'), qr/^xELIFxELIFx$/m, 'elif elif');
like(http_get('/ifif.html?_elif=1'), qr/^xELIFxELSEx$/m, 'elif else');

like(http_get('/ifif.html?if=1'), qr/^xELSExIFx$/m, 'else if');
like(http_get('/ifif.html?elif=1'), qr/^xELSExELIFx$/m, 'else elif');
like(http_get('/ifif.html'), qr/^xELSExELSEx$/m, 'else else');


$t->write_file('zigzag.html',
	"x<!--#if expr='\$arg_0' -->$zig<!--#else -->$zag<!--#endif -->x");

like(http_get('/zigzag.html?0=t&2=t&4=t&6=t&8=t&10=t&12=t&14=t'),
	qr/^xGOODx$/m, 'zigzag');
like(http_get('/zigzag.html?1=t&3=t&5=t&7=t&9=t&11=t&13=t&15=t'),
	qr/^xGOODx$/m, 'zagzig');


$t->write_file('zigzag_block.html',
	'<!--#block name="one" -->'
	. "x<!--#if expr='\$arg_0' -->$zig<!--#else -->$zag<!--#endif -->x"
	. '<!--#endblock -->'
	. 'x<!--#include virtual="/404?$args" stub="one" -->x');

like(http_get('/zigzag_block.html?0=t&2=t&4=t&6=t&8=t&10=t&12=t&14=t'),
	qr/^xGOODx$/m, 'zigzag block');
like(http_get('/zigzag_block.html?1=t&3=t&5=t&7=t&9=t&11=t&13=t&15=t'),
	qr/^xGOODx$/m, 'zagzig block');

}


like(`grep -F '[alert]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no alerts');

###############################################################################
