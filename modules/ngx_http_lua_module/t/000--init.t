# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket::Lua;

repeat_each(1);

plan tests => repeat_each() * (blocks() * 2 + 1);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3306;

our $http_config = <<'_EOC_';
    upstream database {
        drizzle_server 127.0.0.1:$TEST_NGINX_MYSQL_PORT protocol=mysql
                       dbname=ngx_test user=ngx_test password=ngx_test;
    }
_EOC_

no_shuffle();
run_tests();

__DATA__

=== TEST 1: conv_uid - drop table
--- http_config eval: $::http_config
--- config
    location = /init {
        drizzle_pass   database;
        drizzle_query  "DROP TABLE IF EXISTS conv_uid";
    }
--- request
GET /init
--- error_code: 200
--- timeout: 10
--- no_error_log
[error]



=== TEST 2: conv_uid - create table
--- http_config eval: $::http_config
--- config
    location = /init {
        drizzle_pass   database;
        drizzle_query  "CREATE TABLE conv_uid(id serial primary key, new_uid integer, old_uid integer)";
    }
--- request
GET /init
--- error_code: 200
--- timeout: 10
--- no_error_log
[error]



=== TEST 3: conv_uid - insert value
--- http_config eval: $::http_config
--- config
    location = /init {
        drizzle_pass   database;
        drizzle_query  "INSERT INTO conv_uid(old_uid,new_uid) VALUES(32,56),(35,78)";
    }
--- request
GET /init
--- error_code: 200
--- timeout: 10
--- no_error_log
[error]



=== TEST 4: flush data from memcached
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

