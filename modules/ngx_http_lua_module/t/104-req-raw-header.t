# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 15);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: small header
--- config
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header())
        ';
    }
--- request
GET /t
--- response_body eval
qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
\r
}
--- no_error_log
[error]



=== TEST 2: large header
--- config
    client_header_buffer_size 10;
    large_client_header_buffers 30 561;
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header())
        ';
    }
--- request
GET /t
--- more_headers eval
CORE::join "\n", map { "Header$_: value-$_" } 1..512

--- response_body eval
qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
}
.(CORE::join "\r\n", map { "Header$_: value-$_" } 1..512) . "\r\n\r\n"

--- no_error_log
[error]
--- timeout: 5



=== TEST 3: large header (no request line)
--- config
    client_header_buffer_size 10;
    large_client_header_buffers 30 561;
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header(true))
        ';
    }
--- request
GET /t
--- more_headers eval
CORE::join "\n", map { "Header$_: value-$_" } 1..512

--- response_body eval
qq{Host: localhost\r
Connection: close\r
}
.(CORE::join "\r\n", map { "Header$_: value-$_" } 1..512) . "\r\n\r\n"

--- no_error_log
[error]
--- timeout: 5



=== TEST 4: small header (no request line)
--- config
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header(true))
        ';
    }
--- request
GET /t
--- response_body eval
qq{Host: localhost\r
Connection: close\r
\r
}
--- no_error_log
[error]



=== TEST 5: small header (no request line, with leading CRLF)
--- config
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header(true))
        ';
    }
--- raw_request eval
"\r\nGET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
\r
"
--- response_body eval
qq{Host: localhost\r
Connection: close\r
\r
}
--- no_error_log
[error]



=== TEST 6: small header, with leading CRLF
--- config
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header())
        ';
    }
--- raw_request eval
"\r\nGET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
\r
"
--- response_body eval
qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
\r
}
--- no_error_log
[error]



=== TEST 7: large header, with leading CRLF
--- config
    client_header_buffer_size 10;
    large_client_header_buffers 30 561;
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header())
        ';
    }

--- raw_request eval
"\r\nGET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
".
(CORE::join "\r\n", map { "Header$_: value-$_" } 1..512) . "\r\n\r\n"

--- response_body eval
qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
}
.(CORE::join "\r\n", map { "Header$_: value-$_" } 1..512) . "\r\n\r\n"

--- no_error_log
[error]
--- timeout: 5



=== TEST 8: large header, with leading CRLF, excluding request line
--- config
    client_header_buffer_size 10;
    large_client_header_buffers 30 561;
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header(true))
        ';
    }

--- raw_request eval
"\r\nGET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
".
(CORE::join "\r\n", map { "Header$_: value-$_" } 1..512) . "\r\n\r\n"

--- response_body eval
qq{Host: localhost\r
Connection: close\r
}
.(CORE::join "\r\n", map { "Header$_: value-$_" } 1..512) . "\r\n\r\n"

--- no_error_log
[error]
--- timeout: 5



=== TEST 9: large header, with lots of leading CRLF, excluding request line
--- config
    client_header_buffer_size 10;
    large_client_header_buffers 30 561;
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header(true))
        ';
    }

--- raw_request eval
("\r\n" x 534) . "GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
".
(CORE::join "\r\n", map { "Header$_: value-$_" } 1..512) . "\r\n\r\n"

--- response_body eval
qq{Host: localhost\r
Connection: close\r
}
.(CORE::join "\r\n", map { "Header$_: value-$_" } 1..512) . "\r\n\r\n"

--- no_error_log
[error]
--- timeout: 5



=== TEST 10: small header, pipelined
--- config
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header())
        ';
    }
--- pipelined_requests eval
["GET /t", "GET /th"]

--- more_headers
Foo: bar

--- response_body eval
[qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: keep-alive\r
Foo: bar\r
\r
}, qq{GET /th HTTP/1.1\r
Host: localhost\r
Connection: close\r
Foo: bar\r
\r
}]
--- no_error_log
[error]



=== TEST 11: large header, pipelined
--- config
    client_header_buffer_size 10;
    large_client_header_buffers 30 561;
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header())
        ';
    }
--- pipelined_requests eval
["GET /t", "GET /t"]

--- more_headers eval
CORE::join "\n", map { "Header$_: value-$_" } 1..512

--- response_body eval
my $headers = (CORE::join "\r\n", map { "Header$_: value-$_" } 1..512) . "\r\n\r\n";

[qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: keep-alive\r
$headers},
qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
$headers}]

--- no_error_log
[error]
--- timeout: 5



=== TEST 12: small header, multi-line header
--- config
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header())
        ';
    }
--- raw_request eval
"GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
Foo: bar baz\r
  blah\r
\r
"
--- response_body eval
qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
Foo: bar baz\r
  blah\r
\r
}
--- no_error_log
[error]



=== TEST 13: large header, multi-line header
--- config
    client_header_buffer_size 10;
    large_client_header_buffers 50 567;
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header())
        ';
    }

--- raw_request eval
my $headers = (CORE::join "\r\n", map { "Header$_: value-$_\r\n hello $_ world blah blah" } 1..512) . "\r\n\r\n";

qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
$headers}

--- response_body eval
qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
}
.(CORE::join "\r\n", map { "Header$_: value-$_\r\n hello $_ world blah blah" } 1..512) . "\r\n\r\n"

--- no_error_log
[error]
--- timeout: 5



=== TEST 14: small header (POST body)
--- config
    location /t {
        content_by_lua '
            ngx.req.read_body()
            ngx.print(ngx.req.raw_header())
        ';
    }
--- request
POST /t
hello
--- response_body eval
qq{POST /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
Content-Length: 5\r
\r
}
--- no_error_log
[error]



=== TEST 15: small header (POST body) - in subrequests
--- config
    location /t {
        content_by_lua '
            ngx.req.read_body()
            ngx.print(ngx.req.raw_header())
        ';
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/t")
            ngx.print(res.body)
        ';
    }

--- request
POST /main
hello
--- response_body eval
qq{POST /main HTTP/1.1\r
Host: localhost\r
Connection: close\r
Content-Length: 5\r
\r
}
--- no_error_log
[error]



=== TEST 16: large header (POST body)
--- config
    client_header_buffer_size 10;
    large_client_header_buffers 30 561;
    location /t {
        content_by_lua '
            ngx.req.read_body()
            ngx.print(ngx.req.raw_header())
        ';
    }
--- request
POST /t
hello
--- more_headers eval
CORE::join"\n", map { "Header$_: value-$_" } 1..512

--- response_body eval
qq{POST /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
}
.(CORE::join "\r\n", map { "Header$_: value-$_" } 1..512) . "\r\nContent-Length: 5\r\n\r\n"

--- no_error_log
[error]
--- timeout: 5



=== TEST 17: large header (POST body) - in subrequests
--- config
    client_header_buffer_size 10;
    large_client_header_buffers 30 561;
    location /t {
        content_by_lua '
            ngx.req.read_body()
            ngx.print(ngx.req.raw_header())
        ';
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/t")
            ngx.print(res.body)
        ';
    }
--- request
POST /main
hello
--- more_headers eval
CORE::join"\n", map { "Header$_: value-$_" } 1..512

--- response_body eval
qq{POST /main HTTP/1.1\r
Host: localhost\r
Connection: close\r
}
.(CORE::join "\r\n", map { "Header$_: value-$_" } 1..512) . "\r\nContent-Length: 5\r\n\r\n"

--- no_error_log
[error]
--- timeout: 5



=== TEST 18: large header (POST body) - r->header_end is outside r->header_in
--- config
    client_header_buffer_size 10;
    large_client_header_buffers 30 564;
    location /t {
        content_by_lua '
            -- ngx.req.read_body()
            ngx.print(ngx.req.raw_header())
        ';
    }
--- request
POST /t
hello
--- more_headers eval
CORE::join("\n", map { "Header$_: value-$_" } 1..80) . "\nA: abcdefghijklmnopqrs\n"

--- response_body eval
qq{POST /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
}
.(CORE::join "\r\n", map { "Header$_: value-$_" } 1..80)
. "\r\nA: abcdefghijklmnopqrs\r\nContent-Length: 5\r\n\r\n"

--- no_error_log
[error]
--- timeout: 5



=== TEST 19: large header (POST body) - r->header_end is outside r->header_in (2)
--- config
    client_header_buffer_size 10;
    large_client_header_buffers 30 564;
    location /t {
        content_by_lua '
            -- ngx.req.read_body()
            ngx.print(ngx.req.raw_header())
        ';
    }
--- request
POST /t
hello
--- more_headers eval
CORE::join("\n", map { "Header$_: value-$_" } 1..52) . "\nA: abcdefghijklmnopqrs\n"

--- response_body eval
qq{POST /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
}
.(CORE::join "\r\n", map { "Header$_: value-$_" } 1..52)
. "\r\nA: abcdefghijklmnopqrs\r\nContent-Length: 5\r\n\r\n"

--- no_error_log
[error]
--- timeout: 5



=== TEST 20: raw_header (the default header buffer can hold the request line, but not the header entries) - without request line)
--- config
    location /t {
        content_by_lua '
           ngx.print(ngx.req.raw_header(true))
        ';
    }
--- request
GET /t
--- more_headers eval
my $s = "User-Agent: curl\nBah: bah\n";
$s .= "Accept: */*\n";
$s .= "Cookie: " . "C" x 1200 . "\n";
$s
--- response_body eval
"Host: localhost\r
Connection: close\r
User-Agent: curl\r
Bah: bah\r
Accept: */*\r
Cookie: " . ("C" x 1200) . "\r\n\r\n"
--- no_error_log
[error]



=== TEST 21: raw_header (the default header buffer can hold the request line, but not the header entries) - with request line)
--- config
    location /t {
        content_by_lua '
           ngx.print(ngx.req.raw_header())
        ';
    }
--- request
GET /t
--- more_headers eval
my $s = "User-Agent: curl\nBah: bah\n";
$s .= "Accept: */*\n";
$s .= "Cookie: " . "C" x 1200 . "\n";
$s
--- response_body eval
"GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
User-Agent: curl\r
Bah: bah\r
Accept: */*\r
Cookie: " . ("C" x 1200) . "\r\n\r\n"
--- no_error_log
[error]



=== TEST 22: ngx_proxy/ngx_fastcgi/etc change r->header_end to point to their own buffers
--- config
    location = /t {
        proxy_buffering off;
        proxy_pass http://127.0.0.1:$server_port/bad;
        proxy_intercept_errors on;
        error_page 500 = /500;
    }

    location = /bad {
        return 500;
    }

    location = /500 {
        internal;
        content_by_lua '
            ngx.print(ngx.req.raw_header())
        ';
    }
--- request
GET /t
--- response_body eval
"GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
\r
"
--- no_error_log
[error]



=== TEST 23: ngx_proxy/ngx_fastcgi/etc change r->header_end to point to their own buffers (exclusive LF in the request data)
--- config
    location = /t {
        proxy_buffering off;
        proxy_pass http://127.0.0.1:$server_port/bad;
        proxy_intercept_errors on;
        error_page 500 = /500;
    }

    location = /bad {
        return 500;
    }

    location = /500 {
        internal;
        content_by_lua '
            ngx.print(ngx.req.raw_header())
        ';
    }
--- raw_request eval
"GET /t HTTP/1.1
Host: localhost
Connection: close
Content-Length: 5

hello"
--- response_body eval
"GET /t HTTP/1.1
Host: localhost
Connection: close
Content-Length: 5

"
--- no_error_log
[error]



=== TEST 24: ngx_proxy/ngx_fastcgi/etc change r->header_end to point to their own buffers (exclusive LF in the request data, and no status line)
--- config
    location = /t {
        proxy_buffering off;
        proxy_pass http://127.0.0.1:$server_port/bad;
        proxy_intercept_errors on;
        error_page 500 = /500;
    }

    location = /bad {
        return 500;
    }

    location = /500 {
        internal;
        content_by_lua '
            ngx.print(ngx.req.raw_header(true))
        ';
    }
--- raw_request eval
"GET /t HTTP/1.1
Host: localhost
Connection: close
Content-Length: 5

hello"
--- response_body eval
"Host: localhost
Connection: close
Content-Length: 5

"
--- no_error_log
[error]



=== TEST 25: ngx_proxy/ngx_fastcgi/etc change r->header_end to point to their own buffers (mixed LF and CRLF in the request data, and no status line)
--- config
    location = /t {
        proxy_buffering off;
        proxy_pass http://127.0.0.1:$server_port/bad;
        proxy_intercept_errors on;
        error_page 500 = /500;
    }

    location = /bad {
        return 500;
    }

    location = /500 {
        internal;
        content_by_lua '
            ngx.print(ngx.req.raw_header(true))
        ';
    }
--- raw_request eval
"GET /t HTTP/1.1\r
Host: localhost
Connection: close\r
Content-Length: 5\r

hello"
--- response_body eval
"Host: localhost
Connection: close\r
Content-Length: 5\r

"
--- no_error_log
[error]



=== TEST 26: ngx_proxy/ngx_fastcgi/etc change r->header_end to point to their own buffers (another way of mixing LF and CRLF in the request data, and no status line)
--- config
    location = /t {
        proxy_buffering off;
        proxy_pass http://127.0.0.1:$server_port/bad;
        proxy_intercept_errors on;
        error_page 500 = /500;
    }

    location = /bad {
        return 500;
    }

    location = /500 {
        internal;
        content_by_lua '
            ngx.print(ngx.req.raw_header(true))
        ';
    }
--- raw_request eval
"GET /t HTTP/1.1\r
Host: localhost
Connection: close\r
Content-Length: 5
\r
hello"
--- response_body eval
"Host: localhost
Connection: close\r
Content-Length: 5
\r
"
--- no_error_log
[error]



=== TEST 27: two pipelined requests with large headers
--- config
    client_header_buffer_size 10;
    large_client_header_buffers 3 5610;
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header())
        ';
    }
--- pipelined_requests eval
["GET /t", "GET /t"]
--- more_headers eval
CORE::join "\n", map { "Header$_: value-$_" } 1..585

--- response_body eval
[qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: keep-alive\r
}
.(CORE::join "\r\n", map { "Header$_: value-$_" } 1..585) . "\r\n\r\n",
qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
}
.(CORE::join "\r\n", map { "Header$_: value-$_" } 1..585) . "\r\n\r\n",
,
]

--- no_error_log
[error]
--- timeout: 5



=== TEST 28: a request with large header and a smaller pipelined request following
--- config
    client_header_buffer_size 10;
    large_client_header_buffers 2 1921;
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header())
        ';
    }
--- pipelined_requests eval
["GET /t", "GET /t"]
--- more_headers eval
[CORE::join("\n", map { "Header$_: value-$_" } 1..170), "Foo: bar\n"]

--- response_body eval
[qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: keep-alive\r
}
.(CORE::join "\r\n", map { "Header$_: value-$_" } 1..170) . "\r\n\r\n",
qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
Foo: bar\r
\r
},
]

--- no_error_log
[error]
--- timeout: 5



=== TEST 29: a request with large header and a smaller pipelined request following
--- config
    client_header_buffer_size 10;
    large_client_header_buffers 2 1921;
    location /t {
        content_by_lua '
            ngx.print(ngx.req.raw_header())
        ';
    }
--- pipelined_requests eval
["GET /t", "GET /t" . ("a" x 512)]
--- more_headers eval
[CORE::join("\n", map { "Header$_: value-$_" } 1..170), "Foo: bar\n"]

--- response_body eval
[qq{GET /t HTTP/1.1\r
Host: localhost\r
Connection: keep-alive\r
}
.(CORE::join "\r\n", map { "Header$_: value-$_" } 1..170) . "\r\n\r\n",
qq{GET /t} . ("a" x 512) . qq{ HTTP/1.1\r
Host: localhost\r
Connection: close\r
Foo: bar\r
\r
},
]

--- no_error_log
[error]
--- timeout: 5



=== TEST 30: large headers (using single LF as line break)
--- config
    location /t {
        content_by_lua_block {
            ngx.print(ngx.req.raw_header())
        }
    }

--- raw_request eval
"GET /t HTTP/1.1
Host: localhost
Connection: close
".
(CORE::join "\n", map { "Header$_: value-$_" } 1..512) . "\n\n"

--- response_body eval
qq{GET /t HTTP/1.1
Host: localhost
Connection: close
}
.(CORE::join "\n", map { "Header$_: value-$_" } 1..512) . "\n\n"

--- no_error_log
[error]
--- timeout: 5



=== TEST 31: large headers without request line (using single LF as line break)
--- config
    location /t {
        content_by_lua_block {
            ngx.print(ngx.req.raw_header(true))
        }
    }

--- raw_request eval
"GET /t HTTP/1.1
Host: localhost
Connection: close
".
(CORE::join "\n", map { "Header$_: value-$_" } 1..512) . "\n\n"

--- response_body eval
qq{Host: localhost
Connection: close
}
.(CORE::join "\n", map { "Header$_: value-$_" } 1..512) . "\n\n"

--- no_error_log
[error]
--- timeout: 5



=== TEST 32: large headers with leading CRLF (using single LF as line break)
--- config
    location /t {
        content_by_lua_block {
            ngx.print(ngx.req.raw_header())
        }
    }

--- raw_request eval
"\r
GET /t HTTP/1.1
Host: localhost
Connection: close
".
(CORE::join "\n", map { "Header$_: value-$_" } 1..512) . "\n\n"

--- response_body eval
qq{GET /t HTTP/1.1
Host: localhost
Connection: close
}
.(CORE::join "\n", map { "Header$_: value-$_" } 1..512) . "\n\n"

--- no_error_log
[error]
--- timeout: 5



=== TEST 33: large headers without request line but contains leading CRLF (using single LF as line break)
--- config
    location /t {
        content_by_lua_block {
            ngx.print(ngx.req.raw_header(true))
        }
    }

--- raw_request eval
"\r
GET /t HTTP/1.1
Host: localhost
Connection: close
".
(CORE::join "\n", map { "Header$_: value-$_" } 1..512) . "\n\n"

--- response_body eval
qq{Host: localhost
Connection: close
}
.(CORE::join "\n", map { "Header$_: value-$_" } 1..512) . "\n\n"

--- no_error_log
[error]
--- timeout: 5
