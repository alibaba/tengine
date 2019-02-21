# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#log_level("warn");
no_long_string();

run_tests();

__DATA__

=== TEST 1: \0
--- config
    location = /set {
        content_by_lua '
            ngx.say(ngx.quote_sql_str("a\\0b\\0"))
        ';
    }
--- request
GET /set
--- response_body
'a\0b\0'
--- no_error_log
[error]



=== TEST 2: \t
--- config
    location = /set {
        content_by_lua '
            ngx.say(ngx.quote_sql_str("a\\tb\\t"))
        ';
    }
--- request
GET /set
--- response_body
'a\tb\t'
--- no_error_log
[error]



=== TEST 3: \b
--- config
    location = /set {
        content_by_lua '
            ngx.say(ngx.quote_sql_str("a\\bb\\b"))
        ';
    }
--- request
GET /set
--- response_body
'a\bb\b'
--- no_error_log
[error]



=== TEST 4: \Z
--- config
    location = /set {
        content_by_lua '
            ngx.say(ngx.quote_sql_str("a\\026b\\026"))
        ';
    }
--- request
GET /set
--- response_body
'a\Zb\Z'
--- no_error_log
[error]
