# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

our $HtmlDir = html_dir;

add_block_preprocessor(sub {
    my $block = shift;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

no_long_string();
run_tests();

__DATA__

=== TEST 1: resty.core is automatically loaded in the Lua VM
--- config
    location = /t {
        content_by_lua_block {
            local loaded_resty_core = package.loaded["resty.core"]
            local resty_core = require "resty.core"

            ngx.say("resty.core loaded: ", loaded_resty_core == resty_core)
        }
    }
--- response_body
resty.core loaded: true



=== TEST 2: resty.core is automatically loaded in the Lua VM when 'lua_shared_dict' is used
--- http_config
    lua_shared_dict dogs 128k;
--- config
    location = /t {
        content_by_lua_block {
            local loaded_resty_core = package.loaded["resty.core"]
            local resty_core = require "resty.core"

            ngx.say("resty.core loaded: ", loaded_resty_core == resty_core)
        }
    }
--- response_body
resty.core loaded: true



=== TEST 3: resty.core is automatically loaded in the Lua VM with 'lua_code_cache off'
--- http_config
    lua_code_cache off;
--- config
    location = /t {
        content_by_lua_block {
            local loaded_resty_core = package.loaded["resty.core"]
            local resty_core = require "resty.core"

            ngx.say("resty.core loaded: ", loaded_resty_core == resty_core)
        }
    }
--- response_body
resty.core loaded: true



=== TEST 4: resty.core loading honors the lua_package_path directive
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;;';"
--- config
    location = /t {
        content_by_lua_block {
            local loaded_resty_core = package.loaded["resty.core"]
            local resty_core = require "resty.core"

            ngx.say("resty.core loaded: ", loaded_resty_core == resty_core)

            resty_core.go()
        }
    }
--- response_body
resty.core loaded: true
loaded from html dir
--- user_files
>>> resty/core.lua
return {
    go = function ()
        ngx.say("loaded from html dir")
    end
}



=== TEST 5: resty.core not loading aborts the initialization
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;';"
--- config
    location = /t {
        return 200;
    }
--- must_die
--- error_log eval
qr/\[alert\] .*? failed to load the 'resty\.core' module .*? \(reason: module 'resty\.core' not found:/



=== TEST 6: resty.core not loading produces an error with 'lua_code_cache off'
--- http_config
    lua_code_cache off;

    init_by_lua_block {
        package.path = ""
    }
--- config
    location = /t {
        content_by_lua_block {
            ngx.say("ok")
        }
    }
--- error_code: 500
--- error_log eval
qr/\[error\] .*? failed to load the 'resty\.core' module .*? \(reason: module 'resty\.core' not found:/
--- no_error_log eval
qr/\[alert\] .*? failed to load the 'resty\.core' module/



=== TEST 7: lua_load_resty_core logs a deprecation warning when specified (on)
--- http_config
    lua_load_resty_core on;
--- config
    location = /t {
        return 200;
    }
--- grep_error_log eval: qr/\[warn\] .*? lua_load_resty_core is deprecated.*/
--- grep_error_log_out eval
[
qr/\[warn\] .*? lua_load_resty_core is deprecated \(the lua-resty-core library is required since ngx_lua v0\.10\.16\) in .*?nginx\.conf:\d+/,
""
]



=== TEST 8: lua_load_resty_core logs a deprecation warning when specified (off)
--- http_config
    lua_load_resty_core off;
--- config
    location = /t {
        return 200;
    }
--- grep_error_log eval: qr/\[warn\] .*? lua_load_resty_core is deprecated.*/
--- grep_error_log_out eval
[
qr/\[warn\] .*? lua_load_resty_core is deprecated \(the lua-resty-core library is required since ngx_lua v0\.10\.16\) in .*?nginx\.conf:\d+/,
""
]
