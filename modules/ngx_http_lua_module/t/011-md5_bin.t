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


#md5_bin_bin is hard to test, so convert it to hex mode

__DATA__

=== TEST 1: set md5_bin hello ????xxoo
--- config
    location = /md5_bin {
        content_by_lua 'local a = string.gsub(ngx.md5_bin("hello"), ".", function (c)
                    return string.format("%02x", string.byte(c))
                end); ngx.say(a)';
    }
--- request
GET /md5_bin
--- response_body
5d41402abc4b2a76b9719d911017c592



=== TEST 2: set md5_bin hello ????xxoo
--- config
    location = /md5_bin {
        content_by_lua 'ngx.say(string.len(ngx.md5_bin("hello")))';
    }
--- request
GET /md5_bin
--- response_body
16



=== TEST 3: set md5_bin hello
--- config
    location = /md5_bin {
        content_by_lua '
            local s = ngx.md5_bin("hello")
            s = string.gsub(s, ".", function (c)
                    return string.format("%02x", string.byte(c))
                end)
            ngx.say(s)
        ';
    }
--- request
GET /md5_bin
--- response_body
5d41402abc4b2a76b9719d911017c592



=== TEST 4: nil string to ngx.md5_bin
--- config
    location = /md5_bin {
        content_by_lua '
            local s = ngx.md5_bin(nil)
            s = string.gsub(s, ".", function (c)
                    return string.format("%02x", string.byte(c))
                end)
            ngx.say(s)
        ';
    }
--- request
GET /md5_bin
--- response_body
d41d8cd98f00b204e9800998ecf8427e



=== TEST 5: null string to ngx.md5_bin
--- config
    location /md5_bin {
        content_by_lua '
            local s = ngx.md5_bin("")
            s = string.gsub(s, ".", function (c)
                    return string.format("%02x", string.byte(c))
                end)
            ngx.say(s)
        ';
    }
--- request
GET /md5_bin
--- response_body
d41d8cd98f00b204e9800998ecf8427e



=== TEST 6: use ngx.md5_bin in set_by_lua
--- config
    location = /md5_bin {
        set_by_lua $a 'return string.gsub(ngx.md5_bin("hello"), ".", function (c)
                    return string.format("%02x", string.byte(c))
                end)';
        echo $a;
    }
--- request
GET /md5_bin
--- response_body
5d41402abc4b2a76b9719d911017c592



=== TEST 7: use ngx.md5_bin in set_by_lua (nil)
--- config
    location = /md5_bin {
        set_by_lua $a '
            local s = ngx.md5_bin(nil)
            s = string.gsub(s, ".", function (c)
                    return string.format("%02x", string.byte(c))
                end)
            return s
        ';
        echo $a;
    }
--- request
GET /md5_bin
--- response_body
d41d8cd98f00b204e9800998ecf8427e



=== TEST 8: use ngx.md5_bin in set_by_lua (null string)
--- config
    location /md5_bin {
        set_by_lua $a '
            local s = ngx.md5_bin("")
            s = string.gsub(s, ".", function (c)
                    return string.format("%02x", string.byte(c))
                end)
            return s
        ';
        echo $a;
    }
--- request
GET /md5_bin
--- response_body
d41d8cd98f00b204e9800998ecf8427e



=== TEST 9: md5_bin(number)
--- config
    location = /t {
        content_by_lua '
            local s = ngx.md5_bin(45)
            s = string.gsub(s, ".", function (c)
                    return string.format("%02x", string.byte(c))
                end)
            ngx.say(s)

        ';
    }
--- request
GET /t
--- response_body
6c8349cc7260ae62e3b1396831a8398f
