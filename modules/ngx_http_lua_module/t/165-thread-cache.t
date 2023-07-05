# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 4);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: thread cache size == 1
--- http_config
    lua_thread_cache_max_entries 1;

--- config
    location /lua {
        # NOTE: the newline escape sequence must be double-escaped, as nginx config
        # parser will unescape first!
        content_by_lua '
            local ok, err = ngx.print("Hello, Lua!\\n")
            if not ok then
                ngx.log(ngx.ERR, "print failed: ", err)
            end
        ';
    }
--- request
GET /lua
--- response_body
Hello, Lua!
--- no_error_log
[error]
--- grep_error_log eval: qr/lua caching unused lua thread|lua reusing cached lua thread/
--- grep_error_log_out eval
[
    "lua caching unused lua thread\n",
    "lua reusing cached lua thread
lua caching unused lua thread
",
]



=== TEST 2: thread cache size == 0
--- http_config
    lua_thread_cache_max_entries 0;

--- config
    location /lua {
        # NOTE: the newline escape sequence must be double-escaped, as nginx config
        # parser will unescape first!
        content_by_lua '
            local ok, err = ngx.print("Hello, Lua!\\n")
            if not ok then
                ngx.log(ngx.ERR, "print failed: ", err)
            end
        ';
    }
--- request
GET /lua
--- response_body
Hello, Lua!
--- no_error_log
[error]
--- grep_error_log eval: qr/lua caching unused lua thread|lua reusing cached lua thread/
--- grep_error_log_out eval
[
    "",
    "",
]
