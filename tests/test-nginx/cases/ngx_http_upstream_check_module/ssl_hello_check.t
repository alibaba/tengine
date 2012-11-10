# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP;

plan tests => repeat_each(2) * 2 * blocks();

no_root_location();
#no_diff;

run_tests();

__DATA__

=== TEST 1: the ssl_hello_check test
--- http_config
    upstream test{
        server www.alipay.com:443;
        server www.alipay.com:444;
        server www.alipay.com:445;

        check interval=4000 rise=1 fall=1 timeout=2000 type=ssl_hello;
    }

--- config
    location / {
        proxy_ssl_session_reuse off;
        proxy_pass https://test;
    }
   
--- request
GET /
--- response_body_like: ^<(.*)>[\r\n\s\t]*$

=== TEST 2: the ssl_hello_check test with ip_hash
--- http_config
    upstream test{
        server www.alipay.com:443;
        server www.alipay.com:444;
        server www.alipay.com:445;
        ip_hash;

        check interval=4000 rise=1 fall=1 timeout=2000 type=ssl_hello;
    }

--- config
    location / {
        proxy_ssl_session_reuse off;
        proxy_pass https://test;
    }

--- request
GET /
--- response_body_like: ^<(.*)>[\r\n\s\t]*$

=== TEST 3: the ssl_hello_check test with bad ip
--- http_config
    upstream test{
        server www.alipay.com:80;
        server www.alipay.com:443;
        server www.alipay.com:444;
        server www.alipay.com:445;

        check interval=4000 rise=1 fall=1 timeout=2000 type=ssl_hello;
    }

--- config
    location / {
        proxy_ssl_session_reuse off;
        proxy_pass https://test;
    }

--- request
GET /
--- response_body_like: ^<(.*)>[\r\n\s\t]*$

=== TEST 4: the ssl_hello_check test with least_conn
--- http_config
    upstream test{
        server www.alipay.com:443;
        server www.alipay.com:444;
        server www.alipay.com:445;
        least_conn;

        check interval=4000 rise=1 fall=1 timeout=2000 type=ssl_hello;
    }

--- config
    location / {
        proxy_ssl_session_reuse off;
        proxy_pass https://test;
    }

--- request
GET /
--- response_body_like: ^<(.*)>[\r\n\s\t]*$

=== TEST 5: the ssl_hello_check test with port 80
--- http_config
    upstream test{
        server www.alipay.com:443;

        check interval=4000 rise=1 fall=1 timeout=2000 type=http port=80;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

--- config
    location / {
        proxy_ssl_session_reuse off;
        proxy_pass https://test;
    }

--- request
GET /
--- response_body_like: ^<(.*)>[\r\n\s\t]*$

=== TEST 6: the ssl_hello_check test with port 443
--- http_config
    upstream test{
        server www.alipay.com:443;

        check interval=4000 rise=1 fall=1 timeout=2000 type=ssl_hello port=443;
    }

--- config
    location / {
        proxy_ssl_session_reuse off;
        proxy_pass https://test;
    }

--- request
GET /
--- response_body_like: ^<(.*)>[\r\n\s\t]*$

=== TEST 7: the ssl_hello_check test with port 444
--- http_config
    upstream test{
        server www.alipay.com:443;

        check interval=4000 rise=1 fall=1 timeout=2000 type=ssl_hello port=444;
    }

--- config
    location / {
        proxy_ssl_session_reuse off;
        proxy_pass https://test;
    }

--- request
GET /
--- error_code: 502
--- response_body_like: ^.*$

