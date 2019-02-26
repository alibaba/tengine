# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: bytecode ("ngx.say('hello');")
--- config
    root html;
    location /save_call {
        content_by_lua '
            ngx.req.read_body();
            local b = ngx.req.get_body_data();
            local f = io.open(ngx.var.realpath_root.."/test.lua", "w");
            -- luajit bytecode: sub(149,-1), lua bytecode: sub(1,147)
            if jit then
                if not string.find(jit.version, "LuaJIT 2.0") then
                    ngx.say("test skipped")
                    return
                end
                f:write(string.sub(b, 149));
            else
                f:write(string.sub(b, 1, 147));
            end
            f:close();
            local res = ngx.location.capture("/call");
            ngx.print(res.body)
        ';
    }
    location /call {
        content_by_lua_file $realpath_root/test.lua;
    }
--- request eval
"POST /save_call
\x1b\x4c\x75\x61\x51\x00\x01\x04\x08\x04\x08\x00\x0a\x00\x00\x00\x00\x00\x00\x00\x40\x74\x65\x73\x74\x2e\x6c\x75\x61\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x02\x05\x00\x00\x00\x05\x00\x00\x00\x06\x40\x40\x00\x41\x80\x00\x00\x1c\x40\x00\x01\x1e\x00\x80\x00\x03\x00\x00\x00\x04\x04\x00\x00\x00\x00\x00\x00\x00\x6e\x67\x78\x00\x04\x04\x00\x00\x00\x00\x00\x00\x00\x73\x61\x79\x00\x04\x06\x00\x00\x00\x00\x00\x00\x00\x68\x65\x6c\x6c\x6f\x00\x00\x00\x00\x00\x05\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x1b\x4c\x4a\x01\x02\x29\x02\x00\x02\x00\x03\x00\x05\x34\x00\x00\x00\x37\x00\x01\x00\x25\x01\x02\x00\x3e\x00\x02\x01\x47\x00\x01\x00\x0a\x68\x65\x6c\x6c\x6f\x08\x73\x61\x79\x08\x6e\x67\x78\x00"
--- response_body_like chop
^(?:hello|test skipped)$
--- no_error_log
[error]



=== TEST 2: luajit load lua bytecode or lua load luajit bytecode
--- config
    root html;
    location /save_call {
        content_by_lua '
            ngx.req.read_body();
            local b = ngx.req.get_body_data();
            local f = io.open(ngx.var.realpath_root.."/test.lua", "w");
            -- luajit bytecode: sub(149,-1), lua bytecode: sub(1,147)
            if not package.loaded["jit"] then
                f:write(string.sub(b, 149));
            else
                f:write(string.sub(b, 1, 147));
            end
            f:close();
            local res = ngx.location.capture("/call");
            if res.status == 200 then
                ngx.print(res.body)
            else
                ngx.say("error")
            end
        ';
    }
    location /call {
        content_by_lua_file $realpath_root/test.lua;
    }
--- request eval
"POST /save_call
\x1b\x4c\x75\x61\x51\x00\x01\x04\x08\x04\x08\x00\x0a\x00\x00\x00\x00\x00\x00\x00\x40\x74\x65\x73\x74\x2e\x6c\x75\x61\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x02\x05\x00\x00\x00\x05\x00\x00\x00\x06\x40\x40\x00\x41\x80\x00\x00\x1c\x40\x00\x01\x1e\x00\x80\x00\x03\x00\x00\x00\x04\x04\x00\x00\x00\x00\x00\x00\x00\x6e\x67\x78\x00\x04\x04\x00\x00\x00\x00\x00\x00\x00\x73\x61\x79\x00\x04\x06\x00\x00\x00\x00\x00\x00\x00\x68\x65\x6c\x6c\x6f\x00\x00\x00\x00\x00\x05\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x1b\x4c\x4a\x01\x02\x29\x02\x00\x02\x00\x03\x00\x05\x34\x00\x00\x00\x37\x00\x01\x00\x25\x01\x02\x00\x3e\x00\x02\x01\x47\x00\x01\x00\x0a\x68\x65\x6c\x6c\x6f\x08\x73\x61\x79\x08\x6e\x67\x78\x00"
--- response_body
error
--- error_log eval
qr/failed to load external Lua file ".*?test\.lua": .* cannot load incompatible bytecode/



=== TEST 3: unknown bytecode version
--- config
    root html;
    location /save_call {
        content_by_lua '
            ngx.req.read_body();
            local b = ngx.req.get_body_data();
            local f = io.open(ngx.var.realpath_root.."/test.lua", "w");
            -- luajit bytecode: sub(149,-1), lua bytecode: sub(1,147)
            if package.loaded["jit"] then
                f:write(string.sub(b, 149));
            else
                f:write(string.sub(b, 1, 147));
            end
            f:close();
            local res = ngx.location.capture("/call");
            if res.status == 200 then
                ngx.print(res.body)
            else
                ngx.say("error")
            end
        ';
    }
    location /call {
        content_by_lua_file $realpath_root/test.lua;
    }
--- request eval
"POST /save_call
\x1b\x4c\x75\x61\x52\x00\x01\x04\x08\x04\x08\x00\x0a\x00\x00\x00\x00\x00\x00\x00\x40\x74\x65\x73\x74\x2e\x6c\x75\x61\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x02\x05\x00\x00\x00\x05\x00\x00\x00\x06\x40\x40\x00\x41\x80\x00\x00\x1c\x40\x00\x01\x1e\x00\x80\x00\x03\x00\x00\x00\x04\x04\x00\x00\x00\x00\x00\x00\x00\x6e\x67\x78\x00\x04\x04\x00\x00\x00\x00\x00\x00\x00\x73\x61\x79\x00\x04\x06\x00\x00\x00\x00\x00\x00\x00\x68\x65\x6c\x6c\x6f\x00\x00\x00\x00\x00\x05\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x1b\x4c\x4a\x80\x02\x29\x02\x00\x02\x00\x03\x00\x05\x34\x00\x00\x00\x37\x00\x01\x00\x25\x01\x02\x00\x3e\x00\x02\x01\x47\x00\x01\x00\x0a\x68\x65\x6c\x6c\x6f\x08\x73\x61\x79\x08\x6e\x67\x78\x00"
--- response_body
error
--- error_log
cannot load incompatible bytecode



=== TEST 4: bytecode (big endian)
--- config
    root html;
    location /save_call {
        content_by_lua '
            ngx.req.read_body();
            local b = ngx.req.get_body_data();
            local f = io.open(ngx.var.realpath_root.."/test.lua", "w");
            -- luajit bytecode: sub(149,-1), lua bytecode: sub(1,147)
            local do_jit
            if jit then
                if not string.find(jit.version, "LuaJIT 2.0") then
                    ngx.say("test skipped")
                    return
                end

                do_jit = true; f:write(string.sub(b, 149));
            else
                f:write(string.sub(b, 1, 147));
            end
            f:close(); res = ngx.location.capture("/call");
            if do_jit and res.status == 200 then
                ngx.say("ok")
            elseif not do_jit and res.status == 500 then
                ngx.say("ok")
            else
                ngx.say("error")
            end
        ';
    }
    location /call {
        content_by_lua_file $realpath_root/test.lua;
    }
--- request eval
"POST /save_call
\x1b\x4c\x75\x61\x51\x00\x00\x04\x08\x04\x08\x00\x0a\x00\x00\x00\x00\x00\x00\x00\x40\x74\x65\x73\x74\x2e\x6c\x75\x61\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x02\x05\x00\x00\x00\x05\x00\x00\x00\x06\x40\x40\x00\x41\x80\x00\x00\x1c\x40\x00\x01\x1e\x00\x80\x00\x03\x00\x00\x00\x04\x04\x00\x00\x00\x00\x00\x00\x00\x6e\x67\x78\x00\x04\x04\x00\x00\x00\x00\x00\x00\x00\x73\x61\x79\x00\x04\x06\x00\x00\x00\x00\x00\x00\x00\x68\x65\x6c\x6c\x6f\x00\x00\x00\x00\x00\x05\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x1b\x4c\x4a\x01\x03\x29\x02\x00\x02\x00\x03\x00\x05\x00\x00\x00\x34\x00\x01\x00\x37\x00\x02\x01\x25\x01\x02\x00\x3e\x00\x01\x00\x47\x0a\x68\x65\x6c\x6c\x6f\x08\x73\x61\x79\x08\x6e\x67\x78\x00"
--- response_body_like chop
^(?:ok|test skipped)$
--- no_error_log
[error]



=== TEST 5: good header but bad body
--- config
    root html;
    location /save_call {
        content_by_lua '
            ngx.req.read_body();
            local b = ngx.req.get_body_data();
            local f = io.open(ngx.var.realpath_root.."/test.lua", "w");
            -- luajit bytecode: sub(149,-1), lua bytecode: sub(1,147)
            local jit;
            if package.loaded["jit"] then
                jit = true;
                f:write(string.sub(b, 149));
            else
                f:write(string.sub(b, 1, 147));
            end
            if not jit then
                f:close(); res = ngx.location.capture("/call");
                if res.status == 200 then
                    ngx.print("ok")
                else
                    ngx.say("error")
                end
            else
            -- luajit will get a segmentation fault with bad bytecode,
            -- so here just skip this case for luajit
                ngx.say("error")
            end
        ';
    }
    location /call {
        content_by_lua_file $realpath_root/test.lua;
    }
--- request eval
"POST /save_call
\x1b\x4c\x75\x61\x51\x00\x01\x04\x08\x04\x08\x00\x0a\x00\x00\x00\x00\x00\x00\x00\x40\x74\x65\x73\x74\x2e\x6c\x75\x61\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x02\x05\x00\x00\x00\xff\xff\xff\xff\x06\x40\x40\x00\x41\x80\x00\x00\x1c\x40\x00\x01\x1e\x00\x80\x00\x03\x00\x00\x00\x04\x04\x00\x00\x00\x00\x00\x00\x00\x6e\x67\x78\x00\x04\x04\x00\x00\x00\x00\x00\x00\x00\x73\x61\x79\x00\x04\x06\x00\x00\x00\x00\x00\x00\x00\x68\x65\x6c\x6c\x6f\x00\x00\x00\x00\x00\x05\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x1b\x4c\x4a\x01\x02\x29\x02\x00\x02\x00\x03\x00\x05\xff\xff\xff\xff\x37\x00\x01\x00\x25\x01\x02\x00\x3e\x00\x02\x01\x47\x00\x01\x00\x0a\x68\x65\x6c\x6c\x6f\x08\x73\x61\x79\x08\x6e\x67\x78\x00"
--- response_body
error
--- no_error_log
[error]



=== TEST 6: stripped(lua) & no stripped(luajit)
--- config
    root html;
    location /save_call {
        content_by_lua '
            ngx.req.read_body();
            local b = ngx.req.get_body_data();
            local f = io.open(ngx.var.realpath_root.."/test.lua", "w");
            -- luajit bytecode: sub(149,-1), lua bytecode: sub(1,147)
            if jit then
                if not string.find(jit.version, "LuaJIT 2.0") then
                    ngx.say("test skipped")
                    return
                end

                f:write(string.sub(b, 119));
            else
                f:write(string.sub(b, 1, 117));
            end
            f:close(); res = ngx.location.capture("/call");
            ngx.print(res.body)
        ';
    }
    location /call {
        content_by_lua_file $realpath_root/test.lua;
    }
--- request eval
"POST /save_call
\x1b\x4c\x75\x61\x51\x00\x01\x04\x08\x04\x08\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x02\x05\x00\x00\x00\x05\x00\x00\x00\x06\x40\x40\x00\x41\x80\x00\x00\x1c\x40\x00\x01\x1e\x00\x80\x00\x03\x00\x00\x00\x04\x04\x00\x00\x00\x00\x00\x00\x00\x6e\x67\x78\x00\x04\x04\x00\x00\x00\x00\x00\x00\x00\x73\x61\x79\x00\x04\x06\x00\x00\x00\x00\x00\x00\x00\x68\x65\x6c\x6c\x6f\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x1b\x4c\x4a\x01\x00\x09\x40\x74\x65\x73\x74\x2e\x6c\x75\x61\x32\x02\x00\x02\x00\x03\x00\x05\x06\x00\x02\x34\x00\x00\x00\x37\x00\x01\x00\x25\x01\x02\x00\x3e\x00\x02\x01\x47\x00\x01\x00\x0a\x68\x65\x6c\x6c\x6f\x08\x73\x61\x79\x08\x6e\x67\x78\x01\x01\x01\x01\x01\x00\x00"
--- response_body_like chop
^(?:hello|test skipped)$
--- no_error_log
[error]



=== TEST 7: generate & load bytecode for LuaJIT (stripped)
--- config
    location = /t {
        content_by_lua '
            local bcsave = require "jit.bcsave"
            if jit then
                local prefix = "$TEST_NGINX_SERVER_ROOT"
                local infile = prefix .. "/html/a.lua"
                local outfile = prefix .. "/html/a.luac"
                bcsave.start("-s", infile, outfile)
                return ngx.exec("/call")
            end

            ngx.say("test skipped!")
        ';
    }
    location = /call {
        content_by_lua_file html/a.luac;
    }
--- request
    GET /t

--- user_files
>>> a.lua
ngx.status = 201 ngx.say("hello from Lua!")
--- response_body_like chop
^(?:hello from Lua!|test skipped!)$
--- no_error_log
[error]
--- error_code: 201



=== TEST 8: generate & load bytecode for LuaJIT (not stripped)
--- config
    location = /t {
        content_by_lua '
            local bcsave = require "jit.bcsave"
            if jit then
                local prefix = "$TEST_NGINX_SERVER_ROOT"
                local infile = prefix .. "/html/a.lua"
                local outfile = prefix .. "/html/a.luac"
                bcsave.start("-g", infile, outfile)
                return ngx.exec("/call")
            end

            ngx.say("test skipped!")
        ';
    }
    location = /call {
        content_by_lua_file html/a.luac;
    }
--- request
    GET /t

--- user_files
>>> a.lua
ngx.status = 201 ngx.say("hello from Lua!")
--- response_body_like chop
^(?:hello from Lua!|test skipped!)$
--- no_error_log
[error]
--- error_code: 201



=== TEST 9: bytecode (not stripped)
--- config
    location = /t {
        content_by_lua_block {
            local f = assert(loadstring("local a = 1 ngx.say('a = ', a)", "=code"))
            local bc = string.dump(f)
            local f = assert(io.open("$TEST_NGINX_SERVER_ROOT/html/a.luac", "w"))
            f:write(bc)
            f:close()
        }
    }

    location = /t2 {
        content_by_lua_file html/a.luac;
    }

    location = /main {
        echo_location /t;
        echo_location /t2;
    }
--- request
GET /main
--- response_body
a = 1
--- no_error_log
[error]



=== TEST 10: bytecode (stripped)
--- config
    location = /t {
        content_by_lua_block {
            local f = assert(loadstring("local a = 1 ngx.say('a = ', a)", "=code"))
            local bc = string.dump(f, true)
            local f = assert(io.open("$TEST_NGINX_SERVER_ROOT/html/a.luac", "w"))
            f:write(bc)
            f:close()
        }
    }

    location = /t2 {
        content_by_lua_file html/a.luac;
    }

    location = /main {
        echo_location /t;
        echo_location /t2;
    }
--- request
GET /main
--- response_body
a = 1
--- no_error_log
[error]
