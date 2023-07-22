# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 3);

our $HtmlDir = html_dir;

#$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

no_long_string();
#no_diff();
#log_level 'warn';

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        rewrite_by_lua '
            local sock, err = ngx.req.socket()
            if sock then
                ngx.say("got the request socket")
            else
                ngx.say("failed to get the request socket: ", err)
            end

            for i = 1, 3 do
                local data, err, part = sock:receive(5)
                if data then
                    ngx.say("received: ", data)
                else
                    ngx.say("failed to receive: ", err, " [", part, "]")
                end
            end
        ';

        content_by_lua return;
    }
--- request
POST /t
hello world
--- response_body
got the request socket
received: hello
received:  worl
failed to receive: closed [d]
--- no_error_log
[error]



=== TEST 2: multipart rfc sample (just partial streaming)
--- config
    location /t {
        rewrite_by_lua '
            local sock, err = ngx.req.socket()
            if sock then
                ngx.say("got the request socket")
            else
                ngx.say("failed to get the request socket: ", err)
            end

            local boundary
            local header = ngx.var.http_content_type
            local m = ngx.re.match(header, [[; +boundary=(?:"(.*?)"|(\\w+))]], "jo")
            if m then
                boundary = m[1] or m[2]

            else
                ngx.say("invalid content-type header")
                return
            end

            local read_to_boundary = sock:receiveuntil("\\r\\n--" .. boundary)
            local read_line = sock:receiveuntil("\\r\\n")

            local data, err, part = read_to_boundary()
            if data then
                ngx.say("preamble: [" .. data .. "]")
            else
                ngx.say("failed to read the first boundary: ", err)
                return
            end

            local i = 1
            while true do
                local line, err = read_line()

                if not line then
                    ngx.say("failed to read post-boundary line: ", err)
                    return
                end

                m = ngx.re.match(line, "--$", "jo")
                if m then
                    ngx.say("found the end of the stream")
                    return
                end

                while true do
                    local line, err = read_line()
                    if not line then
                        ngx.say("failed to read part ", i, " header: ", err)
                        return
                    end

                    if line == "" then
                        -- the header part completes
                        break
                    end

                    ngx.say("part ", i, " header: [", line, "]")
                end

                local data, err, part = read_to_boundary()
                if data then
                    ngx.say("part ", i, " body: [" .. data .. "]")
                else
                    ngx.say("failed to read part ", i + 1, " boundary: ", err)
                    return
                end

                i = i + 1
            end
        ';

        content_by_lua return;
    }
--- request eval
"POST /t
This is the preamble.  It is to be ignored, though it
is a handy place for mail composers to include an
explanatory note to non-MIME compliant readers.\r
--simple boundary\r
\r
This is implicitly typed plain ASCII text.
It does NOT end with a linebreak.\r
--simple boundary\r
Content-type: text/plain; charset=us-ascii\r
\r
This is explicitly typed plain ASCII text.
It DOES end with a linebreak.
\r
--simple boundary--\r
This is the epilogue.  It is also to be ignored.
"
--- more_headers
Content-Type: multipart/mixed; boundary="simple boundary"
--- response_body
got the request socket
preamble: [This is the preamble.  It is to be ignored, though it
is a handy place for mail composers to include an
explanatory note to non-MIME compliant readers.]
part 1 body: [This is implicitly typed plain ASCII text.
It does NOT end with a linebreak.]
part 2 header: [Content-type: text/plain; charset=us-ascii]
part 2 body: [This is explicitly typed plain ASCII text.
It DOES end with a linebreak.
]
found the end of the stream
--- no_error_log
[error]



=== TEST 3: multipart rfc sample (completely streaming)
--- config
    location /t {
        rewrite_by_lua '
            local sock, err = ngx.req.socket()
            if sock then
                ngx.say("got the request socket")
            else
                ngx.say("failed to get the request socket: ", err)
            end

            local boundary
            local header = ngx.var.http_content_type
            local m = ngx.re.match(header, [[; +boundary=(?:"(.*?)"|(\\w+))]], "jo")
            if m then
                boundary = m[1] or m[2]

            else
                ngx.say("invalid content-type header")
                return
            end

            local read_to_boundary = sock:receiveuntil("\\r\\n--" .. boundary)
            local read_line = sock:receiveuntil("\\r\\n")

            local preamble = ""
            while true do
                local data, err, part = read_to_boundary(1)
                if data then
                    preamble = preamble .. data

                elseif not err then
                    break

                else
                    ngx.say("failed to read the first boundary: ", err)
                    return
                end
            end

            ngx.say("preamble: [" .. preamble .. "]")

            local i = 1
            while true do
                local line, err = read_line(50)

                if not line and err then
                    ngx.say("1: failed to read post-boundary line: ", err)
                    return
                end

                if line then
                    local dummy
                    dummy, err = read_line(1)
                    if err then
                        ngx.say("2: failed to read post-boundary line: ", err)
                        return
                    end

                    if dummy then
                        ngx.say("bad post-boundary line: ", dummy)
                        return
                    end

                    m = ngx.re.match(line, "--$", "jo")
                    if m then
                        ngx.say("found the end of the stream")
                        return
                    end
                end

                while true do
                    local line, err = read_line(50)
                    if not line and err then
                        ngx.say("failed to read part ", i, " header: ", err)
                        return
                    end

                    if line then
                        local line, err = read_line(1)
                        if line or err then
                            ngx.say("error")
                            return
                        end
                    end

                    if line == "" then
                        -- the header part completes
                        break
                    end

                    ngx.say("part ", i, " header: [", line, "]")
                end

                local body = ""

                while true do
                    local data, err, part = read_to_boundary(1)
                    if data then
                        body = body .. data

                    elseif err then
                        ngx.say("failed to read part ", i + 1, " boundary: ", err)
                        return

                    else
                        break
                    end
                end

                ngx.say("part ", i, " body: [" .. body .. "]")

                i = i + 1
            end
        ';

        content_by_lua return;
    }
--- request eval
"POST /t
This is the preamble.  It is to be ignored, though it
is a handy place for mail composers to include an
explanatory note to non-MIME compliant readers.\r
--simple boundary\r
\r
This is implicitly typed plain ASCII text.
It does NOT end with a linebreak.\r
--simple boundary\r
Content-type: text/plain; charset=us-ascii\r
\r
This is explicitly typed plain ASCII text.
It DOES end with a linebreak.
\r
--simple boundary--\r
This is the epilogue.  It is also to be ignored.
"
--- more_headers
Content-Type: multipart/mixed; boundary="simple boundary"
--- response_body
got the request socket
preamble: [This is the preamble.  It is to be ignored, though it
is a handy place for mail composers to include an
explanatory note to non-MIME compliant readers.]
part 1 body: [This is implicitly typed plain ASCII text.
It does NOT end with a linebreak.]
part 2 header: [Content-type: text/plain; charset=us-ascii]
part 2 body: [This is explicitly typed plain ASCII text.
It DOES end with a linebreak.
]
found the end of the stream
--- no_error_log
[error]



=== TEST 4: attempt to use the req socket across request boundary
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /t {
        rewrite_by_lua '
            local test = require "test"
            test.go()
            ngx.say("done")
        ';

        content_by_lua return;
    }
--- user_files
>>> test.lua
module("test", package.seeall)

local sock, err

function go()
    if not sock then
        sock, err = ngx.req.socket()
        if sock then
            ngx.say("got the request socket")
        else
            ngx.say("failed to get the request socket: ", err)
        end
    else
        for i = 1, 3 do
            local data, err, part = sock:receive(5)
            if data then
                ngx.say("received: ", data)
            else
                ngx.say("failed to receive: ", err, " [", part, "]")
            end
        end
    end
end
--- request
POST /t
hello world
--- response_body_like
(?:got the request socket
|failed to receive: closed [d]
)?done
--- no_error_log
[alert]



=== TEST 5: receive until on request_body - receiveuntil(1) on the last byte of the body
See https://groups.google.com/group/openresty/browse_thread/thread/43cf01da3c681aba for details
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /t {
        rewrite_by_lua '
            local test = require "test"
            test.go()
            ngx.say("done")
        ';

        content_by_lua return;
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go()
   local sock, err = ngx.req.socket()
   if sock then
      ngx.say("got the request socket")
   else
      ngx.say("failed to get the request socket: ", err)
      return
   end

   local data, err, part = sock:receive(56)
   if data then
      ngx.say("received: ", data)
   else
      ngx.say("failed to receive: ", err, " [", part, "]")
   end

   local discard_line = sock:receiveuntil('\r\n')

   local data, err, part = discard_line(8192)
   if data then
      ngx.say("received len: ", #data)
   else
      ngx.say("failed to receive: ", err, " [", part, "]")
   end

   local data, err, part = discard_line(1)
   if data then
      ngx.say("received: ", data)
   else
      ngx.say("failed to receive: ", err, " [", part, "]")
   end
end
--- request
POST /t
-----------------------------820127721219505131303151179################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################################$
--- response_body
got the request socket
received: -----------------------------820127721219505131303151179
received len: 8192
received: $
done
--- no_error_log
[error]
--- timeout: 10



=== TEST 6: pipelined POST requests
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /t {
        rewrite_by_lua '
            local test = require "test"
            test.go()
            ngx.say("done")
        ';

        content_by_lua return;
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go()
   local sock, err = ngx.req.socket()
   if sock then
      ngx.say("got the request socket")
   else
      ngx.say("failed to get the request socket: ", err)
      return
   end

   while true do
       local data, err, part = sock:receive(4)
       if data then
          ngx.say("received: ", data)
       else
          ngx.say("failed to receive: ", err, " [", part, "]")
          return
       end
   end
end
--- pipelined_requests eval
["POST /t
hello, world",
"POST /t
hiya, world"]
--- response_body eval
["got the request socket
received: hell
received: o, w
received: orld
failed to receive: closed []
done
",
"got the request socket
received: hiya
received: , wo
failed to receive: closed [rld]
done
"]
--- no_error_log
[error]



=== TEST 7: Expect & 100 Continue
--- config
    location /t {
        rewrite_by_lua '
            local sock, err = ngx.req.socket()
            if sock then
                ngx.say("got the request socket")
            else
                ngx.say("failed to get the request socket: ", err)
                return
            end

            for i = 1, 3 do
                local data, err, part = sock:receive(5)
                if data then
                    ngx.say("received: ", data)
                else
                    ngx.say("failed to receive: ", err, " [", part, "]")
                end
            end
        ';

        content_by_lua return;
    }
--- request
POST /t
hello world
--- more_headers
Expect: 100-Continue
--- error_code: 100
--- response_body_like chomp
\breceived: hello\b.*?\breceived:  worl\b
--- no_error_log
[error]
