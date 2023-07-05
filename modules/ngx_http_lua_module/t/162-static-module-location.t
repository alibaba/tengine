use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

our $HtmlDir = html_dir;

no_long_string();
run_tests();

__DATA__

=== TEST 1: decoded url contains '\0' and '\r\n'
--- config
    server_tokens off;
    location = /t {
        rewrite_by_lua_block {
            ngx.req.read_body();
            local args, _ = ngx.req.get_post_args();
            ngx.req.set_uri(args["url"], true, true);
        }
    }
--- request
POST /t
url=%00%0a%0dset-cookie:1234567
--- error_code: 301
--- response_headers
Location: %00%0A%0Dset-cookie:1234567/
--- response_body_like
.*301 Moved Permanently.*



=== TEST 2: uri contain chinese characters
--- config
    server_tokens off;
--- user_files
>>> t/中文/foo.txt
Hello, world
--- request
GET /t/中文
--- error_code: 301
--- response_headers_like
Location: http:\/\/localhost:\d+\/t\/%E4%B8%AD%E6%96%87\/
--- response_body_like
.*301 Moved Permanently.*



=== TEST 3: uri contain chinese characters with args
--- config
    server_tokens off;
--- user_files
>>> t/中文/foo.txt
Hello, world
--- request
GET /t/中文?q=name
--- error_code: 301
--- response_headers_like
Location: http:\/\/localhost:\d+\/t\/%E4%B8%AD%E6%96%87\/\?q=name
--- response_body_like
.*301 Moved Permanently.*



=== TEST 4: uri already encoded
--- config
    server_tokens off;
--- user_files
>>> t/中文/foo.txt
Hello, world
--- request
GET /t/%E4%B8%AD%E6%96%87
--- error_code: 301
--- response_headers_like
Location: http:\/\/localhost:\d+\/t\/%E4%B8%AD%E6%96%87\/
--- response_body_like
.*301 Moved Permanently.*



=== TEST 5: uri already encoded with args
--- config
    server_tokens off;
--- user_files
>>> t/中文/foo.txt
Hello, world
--- request
GET /t/%E4%B8%AD%E6%96%87?q=name
--- error_code: 301
--- response_headers_like
Location: http://localhost:\d+\/t\/%E4%B8%AD%E6%96%87\/\?q=name
--- response_body_like
.*301 Moved Permanently.*
