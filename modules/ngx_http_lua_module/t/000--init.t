# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(1);

plan tests => repeat_each() * (blocks() * 3);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3306;

our $http_config = <<'_EOC_';
    upstream database {
        drizzle_server 127.0.0.1:$TEST_NGINX_MYSQL_PORT protocol=mysql
                       dbname=ngx_test user=ngx_test password=ngx_test;
    }

    lua_package_path "../lua-resty-mysql/lib/?.lua;;";
_EOC_

no_shuffle();
no_long_string();

run_tests();

__DATA__

=== TEST 1: conv_uid - drop table
--- http_config eval: $::http_config
--- config
    location = /init {
        content_by_lua_block {
            local mysql = require "resty.mysql"
            local db = assert(mysql:new())
            local ok, err, errcode, sqlstate = db:connect{
                host = "127.0.0.1",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test",
                charset = "utf8",
            }

            local queries = {
                "DROP TABLE IF EXISTS conv_uid",
                "CREATE TABLE conv_uid(id serial primary key, new_uid integer, old_uid integer)",
                "INSERT INTO conv_uid(old_uid,new_uid) VALUES(32,56),(35,78)",
            }

            for _, query in ipairs(queries) do
                local ok, err = db:query(query)
                if not ok then
                    ngx.say("failed to run mysql query \"", query, "\": ", err)
                    return
                end
            end

            ngx.say("done!")
        }
    }
--- request
GET /init
--- response_body
done!
--- timeout: 10
--- no_error_log
[error]



=== TEST 2: flush data from memcached
--- config
    location /flush {
        set $memc_cmd flush_all;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
GET /flush
--- error_code: 200
--- response_body eval
"OK\r
"
--- timeout: 10
--- no_error_log
[error]
