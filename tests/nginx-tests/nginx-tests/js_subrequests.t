#!/usr/bin/perl
#
# (C) Dmitry Volyntsev.
# (C) Nginx, Inc.

# Tests for subrequests in http njs module.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { require JSON::PP; };
plan(skip_all => "JSON::PP not installed") if $@;

my $t = Test::Nginx->new()->has(qw/http rewrite proxy cache/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache1
                       keys_zone=ON:1m      use_temp_path=on;

    js_import test.js;

    js_set $async_var       test.async_var;
    js_set $subrequest_var  test.subrequest_var;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /njs {
            js_content test.njs;
        }

        location /sr {
            js_content test.sr;
        }

        location /sr_pr {
            js_content test.sr_pr;
        }

        location /sr_args {
            js_content test.sr_args;
        }

        location /sr_options_args {
            js_content test.sr_options_args;
        }

        location /sr_options_args_pr {
            js_content test.sr_options_args_pr;
        }

        location /sr_options_method {
            js_content test.sr_options_method;
        }

        location /sr_options_method_pr {
            js_content test.sr_options_method_pr;
        }

        location /sr_options_body {
            js_content test.sr_options_body;
        }

        location /sr_options_method_head {
            js_content test.sr_options_method_head;
        }

        location /sr_body {
            js_content test.sr_body;
        }

        location /sr_body_pr {
            js_content test.sr_body_pr;
        }

        location /sr_body_special {
            js_content test.sr_body_special;
        }

        location /sr_in_variable_handler {
            set $_ $async_var;
            js_content test.sr_in_variable_handler;
        }

        location /sr_detached_in_variable_handler {
            return 200 $subrequest_var;
        }

        location /sr_async_var {
            set $_ $async_var;
            error_page 404 /return;
            return 404;
        }

        location /sr_error_page {
            js_content test.sr_error_page;
        }

        location /sr_js_in_subrequest {
            js_content test.sr_js_in_subrequest;
        }

        location /sr_js_in_subrequest_pr {
            js_content test.sr_js_in_subrequest_pr;
        }

        location /sr_file {
            js_content test.sr_file;
        }

        location /sr_cache {
            js_content test.sr_cache;
        }


        location /sr_unavail {
            js_content test.sr_unavail;
        }

        location /sr_unavail_pr {
            js_content test.sr_unavail_pr;
        }

        location /sr_broken {
            js_content test.sr_broken;
        }

        location /sr_too_large {
            js_content test.sr_too_large;
        }

        location /sr_out_of_order {
            js_content test.sr_out_of_order;
        }

        location /sr_except_not_a_func {
            js_content test.sr_except_not_a_func;
        }

        location /sr_except_failed_to_convert_options_arg {
            js_content test.sr_except_failed_to_convert_options_arg;
        }

        location /sr_except_invalid_options_header_only {
            js_content test.sr_except_invalid_options_header_only;
        }

        location /sr_in_sr_callback {
            js_content test.sr_in_sr_callback;
        }

        location /sr_uri_except {
            js_content test.sr_uri_except;
        }


        location /file/ {
            alias %%TESTDIR%%/;
        }

        location /p/ {
            proxy_cache $arg_c;
            proxy_pass http://127.0.0.1:8081/;
        }

        location /daemon/ {
            proxy_pass http://127.0.0.1:8082/;
        }

        location /too_large/ {
            subrequest_output_buffer_size 3;
            proxy_pass http://127.0.0.1:8081/;
        }

        location /sr_in_sr {
            js_content test.sr_in_sr;
        }

        location /unavail {
            proxy_pass http://127.0.0.1:8084/;
        }

        location /sr_parent {
             js_content test.sr_parent;
        }

        location /js_sub {
            js_content test.js_sub;
        }

        location /return {
            return 200 '["$request_method"]';
        }

        location /error_page_404 {
            return 404;

            error_page 404 /404.html;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location /sub1 {
            add_header H $arg_h;
            return 206 '{"a": {"b": 1}}';
        }

        location /sub2 {
            return 404 '{"e": "msg"}';
        }

        location /method {
            return 200 '["$request_method"]';
        }

        location /body {
            js_content test.body;
        }

        location /detached {
            js_content test.detached;
        }

        location /delayed {
            js_content test.delayed;
        }
    }

    server {
        listen       127.0.0.1:8084;
        server_name  localhost;

        return 444;
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    function sr(r) {
        subrequest_fn(r, ['/p/sub2'], ['uri', 'status'])
    }

    function sr_pr(r) {
        r.subrequest('/p/sub1', 'h=xxx')
        .then(reply => r.return(200, JSON.stringify({h:reply.headersOut.h})))
    }

    function sr_args(r) {
        r.subrequest('/p/sub1', 'h=xxx', reply => {
            r.return(200, JSON.stringify({h:reply.headersOut.h}));
        });
    }

    function sr_options_args(r) {
        r.subrequest('/p/sub1', {args:'h=xxx'}, reply => {
            r.return(200, JSON.stringify({h:reply.headersOut.h}));
        });
    }

    function sr_options_args_pr(r) {
        r.subrequest('/p/sub1', {args:'h=xxx'})
        .then(reply => r.return(200, JSON.stringify({h:reply.headersOut.h})))
    }

    function sr_options_method(r) {
        r.subrequest('/p/method', {method:r.args.m}, body_fwd_cb);
    }

    function sr_options_method_pr(r) {
        r.subrequest('/p/method', {method:r.args.m})
        .then(body_fwd_cb);
    }

    function sr_options_body(r) {
        r.subrequest('/p/body', {method:'POST', body:'["REQ-BODY"]'},
                     body_fwd_cb);
    }

    function sr_options_method_head(r) {
        r.subrequest('/p/method', {method:'HEAD'}, reply => {
            r.return(200, JSON.stringify({c:reply.status}));
        });
    }

    function sr_body(r) {
        r.subrequest('/p/sub1', body_fwd_cb);
    }

    function sr_body_pr(r) {
        r.subrequest('/p/sub1')
        .then(body_fwd_cb);
    }

    function sr_body_special(r) {
        r.subrequest('/p/sub2', body_fwd_cb);
    }

    function body(r) {
        r.return(200, r.variables.request_body);
    }

    function delayed(r) {
        setTimeout(r => r.return(200), 100, r);
    }

    function detached(r) {
        var method = r.variables.request_method;
        r.log(`DETACHED: \${method} args: \${r.variables.args}`);

        r.return(200);
    }

    function sr_in_variable_handler(r) {
    }

    function async_var(r) {
        r.subrequest('/p/delayed', reply => {
            r.return(200, JSON.stringify(["CB-VAR"]));
        });

        return "";
    }

    function sr_error_page(r) {
         r.subrequest('/error_page_404')
         .then(reply => {r.return(200, `reply.status:\${reply.status}`)});
    }

    function subrequest_var(r) {
        r.subrequest('/p/detached',  {detached:true});
        r.subrequest('/p/detached',  {detached:true, args:'a=yyy',
                                      method:'POST'});

        return "subrequest_var";
    }

    function sr_file(r) {
        r.subrequest('/file/t', body_fwd_cb);
    }

    function sr_cache(r) {
        r.subrequest('/p/t', body_fwd_cb);
    }

    function sr_unavail(req) {
        subrequest_fn(req, ['/unavail'], ['uri', 'status']);
    }

    function sr_unavail_pr(req) {
        subrequest_fn_pr(req, ['/unavail'], ['uri', 'status']);
    }

    function sr_broken(r) {
        r.subrequest('/daemon/unfinished', reply => {
            r.return(200, JSON.stringify({code:reply.status}));
        });
    }

    function sr_too_large(r) {
        r.subrequest('/too_large/t', body_fwd_cb);
    }

    function sr_in_sr(r) {
        r.subrequest('/sr', body_fwd_cb);
    }

    function sr_js_in_subrequest(r) {
        r.subrequest('/js_sub', body_fwd_cb);
    }

    function sr_js_in_subrequest_pr(r) {
        r.subrequest('/js_sub')
        .then(body_fwd_cb);
    }

    function sr_in_sr_callback(r) {
        r.subrequest('/return', function (reply) {
                try {
                    reply.subrequest('/return');

                } catch (err) {
                    r.return(200, JSON.stringify({e:err.message}));
                    return;
                }

                r.return(200);
            });
    }

    function sr_parent(r) {
        try {
            var parent = r.parent;

        } catch (err) {
            r.return(200, JSON.stringify({e:err.message}));
            return;
        }

        r.return(200);
    }

    function sr_out_of_order(r) {
        subrequest_fn(r, ['/p/delayed', '/p/sub1', '/unknown'],
                      ['uri', 'status']);
    }

    function collect(replies, props, total, reply) {
        reply.log(`subrequest handler: \${reply.uri} status: \${reply.status}`)

        var rep = {};
        props.forEach(p => {rep[p] = reply[p]});

        replies.push(rep);

        if (replies.length == total) {
            reply.parent.return(200, JSON.stringify(replies));
        }
    }

    function subrequest_fn(r, subs, props) {
        var replies = [];

        subs.forEach(sr =>
                     r.subrequest(sr, collect.bind(null, replies,
                                                   props, subs.length)));
    }

    function subrequest_fn_pr(r, subs, props) {
        var replies = [];

        subs.forEach(sr => r.subrequest(sr)
            .then(collect.bind(null, replies, props, subs.length)));
    }

    function sr_except_not_a_func(r) {
        r.subrequest('/sub1', 'a=1', 'b');
    }

    let Failed = {get toConvert() { return {toString(){return {};}}}};

    function sr_except_failed_to_convert_options_arg(r) {
        r.subrequest('/sub1', {args:Failed.toConvert}, ()=>{});
    }

    function sr_uri_except(r) {
        r.subrequest(Failed.toConvert, 'a=1', 'b');
    }

    function body_fwd_cb(r) {
        r.parent.return(200, JSON.stringify(JSON.parse(r.responseText)));
    }

    function js_sub(r) {
        r.return(200, '["JS-SUB"]');
    }

    export default {njs:test_njs, sr, sr_pr, sr_args, sr_options_args,
                    sr_options_args_pr, sr_options_method, sr_options_method_pr,
                    sr_options_method_head, sr_options_body, sr_body,
                    sr_body_pr, sr_body_special, body, delayed, detached,
                    sr_in_variable_handler, async_var, sr_error_page,
                    subrequest_var, sr_file, sr_cache, sr_unavail, sr_parent,
                    sr_unavail_pr, sr_broken, sr_too_large, sr_in_sr,
                    sr_js_in_subrequest, sr_js_in_subrequest_pr, js_sub,
                    sr_in_sr_callback, sr_out_of_order, sr_except_not_a_func,
                    sr_uri_except, sr_except_failed_to_convert_options_arg};

EOF

$t->write_file('t', '["SEE-THIS"]');

$t->try_run('no njs available')->plan(32);
$t->run_daemon(\&http_daemon);

###############################################################################

is(get_json('/sr'), '[{"status":404,"uri":"/p/sub2"}]', 'sr');
is(get_json('/sr_args'), '{"h":"xxx"}', 'sr_args');
is(get_json('/sr_options_args'), '{"h":"xxx"}', 'sr_options_args');
is(get_json('/sr_options_method?m=POST'), '["POST"]', 'sr method POST');
is(get_json('/sr_options_method?m=PURGE'), '["PURGE"]', 'sr method PURGE');
is(get_json('/sr_options_body'), '["REQ-BODY"]', 'sr_options_body');
is(get_json('/sr_options_method_head'), '{"c":200}', 'sr_options_method_head');
is(get_json('/sr_body'), '{"a":{"b":1}}', 'sr_body');
is(get_json('/sr_body_special'), '{"e":"msg"}', 'sr_body_special');
is(get_json('/sr_in_variable_handler'), '["CB-VAR"]', 'sr_in_variable_handler');
is(get_json('/sr_file'), '["SEE-THIS"]', 'sr_file');
is(get_json('/sr_cache?c=1'), '["SEE-THIS"]', 'sr_cache');
is(get_json('/sr_cache?c=1'), '["SEE-THIS"]', 'sr_cached');
is(get_json('/sr_js_in_subrequest'), '["JS-SUB"]', 'sr_js_in_subrequest');
is(get_json('/sr_unavail'), '[{"status":502,"uri":"/unavail"}]',
	'sr_unavail');
is(get_json('/sr_out_of_order'),
	'[{"status":404,"uri":"/unknown"},' .
	'{"status":206,"uri":"/p/sub1"},' .
	'{"status":200,"uri":"/p/delayed"}]',
	'sr_multi');

is(get_json('/sr_pr'), '{"h":"xxx"}', 'sr_promise');
is(get_json('/sr_options_args_pr'), '{"h":"xxx"}', 'sr_options_args_pr');
is(get_json('/sr_options_method_pr?m=PUT'), '["PUT"]', 'sr method PUT');
is(get_json('/sr_body_pr'), '{"a":{"b":1}}', 'sr_body_pr');
is(get_json('/sr_js_in_subrequest_pr'), '["JS-SUB"]', 'sr_js_in_subrequest_pr');
is(get_json('/sr_unavail_pr'), '[{"status":502,"uri":"/unavail"}]',
	'sr_unavail_pr');

like(http_get('/sr_detached_in_variable_handler'), qr/subrequest_var/,
     'sr_detached_in_variable_handler');

like(http_get('/sr_error_page'), qr/reply\.status:404/,
     'sr_error_page');

http_get('/sr_broken');
http_get('/sr_in_sr');
http_get('/sr_in_variable_handler');
http_get('/sr_async_var');
http_get('/sr_too_large');
http_get('/sr_except_not_a_func');
http_get('/sr_except_failed_to_convert_options_arg');
http_get('/sr_uri_except');

is(get_json('/sr_in_sr_callback'),
	'{"e":"subrequest can only be created for the primary request"}',
	'subrequest for non-primary request');

$t->stop();

ok(index($t->read_file('error.log'), 'callback is not a function') > 0,
	'subrequest cb exception');
ok(index($t->read_file('error.log'), 'failed to convert uri arg') > 0,
	'subrequest uri exception');
ok(index($t->read_file('error.log'), 'failed to convert options.args') > 0,
	'subrequest invalid args exception');
ok(index($t->read_file('error.log'), 'too big subrequest response') > 0,
	'subrequest too large body');
ok(index($t->read_file('error.log'), 'subrequest creation failed') > 0,
	'subrequest creation failed');
ok(index($t->read_file('error.log'),
		'js subrequest: failed to get the parent context') > 0,
	'zero parent ctx');

ok(index($t->read_file('error.log'), 'DETACHED') > 0,
	'detached subrequest');

###############################################################################

sub recode {
	my $json;
	eval { $json = JSON::PP::decode_json(shift) };

	if ($@) {
		return "<failed to parse JSON>";
	}

	JSON::PP->new()->canonical()->encode($json);
}

sub get_json {
	http_get(shift) =~ /\x0d\x0a?\x0d\x0a?(.*)/ms;
	recode($1);
}

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . port(8082),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';
		my $uri = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;

		if ($uri eq '/unfinished') {
			print $client
				"HTTP/1.1 200 OK" . CRLF .
				"Transfer-Encoding: chunked" . CRLF .
				"Content-Length: 100" . CRLF .
				CRLF .
				"unfinished" . CRLF;
			close($client);
		}
	}
}

###############################################################################
