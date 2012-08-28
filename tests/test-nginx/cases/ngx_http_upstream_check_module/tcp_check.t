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
        server blog.163.com:80;
        server blog.163.com:81;
        server blog.163.com:82;

        check interval=3000 rise=1 fall=5 timeout=1000;
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
        server blog.163.com:80;
        server blog.163.com:81;
        server blog.163.com:82;
        ip_hash;

        check interval=3000 rise=1 fall=5 timeout=1000 type=tcp;
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
        server blog.163.com:80;
        server blog.163.com:81;
        server blog.163.com:82;

        check interval=3000 rise=1 fall=5 timeout=1000;
    }

--- config
    location / {
        proxy_pass http://blog.163.com;
    }

--- request
GET /
--- response_body_like: ^<(.*)>$

=== TEST 3: the tcp_check test with least_conn;
--- http_config
    upstream test{
        server blog.163.com:80;
        server blog.163.com:81;
        server blog.163.com:82;
        least_conn;

        check interval=3000 rise=1 fall=5 timeout=1000 type=tcp;
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
        server blog.163.com:81;

        check interval=3000 rise=1 fall=1 timeout=1000 type=tcp port=80;
    }

--- config
    location / { 
        proxy_pass http://test;
    }

--- request
GET /
--- error_code: 504
--- response_body_like: ^.*$

=== TEST 5: the tcp_check test with port
--- http_config
    upstream test{
        server blog.163.com:80;

        check interval=2000 rise=1 fall=1 timeout=1000 type=tcp port=81;
    }

--- config
    location / { 
        proxy_pass http://test;
    }

--- request
GET /
--- error_code: 502
--- response_body_like: ^.*$

