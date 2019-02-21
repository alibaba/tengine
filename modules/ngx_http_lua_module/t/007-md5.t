# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: set md5 hello
--- config
    location = /md5 {
        content_by_lua 'ngx.say(ngx.md5("hello"))';
    }
--- request
GET /md5
--- response_body
5d41402abc4b2a76b9719d911017c592



=== TEST 2: nil string to ngx.md5
--- config
    location = /md5 {
        content_by_lua 'ngx.say(ngx.md5(nil))';
    }
--- request
GET /md5
--- response_body
d41d8cd98f00b204e9800998ecf8427e



=== TEST 3: null string to ngx.md5
--- config
    location /md5 {
        content_by_lua 'ngx.say(ngx.md5(""))';
    }
--- request
GET /md5
--- response_body
d41d8cd98f00b204e9800998ecf8427e



=== TEST 4: use ngx.md5 in set_by_lua
--- config
    location = /md5 {
        set_by_lua $a 'return ngx.md5("hello")';
        echo $a;
    }
--- request
GET /md5
--- response_body
5d41402abc4b2a76b9719d911017c592



=== TEST 5: use ngx.md5 in set_by_lua (nil)
--- config
    location = /md5 {
        set_by_lua $a 'return ngx.md5(nil)';
        echo $a;
    }
--- request
GET /md5
--- response_body
d41d8cd98f00b204e9800998ecf8427e



=== TEST 6: use ngx.md5 in set_by_lua (null string)
--- config
    location /md5 {
        set_by_lua $a 'return ngx.md5("")';
        echo $a;
    }
--- request
GET /md5
--- response_body
d41d8cd98f00b204e9800998ecf8427e



=== TEST 7: md5(number)
--- config
    location = /md5 {
        content_by_lua 'ngx.say(ngx.md5(45))';
    }
--- request
GET /md5
--- response_body
6c8349cc7260ae62e3b1396831a8398f
