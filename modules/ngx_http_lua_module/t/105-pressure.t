# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#log_level('debug');

repeat_each(20);

plan tests => repeat_each() * (blocks() * 3);

our $HtmlDir = html_dir;
#warn $html_dir;

our $Id;

#no_diff();
#no_long_string();

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#no_shuffle();
no_long_string();

run_tests();

__DATA__

=== TEST 1: memory issue in the "args" string option for ngx.location.capture
--- config
    location /test1 {
        content_by_lua '
            local res = ngx.location.capture("/test2/auth", {args = ngx.var.args})
            ngx.print(res.body)
        ';
    }
    location /test2 {
        content_by_lua '
            collectgarbage()
            ngx.say(ngx.var.args)
        ';
    }

--- request eval
$::Id = int rand 10000;
"GET /test1?parent=$::Id&name=2013031816214284300707&footprint=dsfasfwefklds"

--- response_body eval
"parent=$::Id&name=2013031816214284300707&footprint=dsfasfwefklds\n"

--- no_error_log
[error]
