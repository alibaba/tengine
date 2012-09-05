use lib 'lib';
use Test::Nginx::Socket;
plan tests => blocks() + 0;
run_tests();

__DATA__

=== TEST 1: syslog:user for access log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    access_log syslog:user;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 2: syslog:user:info for access log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    access_log syslog:user:info;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 3: syslog:user:info:127.0.0.1 for access log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    access_log syslog:user:info:127.0.0.1;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 4: syslog:user:info:127.0.0.1:514 for access log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    access_log syslog:user:info:127.0.0.1:514;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 5: syslog:user:info:127.0.0.1:514:test.taobao.com for access log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    access_log syslog:user:info:127.0.0.1:514:test.taobao.com;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 6: syslog:user::127.0.0.1:514:test.taobao.com for access log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    access_log syslog:user::127.0.0.1:514:test.taobao.com;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 7: syslog:user:info:127.0.0.1::test.taobao.com for access log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    access_log syslog:user:info:127.0.0.1::test.taobao.com;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 8: syslog:user:info:/dev/log:test.taobao.com for access log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    access_log syslog:user::/dev/log:test.taobao.com;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 9: syslog:user:info:/dev/log for access log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    access_log syslog:user::/dev/log;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 11: syslog:user for error log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    error_log syslog:user;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 12: syslog:user:info for error log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    error_log syslog:user:info;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 13: syslog:user:info:127.0.0.1 for error log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    error_log syslog:user:info:127.0.0.1;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 14: syslog:user:info:127.0.0.1:514 for error log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    error_log syslog:user:info:127.0.0.1:514;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 15: syslog:user:info:127.0.0.1:514:test.taobao.com for error log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    error_log syslog:user:info:127.0.0.1:514:test.taobao.com;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 16: syslog:user::127.0.0.1:514:test.taobao.com for error log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    error_log syslog:user::127.0.0.1:514:test.taobao.com;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 17: syslog:user:info:127.0.0.1::test.taobao.com for error log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    error_log syslog:user:info:127.0.0.1::test.taobao.com;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 18: syslog:user:info:/dev/log:test.taobao.com for error log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    error_log syslog:user::/dev/log:test.taobao.com;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 19: syslog:user:info:/dev/log for error log ===
--- include_dso_modules
ngx_http_empty_gif_module ngx_http_empty_gif_module
--- config
location /p {
    error_log syslog:user::/dev/log;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

