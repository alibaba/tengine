# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: ngx.config.debug
--- config
    location /t {
        content_by_lua '
            ngx.say("debug: ", ngx.config.debug)
        ';
    }
--- request
GET /t
--- response_body_like chop
^debug: (?:true|false)$
--- no_error_log
[error]



=== TEST 2: ngx.config.subsystem
--- config
    location /t {
        content_by_lua '
            ngx.say("subsystem: ", ngx.config.subsystem)
        ';
    }
--- request
GET /t
--- response_body
subsystem: http
--- no_error_log
[error]
