# vi:filetype=perl

# Blocks whose expectation depends on a peer being up wait in "--- init" first:
# peers start out down (default_down defaults to true) and the first check only
# fires after a random delay of up to max(interval, 1s), while the framework
# sends its request roughly 100ms after the server starts. Those blocks also use
# a shorter check interval so the wait can stay short. Blocks that expect 502,
# that bypass the checked upstream, or that have no check directive are left
# untouched.
#
# The two www.taobao.com servers of the multi_server block were replaced with
# 127.0.0.1 so the case no longer needs third-party network reachability.

use lib 'lib';
use Test::Nginx::LWP;
use Test::Nginx::Socket;

plan tests => repeat_each(2) * 2 * blocks();

no_root_location();

run_tests();

__DATA__

=== TEST 1: the http_check test-single server
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        check interval=500 rise=1 fall=1 timeout=1000 type=http;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- init: sleep 2;
--- request
GET /
--- response_body_like: ^<(.*)>$

=== TEST 2: the http_check test-multi_server
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;

        check interval=500 rise=1 fall=1 timeout=1000 type=http;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    upstream foo{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;

        check interval=500 rise=1 fall=5 timeout=2000 type=http;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- init: sleep 2;
--- request
GET /
--- response_body_like: ^<(.*)>$

=== TEST 3: the http_check test
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;

        check interval=3000 rise=1 fall=1 timeout=1000 type=http;
        check_http_send "GET /foo HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- request
GET /
--- error_code: 502
--- response_body_like: ^.*$

=== TEST 4: the http_check without check directive
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- request
GET /
--- response_body_like: ^<(.*)>$

=== TEST 5: the http_check which does not use the upstream
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;

        check interval=3000 rise=1 fall=1 timeout=1000 type=http;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://127.0.0.1:1970;
    }

--- request
GET /
--- response_body_like: ^<(.*)>$

=== TEST 6: the http_check test-single server
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        ip_hash;

        check interval=500 rise=1 fall=1 timeout=1000 type=http;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- init: sleep 2;
--- request
GET /
--- response_body_like: ^<(.*)>$

=== TEST 7: the http_check test-multi_server
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;
        ip_hash;

        check interval=500 rise=1 fall=1 timeout=1000 type=http;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- init: sleep 2;
--- request
GET /
--- response_body_like: ^<(.*)>$

=== TEST 8: the http_check test
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;
        ip_hash;

        check interval=3000 rise=1 fall=1 timeout=1000 type=http;
        check_http_send "GET /foo HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- request
GET /
--- error_code: 502
--- response_body_like: ^.*$

=== TEST 9: the http_check without check directive
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;
        ip_hash;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- request
GET /
--- response_body_like: ^<(.*)>$

=== TEST 10: the http_check which does not use the upstream
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;
        ip_hash;

        check interval=3000 rise=1 fall=1 timeout=1000 type=http;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://127.0.0.1:1970;
    }

--- request
GET /
--- response_body_like: ^<(.*)>$

=== TEST 11: the http_check which does not use the upstream, with variable
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;
        ip_hash;

        check interval=3000 rise=1 fall=1 timeout=1000 type=http;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    resolver 8.8.8.8;

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        set $test "/";
        proxy_pass http://127.0.0.1:1970$test;
    }

--- request
GET /
--- response_body_like: ^<(.*)>$

=== TEST 12: the http_check test-single server, least conn
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        least_conn;

        check interval=500 rise=1 fall=1 timeout=1000 type=http;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- init: sleep 2;
--- request
GET /
--- response_body_like: ^<(.*)>$

=== TEST 13: the http_check test-multi_server, least conn
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;
        least_conn;

        check interval=500 rise=1 fall=1 timeout=1000 type=http;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- init: sleep 2;
--- request
GET /
--- response_body_like: ^<(.*)>$

=== TEST 14: the http_check test, least conn
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;
        least_conn;

        check interval=3000 rise=1 fall=1 timeout=1000 type=http;
        check_http_send "GET /foo HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- request
GET /
--- error_code: 502
--- response_body_like: ^.*$

=== TEST 15: the http_check without check directive, least conn
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;
        least_conn;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- request
GET /
--- response_body_like: ^<(.*)>$

=== TEST 16: the http_check with port
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        check interval=2000 rise=1 fall=1 timeout=1000 type=http port=1971;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- request
GET /
--- error_code: 502
--- response_body_like: ^.*$

=== TEST 17: the http_check with port
--- http_config
    upstream test{
        server 127.0.0.1:1971;
        check interval=3000 rise=1 fall=1 timeout=1000 type=http port=1970;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- request
GET /
--- error_code: 502
--- response_body_like: ^.*$

=== TEST 18: the http_check with check_keepalive_requests configured
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        check_keepalive_requests 10;
        check interval=500 rise=1 fall=1 timeout=1000 type=http;
        check_http_send "GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }

--- init: sleep 2;
--- request
GET /
--- response_body_like: ^<(.*)>$


=== TEST 19: the http_check with type!=http and check_http_send configured
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        check_keepalive_requests 10;
        check interval=3000 rise=1 fall=1 timeout=1000 type=tcp;
        check_http_send "GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }
--- request
GET /
--- must_die
--- error_log: invalid check_http_send for type


=== TEST 20: the http_check with check_http_send configured before check
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        check_keepalive_requests 10;
        check_http_send "GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n";
        check interval=3000 rise=1 fall=1 timeout=1000 type=http;
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://test;
    }
--- request
GET /
--- must_die
--- error_log: invalid check_http_send should set
