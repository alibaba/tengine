#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for stream njs module, exit hook.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http stream/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    js_import test.js;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /njs {
            js_content test.njs;
        }
    }
}

stream {
    %%TEST_GLOBALS_STREAM%%

    js_import test.js;

    server {
        listen      127.0.0.1:8081;
        js_access   test.access;
        js_filter   test.filter;
        proxy_pass  127.0.0.1:8090;
    }

    server {
        listen      127.0.0.1:8082;
        js_access   test.access;
        proxy_pass  127.0.0.1:1;
    }
}

EOF

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    function access(s) {
        njs.on('exit', () => {
            var v = s.variables;
            var c = `\${v.bytes_received}/\${v.bytes_sent}`;
            var u = `\${v.upstream_bytes_received}/\${v.upstream_bytes_sent}`;
            s.error(`s:\${s.status} C: \${c} U: \${u}`);
        });

        s.allow();
    }

    function filter(s) {
        s.on('upload', (data, flags) => {
            s.send(`@\${data}`, flags);
        });

        s.on('download', (data, flags) => {
            s.send(data.slice(2), flags);
        });
    }

    export default {njs: test_njs, access, filter};
EOF

$t->try_run('no stream njs available')->plan(2);

$t->run_daemon(\&stream_daemon, port(8090));
$t->waitforsocket('127.0.0.1:' . port(8090));

###############################################################################

local $TODO = 'not yet'
	unless http_get('/njs') =~ /^([.0-9]+)$/m && $1 ge '0.5.2';

stream('127.0.0.1:' . port(8081))->io('###');
stream('127.0.0.1:' . port(8082))->io('###');

$t->stop();

ok(index($t->read_file('error.log'), 's:200 C: 3/6 U: 8/4') > 0, 'normal');
ok(index($t->read_file('error.log'), 's:502 C: 0/0 U: 0/0') > 0, 'failed conn');

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

		$buffer = $buffer . $buffer;

		log2o("$client $buffer");

		$client->syswrite($buffer);

		close $client;
	}
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
