# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (4 * blocks());

#no_diff();
no_long_string();

run_tests();

__DATA__

=== TEST 1: clear Opera user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", nil)

        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- more_headers
User-Agent: Opera/9.80 (Macintosh; Intel Mac OS X 10.7.4; U; en) Presto/2.10.229 Version/11.62

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: opera: %d\n", $r->headers_in->opera)
}


F(ngx_http_core_content_phase) {
    printf("content: opera: %d\n", $r->headers_in->opera)
}

--- stap_out
rewrite: opera: 1
content: opera: 0

--- response_body
User-Agent: 
--- no_error_log
[error]



=== TEST 2: clear MSIE 4 user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", nil)

        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- more_headers
User-Agent: Mozilla/4.0 (compatible; MSIE 4.01; Windows NT 5.0)

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

F(ngx_http_core_content_phase) {
    printf("content: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

--- stap_out
rewrite: msie=1 msie6=1
content: msie=0 msie6=0

--- response_body
User-Agent: 
--- no_error_log
[error]



=== TEST 3: set custom MSIE 4 user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", "Mozilla/4.0 (compatible; MSIE 4.01; Windows NT 5.0)")
        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

F(ngx_http_core_content_phase) {
    printf("content: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

--- stap_out
rewrite: msie=0 msie6=0
content: msie=1 msie6=1

--- response_body
User-Agent: Mozilla/4.0 (compatible; MSIE 4.01; Windows NT 5.0)
--- no_error_log
[error]



=== TEST 4: clear MSIE 5 user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", nil)

        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- more_headers
User-Agent: Mozilla/4.0 (compatible; MSIE 5.01; Windows 95; MSIECrawler)

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

F(ngx_http_core_content_phase) {
    printf("content: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

--- stap_out
rewrite: msie=1 msie6=1
content: msie=0 msie6=0

--- response_body
User-Agent: 
--- no_error_log
[error]



=== TEST 5: set custom MSIE 5 user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", "Mozilla/4.0 (compatible; MSIE 5.01; Windows 95; MSIECrawler)")
        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

F(ngx_http_core_content_phase) {
    printf("content: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

--- stap_out
rewrite: msie=0 msie6=0
content: msie=1 msie6=1

--- response_body
User-Agent: Mozilla/4.0 (compatible; MSIE 5.01; Windows 95; MSIECrawler)
--- no_error_log
[error]



=== TEST 6: clear MSIE 6 (without SV1) user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", nil)

        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- more_headers
User-Agent: Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.0; Google Wireless Transcoder;)

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

F(ngx_http_core_content_phase) {
    printf("content: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

--- stap_out
rewrite: msie=1 msie6=1
content: msie=0 msie6=0

--- response_body
User-Agent: 
--- no_error_log
[error]



=== TEST 7: set custom MSIE 6 (without SV1) user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.0; Google Wireless Transcoder;)")
        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

F(ngx_http_core_content_phase) {
    printf("content: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

--- stap_out
rewrite: msie=0 msie6=0
content: msie=1 msie6=1

--- response_body
User-Agent: Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.0; Google Wireless Transcoder;)
--- no_error_log
[error]



=== TEST 8: clear MSIE 6 (with SV1) user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", nil)

        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- more_headers
User-Agent: Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1; InfoPath.1)

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

F(ngx_http_core_content_phase) {
    printf("content: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

--- stap_out
rewrite: msie=1 msie6=0
content: msie=0 msie6=0

--- response_body
User-Agent: 
--- no_error_log
[error]



=== TEST 9: set custom MSIE 6 (with SV1) user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1; InfoPath.1)")
        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

F(ngx_http_core_content_phase) {
    printf("content: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

--- stap_out
rewrite: msie=0 msie6=0
content: msie=1 msie6=0

--- response_body
User-Agent: Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1; InfoPath.1)
--- no_error_log
[error]



=== TEST 10: set custom MSIE 7 user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", "Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; winfx; .NET CLR 1.1.4322; .NET CLR 2.0.50727; Zune 2.0)")
        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

F(ngx_http_core_content_phase) {
    printf("content: msie=%d msie6=%d\n",
           $r->headers_in->msie,
           $r->headers_in->msie6)
}

--- stap_out
rewrite: msie=0 msie6=0
content: msie=1 msie6=0

--- response_body
User-Agent: Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; winfx; .NET CLR 1.1.4322; .NET CLR 2.0.50727; Zune 2.0)
--- no_error_log
[error]



=== TEST 11: clear Gecko user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", nil)

        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- more_headers
User-Agent: Mozilla/5.0 (Android; Mobile; rv:13.0) Gecko/13.0 Firefox/13.0

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: gecko: %d\n", $r->headers_in->gecko)
}


F(ngx_http_core_content_phase) {
    printf("content: gecko: %d\n", $r->headers_in->gecko)
}

--- stap_out
rewrite: gecko: 1
content: gecko: 0

--- response_body
User-Agent: 
--- no_error_log
[error]



=== TEST 12: set custom Gecko user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", "Mozilla/5.0 (Android; Mobile; rv:13.0) Gecko/13.0 Firefox/13.0")

        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: gecko: %d\n", $r->headers_in->gecko)
}


F(ngx_http_core_content_phase) {
    printf("content: gecko: %d\n", $r->headers_in->gecko)
}

--- stap_out
rewrite: gecko: 0
content: gecko: 1

--- response_body
User-Agent: Mozilla/5.0 (Android; Mobile; rv:13.0) Gecko/13.0 Firefox/13.0
--- no_error_log
[error]



=== TEST 13: clear Chrome user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", nil)

        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- more_headers
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_3) AppleWebKit/535.19 (KHTML, like Gecko) Chrome/18.0.1025.151 Safari/535.19

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: chrome: %d\n", $r->headers_in->chrome)
}


F(ngx_http_core_content_phase) {
    printf("content: chrome: %d\n", $r->headers_in->chrome)
}

--- stap_out
rewrite: chrome: 1
content: chrome: 0

--- response_body
User-Agent: 
--- no_error_log
[error]



=== TEST 14: set custom Chrome user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_3) AppleWebKit/535.19 (KHTML, like Gecko) Chrome/18.0.1025.151 Safari/535.19")

        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: chrome: %d\n", $r->headers_in->chrome)
}


F(ngx_http_core_content_phase) {
    printf("content: chrome: %d\n", $r->headers_in->chrome)
}

--- stap_out
rewrite: chrome: 0
content: chrome: 1

--- response_body
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_3) AppleWebKit/535.19 (KHTML, like Gecko) Chrome/18.0.1025.151 Safari/535.19
--- no_error_log
[error]



=== TEST 15: clear Safari (Mac OS X) user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", nil)

        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- more_headers
User-Agent: Mozilla/5.0 (Macintosh; U; PPC Mac OS X; en) AppleWebKit/125.2 (KHTML, like Gecko) Safari/125.8

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: safari: %d\n", $r->headers_in->safari)
}


F(ngx_http_core_content_phase) {
    printf("content: safari: %d\n", $r->headers_in->safari)
}

--- stap_out
rewrite: safari: 1
content: safari: 0

--- response_body
User-Agent: 
--- no_error_log
[error]



=== TEST 16: set custom Safari user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", "Mozilla/5.0 (Macintosh; U; PPC Mac OS X; en) AppleWebKit/125.2 (KHTML, like Gecko) Safari/125.8")
        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: safari: %d\n", $r->headers_in->safari)
}


F(ngx_http_core_content_phase) {
    printf("content: safari: %d\n", $r->headers_in->safari)
}

--- stap_out
rewrite: safari: 0
content: safari: 1

--- response_body
User-Agent: Mozilla/5.0 (Macintosh; U; PPC Mac OS X; en) AppleWebKit/125.2 (KHTML, like Gecko) Safari/125.8
--- no_error_log
[error]



=== TEST 17: clear Konqueror user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", nil)

        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- more_headers
User-Agent: Mozilla/5.0 (compatible; Konqueror/3.5; Linux) KHTML/3.5.10 (like Gecko) (Kubuntu)

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: konqueror: %d\n", $r->headers_in->konqueror)
}


F(ngx_http_core_content_phase) {
    printf("content: konqueror: %d\n", $r->headers_in->konqueror)
}

--- stap_out
rewrite: konqueror: 1
content: konqueror: 0

--- response_body
User-Agent: 
--- no_error_log
[error]



=== TEST 18: set custom Konqueror user-agent
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", "Mozilla/5.0 (compatible; Konqueror/3.5; Linux) KHTML/3.5.10 (like Gecko) (Kubuntu)")
        ';
        echo "User-Agent: $http_user_agent";
    }

--- request
GET /t

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: konqueror: %d\n", $r->headers_in->konqueror)
}


F(ngx_http_core_content_phase) {
    printf("content: konqueror: %d\n", $r->headers_in->konqueror)
}

--- stap_out
rewrite: konqueror: 0
content: konqueror: 1

--- response_body
User-Agent: Mozilla/5.0 (compatible; Konqueror/3.5; Linux) KHTML/3.5.10 (like Gecko) (Kubuntu)
--- no_error_log
[error]
