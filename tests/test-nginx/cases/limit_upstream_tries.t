use lib 'lib';
use Test::Nginx::Socket;

log_level('debug');
plan tests => 2 * blocks();

run_tests();

__DATA__

=== TEST 1: proxy_pass
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /proxy { proxy_upstream_tries 2; proxy_pass http://server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 2: fastcgi_pass
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /fastcgi { fastcgi_upstream_tries 2; fastcgi_pass server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /fastcgi
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 3: uwsgi_pass
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /uwsgi { uwsgi_upstream_tries 2; uwsgi_pass server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /uwsgi
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 4: memcached_pass
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /memcached { memcached_upstream_tries 2; set $memcached_key "$uri?$args"; memcached_pass server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /memcached
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 5: scgi_pass
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /scgi { scgi_upstream_tries 2; scgi_pass server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /scgi
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 6: server config
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    proxy_upstream_tries 2;
    location /proxy { proxy_pass http://server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 7: server and location config
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    proxy_upstream_tries 1;
    location /proxy { proxy_upstream_tries 2; proxy_pass http://server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 8: proxy_upstream_tries not set
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /proxy { proxy_pass http://server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 9: proxy_upstream_tries not set, with other config
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /proxy { fastcgi_upstream_tries 2; proxy_pass http://server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 10: proxy_upstream_tries = 0
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /proxy { proxy_upstream_tries 0; proxy_pass http://server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 11: proxy_upstream_treis = server number.
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /proxy { proxy_upstream_tries 3; proxy_pass http://server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 12: proxy_upstream_treis > server number.
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /proxy { proxy_upstream_tries 4; proxy_pass http://server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 13: proxy_upstream_treis = 1
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /proxy { proxy_upstream_tries 1; proxy_pass http://server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d$

=== TEST 14: proxy_next_upstream off
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /proxy { proxy_upstream_tries 2; proxy_next_upstream off; proxy_pass http://server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d$

=== TEST 15: proxy_next_upstream http_404
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /proxy { proxy_upstream_tries 2; proxy_next_upstream http_404; proxy_pass http://server; }
    location @error { echo "$upstream_addr"; }
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d$

=== TEST 16: success connect
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:1984;  # this server is alive.
        server 127.0.0.1:7002;
    }
    error_page 502 = @error;
--- config
    location /proxy/    { proxy_upstream_tries 2; proxy_pass http://server/; }
    location /t        { echo "success";}
    location @error    { echo "$upstream_addr"; }
--- request
    GET /proxy/t
--- response_body_like
^success|127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 17: ip_hash
--- http_config
    upstream server {
        ip_hash;
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /proxy    { proxy_upstream_tries 2; proxy_pass http://server; }
    location @error    { echo "$upstream_addr"; }
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 18: keepalive
--- http_config
    upstream server {
        keepalive 10;
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /proxy    { proxy_upstream_tries 2; proxy_pass http://server; }
    location @error    { echo "$upstream_addr"; }
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 19: session_sticky
--- http_config
    upstream server {
        session_sticky;
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /proxy    { proxy_upstream_tries 2; proxy_pass http://server; }
    location @error    { echo "$upstream_addr"; }
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$
