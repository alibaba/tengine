use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

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

=== TEST 1: lua_load_resty_core is enabled by default
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



=== TEST 2: lua_load_resty_core can be disabled
--- http_config
    lua_load_resty_core off;
--- config
    location = /t {
        content_by_lua_block {
            local loaded_resty_core = package.loaded["resty.core"]

            ngx.say("resty.core loaded: ", loaded_resty_core ~= nil)
        }
    }
--- response_body
resty.core loaded: false



=== TEST 3: lua_load_resty_core is effective when using lua_shared_dict
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
