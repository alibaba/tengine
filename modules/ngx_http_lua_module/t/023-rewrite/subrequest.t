# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: DELETE
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/other",
                { method = ngx.HTTP_DELETE });

            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
DELETE



=== TEST 2: DELETE (proxy method)
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo",
                { method = ngx.HTTP_DELETE });

            ngx.print(res.body)
        ';

        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
DELETE



=== TEST 3: POST (nobody, proxy method)
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo",
                { method = ngx.HTTP_POST });

            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
POST



=== TEST 4: HEAD
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/other",
                { method = ngx.HTTP_HEAD });

            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body



=== TEST 5: explicit GET
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo",
                { method = ngx.HTTP_GET });

            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
GET



=== TEST 6: implicit GET
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo")

            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
GET



=== TEST 7: implicit GET (empty option table)
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo", {})

            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
GET



=== TEST 8: PUT (nobody, proxy method)
--- config
    location /other {
        default_type 'foo/bar';
        echo_read_request_body;

        echo $echo_request_method;
        echo_request_body;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo",
                { method = ngx.HTTP_PUT, body = "hello" });

            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body chomp
PUT
hello



=== TEST 9: PUT (nobody, no proxy method)
--- config
    location /other {
        default_type 'foo/bar';
        #echo_read_request_body;

        echo $echo_request_method;
        #echo $echo_request_body;
        echo_request_body;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/other",
                { method = ngx.HTTP_PUT, body = "hello" });

            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body chomp
PUT
hello



=== TEST 10: PUT (nobody, no proxy method)
--- config
    location /other {
        default_type 'foo/bar';
        #echo_read_request_body;

        echo $echo_request_method;
        #echo $echo_request_body;
        echo_request_body;
        #echo "[$http_content_length]";
        echo;
    }

    location /foo {
        echo $echo_request_method;
        echo -n "[$http_content_length]";
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/other",
                { method = ngx.HTTP_PUT, body = "hello" });

            ngx.print(res.body)

            res = ngx.location.capture("/foo")
            ngx.say(res.body)

        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
PUT
hello
GET
[]



=== TEST 11: POST (with body, proxy method)
--- config
    location /other {
        default_type 'foo/bar';
        echo_read_request_body;

        echo $echo_request_method;
        echo_request_body;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo",
                { method = ngx.HTTP_POST, body = "hello" });

            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body chomp
POST
hello



=== TEST 12: POST (with body, memc method)
--- config
    location /flush {
        set $memc_cmd flush_all;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location /memc {
        set $memc_key $echo_request_uri;
        set $memc_exptime 600;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location /lua {
        rewrite_by_lua '
            ngx.location.capture("/flush");

            local res = ngx.location.capture("/memc");
            ngx.say("GET: " .. res.status);

            res = ngx.location.capture("/memc",
                { method = ngx.HTTP_PUT, body = "hello" });
            ngx.say("PUT: " .. res.status);

            res = ngx.location.capture("/memc");
            ngx.say("cached: " .. res.body);

        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
GET: 404
PUT: 201
cached: hello



=== TEST 13: POST (with body, memc method)
--- config
    location /flush {
        set $memc_cmd flush_all;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location /memc {
        set $memc_cmd "";
        set $memc_key $echo_request_uri;
        set $memc_exptime 600;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location /lua {
        rewrite_by_lua '
            ngx.location.capture("/flush",
                { share_all_vars = true });

            local res = ngx.location.capture("/memc",
                { share_all_vars = true });
            ngx.say("GET: " .. res.status);

            res = ngx.location.capture("/memc",
                { method = ngx.HTTP_PUT, body = "hello", share_all_vars = true });
            ngx.say("PUT: " .. res.status);

            res = ngx.location.capture("/memc", { share_all_vars = true });
            ngx.say("cached: " .. res.body);

        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
GET: 404
PUT: 201
cached: hello



=== TEST 14: empty args option table
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo",
                { args = {} })
            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body eval: "\n"



=== TEST 15: non-empty args option table (1 pair)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo",
                { args = { ["fo="] = "=>" } })
            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
fo%3D=%3D%3E



=== TEST 16: non-empty args option table (2 pairs)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo",
                { args = { ["fo="] = "=>",
                    ["="] = ":" } })
            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body_like chop
^(?:fo%3D=%3D%3E\&%3D=%3A|%3D=%3A\&fo%3D=%3D%3E)$



=== TEST 17: non-empty args option table (2 pairs, no special chars)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo",
                { args = { foo = 3,
                    bar = "hello" } })
            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body_like chop
^(?:bar=hello\&foo=3|foo=3\&bar=hello)$



=== TEST 18: non-empty args option table (number key)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo",
                { args = { [57] = "hi" } })
            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 19: non-empty args option table (plain arrays)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo",
                { args = { "hi" } })
            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 20: more args
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo?a=3",
                { args = { b = 4 } })
            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
a=3&b=4



=== TEST 21: more args
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo?a=3",
                { args = "b=4" })
            ngx.print(res.body)
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
a=3&b=4



=== TEST 22: more args
--- config
    location /memc {
        set $memc_cmd get;
        set $memc_key $arg_key;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location /memc_set {
        #set $memc_cmd set;
        #set $memc_key $arg_key;
        #memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
        echo OK;
    }

    location /lua {
        rewrite_by_lua '
            print("HELLO")
            local memc_key = "hello"
            local res = ngx.location.capture("/memc?key=" .. memc_key )
            ngx.say("copass: res " .. res.status)

            if res.status == 404 then
                   ngx.say("copas: capture /memc_set")
                   res = ngx.location.capture("/memc_set?key=" .. memc_key)
                   ngx.say("copss: status " .. res.status);
            end
        ';
        content_by_lua 'return';
        #echo Hi;
    }
--- request
    GET /lua
--- response_body
copass: res 404
copas: capture /memc_set
copss: status 200



=== TEST 23: I/O in named location
the nginx core requires the patch https://github.com/agentzh/ngx_openresty/blob/master/patches/nginx-1.0.15-reset_wev_handler_in_named_locations.patch
--- config
    location /t {
        echo_exec @named;
    }

    location @named {
        rewrite_by_lua '
            ngx.location.capture("/hello")
        ';
        echo done;
    }

    location /hello {
        echo hello;
    }
--- request
    GET /t
--- response_body
done
