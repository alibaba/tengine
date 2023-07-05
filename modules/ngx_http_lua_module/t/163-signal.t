# vi:ft=

our $SkipReason;

BEGIN {
    if ($ENV{TEST_NGINX_USE_HUP}) {
        $SkipReason = "unavailable under hup test mode";
    }
}

use Test::Nginx::Socket::Lua $SkipReason ? (skip_all => $SkipReason) : ();

plan tests => 2 * blocks();

no_long_string();


run_tests();

__DATA__

=== TEST 1: SIGHUP followed by SIGQUIT
--- config
    location = /t {
        content_by_lua_block {
            local pid = ngx.worker.pid()
            os.execute("kill -HUP " .. pid)
            ngx.sleep(0.01)

            os.execute("kill -QUIT " .. pid)
        }
    }
--- request
GET /t
--- ignore_response
--- wait: 0.1
--- error_log eval
qr/\[notice\] \d+#\d+: exit$/
--- no_error_log eval
qr/\[notice\] \d+#\d+: reconfiguring/



=== TEST 2: exit after receiving SIGHUP in single process mode
--- config
    location = /t {
        content_by_lua_block {
            local pid = ngx.worker.pid()
            os.execute("kill -HUP " .. pid)
        }
    }
--- request
GET /t
--- ignore_response
--- wait: 0.1
--- error_log eval
qr/\[notice\] \d+#\d+: exit$/
--- no_error_log eval
qr/\[notice\] \d+#\d+: reconfiguring/
