use Test::Nginx::Socket::Lua;

#master_on();
#workers(1);
#worker_connections(1014);
#log_level('warn');
#master_process_enabled(1);

repeat_each(2);

plan tests => repeat_each() * blocks() * 2;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#no_diff();
no_long_string();
#no_shuffle();

run_tests();

__DATA__

=== TEST 1: not internal request
--- config
    location /test {
        rewrite ^/test$ /lua last;
    }
    location /lua {
        content_by_lua '
            if ngx.req.is_internal() then
                ngx.say("internal")
            else
                ngx.say("not internal")
            end
        ';
    }
--- request
GET /lua
--- response_body
not internal



=== TEST 2: internal request
--- config
    location /test {
        rewrite ^/test$ /lua last;
    }
    location /lua {
        content_by_lua '
            if ngx.req.is_internal() then
                ngx.say("internal")
            else
                ngx.say("not internal")
            end
        ';
    }
--- request
GET /test
--- response_body
internal
