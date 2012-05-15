# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(10);

plan tests => blocks() * 1;

run_tests();

__DATA__

=== TEST 1: sanity (integer)
--- config
    location /lua {
        echo 2;
    }
--- request
GET /lua
--- response_body_like
2

