use Test::Nginx::Socket;
use lib 'lib';

no_long_string();
log_level 'debug';
repeat_each(3);
plan tests => repeat_each() * ((blocks() - 3) * 5 + 3);
run_tests();


__DATA__


=== TEST 1: zstd_static off
--- config
    location /test {
        zstd_static off;
        root ../../t/suite;
    }
--- request
GET /test
--- response_headers
Content-Length: 59738
ETag: "5be17d33-e95a"
!Content-Encoding
--- no_error_log
[error]



=== TEST 2: zstd_static off (with accept-encoding header)
--- config
    location /test {
        zstd_static off;
        root ../../t/suite;
    }
--- request
GET /test
Accept-Encoding: gzip,zstd
--- response_headers
Content-Length: 59738
ETag: "5be17d33-e95a"
!Content-Encoding
--- no_error_log
[error]



=== TEST 3: zstd_static on
--- config
    location /test {
        zstd_static on;
        root ../../t/suite;
    }
--- request
GET /test
--- more_headers
Accept-Encoding: gzip, zstd
--- response_headers
Content-Length: 20706
ETag: "5be17d33-50e2"
!Content-Encoding
Content-Encoding: zstd
--- no_error_log
[error]



=== TEST 4: zstd_static on (without accept-encoding header)
--- config
    location /test {
        zstd_static on;
        root ../../t/suite;
    }
--- request
GET /test
--- response_headers
Content-Length: 59738
ETag: "5be17d33-e95a"
Content-Encoding: zstd
!Content-Encoding
--- no_error_log
[error]



=== TEST 5: zstd_static on (without zstd component in accept-encoding header)
--- config
    location /test {
        zstd_static on;
        root ../../t/suite;
    }
--- request
GET /test
--- more_headers
Accept-Encoding: gzip, br
--- response_headers
Content-Length: 59738
ETag: "5be17d33-e95a"
!Content-Encoding
--- no_error_log
[error]



=== TEST 6: zstd_static always
--- config
    location /test {
        zstd_static always;
        root ../../t/suite;
    }
--- request
GET /test
--- more_headers
Accept-Encoding: gzip, br
--- response_headers
Content-Length: 20706
ETag: "5be17d33-50e2"
Content-Encoding: zstd
--- no_error_log
[error]



=== TEST 6: zstd_static always (without accept-encoding header)
--- config
    location /test {
        zstd_static always;
        root ../../t/suite;
    }
--- request
GET /test
--- response_headers
Content-Length: 20706
ETag: "5be17d33-50e2"
Content-Encoding: zstd
--- no_error_log
[error]



=== TEST 7: zstd_static always (without zstd component in accept-encoding header)
--- config
    location /test {
        zstd_static always;
        root ../../t/suite;
    }
--- request
GET /test
--- more_headers
Accept-Encoding: gzip, br
--- response_headers
Content-Length: 20706
ETag: "5be17d33-50e2"
Content-Encoding: zstd
--- no_error_log
[error]


=== TEST 8: zstd_static always (file does not exist)
--- config
    location /test2 {
        zstd_static always;
        root ../../t/suite;
    }
--- request
GET /test2
--- more_headers
Accept-Encoding: gzip, br
--- error_code: 404



=== TEST 9: zstd_static on (file does not exist)
--- config
    location /test2 {
        zstd_static on;
        root ../../t/suite;
    }
--- request
GET /test2
--- more_headers
Accept-Encoding: gzip, br
--- error_code: 404



=== TEST 10: zstd_static off (file does not exist)
--- config
    location /test2 {
        zstd_static off;
        root ../../t/suite;
    }
--- request
GET /test2
--- more_headers
Accept-Encoding: gzip, br
--- error_code: 404
