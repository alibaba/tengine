# vim:set ft= ts=4 sw=4 et fdm=marker:

BEGIN {
    if (!defined $ENV{LD_PRELOAD}) {
        $ENV{LD_PRELOAD} = '';
    }

    if ($ENV{LD_PRELOAD} !~ /\bmockeagain\.so\b/) {
        $ENV{LD_PRELOAD} = "mockeagain.so $ENV{LD_PRELOAD}";
    }

    if ($ENV{MOCKEAGAIN} eq 'r') {
        $ENV{MOCKEAGAIN} = 'rw';

    } else {
        $ENV{MOCKEAGAIN} = 'w';
    }

    $ENV{TEST_NGINX_EVENT_TYPE} = 'poll';
    $ENV{MOCKEAGAIN_WRITE_TIMEOUT_PATTERN} = 'slow';
}

use Test::Nginx::Socket::Lua;

log_level('debug');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2);

run_tests();

__DATA__

=== TEST 1: raw downstream cosocket used in two different threads. See issue #481
--- config
    lua_socket_read_timeout 1ms;
    lua_socket_send_timeout 1s;
    lua_socket_log_errors off;

    location /t {
        content_by_lua '
            local function reader(req_socket)
               -- First we receive in a blocking fashion so that ctx->downstream_co_ctx will be changed
               local data, err, partial = req_socket:receive(1)
               if err ~= "timeout" then
                  ngx.log(ngx.ERR, "Did not get timeout in the receiving thread!")
                  return
               end

               -- Now, sleep so that coctx->data is changed to sleep handler
               ngx.sleep(1)
            end

            local function writer(req_socket)
               -- send in a slow manner with a low timeout, so that the timeout handler will be
               local bytes, err = req_socket:send("slow!!!")
               if err ~= "timeout" then
                  return error("Did not get timeout in the sending thread!")
               end
            end

            local req_socket, err = ngx.req.socket(true)
            if req_socket == nil then
               ngx.status = 500
               return error("Unable to get request socket:" .. (err or "nil"))
            end

            local writer_thread = ngx.thread.spawn(writer, req_socket)
            local reader_thread = ngx.thread.spawn(reader, req_socket)

            ngx.thread.wait(writer_thread)
            ngx.thread.wait(reader_thread)
            print("The two threads finished")
';
        }
--- request
POST /t
--- more_headers
Content-Length: 1
--- no_error_log
[error]
--- error_log: The two threads finished
--- wait: 0.1
--- ignore_response
--- timeout: 10



=== TEST 2: normal downstream cosocket used in two different threads. See issue #481
--- config
    lua_socket_read_timeout 1ms;
    lua_socket_send_timeout 1s;
    lua_socket_log_errors off;
    send_timeout 1s;

    location /t {
        content_by_lua '
            local function reader(req_socket)
               -- First we receive in a blocking fashion so that ctx->downstream_co_ctx will be changed
               local data, err, partial = req_socket:receive(1)
               if err ~= "timeout" then
                  ngx.log(ngx.ERR, "Did not get timeout in the receiving thread!")
                  return
               end

               -- Now, sleep so that coctx->data is changed to sleep handler
               ngx.sleep(1)
            end

            local function writer(req_socket)
               -- send in a slow manner with a low timeout, so that the timeout handler will be
               ngx.sleep(0.3)
               ngx.say("slow!!!")
               ngx.flush(true)
            end

            local req_socket, err = ngx.req.socket()
            if req_socket == nil then
               ngx.status = 500
               return error("Unable to get request socket:" .. (err or "nil"))
            end

            local writer_thread = ngx.thread.spawn(writer, req_socket)
            local reader_thread = ngx.thread.spawn(reader, req_socket)

            ngx.thread.wait(writer_thread)
            ngx.thread.wait(reader_thread)
            print("The two threads finished")
';
        }
--- request
POST /t
--- more_headers
Content-Length: 1
--- no_error_log
[error]
--- error_log: The two threads finished
--- wait: 0.1
--- ignore_response
--- timeout: 10
