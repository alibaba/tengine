# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP;

plan tests => repeat_each(2) * 3 * blocks();

no_root_location();

run_tests();

__DATA__

=== TEST 1: the http_check interface, default type
--- http_config
upstream backend {
    server 127.0.0.1:1971;
    server 127.0.0.1:1972;
    server 127.0.0.1:1973;
    server 127.0.0.1:1970;
    server 127.0.0.1:1974;
    server 127.0.0.1:1975;

    check interval=3000 rise=1 fall=1 timeout=1000 type=http;
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
        proxy_pass http://backend;
    }

    location /status {
        check_status;
    }

--- request
GET /status
--- response_headers
Content-Type: text/html
--- response_body_like: ^.*Check upstream server number: 6.*$

=== TEST 2: the http_check interface, html
--- http_config
upstream backend {
    server 127.0.0.1:1971;
    server 127.0.0.1:1972;
    server 127.0.0.1:1973;
    server 127.0.0.1:1970;
    server 127.0.0.1:1974;
    server 127.0.0.1:1975;

    check interval=3000 rise=1 fall=1 timeout=1000 type=http;
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
        proxy_pass http://backend;
    }

    location /status {
        check_status html;
    }

--- request
GET /status
--- response_headers
Content-Type: text/html
--- response_body_like: ^.*Check upstream server number: 6.*$

=== TEST 3: the http_check interface, csv 
--- http_config
upstream backend {
    server 127.0.0.1:1971;
    server 127.0.0.1:1972;
    server 127.0.0.1:1973;
    server 127.0.0.1:1970;
    server 127.0.0.1:1974;
    server 127.0.0.1:1975;

    check interval=3000 rise=1 fall=1 timeout=1000 type=http;
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
        proxy_pass http://backend;
    }

    location /status {
        check_status csv;
    }

--- request
GET /status
--- response_headers
Content-Type: text/plain
--- response_body_like: ^.*$

=== TEST 4: the http_check interface, json 
--- http_config
upstream backend {
    server 127.0.0.1:1971;
    server 127.0.0.1:1972;
    server 127.0.0.1:1973;
    server 127.0.0.1:1970;
    server 127.0.0.1:1974;
    server 127.0.0.1:1975;

    check interval=3000 rise=1 fall=1 timeout=1000 type=http;
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
        proxy_pass http://backend;
    }

    location /status {
        check_status json;
    }

--- request
GET /status
--- response_headers
Content-Type: application/json
--- response_body_like: ^.*"total": 6,.*$

=== TEST 5: the http_check interface, default html, request csv
--- http_config
upstream backend {
    server 127.0.0.1:1971;
    server 127.0.0.1:1972;
    server 127.0.0.1:1973;
    server 127.0.0.1:1970;
    server 127.0.0.1:1974;
    server 127.0.0.1:1975;

    check interval=3000 rise=1 fall=1 timeout=1000 type=http;
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
        proxy_pass http://backend;
    }

    location /status {
        check_status html;
    }

--- request
GET /status?format=csv
--- response_headers
Content-Type: text/plain
--- response_body_like: ^.*$

=== TEST 6: the http_check interface, default csv, request json
--- http_config
upstream backend {
    server 127.0.0.1:1971;
    server 127.0.0.1:1972;
    server 127.0.0.1:1973;
    server 127.0.0.1:1970;
    server 127.0.0.1:1974;
    server 127.0.0.1:1975;

    check interval=3000 rise=1 fall=1 timeout=1000 type=http;
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
        proxy_pass http://backend;
    }

    location /status {
        check_status csv;
    }

--- request
GET /status?format=json
--- response_headers
Content-Type: application/json
--- response_body_like: ^.*"total": 6,.*$

=== TEST 7: the http_check interface, default json, request html 
--- http_config
upstream backend {
    server 127.0.0.1:1971;
    server 127.0.0.1:1972;
    server 127.0.0.1:1973;
    server 127.0.0.1:1970;
    server 127.0.0.1:1974;
    server 127.0.0.1:1975;

    check interval=3000 rise=1 fall=1 timeout=1000 type=http;
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
        proxy_pass http://backend;
    }

    location /status {
        check_status json;
    }

--- request
GET /status?format=html
--- response_headers
Content-Type: text/html
--- response_body_like: ^.*Check upstream server number: 6.*$

=== TEST 8: the http_check interface, default json, request htm, bad format
--- http_config
upstream backend {
    server 127.0.0.1:1971;
    server 127.0.0.1:1972;
    server 127.0.0.1:1973;
    server 127.0.0.1:1970;
    server 127.0.0.1:1974;
    server 127.0.0.1:1975;

    check interval=3000 rise=1 fall=1 timeout=1000 type=http;
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
        proxy_pass http://backend;
    }

    location /status {
        check_status json;
    }

--- request
GET /status?format=htm
--- response_headers
Content-Type: application/json
--- response_body_like: ^.*"total": 6,.*$

=== TEST 9: the http_check interface, default html, request csv and up
--- http_config
upstream backend {
    server 127.0.0.1:1971;
    server 127.0.0.1:1972;
    server 127.0.0.1:1973;
    server 127.0.0.1:1970;
    server 127.0.0.1:1974;
    server 127.0.0.1:1975;

    check interval=3000 rise=1 fall=1 timeout=1000 type=http;
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
        proxy_pass http://backend;
    }

    location /status {
        check_status html;
    }

--- request
GET /status?format=csv&status=up
--- response_headers
Content-Type: text/plain
--- response_body_like: ^[:\.,\w]+\n$

=== TEST 10: the http_check interface, default csv, request json and down
--- http_config
upstream backend {
    server 127.0.0.1:1971;
    server 127.0.0.1:1972;
    server 127.0.0.1:1973;
    server 127.0.0.1:1970;
    server 127.0.0.1:1974;
    server 127.0.0.1:1975;

    check interval=3000 rise=1 fall=1 timeout=1000 type=http;
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
        proxy_pass http://backend;
    }

    location /status {
        check_status csv;
    }

--- request
GET /status?format=json&status=down
--- response_headers
Content-Type: application/json
--- response_body_like: ^.*"total": 5,.*$

=== TEST 11: the http_check interface, default json, request html and up
--- http_config
upstream backend {
    server 127.0.0.1:1971;
    server 127.0.0.1:1972;
    server 127.0.0.1:1973;
    server 127.0.0.1:1970;
    server 127.0.0.1:1974;
    server 127.0.0.1:1975;

    check interval=3000 rise=1 fall=1 timeout=2000 type=http;
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
        proxy_pass http://backend;
    }

    location /status {
        check_status json;
    }

--- request
GET /status?format=html&status=up
--- response_headers
Content-Type: text/html
--- response_body_like: ^.*Check upstream server number: 1.*$

=== TEST 12: the http_check interface, default json, request html, bad status
--- http_config
upstream backend {
    server 127.0.0.1:1971;
    server 127.0.0.1:1972;
    server 127.0.0.1:1973;
    server 127.0.0.1:1970;
    server 127.0.0.1:1974;
    server 127.0.0.1:1975;

    check interval=3000 rise=1 fall=1 timeout=1000 type=http;
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
        proxy_pass http://backend;
    }

    location /status {
        check_status json;
    }

--- request
GET /status?format=html&status=foo
--- response_headers
Content-Type: text/html
--- response_body_like: ^.*Check upstream server number: 6.*$

=== TEST 13: the http_check interface, with check_keepalive_requests configured
--- http_config
upstream backend {
    server 127.0.0.1:1971;
    server 127.0.0.1:1972;
    server 127.0.0.1:1973;
    server 127.0.0.1:1970;
    server 127.0.0.1:1974;
    server 127.0.0.1:1975;

    check_keepalive_requests 10;
    check interval=3000 rise=1 fall=1 timeout=1000 type=http;
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
        proxy_pass http://backend;
    }

    location /status {
        check_status;
    }

--- request
GET /status
--- response_headers
Content-Type: text/html
--- response_body_like: ^.*Check upstream server number: 6.*$
