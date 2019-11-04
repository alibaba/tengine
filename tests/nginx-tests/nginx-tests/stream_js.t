#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for stream njs module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ dgram stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy rewrite stream stream_return udp/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    js_include test.js;

    server {
        listen       127.0.0.1:8079;
        server_name  localhost;

        location /njs {
            js_content test_njs;
        }

        location /p/ {
            proxy_pass http://127.0.0.1:8095/;

        }

        location /return {
            return 200 $http_foo;
        }
    }
}

stream {
    js_set $js_addr      js_addr;
    js_set $js_var       js_var;
    js_set $js_log       js_log;
    js_set $js_unk       js_unk;
    js_set $js_req_line  js_req_line;
    js_set $js_sess_unk  js_sess_unk;

    js_include test.js;

    server {
        listen  127.0.0.1:8080;
        return  $js_addr;
    }

    server {
        listen  127.0.0.1:8081;
        return  $js_log;
    }

    server {
        listen  127.0.0.1:8082;
        return  $js_var;
    }

    server {
        listen  127.0.0.1:8083;
        return  $js_unk;
    }

    server {
        listen  127.0.0.1:8084;
        return  $js_sess_unk;
    }

    server {
        listen  127.0.0.1:%%PORT_8985_UDP%% udp;
        return  $js_addr;
    }

    server {
        listen      127.0.0.1:8086;
        js_access   js_access_step;
        js_preread  js_preread_step;
        js_filter   js_filter_step;
        proxy_pass  127.0.0.1:8090;
    }

    server {
        listen      127.0.0.1:8087;
        js_access   js_access_undecided;
        return      OK;
    }

    server {
        listen      127.0.0.1:8088;
        js_access   js_access_allow;
        return      OK;
    }

    server {
        listen      127.0.0.1:8089;
        js_access   js_access_deny;
        return      OK;
    }

    server {
        listen      127.0.0.1:8091;
        js_preread  js_preread_async;
        proxy_pass  127.0.0.1:8090;
    }

    server {
        listen      127.0.0.1:8092;
        js_preread  js_preread_data;
        proxy_pass  127.0.0.1:8090;
    }

    server {
        listen      127.0.0.1:8093;
        js_preread  js_preread_req_line;
        return      $js_req_line;
    }

    server {
        listen      127.0.0.1:8094;
        js_filter   js_filter_empty;
        proxy_pass  127.0.0.1:8090;
    }

    server {
        listen      127.0.0.1:8095;
        js_filter   js_filter_header_inject;
        proxy_pass  127.0.0.1:8079;
    }

    server {
        listen      127.0.0.1:8096;
        js_filter   js_filter_search;
        proxy_pass  127.0.0.1:8090;
    }

    server {
        listen      127.0.0.1:8097;
        js_access   js_access_except;
        proxy_pass  127.0.0.1:8090;
    }

    server {
        listen      127.0.0.1:8098;
        js_preread  js_preread_except;
        proxy_pass  127.0.0.1:8090;
    }

    server {
        listen      127.0.0.1:8099;
        js_filter   js_filter_except;
        proxy_pass  127.0.0.1:8090;
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    function js_addr(s) {
        return 'addr=' + s.remoteAddress;
    }

    function js_var(s) {
        return 'variable=' + s.variables.remote_addr;
    }

    function js_sess_unk(s) {
        return 'sess_unk=' + s.unk;
    }

    function js_log(s) {
        s.log("SEE-THIS");
    }

    var res = '';

    function js_access_step(s) {
        res += '1';

        setTimeout(function() {
            if (s.remoteAddress.match('127.0.0.1')) {
                s.allow();
            }
        }, 1);
    }

    function js_preread_step(s) {
        s.on('upload', function (data) {
            res += '2';
            if (res.length >= 3) {
                s.done();
            }
        });
    }

    function js_filter_step(s) {
        s.on('upload', function(data, flags) {
            s.send(data);
            res += '3';
        });

        s.on('download', function(data, flags) {

            if (!flags.last) {
                res += '4';
                s.send(data);

            } else {
                res += '5';
                s.send(res, {last:1});
                s.off('download');
            }
        });
    }

    function js_access_undecided(s) {
        s.decline();
    }

    function js_access_allow(s) {
        if (s.remoteAddress.match('127.0.0.1')) {
            s.done();
            return;
        }

        s.abort();
    }

    function js_access_deny(s) {
        if (s.remoteAddress.match('127.0.0.1')) {
            s.abort();
            return;
        }

        s.allow();
    }


    function js_preread_async(s) {
        setTimeout(function() {
            s.done();
        }, 1);
    }

    function js_preread_data(s) {
        s.on('upload', function (data, flags) {
            if (data.indexOf('z') != -1) {
                s.done();
            }
        });
    }

    var line = '';

    function js_preread_req_line(s) {
        s.on('upload', function (data, flags) {
            var n = data.indexOf('\\n');
            if (n != -1) {
                line = data.substr(0, n);
                s.done();
            }
        });
    }

    function js_req_line(s) {
        return line;
    }

    function js_filter_empty(s) {
    }

    function js_filter_header_inject(s) {
        var req = '';

        s.on('upload', function(data, flags) {
            req += data;

            var n = req.search('\\n');
            if (n != -1) {
                var rest = req.substr(n + 1);
                req = req.substr(0, n + 1);

                s.send(req + 'Foo: foo' + '\\r\\n' + rest, flags);

                s.off('upload');
            }
        });
    }

    function js_filter_search(s) {
        s.on('download', function(data, flags) {
            var n = data.search('y');
            if (n != -1) {
                s.send('z');
            }
        });

        s.on('upload', function(data, flags) {
            var n = data.search('x');
            if (n != -1) {
                s.send('y');
            }
        });
    }

    function js_access_except(s) {
        function done() {return s.a.a};

        setTimeout(done, 1);
        setTimeout(done, 2);
    }

    function js_preread_except(s) {
        var fs = require('fs');
        fs.readFileSync();
    }

    function js_filter_except(s) {
        s.on('unknown', function() {});
    }

EOF

$t->run_daemon(\&stream_daemon, port(8090));
$t->try_run('no stream njs available')->plan(19);
$t->waitforsocket('127.0.0.1:' . port(8090));

###############################################################################

is(stream('127.0.0.1:' . port(8080))->read(), 'addr=127.0.0.1',
	's.remoteAddress');
is(dgram('127.0.0.1:' . port(8985))->io('.'), 'addr=127.0.0.1',
	's.remoteAddress udp');
is(stream('127.0.0.1:' . port(8081))->read(), 'undefined', 's.log');
is(stream('127.0.0.1:' . port(8082))->read(), 'variable=127.0.0.1',
	's.variables');
is(stream('127.0.0.1:' . port(8083))->read(), '', 'stream js unknown function');
is(stream('127.0.0.1:' . port(8084))->read(), 'sess_unk=undefined', 's.unk');

TODO: {
local $TODO = 'not yet'
	unless get('/njs') =~ /^([.0-9]+)$/m && $1 ge '0.2.4';

is(stream('127.0.0.1:' . port(8086))->io('0'), '0122345',
	'async handlers order');
is(stream('127.0.0.1:' . port(8087))->io('#'), 'OK', 'js_access_undecided');
is(stream('127.0.0.1:' . port(8088))->io('#'), 'OK', 'js_access_allow');
is(stream('127.0.0.1:' . port(8089))->io('#'), '', 'js_access_deny');

is(stream('127.0.0.1:' . port(8091))->io('#'), '#', 'js_preread_async');
is(stream('127.0.0.1:' . port(8092))->io('#z'), '#z', 'js_preread_async_data');
is(stream('127.0.0.1:' . port(8093))->io("xy\na"), 'xy', 'js_preread_req_line');

is(stream('127.0.0.1:' . port(8094))->io('x'), 'x', 'js_filter_empty');
like(get('/p/return'), qr/foo/, 'js_filter_injected_header');
is(stream('127.0.0.1:' . port(8096))->io('x'), 'z', 'js_filter_search');

}

stream('127.0.0.1:' . port(8097))->io('x');
stream('127.0.0.1:' . port(8098))->io('x');
stream('127.0.0.1:' . port(8099))->io('x');

$t->stop();

ok(index($t->read_file('error.log'), 'SEE-THIS') > 0, 'stream js log');
ok(index($t->read_file('error.log'), 'at fs.readFileSync') > 0,
	'stream js_preread backtrace');
ok(index($t->read_file('error.log'), 'at js_filter_except') > 0,
	'stream js_filter backtrace');

###############################################################################

sub stream_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . port(8090),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		log2c("(new connection $client)");

		$client->sysread(my $buffer, 65536) or next;

		log2i("$client $buffer");

		log2o("$client $buffer");

		$client->syswrite($buffer);

		close $client;
	}
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

sub get {
	my ($url, %extra) = @_;

	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => '127.0.0.1:' . port(8079)
	) or die "Can't connect to nginx: $!\n";

	return http_get($url, socket => $s);
}

###############################################################################
