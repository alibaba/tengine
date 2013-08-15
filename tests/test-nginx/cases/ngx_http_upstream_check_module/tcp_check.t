# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP;

plan tests => repeat_each(2) * 2 * blocks();

no_root_location();
#no_diff;

run_tests();

__DATA__

=== TEST 1: the tcp_check test
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;
        server 127.0.0.1:1972;

        check interval=3000 rise=1 fall=1 timeout=1000;
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

=== TEST 2: the tcp_check test with ip_hash
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;
        server 127.0.0.1:1972;
        ip_hash;

        check interval=3000 rise=1 fall=1 timeout=1000 type=tcp;
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

=== TEST 3: the tcp_check test which don't use the checked upstream
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;
        server 127.0.0.1:1972;

        check interval=3000 rise=1 fall=1 timeout=1000;
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

=== TEST 3: the tcp_check test with least_conn;
--- http_config
    upstream test{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;
        server 127.0.0.1:1972;
        least_conn;

        check interval=3000 rise=1 fall=5 timeout=1000 type=tcp;
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

=== TEST 4: the tcp_check test with port
--- http_config
    upstream test{
        server 127.0.0.1:1971;

        check interval=3000 rise=1 fall=1 timeout=1000 type=tcp port=1970;
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

=== TEST 5: the tcp_check test with port
--- http_config
    upstream test{
        server 127.0.0.1:1970;

        check interval=2000 rise=1 fall=1 timeout=1000 type=tcp port=1971;
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

=== TEST 5: the tcp_check test with check_keepalive_requests configured
--- http_config
    upstream test{
        server 127.0.0.1:1970;

        check_keepalive_requests 10;
        check interval=2000 rise=1 fall=1 timeout=1000 type=tcp;
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
