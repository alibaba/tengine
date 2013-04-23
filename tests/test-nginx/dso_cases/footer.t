use lib 'lib';
use Shell;
use Test::Nginx::Socket;
plan tests => blocks() * 2;
run_tests();

__DATA__

=== TEST 0:0
--- http_config
    footer "taobao\n";
--- config
    location /e {
    }
--- include_dso_modules
nginx-http-footer-filter ngx_http_footer_filter_module
--- user_files
>>> a.html
--- request
    GET /a.html
--- response_body
taobao

=== TEST 1:1
--- include_dso_modules
nginx-http-footer-filter ngx_http_footer_filter_module
--- config
    location /e {
    }
--- user_files
>>> a.html
--- request
    GET /a.html
--- response_headers_like
HTTP/1.1 200 OK

=== TEST 2:2
--- include_dso_modules
nginx-http-footer-filter ngx_http_footer_filter_module
--- config
    location /e {
    }
--- user_files
>>> a.html
--- request
    GET /a.html
--- response_body
