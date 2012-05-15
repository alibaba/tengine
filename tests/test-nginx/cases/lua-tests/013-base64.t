# vim:set ft=perl ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
#no_long_string();
run_tests();


__DATA__

=== TEST 1: base64 encode hello
--- config
    location = /encode_base64 {
        content_by_lua 'ngx.say(ngx.encode_base64("hello"))';
    }
--- request
GET /encode_base64
--- response_body
aGVsbG8=



=== TEST 2: nil string to ngx.encode_base64
--- config
    location = /encode_base64 {
        content_by_lua 'ngx.say("left" .. ngx.encode_base64(nil) .. "right")';
    }
--- request
GET /encode_base64
--- response_body
leftright



=== TEST 3: null string to ngx.encode_base64
--- config
    location = /encode_base64 {
        content_by_lua 'ngx.say("left" .. ngx.encode_base64("") .. "right")';
    }
--- request
GET /encode_base64
--- response_body
leftright



=== TEST 4: use ngx.encode_base64 in set_by_lua
--- config
    location = /encode_base64 {
        set_by_lua $a 'return ngx.encode_base64("hello")';
        echo $a;
    }
--- request
GET /encode_base64
--- response_body
aGVsbG8=



=== TEST 5: use ngx.encode_base64 in set_by_lua (nil)
--- config
    location = /encode_base64 {
        set_by_lua $a 'return "left" .. ngx.encode_base64(nil) .. "right"';
        echo $a;
    }
--- request
GET /encode_base64
--- response_body
leftright



=== TEST 6: use ngx.encode_base64 in set_by_lua (null string)
--- config
    location /encode_base64 {
        set_by_lua $a 'return "left" .. ngx.encode_base64("") .. "right"';
        echo $a;
    }
--- request
GET /encode_base64
--- response_body
leftright



=== TEST 7: base64 encode hello
--- config
    location = /decode_base64 {
        content_by_lua 'ngx.say(ngx.decode_base64("aGVsbG8="))';
    }
--- request
GET /decode_base64
--- response_body
hello



=== TEST 8: nil string to ngx.decode_base64
--- config
    location = /decode_base64 {
        content_by_lua 'ngx.say("left" .. ngx.decode_base64(nil) .. "right")';
    }
--- request
GET /decode_base64
--- response_body
leftright



=== TEST 9: null string to ngx.decode_base64
--- config
    location = /decode_base64 {
        content_by_lua 'ngx.say("left" .. ngx.decode_base64("") .. "right")';
    }
--- request
GET /decode_base64
--- response_body
leftright



=== TEST 10: use ngx.decode_base64 in set_by_lua
--- config
    location = /decode_base64 {
        set_by_lua $a 'return ngx.decode_base64("aGVsbG8=")';
        echo $a;
    }
--- request
GET /decode_base64
--- response_body
hello



=== TEST 11: use ngx.decode_base64 in set_by_lua (nil)
--- config
    location = /decode_base64 {
        set_by_lua $a 'return "left" .. ngx.decode_base64(nil) .. "right"';
        echo $a;
    }
--- request
GET /decode_base64
--- response_body
leftright



=== TEST 12: use ngx.decode_base64 in set_by_lua (null string)
--- config
    location /decode_base64 {
        set_by_lua $a 'return "left" .. ngx.decode_base64("") .. "right"';
        echo $a;
    }
--- request
GET /decode_base64
--- response_body
leftright

