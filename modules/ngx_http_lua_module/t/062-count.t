# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(4);
#log_level('warn');
no_root_location();

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

our $HtmlDir = html_dir;

#$ENV{LUA_CPATH} = "/usr/local/openresty/lualib/?.so;" . $ENV{LUA_CPATH};

no_long_string();
run_tests();

__DATA__

=== TEST 1: entries under ngx. (content by lua)
--- config
        location = /test {
            content_by_lua '
                local n = 0
                for k, v in pairs(ngx) do
                    n = n + 1
                end
                ngx.say("ngx: ", n)
            ';
        }
--- request
GET /test
--- response_body
ngx: 99
--- no_error_log
[error]



=== TEST 2: entries under ngx. (set by lua)
--- config
        location = /test {
            set_by_lua $n '
                local n = 0
                for k, v in pairs(ngx) do
                    n = n + 1
                end
                return n;
            ';
            echo $n;
        }
--- request
GET /test
--- response_body
99
--- no_error_log
[error]



=== TEST 3: entries under ngx. (header filter by lua)
--- config
        location = /test {
            set $n '';

            content_by_lua '
                ngx.send_headers()
                ngx.say("n = ", ngx.var.n)
            ';

            header_filter_by_lua '
                local n = 0
                for k, v in pairs(ngx) do
                    n = n + 1
                end

                ngx.var.n = n
            ';
        }
--- request
GET /test
--- response_body
n = 99
--- no_error_log
[error]



=== TEST 4: entries under ndk. (content by lua)
--- config
        location = /test {
            content_by_lua '
                local n = 0
                for k, v in pairs(ndk) do
                    n = n + 1
                end
                ngx.say("n = ", n)
            ';
        }
--- request
GET /test
--- response_body
n = 1
--- no_error_log
[error]



=== TEST 5: entries under ngx.req (content by lua)
--- config
        location = /test {
            content_by_lua '
                local n = 0
                for k, v in pairs(ngx.req) do
                    n = n + 1
                end
                ngx.say("n = ", n)
            ';
        }
--- request
GET /test
--- response_body
n = 23
--- no_error_log
[error]



=== TEST 6: entries under ngx.req (set by lua)
--- config
        location = /test {
            set_by_lua $n '
                local n = 0
                for k, v in pairs(ngx.req) do
                    n = n + 1
                end
                return n
            ';

            echo "n = $n";
        }
--- request
GET /test
--- response_body
n = 23
--- no_error_log
[error]



=== TEST 7: entries under ngx.req (header filter by lua)
--- config
        location = /test {
            set $n '';

            header_filter_by_lua '
                local n = 0
                for k, v in pairs(ngx.req) do
                    n = n + 1
                end
                ngx.var.n = n
            ';

            content_by_lua '
                ngx.send_headers()
                ngx.say("n = ", ngx.var.n)
            ';
        }
--- request
GET /test
--- response_body
n = 23
--- no_error_log
[error]



=== TEST 8: entries under ngx.location
--- config
        location = /test {
            content_by_lua '
                local n = 0
                for k, v in pairs(ngx.location) do
                    n = n + 1
                end
                ngx.say("n = ", n)
            ';
        }
--- request
GET /test
--- response_body
n = 2
--- no_error_log
[error]



=== TEST 9: entries under ngx.socket
--- config
        location = /test {
            content_by_lua '
                local n = 0
                for k, v in pairs(ngx.socket) do
                    n = n + 1
                end
                ngx.say("n = ", n)
            ';
        }
--- request
GET /test
--- response_body
n = 3
--- no_error_log
[error]



=== TEST 10: entries under ngx._tcp_meta
--- SKIP
--- config
        location = /test {
            content_by_lua '
                local n = 0
                for k, v in pairs(ngx._tcp_meta) do
                    n = n + 1
                end
                ngx.say("n = ", n)
            ';
        }
--- request
GET /test
--- response_body
n = 10
--- no_error_log
[error]



=== TEST 11: entries under ngx._reqsock_meta
--- SKIP
--- config
        location = /test {
            content_by_lua '
                local n = 0
                for k, v in pairs(ngx._reqsock_meta) do
                    n = n + 1
                end
                ngx.say("n = ", n)
            ';
        }
--- request
GET /test
--- response_body
n = 4
--- no_error_log
[error]



=== TEST 12: shdict metatable
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local mt = dogs.__index
            local n = 0
            for k, v in pairs(mt) do
                n = n + 1
            end
            ngx.say("n = ", n)
        ';
    }
--- request
GET /test
--- response_body
n = 13
--- no_error_log
[error]



=== TEST 13: entries under ngx. (log by lua)
--- config
    location = /t {
        log_by_lua '
            local n = 0
            for k, v in pairs(ngx) do
                n = n + 1
            end
            ngx.log(ngx.ERR, "ngx. entry count: ", n)
        ';
    }
--- request
GET /t
--- response_body_like: 404 Not Found
--- error_code: 404
--- error_log
ngx. entry count: 99



=== TEST 14: entries under ngx.timer
--- config
        location = /test {
            content_by_lua '
                local n = 0
                for k, v in pairs(ngx.timer) do
                    n = n + 1
                end
                ngx.say("n = ", n)
            ';
        }
--- request
GET /test
--- response_body
n = 1
--- no_error_log
[error]



=== TEST 15: entries under ngx.config
--- config
        location = /test {
            content_by_lua '
                local n = 0
                for k, v in pairs(ngx.config) do
                    n = n + 1
                end
                ngx.say("n = ", n)
            ';
        }
--- request
GET /test
--- response_body
n = 5
--- no_error_log
[error]



=== TEST 16: entries under ngx.re
--- config
        location = /test {
            content_by_lua '
                local n = 0
                for k, v in pairs(ngx.re) do
                    n = n + 1
                end
                ngx.say("n = ", n)
            ';
        }
--- request
GET /test
--- response_body
n = 5
--- no_error_log
[error]



=== TEST 17: entries under coroutine. (content by lua)
--- config
        location = /test {
            content_by_lua '
                local n = 0
                for k, v in pairs(coroutine) do
                    n = n + 1
                end
                ngx.say("coroutine: ", n)
            ';
        }
--- request
GET /test
--- stap2
global c
probe process("$LIBLUA_PATH").function("rehashtab") {
    c++
    printf("rehash: %d\n", c)
}
--- stap_out2
3
--- response_body
coroutine: 14
--- no_error_log
[error]



=== TEST 18: entries under ngx.thread. (content by lua)
--- config
        location = /test {
            content_by_lua '
                local n = 0
                for k, v in pairs(ngx.thread) do
                    n = n + 1
                end
                ngx.say("thread: ", n)
            ';
        }
--- request
GET /test
--- stap2
global c
probe process("$LIBLUA_PATH").function("rehashtab") {
    c++
    printf("rehash: %d\n", c)
}
--- stap_out2
--- response_body
thread: 3
--- no_error_log
[error]



=== TEST 19: entries under ngx.worker
--- config
        location = /test {
            content_by_lua '
                local n = 0
                for k, v in pairs(ngx.worker) do
                    n = n + 1
                end
                ngx.say("worker: ", n)
            ';
        }
--- request
GET /test
--- response_body
worker: 2
--- no_error_log
[error]

