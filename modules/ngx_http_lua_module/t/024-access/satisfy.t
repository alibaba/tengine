# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

worker_connections(1014);
#master_on();
#workers(4);
#log_level('warn');
no_root_location();

#repeat_each(2);
#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

our $HtmlDir = html_dir;

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: satisfy any
--- config
    location /test {
        satisfy any;
        allow all;
        access_by_lua 'ngx.exit(403)';

        echo something important;
    }
--- request
    GET /test
--- more_headers
--- response_body
something important
--- no_error_log
[error]



=== TEST 2: satisfy any
--- config
    location /test {
        satisfy any;
        deny all;
        access_by_lua 'ngx.exit(403)';

        echo something important;
    }
--- request
    GET /test
--- more_headers
--- response_body_like: 403 Forbidden
--- error_code: 403
--- error_log
access forbidden by rule



=== TEST 3: satisfy any (explicit ngx.exit(0))
--- config
    location /test {
        satisfy any;
        deny all;
        access_by_lua 'ngx.exit(0)';

        echo something important;
    }
--- request
    GET /test
--- more_headers
--- response_body
something important
--- error_code: 200
--- no_error_log
[error]



=== TEST 4: satisfy any (simple return)
--- config
    location /test {
        satisfy any;
        deny all;
        access_by_lua return;

        echo something important;
    }
--- request
    GET /test
--- more_headers
--- response_body
something important
--- error_code: 200
--- no_error_log
[error]



=== TEST 5: satisfy any (declined)
--- config
    location /test {
        satisfy any;
        deny all;
        access_by_lua 'ngx.exit(ngx.DECLINED)';

        echo something important;
    }
--- request
    GET /test
--- more_headers
--- response_body_like: 403 Forbidden
--- error_code: 403
--- error_log
access forbidden by rule



=== TEST 6: satisfy any (declined, with I/O)
--- config
    location /test {
        satisfy any;
        deny all;
        access_by_lua 'ngx.location.capture("/echo") ngx.exit(ngx.DECLINED)';

        echo something important;
    }

    location /echo {
        echo hi;
        #echo_sleep 0.01;
    }
--- request
    GET /test
--- more_headers
--- response_body_like: 403 Forbidden
--- error_code: 403
--- error_log
access forbidden by rule



=== TEST 7: satisfy any (simple return, with I/O)
--- config
    location /test {
        satisfy any;
        deny all;
        access_by_lua 'ngx.location.capture("/echo") return';

        echo something important;
    }

    location /echo {
        echo hi;
    }
--- request
    GET /test
--- more_headers
--- response_body
something important
--- error_code: 200
--- no_error_log
[error]



=== TEST 8: satisfy any - with I/O
--- config
    location /test {
        satisfy any;
        deny all;
        access_by_lua 'ngx.location.capture("/echo") ngx.exit(403)';

        echo something important;
    }

    location /echo {
        echo hi;
    }
--- request
    GET /test
--- more_headers
--- response_body_like: 403 Forbidden
--- error_code: 403
--- error_log
access forbidden by rule



=== TEST 9: satisfy any (explicit ngx.exit(0), with I/O)
--- config
    location /test {
        satisfy any;
        deny all;
        access_by_lua 'ngx.location.capture("/echo") ngx.exit(0)';

        echo something important;
    }

    location /echo {
        echo hi;
    }
--- request
    GET /test
--- more_headers
--- response_body
something important
--- error_code: 200
--- no_error_log
[error]
