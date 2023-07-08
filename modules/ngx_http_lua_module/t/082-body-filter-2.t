# vim:set ft= ts=4 sw=4 et fdm=marker:

our $SkipReason;

BEGIN {
    if ($ENV{TEST_NGINX_EVENT_TYPE} && $ENV{TEST_NGINX_EVENT_TYPE} ne 'poll') {
        $SkipReason = "unavailable for the event type '$ENV{TEST_NGINX_EVENT_TYPE}'";

    } else {
        $ENV{TEST_NGINX_POSTPONE_OUTPUT} = 1;
        $ENV{TEST_NGINX_EVENT_TYPE} = 'poll';
        $ENV{MOCKEAGAIN}='w'
    }
}

use Test::Nginx::Socket::Lua $SkipReason ? (skip_all => $SkipReason) : ();

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

log_level('debug');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 5);

#no_diff();
no_long_string();

run_tests();

__DATA__

=== TEST 1: check ctx->busy_bufs
--- config
    location /t {
        postpone_output 1;
        content_by_lua_block {
            for i = 1, 5 do
                ngx.say(i, ": Hello World!")
            end
        }

        body_filter_by_lua_block {
            ngx.arg[1] = ngx.arg[1]
        }
    }
--- request
GET /t
--- response_body
1: Hello World!
2: Hello World!
3: Hello World!
4: Hello World!
5: Hello World!

--- error_log
waiting body filter busy buffer to be sent
lua say response has busy bufs
--- no_error_log
[error]
