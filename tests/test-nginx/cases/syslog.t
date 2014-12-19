use lib 'lib';
use Test::Nginx::Socket;
plan tests => blocks() + 0;
run_tests();

__DATA__

=== TEST 1: syslog:user for access log ===
--- config
location /p {
    access_log syslog:user;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 2: syslog:user:info for access log ===
--- config
location /p {
    access_log syslog:user:info;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 3: syslog:user:info:127.0.0.1 for access log ===
--- config
location /p {
    access_log syslog:user:info:127.0.0.1;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 4: syslog:user:info:127.0.0.1:514 for access log ===
--- config
location /p {
    access_log syslog:user:info:127.0.0.1:514;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 5: syslog:user:info:127.0.0.1:514:test.taobao.com for access log ===
--- config
location /p {
    access_log syslog:user:info:127.0.0.1:514:test.taobao.com;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 6: syslog:user::127.0.0.1:514:test.taobao.com for access log ===
--- config
location /p {
    access_log syslog:user::127.0.0.1:514:test.taobao.com;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 7: syslog:user:info:127.0.0.1::test.taobao.com for access log ===
--- config
location /p {
    access_log syslog:user:info:127.0.0.1::test.taobao.com;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 8: syslog:user:info:/dev/log:test.taobao.com for access log ===
--- config
location /p {
    access_log syslog:user::/dev/log:test.taobao.com;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 9: syslog:user:info:/dev/log for access log ===
--- config
location /p {
    access_log syslog:user::/dev/log;
    empty_gif;
}
--- request
GET /p
--- error_code: 200

=== TEST 11: syslog:user for error log ===
--- config
location /p {
    error_log syslog:user debug;
    root /not/exist;
}
--- request
GET /p
--- error_code: 404

=== TEST 12: syslog:user:info for error log ===
--- config
location /p {
    error_log syslog:user:info;
    root /not/exist;
}
--- request
GET /p
--- error_code: 404

=== TEST 13: syslog:user:info:127.0.0.1 for error log ===
--- config
location /p {
    error_log syslog:user:info:127.0.0.1 debug;
    root /not/exist;
}
--- request
GET /p
--- error_code: 404

=== TEST 14: syslog:user:info:127.0.0.1:514 for error log ===
--- config
location /p {
    error_log syslog:user:info:127.0.0.1:514 debug;
    root /not/exist;
}
--- request
GET /p
--- error_code: 404

=== TEST 15: syslog:user:info:127.0.0.1:514:test.taobao.com for error log ===
--- config
location /p {
    error_log syslog:user:info:127.0.0.1:514:test.taobao.com debug;
    root /not/exist;
}
--- request
GET /p
--- error_code: 404

=== TEST 16: syslog:user::127.0.0.1:514:test.taobao.com for error log ===
--- config
location /p {
    error_log syslog:user::127.0.0.1:514:test.taobao.com debug;
    root /not/exist;
}
--- request
GET /p
--- error_code: 404

=== TEST 17: syslog:user:info:127.0.0.1::test.taobao.com for error log ===
--- config
location /p {
    error_log syslog:user:info:127.0.0.1::test.taobao.com debug;
    root /not/exist;
}
--- request
GET /p
--- error_code: 404

=== TEST 18: syslog:user:info:/dev/log:test.taobao.com for error log ===
--- config
location /p {
    error_log syslog:user::/dev/log:test.taobao.com debug;
    root /not/exist;
}
--- request
GET /p
--- error_code: 404

=== TEST 19: syslog:user:info:/dev/log for error log ===
--- config
location /p {
    error_log syslog:user::/dev/log debug;
    root /not/exist;
}
--- request
GET /p
--- error_code: 404

=== Test 20: hostname and domain support, besides ip ===
--- config
location /p {
    access_log syslog:user:info:localhost::test.taobao.com;
    empty_gif;
}
--- request
GET /p
--- error_code: 200
