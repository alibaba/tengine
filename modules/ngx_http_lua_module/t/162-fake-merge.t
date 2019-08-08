# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
master_on();
#workers(2);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: get fake_var 
--- http_config
    init_worker_by_lua '
        local a = 1
    ';
--- config
    location /t {
        content_by_lua '
            ngx.say("fake_var = ", ngx.var.fake_var)
        ';
    }
--- request
    GET /t
--- response_body
fake_var = 1
--- no_error_log
[error]
