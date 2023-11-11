# -*- mode: conf -*-
# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket::Lua;

log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

no_long_string();
run_tests();

__DATA__

=== TEST 1: start time
--- config
    location = /start {
        return 200 $request_start_time;
    }
--- request
GET /start
--- response_body_like: ^\d\d/[A-Z][a-z]{2}/\d{4}:\d\d:\d\d:\d\d [+-]\d{4}$
--- no_error_log
[error]

