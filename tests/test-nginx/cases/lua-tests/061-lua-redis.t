# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;
$ENV{TEST_NGINX_CLIENT_PORT} ||= server_port();

#log_level "warn";
#worker_connections(1024);
#master_on();

my $pwd = `pwd`;
chomp $pwd;
$ENV{TEST_NGINX_PWD} ||= $pwd;

no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- http_config
    lua_package_path '$TEST_NGINX_PWD/t/lib/?.lua;;';
--- config
    location /test {
        content_by_lua '
            package.loaded["socket"] = ngx.socket
            local Redis = require "Redis"

            local redis = Redis.connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)

            redis:set("some_key", "hello 1234")
            local data = redis:get("some_key")
            ngx.say("some_key: ", data)
        ';
    }
--- request
    GET /test
--- response_body
some_key: hello 1234
--- no_error_log
[error]

