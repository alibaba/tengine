# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua
    skip_all => 'no mmap(sbrk(0)) trick since glibc leaks memory in this case';

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: avoid the data segment from growing on Linux
This is to maximize the address space that can be used by LuaJIT.
--- config
    location = /t {
        content_by_lua_block {
            local ffi = require "ffi"
            ffi.cdef[[
                void *malloc(size_t size);
                void free(void *p);
            ]]
            local p = ffi.C.malloc(1);
            local num = tonumber(ffi.cast("uintptr_t", p))
            ffi.C.free(p)
            if ffi.abi("64bit") then
                if num < 2^31 then
                    ngx.say("fail: ", string.format("p = %#x", num))
                    return
                end
            end
            ngx.say("pass")
        }
    }
--- request
GET /t
--- response_body
pass
--- no_error_log
[error]
