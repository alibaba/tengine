# vim:set ft= ts=4 sw=4 et fdm=marker:

BEGIN {
    if (!defined $ENV{LD_PRELOAD}) {
        $ENV{LD_PRELOAD} = '';
    }

    if ($ENV{LD_PRELOAD} !~ /\bmockeagain\.so\b/) {
        $ENV{LD_PRELOAD} = "mockeagain.so $ENV{LD_PRELOAD}";
    }

    if ($ENV{MOCKEAGAIN} eq 'r') {
        $ENV{MOCKEAGAIN} = 'rw';

    } else {
        $ENV{MOCKEAGAIN} = 'w';
    }

    $ENV{TEST_NGINX_EVENT_TYPE} = 'poll';
    $ENV{MOCKEAGAIN_WRITE_TIMEOUT_PATTERN} = 'hello, world';
    $ENV{TEST_NGINX_POSTPONE_OUTPUT} = 1;
}

use Test::Nginx::Socket::Lua;
use t::StapThread;

our $GCScript = $t::StapThread::GCScript;
our $StapScript = $t::StapThread::StapScript;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: pending response header data
--- config
    server_tokens off;
    postpone_output 1;
    location = /t {
        content_by_lua '
            ngx.send_headers()
            ngx.req.read_body()
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end
        ';
    }

--- raw_request eval
"GET /t HTTP/1.1\r
Host: localhost\r
Upgrade: mysocket\r
Connection: close\r
\r
"
--- stap2
F(ngx_http_header_filter) {
    println("header filter")
}
F(ngx_http_lua_req_socket) {
    println("lua req socket")
}
--- response_body
--- error_log
server: failed to get raw req socket: pending data to write



=== TEST 2: send timeout
--- config
    server_tokens off;
    postpone_output 1;
    location = /t {
        content_by_lua '
            ngx.send_headers()
            ngx.req.read_body()
            ngx.flush(true)
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end
            sock:settimeout(100)
            local ok, err = sock:send("hello, world!")
            if not ok then
                ngx.log(ngx.ERR, "server: failed to send: ", err)
            end
            ngx.exit(444)
        ';
    }

--- raw_request eval
"GET /t HTTP/1.1\r
Host: localhost\r
Upgrade: mysocket\r
Connection: close\r
\r
"
--- ignore_response
--- error_log
lua tcp socket write timed out
server: failed to send: timeout
--- no_error_log
[alert]
