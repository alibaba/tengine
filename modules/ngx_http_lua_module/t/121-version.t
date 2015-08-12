# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: nginx version
--- config
    location /lua {
        content_by_lua '
            ngx.say("version: ", ngx.config.nginx_version)
        ';
    }
--- request
GET /lua
--- response_body_like chop
^version: \d+$
--- no_error_log
[error]



=== TEST 2: ngx_lua_version
--- config
    location /lua {
        content_by_lua '
            ngx.say("version: ", ngx.config.ngx_lua_version)
        ';
    }
--- request
GET /lua
--- response_body_like chop
^version: \d+$
--- no_error_log
[error]

