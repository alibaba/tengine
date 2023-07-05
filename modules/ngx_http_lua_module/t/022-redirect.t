# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 3 + 9);

#no_diff();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: default 302
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo");
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo
--- response_body_like: 302 Found
--- error_code: 302



=== TEST 2: explicit 302
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo", ngx.HTTP_MOVED_TEMPORARILY);
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo
--- response_body_like: 302 Found
--- error_code: 302



=== TEST 3: explicit 301
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo", ngx.HTTP_MOVED_PERMANENTLY);
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo
--- response_body_like: 301 Moved Permanently
--- error_code: 301



=== TEST 4: bad rc
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo", 404);
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
!Location
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
only ngx.HTTP_MOVED_TEMPORARILY, ngx.HTTP_MOVED_PERMANENTLY, ngx.HTTP_PERMANENT_REDIRECT, ngx.HTTP_SEE_OTHER, and ngx.HTTP_TEMPORARY_REDIRECT are allowed



=== TEST 5: no args
--- config
    location /read {
        content_by_lua '
            ngx.redirect()
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
!Location
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 6: relative uri
--- config
    location /echo {
        echo hello, world;
    }
    location /proxy {
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/echo;
    }
    location /read {
        content_by_lua '
            ngx.location.capture("/proxy")
            ngx.redirect("/echo")
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- raw_response_headers_like: Location: /echo\r\n
--- response_body_like: 302 Found
--- error_code: 302



=== TEST 7: default 302 (with uri args)
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo?bar=3");
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo?bar=3
--- response_body_like: 302 Found
--- error_code: 302



=== TEST 8: location.capture + ngx.redirect
--- config
    location /echo {
        echo hello, world;
    }
    location /proxy {
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/echo;
    }
    location /read {
        content_by_lua '
            ngx.location.capture("/proxy")
            ngx.location.capture("/proxy")
            ngx.redirect("/echo")
            ngx.exit(403)
        ';
    }
--- pipelined_requests eval
["GET /read/1", "GET /read/2"]
--- error_code eval
[302, 302]
--- response_body eval
[qr/302 Found/, qr/302 Found/]



=== TEST 9: explicit 307
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo", ngx.HTTP_TEMPORARY_REDIRECT);
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo
--- response_body_like: 307 Temporary Redirect
--- error_code: 307



=== TEST 10: explicit 307 with args
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo?a=b&c=d", ngx.HTTP_TEMPORARY_REDIRECT);
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo?a=b&c=d
--- response_body_like: 307 Temporary Redirect
--- error_code: 307



=== TEST 11: explicit 307
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo?a=b&c=d", 307);
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo?a=b&c=d
--- response_body_like: 307 Temporary Redirect
--- error_code: 307



=== TEST 12: explicit 303
--- config
    location /read {
        content_by_lua_block {
            ngx.redirect("http://agentzh.org/foo", ngx.HTTP_SEE_OTHER);
            ngx.say("hi")
        }
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo
--- response_body_like: 303 See Other
--- error_code: 303



=== TEST 13: explicit 303 with args
--- config
    location /read {
        content_by_lua_block {
            ngx.redirect("http://agentzh.org/foo?a=b&c=d", ngx.HTTP_SEE_OTHER);
            ngx.say("hi")
        }
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo?a=b&c=d
--- response_body_like: 303 See Other
--- error_code: 303



=== TEST 14: explicit 303
--- config
    location /read {
        content_by_lua_block {
            ngx.redirect("http://agentzh.org/foo?a=b&c=d", 303);
            ngx.say("hi")
        }
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo?a=b&c=d
--- response_body_like: 303 See Other
--- error_code: 303



=== TEST 15: explicit 308 with args
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo?a=b&c=d", ngx.HTTP_PERMANENT_REDIRECT);
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_body_like: 308 Permanent Redirect
--- response_headers
Location: http://agentzh.org/foo?a=b&c=d
--- error_code: 308



=== TEST 16: explicit 308
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo?a=b&c=d", 308);
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_body_like: 308 Permanent Redirect
--- response_headers
Location: http://agentzh.org/foo?a=b&c=d
--- error_code: 308



=== TEST 17: explicit 308 with args
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo?a=b&c=d", 308);
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_body_like: 308 Permanent Redirect
--- response_headers
Location: http://agentzh.org/foo?a=b&c=d
--- error_code: 308



=== TEST 18: unsafe uri (with '\r')
--- config
    location = /t {
        content_by_lua_block {
            ngx.redirect("http://agentzh.org/foo\rfoo:bar\nbar:foo");
            ngx.say("hi")
        }
    }
--- request
GET /t
--- error_code: 500
--- response_headers
Location:
foo:
bar:
--- error_log
unsafe byte "0x0d" in redirect uri "http://agentzh.org/foo\x0Dfoo:bar\x0Abar:foo"



=== TEST 19: unsafe uri (with '\n')
--- config
    location = /t {
        content_by_lua_block {
            ngx.redirect("http://agentzh.org/foo\nfoo:bar\rbar:foo");
            ngx.say("hi")
        }
    }
--- request
GET /t
--- error_code: 500
--- response_headers
Location:
foo:
bar:
--- error_log
unsafe byte "0x0a" in redirect uri "http://agentzh.org/foo\x0Afoo:bar\x0Dbar:foo"



=== TEST 20: unsafe uri (with prefix '\n')
--- config
    location = /t {
        content_by_lua_block {
            ngx.redirect("\nfoo:http://agentzh.org/foo");
            ngx.say("hi")
        }
    }
--- request
GET /t
--- error_code: 500
--- response_headers
Location:
foo:
--- error_log
unsafe byte "0x0a" in redirect uri "\x0Afoo:http://agentzh.org/foo"



=== TEST 21: unsafe uri (with prefix '\r')
--- config
    location = /t {
        content_by_lua_block {
            ngx.redirect("\rfoo:http://agentzh.org/foo");
            ngx.say("hi")
        }
    }
--- request
GET /t
--- error_code: 500
--- response_headers
Location:
foo:
--- error_log
unsafe byte "0x0d" in redirect uri "\x0Dfoo:http://agentzh.org/foo"



=== TEST 22: unsafe uri logging escapes '"' and '\' characters
--- config
    location = /t {
        content_by_lua_block {
            ngx.redirect("\rhttp\\://\"agentzh.org\"/foo");
            ngx.say("hi")
        }
    }
--- request
GET /t
--- error_code: 500
--- response_headers
Location:
foo:
--- error_log
unsafe byte "0x0d" in redirect uri "\x0Dhttp\x5C://\x22agentzh.org\x22/foo"
