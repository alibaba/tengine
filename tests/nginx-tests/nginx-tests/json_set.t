#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for ngx_http_json_module, json_set directive.

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

my $t = Test::Nginx->new()->has(qw/http json rewrite proxy/)->plan(102)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    json_max_depth 5;

    json_set $jp_name $arg_json name;
    json_set $jp_age $arg_json age;
    json_set $jp_active $arg_json active;

    json_set $jp_nothing $arg_json nothing;

    json_set $jp_city $arg_json address.city;
    json_set $jp_zip $arg_json address.zip;
    json_set $jp_country $arg_json address.country.name;

    json_set $jp_tag0 $arg_json tags[0];
    json_set $jp_tag1 $arg_json tags[1];
    json_set $jp_tag2 $arg_json tags[2];

    json_set $jp_tags $arg_json tags;
    json_set $jp_address $arg_json address;

    json_set $jp_score0 $arg_json results.scores[0];
    json_set $jp_score1 $arg_json results.scores[1];
    json_set $jp_scores $arg_json results.scores;

    json_set $jp_bt $arg_json bt;
    json_set $jp_bf $arg_json bf;
    json_set $jp_nv $arg_json nv;

    json_set $jp_deep $arg_json a.b.c.d.e;

    json_set $jp_m00 $arg_json matrix[0][0];
    json_set $jp_m01 $arg_json matrix[0][1];
    json_set $jp_m10 $arg_json matrix[1][0];
    json_set $jp_m1 $arg_json matrix[1];

    json_set $jp_int $arg_json num_int;
    json_set $jp_neg $arg_json num_neg;
    json_set $jp_frac $arg_json num_frac;
    json_set $jp_exp $arg_json num_exp;

    json_set $jp_esc $arg_json escaped;
    json_set $jp_u_emoji $arg_json e;
    json_set $jp_u_8898 $arg_json u;

    json_set $jp_eobj $arg_json eobj;
    json_set $jp_earr $arg_json earr;

    json_set $jp_top0 $arg_json [0];
    json_set $jp_top1 $arg_json [1];

    json_set $jp_skip1 $arg_arrx [1].wanted;

    json_set $jp_wholeobj $arg_json items[1];

    json_set $jp_sp_name $arg_json data.user.name;
    json_set $jp_sp_age $arg_json data.user.age;
    json_set $jp_sp_city $arg_json data.user.addr.city;

    json_set $jp_ov_obj $arg_json a.b;
    json_set $jp_ov_c $arg_json a.b.c;

    json_set $jp_ar0 $arg_json arr[0];
    json_set $jp_ar2 $arg_json arr[2];

    json_set $jp_same_name1 $arg_json name;
    json_set $jp_same_name2 $arg_json name;

    json_set $jp_cache_a $arg_json a;
    json_set $jp_cache_b $arg_json b;

    json_set $jp_dup $arg_json dup;
    json_set $jp_dup_nested $arg_json obj.k;

    json_set $x $arg_json a;
    json_set $y $arg_json b;

    json_set $http_authorization $arg_json token;

    json_set $jp_nul_x $request_body '["a\\u0000x"]';
    json_set $jp_nul_y $request_body '["a\\u0000y"]';

    json_set $jp_body_x $request_body x;
    json_set $jp_body_y $request_body y.z;

    json_set $jp_qk_brk $arg_json 'foo["x[0]"]';
    json_set $jp_qk_rbr $arg_json '["a]b"]';
    json_set $jp_qk_empty $arg_json '[""]';
    json_set $jp_qk_mixed $arg_json 'data["a.b"].c';

    json_set $jp_qk_allq $request_body '["\\"asd\\u8898  smth\\""]';

    json_set $jp_qk_bs $arg_json 'o["a\\\\b"]';
    json_set $jp_qk_tb $arg_json 'o["ab\\\\"]';

    json_set $jp_qk_sur $arg_json 'o["x\\uD83D\\uDE00y"]';

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /simple {
            return 200 "name=[$jp_name] age=[$jp_age] active=[$jp_active]\n";
        }

        location /notfound {
            return 200 "nothing=[$jp_nothing]\n";
        }

        location /nested {
            return 200 "city=[$jp_city] zip=[$jp_zip] country=[$jp_country]\n";
        }

        location /array {
            return 200 "t0=[$jp_tag0] t1=[$jp_tag1] t2=[$jp_tag2]\n";
        }

        location /compound {
            return 200 "tags=[$jp_tags] address=[$jp_address]\n";
        }

        location /nested_array {
            return 200 "s0=[$jp_score0] s1=[$jp_score1] scores=[$jp_scores]\n";
        }

        location /literals {
            return 200 "bt=[$jp_bt] bf=[$jp_bf] nv=[$jp_nv]\n";
        }

        location /deep {
            return 200 "deep=[$jp_deep]\n";
        }

        location /matrix {
            return 200 "m00=[$jp_m00] m01=[$jp_m01] m10=[$jp_m10] m1=[$jp_m1]\n";
        }

        location /numbers {
            return 200 "int=[$jp_int] neg=[$jp_neg] frac=[$jp_frac] exp=[$jp_exp]\n";
        }

        location /escaped {
            return 200 "esc=[$jp_esc]\n";
        }

        location /unicode_value {
            return 200 "e=[$jp_u_emoji] u=[$jp_u_8898]\n";
        }

        location /empty {
            return 200 "eobj=[$jp_eobj] earr=[$jp_earr]\n";
        }

        location /toparray {
            return 200 "t0=[$jp_top0] t1=[$jp_top1]\n";
        }

        location /skipidx {
            return 200 "wanted=[$jp_skip1]\n";
        }

        location /wholeobj {
            return 200 "obj=[$jp_wholeobj]\n";
        }

        location /shared {
            return 200 "name=[$jp_sp_name] age=[$jp_sp_age] city=[$jp_sp_city]\n";
        }

        location /overlap {
            return 200 "obj=[$jp_ov_obj] c=[$jp_ov_c]\n";
        }

        location /siblings {
            return 200 "a0=[$jp_ar0] a2=[$jp_ar2]\n";
        }

        location /invalid {
            return 200 "name=[$jp_name]\n";
        }

        location /empty_src {
            return 200 "name=[$jp_name]\n";
        }

        location /samepath {
            return 200 "n1=[$jp_same_name1] n2=[$jp_same_name2]\n";
        }

        location /cache {
            return 200 "a=[$jp_cache_a] b=[$jp_cache_b]\n";
        }

        location /dup {
            return 200 "dup=[$jp_dup] nested=[$jp_dup_nested]\n";
        }

        location /interfere {
            set $x fixed;
            return 200 "x1=[$x] y=[$y] x2=[$x]\n";
        }

        location /auth_collision {
            return 200 "auth=[$http_authorization]\n";
        }

        location /quoted {
            return 200 "brk=[$jp_qk_brk] rbr=[$jp_qk_rbr] empty=[$jp_qk_empty] mixed=[$jp_qk_mixed]\n";
        }

        location /allq {
            proxy_pass http://127.0.0.1:8080/allq_echo;
            proxy_set_header X-Match $jp_qk_allq;
        }

        location /allq_echo {
            return 200 "k=[$http_x_match]\n";
        }

        location /nul {
            proxy_pass http://127.0.0.1:8080/nul_echo;
            proxy_set_header X-Nul-X $jp_nul_x;
            proxy_set_header X-Nul-Y $jp_nul_y;
        }

        location /nul_echo {
            return 200 "x=[$http_x_nul_x] y=[$http_x_nul_y]\n";
        }

        location /mixed_sources {
            proxy_pass http://127.0.0.1:8080/mixed_sources_echo;
            proxy_set_header X-Name $jp_name;
            proxy_set_header X-Nul-X $jp_nul_x;
            proxy_set_header X-Nul-Y $jp_nul_y;
        }

        location /mixed_sources_echo {
            return 200 "name=[$http_x_name] x=[$http_x_nul_x] y=[$http_x_nul_y]\n";
        }

        location /body {
            proxy_pass http://127.0.0.1:8080/body_echo;
            proxy_set_header X-Body-X $jp_body_x;
            proxy_set_header X-Body-Y $jp_body_y;
        }

        location /body_echo {
            return 200 "x=[$http_x_body_x] y=[$http_x_body_y]\n";
        }

        location /backslash {
            return 200 "bs=[$jp_qk_bs] tb=[$jp_qk_tb]\n";
        }

        location /surrogate {
            return 200 "sur=[$jp_qk_sur]\n";
        }
    }
}

EOF

$t->run();

my $testdir = $t->testdir();
my $globals = $t->test_globals();
my $globals_http = $t->test_globals_http();

###############################################################################

like(http_get('/simple?json={"name":"John","age":30,"active":true}'),
	qr/name=\[John\] age=\[30\] active=\[true\]/,
	'simple scalar values');

like(http_get('/simple?json={"name":"","age":0,"active":false}'),
	qr/name=\[\] age=\[0\] active=\[false\]/, 'empty string value');

like(http_get('/notfound?json={"name":"John"}'), qr/nothing=\[\]/,
	'non-existent path');

like(http_get('/notfound?json=42'), qr/nothing=\[\]/, 'top-level number');

like(http_get('/notfound?json="str"'), qr/nothing=\[\]/, 'top-level string');

like(http_get('/notfound?json=true'), qr/nothing=\[\]/, 'top-level boolean');

like(http_get('/notfound?json=null'), qr/nothing=\[\]/, 'top-level null');

like(http_get('/nested?json={"address":{"city":"NYC","zip":"10001","country":'
	. '{"name":"US"}}}'), qr/city=\[NYC\] zip=\[10001\] country=\[US\]/,
	'nested object paths');

like(http_get('/array?json={"tags":["go","rust","perl"]}'),
	qr/t0=\[go\] t1=\[rust\] t2=\[perl\]/,
	'array element access');

like(http_get('/compound?json={"tags":[1,2],"address":{"x":1}}'),
	qr/tags=\[\[1,2\]\] address=\[\{"x":1\}\]/,
	'compound values');

like(http_get('/nested_array?json={"results":{"scores":[100,200]}}'),
	qr/s0=\[100\] s1=\[200\] scores=\[\[100,200\]\]/,
	'nested array in object');

like(http_get('/literals?json={"bt":true,"bf":false,"nv":null}'),
	qr/bt=\[true\] bf=\[false\] nv=\[null\]/,
	'literals true false null');

like(http_get('/deep?json={"a":{"b":{"c":{"d":{"e":42}}}}}'), qr/deep=\[42\]/,
	'deeply nested path at max depth');

like(http_get('/deep?json={"a":{"b":{"c":{"d":{"e":{"f":42}}}}}}'),
	qr/deep=\[\]/, 'json deeper than max depth rejected');

like(http_get('/matrix?json={"matrix":[[1,2],[3,4]]}'),
	qr/m00=\[1\] m01=\[2\] m10=\[3\] m1=\[\[3,4\]\]/, 'array of arrays');

like(http_get('/numbers?json={"num_int":42,"num_neg":-7,"num_frac":3.14,'
	. '"num_exp":1e10}'), qr/int=\[42\] neg=\[-7\] frac=\[3\.14\] exp=\[1e10\]/,
	'number types');

like(http_get('/numbers?json={"num_int":0,"num_neg":-0,"num_frac":0.5,'
	. '"num_exp":0e1}'), qr/int=\[0\] neg=\[-0\] frac=\[0\.5\] exp=\[0e1\]/,
	'number types with zero');

like(http_get('/numbers?json={"num_int":1,"num_neg":1.5e3,"num_frac":1e+10,'
	. '"num_exp":1E-5}'),
	qr/int=\[1\] neg=\[1\.5e3\] frac=\[1e\+10\] exp=\[1E-5\]/,
	'number types with exponent');

like(http_get('/escaped?json={"escaped":"a\\nb\\tc"}'), qr/esc=\[a\nb\tc\]/,
	'string with escapes');

like(http_get('/escaped?json={"escaped":"a\\bb\\fc\\rd\\/e"}'),
	qr/esc=\[a\x08b\x0Cc\x0Dd\/e\]/, 'string with control escapes');

like(http_get('/unicode_value?json={"e":"\\uD83D\\uDE00","u":"\\u8898"}'),
	qr/e=\[\xF0\x9F\x98\x80\] u=\[\xE8\xA2\x98\]/,
	'unicode escapes in values decode to UTF-8 bytes');

like(http_get('/unicode_value?json={"e":"\\u00e9","u":"\\u07ff"}'),
	qr/e=\[\xC3\xA9\] u=\[\xDF\xBF\]/,
	'two-byte unicode escapes decode to UTF-8 bytes');

like(http_get('/empty?json={"eobj":{},"earr":[]}'),
	qr/eobj=\[\{\}\] earr=\[\[\]\]/, 'empty object and array');

like(http_get('/empty?json={"eobj":{},"earr":[1,2]}'),
	qr/eobj=\[\{\}\] earr=\[\[1,2\]\]/, 'array without element paths');

like(http_get('/toparray?json=[10,20,30]'), qr/t0=\[10\] t1=\[20\]/,
	'top-level array');

like(http_post('/body', "\n{\n\t\"x\" : 1 ,\n\t\"y\" : { \"z\" : 2 },\n"
	. "\t\"w\" : [ 1 , 2 ]\n}\n"), qr/x=\[1\] y=\[2\]/,
	'insignificant whitespace');

like(http_get('/invalid?json={bad'), qr/name=\[\]/, 'invalid json');

like(http_get('/invalid?json={"name":"John"'), qr/name=\[\]/,
	'invalid json truncated after match');

like(http_get('/invalid?json={"name":"John","x":"\\uDEAD"}'),
	qr/name=\[\]/, 'invalid json sibling string resets prior match');

like(http_get('/invalid?json={"name":"John","x":01}'), qr/name=\[\]/,
	'invalid json number with leading zero');

like(http_get('/invalid?json={"name":"John","x":1.}'), qr/name=\[\]/,
	'invalid json fraction without digits');

like(http_get('/invalid?json={"name":"John","x":-z}'), qr/name=\[\]/,
	'invalid json minus without digits');

like(http_get('/invalid?json={"name":"John","x":1e}'), qr/name=\[\]/,
	'invalid json exponent without digits');

like(http_get('/invalid?json={"name":"John","x":1e+}'), qr/name=\[\]/,
	'invalid json exponent sign without digits');

like(http_get('/invalid?json={"name":"John","x":.5}'), qr/name=\[\]/,
	'invalid json number without integer part');

like(http_get('/invalid?json={"name":"John","x":tru}'), qr/name=\[\]/,
	'invalid json truncated true');

like(http_get('/invalid?json={"name":"John","x":fals}'), qr/name=\[\]/,
	'invalid json truncated false');

like(http_get('/invalid?json={"name":"John","x":nul}'), qr/name=\[\]/,
	'invalid json truncated null');

like(http_get('/invalid?json={"name":"John","x":?}'), qr/name=\[\]/,
	'invalid json value start');

like(http_get('/invalid?json={"name":"John"}x'), qr/name=\[\]/,
	'invalid json trailing garbage');

like(http_get('/invalid?json={"name":"John","x":"\\q"}'), qr/name=\[\]/,
	'invalid json escape');

like(http_get('/invalid?json={"name":"John","x":"\\uZZZZ"}'), qr/name=\[\]/,
	'invalid json unicode escape');

like(http_get('/invalid?json={"name":"John","x":"\\uD83Dz"}'), qr/name=\[\]/,
	'invalid json high surrogate without escape');

like(http_get('/invalid?json={"name":"John","x":"\\uD83D\\n"}'),
	qr/name=\[\]/, 'invalid json high surrogate with non-unicode escape');

like(http_get('/invalid?json={"name":"John","x":"\\uD83D\\uZZZZ"}'),
	qr/name=\[\]/, 'invalid json high surrogate with invalid hex');

like(http_get('/invalid?json={"name":"John","x":"\\uD83D\\u0041"}'),
	qr/name=\[\]/, 'invalid json high surrogate without low surrogate');

like(http_post('/body', '{"x":1,"y" 2}'), qr/x=\[\]/,
	'invalid json name separator');

like(http_post('/body', '{"x":1 "y":2}'), qr/x=\[\]/,
	'invalid json value separator');

like(http_post('/body', '{"x":1,"y":[1 2]}'), qr/x=\[\]/,
	'invalid json array separator');

like(http_post('/body', "{\"x\":1,\"y\":\"a\x01b\"}"), qr/x=\[\]/,
	'invalid json control character in string');

like(http_get('/empty_src'), qr/name=\[\]/, 'empty source');

like(http_get('/samepath?json={"name":"locval"}'),
	qr/n1=\[locval\] n2=\[locval\]/,
	'same path populates multiple destinations');

like(http_get('/cache?json={"a":"one","b":"two"}'), qr/a=\[one\] b=\[two\]/,
	'cache shared source');

like(http_get('/skipidx?arrx=[{"ignored":{"deep":[1,2,3]}},{"wanted":"yes"}]'),
	qr/wanted=\[yes\]/, 'array index after skipped unconfigured element');

like(http_get('/wholeobj?json={"items":[{"a":1},{"b":2,"c":[3,4]}]}'),
	qr/obj=\[\{"b":2,"c":\[3,4\]\}\]/, 'whole object captured as text');

like(http_get('/shared?json={"data":{"user":{"name":"jo","age":42,'
	. '"addr":{"city":"NYC"}}}}'),
	qr/name=\[jo\] age=\[42\] city=\[NYC\]/, 'shared-prefix targets');

like(http_get('/overlap?json={"a":{"b":{"c":7,"d":8}}}'),
	qr/obj=\[\{"c":7,"d":8\}\] c=\[7\]/, 'prefix overlap object and scalar');

like(http_get('/siblings?json={"arr":[10,20,30,40]}'),
	qr/a0=\[10\] a2=\[30\]/, 'non-contiguous sibling array elements');

like(http_get('/dup?json={"dup":"first","dup":"second","obj":{"k":1,"k":2}}'),
	qr/dup=\[second\] nested=\[2\]/, 'last match wins on duplicate keys');

like(http_get('/interfere?json={"a":"A","b":"B"}'),
	qr/x1=\[fixed\] y=\[B\] x2=\[fixed\]/,
	'sibling evaluation does not clobber existing destination variable');

like(http_get('/auth_collision?json={"token":"json-token"}'),
	qr/auth=\[json-token\]/,
	'json_set exact variable overrides http_ prefix lookup without header');

my $auth_collision = http(<<'EOF');
GET /auth_collision?json={"token":"json-token"} HTTP/1.0
Host: localhost
Authorization: Basic dXNlcjpzZWNyZXQ=

EOF

like($auth_collision, qr/auth=\[json-token\]/,
	'json_set exact variable overrides Authorization header lookup');

like(http_get('/quoted?json={"foo":{"x[0]":"brkkey"},'
	. '"a]b":"rbrkey","":"emptykey","data":{"a.b":{"c":"deep"}}}'),
	qr/brk=\[brkkey\] rbr=\[rbrkey\] empty=\[emptykey\] mixed=\[deep\]/,
	'quoted key segments');

like(http_get('/quoted?json={"a.b":"x","foo":{},"a]b":"y","data":{}}'),
	qr/rbr=\[y\] empty=\[\]/, 'quoted empty key absent');

like(http_post('/allq', '{"\\"asd\\u8898  smth\\"":"hit"}'),
	qr/k=\[hit\]/, 'quoted key with escaped quotes, unicode and spaces');

like(http_get('/backslash?json={"o":{"a\\\\b":"bs","ab\\\\":"tb"}}'),
	qr/bs=\[bs\] tb=\[tb\]/, 'quoted key with literal backslash');

like(http_post('/nul', '{"a\\u0000x":"X","a\\u0000y":"Y"}'),
	qr/x=\[X\] y=\[Y\]/, 'binary-safe keys with embedded NUL');

like(http_post('/mixed_sources?json={"name":"John"}',
	'{"a\\u0000x":"X","a\\u0000y":"Y"}'),
	qr/name=\[John\] x=\[X\] y=\[Y\]/,
	'mixed arg_json and request_body sources stay isolated');

like(http_get('/surrogate?json={"o":{"x\\uD83D\\uDE00y":"emoji"}}'),
	qr/sur=\[emoji\]/, 'quoted key with surrogate pair');

###############################################################################

# invalid json_set paths

is(check_path('.foo'), 1, 'leading dot rejected');
is(check_path('a[0]b'), 1, 'bare key after index without separator rejected');
is(check_path('a["x"]y'), 1, 'bare key after quoted key without separator rejected');
is(check_path('foo.'), 1, 'trailing dot rejected');
is(check_path('foo..bar'), 1, 'double dot rejected');
is(check_path('$.foo'), 1, 'root selector followed by segment rejected');

is(check_path('a[]'), 1, 'empty index rejected');
is(check_path('a[xyz]'), 1, 'non-digit index rejected');
is(check_path('a[1a]'), 1, 'index with trailing letter rejected');
is(check_path('a[12'), 1, 'unterminated index rejected');
is(check_path('a[99999999999999999999]'), 1, 'index overflow rejected');

is(check_path('a["abc'), 1, 'unterminated quoted key rejected');
is(check_path('a["x"'), 1, 'quoted key missing closing bracket rejected');
is(check_path('a["x"b'), 1, 'quoted key not followed by bracket end rejected');
is(check_conf_rejected("    json_set \$v \$arg_json 'a[\"x\\\\q\"]';\n",
	qr/invalid json_set path/), 1,
	'quoted key invalid escape rejected');
is(check_conf_rejected("    json_set \$v \$arg_json 'a[\"\\\\u12\"]';\n",
	qr/invalid json_set path/), 1,
	'quoted key short unicode escape rejected');
is(check_conf_rejected("    json_set \$v \$arg_json 'o[\"x\\\\uD83D\"]';\n",
	qr/invalid json_set path/), 1,
	'quoted key lone high surrogate rejected');
is(check_path('a["\\uZZZZ"]'), 1, 'quoted key invalid hex rejected');
is(check_path('a["\\uDC00"]'), 1, 'quoted key lone low surrogate rejected');
is(check_path('a["\\uD83Dz"]'), 1,
	'quoted key high surrogate without escape rejected');
is(check_path('a["\\uD83D\\u0041"]'), 1,
	'quoted key high surrogate without low surrogate rejected');
is(check_conf_rejected("    json_set \$v \$arg_json '';\n",
	qr/empty json_set path/), 1,
	'empty json_set path rejected');
is(check_conf_rejected("    json_set v \$arg_json a;\n",
	qr/invalid variable name "v"/), 1,
	'non-variable destination rejected');
is(check_conf_rejected("    json_set \$v arg_json a;\n",
	qr/invalid variable name "arg_json"/), 1,
	'non-variable source rejected');

is(check_conf_ok("    json_set \$v \$arg_json 'foo[\"x\"].bar';\n"), 1,
	'quoted key then bare key accepted');
is(check_path('$'), 1, 'root selector is not accepted');

# json_max_depth bounds

is(check_conf_ok("    json_max_depth 1;\n"), 1,
	'minimum json_max_depth accepted');
is(check_conf_ok("    json_max_depth 256;\n"), 1,
	'maximum json_max_depth accepted');
is(check_conf_rejected("    json_max_depth 0;\n",
	qr/value must be between 1 and 256/), 1,
	'json_max_depth below minimum rejected');
is(check_conf_rejected("    json_max_depth 257;\n",
	qr/value must be between 1 and 256/), 1,
	'json_max_depth above maximum rejected');

# json_set context

is(check_conf_rejected_server("        json_set \$v \$arg_json a;\n",
	qr/"json_set" directive is not allowed here/), 1,
	'json_set rejected in server context');

is(check_conf_rejected_location("            json_set \$v \$arg_json a;\n",
	qr/"json_set" directive is not allowed here/), 1,
	'json_set rejected in location context');

# duplicate json_set target

is(check_conf_rejected("    json_set \$foo \$arg_json a;\n"
	. "    json_set \$foo \$arg_json b;\n",
	qr/json_set variable "foo" is already defined/),
	1, 'duplicate json_set target rejected');

###############################################################################

sub check_path {
	my ($path) = @_;

	return check_conf_rejected("    json_set \$v \$arg_json '$path';\n",
		qr/invalid json_set path/);
}

sub run_check_conf {
	my ($snippet) = @_;

	# no server block: "nginx -t" opens listening sockets
	my $conf = $globals . "\n"
		. "daemon off;\n"
		. "events {}\n"
		. "http {\n"
		. $globals_http . "\n"
		. $snippet
		. "}\n";

	my $file = "$testdir/invalid.conf";
	open my $fh, '>', $file or die "can't open $file: $!";
	print $fh $conf;
	close $fh;

	# a dedicated log keeps errors out of the error.log checked on teardown
	my $bin = $Test::Nginx::NGINX;
	return `$bin -t -p $testdir/ -c invalid.conf -e invalid_error.log 2>&1`;
}

sub check_conf_rejected {
	my ($snippet, $re) = @_;

	return (run_check_conf($snippet) =~ $re) ? 1 : 0;
}

sub check_conf_ok {
	my ($snippet) = @_;
	my $out = run_check_conf($snippet);

	# sanitizer builds may exit non-zero after a successful check
	if ($out !~ /syntax is ok/) {
		diag($out);
		return 0;
	}

	return 1;
}

sub check_conf_rejected_server {
	my ($snippet, $re) = @_;

	return check_conf_rejected_server_block($snippet, '', $re);
}

sub check_conf_rejected_location {
	my ($snippet, $re) = @_;

	return check_conf_rejected_server_block('', $snippet, $re);
}

sub check_conf_rejected_server_block {
	my ($server_snippet, $location_snippet, $re) = @_;

	my $snippet = "    server {\n"
		. $server_snippet
		. "        location / {\n"
		. $location_snippet
		. "            return 200 ok;\n"
		. "        }\n"
		. "    }\n";

	return check_conf_rejected($snippet, $re);
}

###############################################################################

sub http_post {
	my ($url, $body) = @_;

	return http(<<EOF . $body);
POST $url HTTP/1.0
Host: localhost
Content-Length: ${\ length($body) }

EOF
}

###############################################################################
