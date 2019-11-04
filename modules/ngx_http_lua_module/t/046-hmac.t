# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /lua {
        content_by_lua '
            local digest = ngx.hmac_sha1("thisisverysecretstuff", "some string we want to sign")
            ngx.say(ngx.encode_base64(digest))
        ';
    }
--- request
GET /lua
--- response_body
R/pvxzHC4NLtj7S+kXFg/NePTmk=
