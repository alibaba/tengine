use lib 'lib';
use Test::Nginx::Socket;

log_level('debug');
plan tests => 2 * blocks();

run_tests();

__DATA__

=== TEST 1: proxy
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;

        next_upstream_tries 2;
    }
    error_page 502 = @error;
--- config
    location /proxy { proxy_pass http://server;}
    location @error { echo "$upstream_addr";}
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 2: fastcgi
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;

        next_upstream_tries 2;
    }
    error_page 502 = @error;
--- config
    location /fastcgi { fastcgi_pass server;}
    location @error { echo "$upstream_addr";}
--- request
    GET /fastcgi
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 3: uwsgi
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;

        next_upstream_tries 2;
    }
    error_page 502 = @error;
--- config
    location /uwsgi { uwsgi_pass server;}
    location @error { echo "$upstream_addr";}
--- request
    GET /uwsgi
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 4: memcached
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;

        next_upstream_tries 2;
    }
    error_page 502 = @error;
--- config
    location /memcached { set $memcached_key "$uri?$args"; memcached_pass server;}
    location @error { echo "$upstream_addr";}
--- request
    GET /memcached
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 5: default
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;
    }
    error_page 502 = @error;
--- config
    location /proxy { proxy_pass http://server;}
    location @error { echo "$upstream_addr";}
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 6: next_upstream_tries = 0 ( default )
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;

        next_upstream_tries 0;
    }
    error_page 502 = @error;
--- config
    location /uwsgi { uwsgi_pass server;}
    location @error { echo "$upstream_addr";}
--- request
    GET /uwsgi
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 7: next_upstream_treis > server number.
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;

        next_upstream_tries 4;
    }
    error_page 502 = @error;
--- config
    location /proxy { proxy_pass http://server;}
    location @error { echo "$upstream_addr";}
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 8: next_upstream_treis = server number.
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;

        next_upstream_tries 3;
    }
    error_page 502 = @error;
--- config
    location /proxy { proxy_pass http://server;}
    location @error { echo "$upstream_addr";}
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 9: next_upstream_treis = 1
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;

        next_upstream_tries 1;
    }
    error_page 502 = @error;
--- config
    location /proxy { proxy_pass http://server;}
    location @error { echo "$upstream_addr";}
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d$

=== TEST 10: fastcgi_next_upstream off
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;

        next_upstream_tries 2;
    }
    error_page 502 = @error;
--- config
    location /fastcgi { fastcgi_next_upstream off;fastcgi_pass server;}
    location @error { echo "$upstream_addr";}
--- request
    GET /fastcgi
--- response_body_like
^127.0.0.1:700\d$

=== TEST 11: proxy_next_upstream http_404
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;

        next_upstream_tries 2;
    }
    error_page 502 = @error;
--- config
    location /proxy { proxy_next_upstream http_404;proxy_pass http://server;}
    location @error { echo "$upstream_addr";}
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d$


=== TEST 12: success connect
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:1984;  # the server is live.
        server 127.0.0.1:7002;

        next_upstream_tries 2;
    }
    error_page 502 = @error;
--- config
    location /proxy/    { proxy_pass http://server/;}
    location /t        { echo "success";}
    location @error    { echo "$upstream_addr";}
--- request
    GET /proxy/t
--- response_body_like
^success|127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 13: ip_hash
--- http_config
    upstream server {
        ip_hash;

        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;

        next_upstream_tries 2;
    }
    error_page 502 = @error;
--- config
    location /proxy    { proxy_pass http://server;}
    location @error    { echo "$upstream_addr";}
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$

=== TEST 14: keepalive
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;

        keepalive 10;
        next_upstream_tries 2;
    }
    error_page 502 = @error;
--- config
    location /proxy    { proxy_pass http://server;}
    location @error    { echo "$upstream_addr";}
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$


=== TEST 15: session_sticky
--- http_config
    upstream server {
        server 127.0.0.1:7001;
        server 127.0.0.1:7002;
        server 127.0.0.1:7003;

        session_sticky;
        next_upstream_tries 2;
    }
    error_page 502 = @error;
--- config
    location /proxy    { proxy_pass http://server;}
    location @error    { echo "$upstream_addr";}
--- request
    GET /proxy
--- response_body_like
^127.0.0.1:700\d, 127.0.0.1:700\d$
