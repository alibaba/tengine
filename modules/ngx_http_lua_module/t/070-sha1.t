# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: set sha1 hello
--- config
    location = /sha1 {
        content_by_lua 'ngx.say(ngx.encode_base64(ngx.sha1_bin("hello")))';
    }
--- request
GET /sha1
--- response_body
qvTGHdzF6KLavt4PO0gs2a6pQ00=
--- no_error_log
[error]



=== TEST 2: set sha1 ""
--- config
    location = /sha1 {
        content_by_lua 'ngx.say(ngx.encode_base64(ngx.sha1_bin("")))';
    }
--- request
GET /sha1
--- response_body
2jmj7l5rSw0yVb/vlWAYkK/YBwk=
--- no_error_log
[error]



=== TEST 3: set sha1 nil
--- config
    location = /sha1 {
        content_by_lua 'ngx.say(ngx.encode_base64(ngx.sha1_bin(nil)))';
    }
--- request
GET /sha1
--- response_body
2jmj7l5rSw0yVb/vlWAYkK/YBwk=
--- no_error_log
[error]



=== TEST 4: set sha1 number
--- config
    location = /sha1 {
        content_by_lua 'ngx.say(ngx.encode_base64(ngx.sha1_bin(512)))';
    }
--- request
GET /sha1
--- response_body
zgmxJ9SPg4aKRWReJG07UvS97L4=
--- no_error_log
[error]
