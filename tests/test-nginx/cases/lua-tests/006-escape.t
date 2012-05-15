# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 2 + 1);

no_long_string();

run_tests();

__DATA__

=== TEST 1: escape uri in set_by_lua
--- config
    location /escape {
        set_by_lua $res "return ngx.escape_uri('a 你')";
        echo $res;
    }
--- request
GET /escape
--- response_body
a%20%e4%bd%a0



=== TEST 2: unescape uri in set_by_lua
--- config
    location /unescape {
        set_by_lua $res "return ngx.unescape_uri('a%20%e4%bd%a0')";
        echo $res;
    }
--- request
GET /unescape
--- response_body
a 你



=== TEST 3: escape uri in content_by_lua
--- config
    location /escape {
        content_by_lua "ngx.say(ngx.escape_uri('a 你'))";
    }
--- request
GET /escape
--- response_body
a%20%e4%bd%a0



=== TEST 4: unescape uri in content_by_lua
--- config
    location /unescape {
        content_by_lua "ngx.say(ngx.unescape_uri('a%20%e4%bd%a0'))";
    }
--- request
GET /unescape
--- response_body
a 你



=== TEST 5: escape uri in set_by_lua
--- config
    location /escape {
        set_by_lua $res "return ngx.escape_uri('a+b')";
        echo $res;
    }
--- request
GET /escape
--- response_body
a%2bb



=== TEST 6: escape uri in set_by_lua
--- config
    location /escape {
        set_by_lua $res "return ngx.escape_uri('\"a/b={}:<>;&[]\\\\^')";
        echo $res;
    }
--- request
GET /escape
--- response_body
%22a%2fb%3d%7b%7d%3a%3c%3e%3b%26%5b%5d%5c%5e



=== TEST 7: escape uri in set_by_lua
--- config
    location /escape {
        echo hello;
        header_filter_by_lua '
            ngx.header.baz = ngx.escape_uri(" ")
        ';
    }
--- request
GET /escape
--- response_headers
baz: %20
--- response_body
hello

