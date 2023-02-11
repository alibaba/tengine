#!/usr/bin/perl

# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for stream njs module, fetch method.

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

    server {
        listen       127.0.0.1:8080;
        server_name  aaa;

        location /validate {
            js_content test.validate;
        }
    }
}

stream {
    %%TEST_GLOBALS_STREAM%%

    js_import test.js;

    server {
        listen      127.0.0.1:8081;
        js_preread  test.preread_verify;
        proxy_pass  127.0.0.1:8090;
    }

    server {
        listen      127.0.0.1:8082;
        js_filter   test.filter_verify;
        proxy_pass  127.0.0.1:8091;
    }
}

EOF

my $p = port(8080);

$t->write_file('test.js', <<EOF);
    function test_njs(r) {
        r.return(200, njs.version);
    }

    function validate(r) {
        r.return((r.requestText == 'QZ') ? 200 : 403);
    }

    function preread_verify(s) {
        var collect = Buffer.from([]);

        s.on('upstream', async function (data, flags) {
            collect = Buffer.concat([collect, data]);

            if (collect.length >= 4 && collect.readUInt16BE(0) == 0xabcd) {
                s.off('upstream');

                let reply = await ngx.fetch('http://127.0.0.1:$p/validate',
                                            {body: collect.slice(2,4),
                                             headers: {Host:'aaa'}});

                (reply.status == 200) ? s.done(): s.deny();

            } else if (collect.length) {
                s.deny();
            }
        });
    }

    function filter_verify(s) {
        var collect = Buffer.from([]);

        s.on('upstream', async function (data, flags) {
            collect = Buffer.concat([collect, data]);

            if (collect.length >= 4 && collect.readUInt16BE(0) == 0xabcd) {
                s.off('upstream');

                let reply = await ngx.fetch('http://127.0.0.1:$p/validate',
                                            {body: collect.slice(2,4),
                                             headers: {Host:'aaa'}});

                if (reply.status == 200) {
                    s.send(collect.slice(4), flags);

                } else {
                    s.send("__CLOSE__", flags);
                }
            }
        });
    }

    export default {njs: test_njs, validate, preread_verify, filter_verify};
EOF

$t->try_run('no stream njs available')->plan(7);

$t->run_daemon(\&stream_daemon, port(8090), port(8091));
$t->waitforsocket('127.0.0.1:' . port(8090));
$t->waitforsocket('127.0.0.1:' . port(8091));

###############################################################################

local $TODO = 'not yet'
	unless http_get('/njs') =~ /^([.0-9]+)$/m && $1 ge '0.5.1';

is(stream('127.0.0.1:' . port(8081))->io('###'), '', 'preread not enough');
is(stream('127.0.0.1:' . port(8081))->io("\xAB\xCDQZ##"), "\xAB\xCDQZ##",
	'preread validated');
is(stream('127.0.0.1:' . port(8081))->io("\xAC\xCDQZ##"), '',
	'preread invalid magic');
is(stream('127.0.0.1:' . port(8081))->io("\xAB\xCDQQ##"), '',
	'preread validation failed');

TODO: {
todo_skip 'leaves coredump', 3 unless $ENV{TEST_NGINX_UNSAFE}
	or http_get('/njs') =~ /^([.0-9]+)$/m && $1 ge '0.7.7';

my $s = stream('127.0.0.1:' . port(8082));
is($s->io("\xAB\xCDQZ##", read => 1), '##', 'filter validated');
is($s->io("@@", read => 1), '@@', 'filter off');

is(stream('127.0.0.1:' . port(8082))->io("\xAB\xCDQQ##"), '',
	'filter validation failed');

}

###############################################################################

sub stream_daemon {
	my (@ports) = @_;
	my (@socks, @clients);

	for my $port (@ports) {
		my $server = IO::Socket::INET->new(
			Proto => 'tcp',
			LocalAddr => "127.0.0.1:$port",
			Listen => 5,
			Reuse => 1
		)
			or die "Can't create listening socket: $!\n";
		push @socks, $server;
	}

	my $sel = IO::Select->new(@socks);

	local $SIG{PIPE} = 'IGNORE';

	while (my @ready = $sel->can_read) {
		foreach my $fh (@ready) {
			if (grep $_ == $fh, @socks) {
				my $new = $fh->accept;
				$new->autoflush(1);
				$sel->add($new);

			} elsif (stream_handle_client($fh)
				|| $fh->sockport() == port(8090))
			{
				$sel->remove($fh);
				$fh->close;
			}
		}
	}
}

sub stream_handle_client {
	my ($client) = @_;

	log2c("(new connection $client)");

	$client->sysread(my $buffer, 65536) or return 1;

	log2i("$client $buffer");

	if ($buffer eq "__CLOSE__") {
		return 1;
	}

	log2o("$client $buffer");

	$client->syswrite($buffer);

	return 0;
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
