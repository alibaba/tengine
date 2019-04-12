# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

add_block_preprocessor(sub {
    my $block = shift;

    my $http_config = $block->http_config || '';

    $http_config .= <<_EOC_;
    init_by_lua_block {
        function test_sa_restart()
            local signals = {
                --"HUP",
                --"INFO",
                --"XCPU",
                --"USR1",
                --"USR2",
                "ALRM",
                --"INT",
                "IO",
                "CHLD",
                --"WINCH",
            }

            for _, signame in ipairs(signals) do
                local cmd = string.format("kill -s %s %d && sleep 0.01",
                                          signame, ngx.worker.pid())
                local err = select(2, io.popen(cmd):read("*a"))
                if err then
                    error("SIG" .. signame .. " caused: " .. err)
                end
            end
        end
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!defined $block->config) {
        my $config = <<_EOC_;
        location /t {
            echo ok;
        }
_EOC_

        $block->set_value("config", $config);
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->response_body) {
        $block->set_value("ignore_response_body");
    }

    if (!defined $block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

plan tests => repeat_each() * (blocks() * 2 + 1);

no_long_string();
run_tests();

__DATA__

=== TEST 1: lua_sa_restart default - sets SA_RESTART in init_worker_by_lua*
--- http_config
    init_worker_by_lua_block {
        test_sa_restart()
    }



=== TEST 2: lua_sa_restart off - does not set SA_RESTART
--- http_config
    lua_sa_restart off;

    init_worker_by_lua_block {
        test_sa_restart()
    }
--- no_error_log
[crit]
--- error_log
Interrupted system call



=== TEST 3: lua_sa_restart on (default) - sets SA_RESTART if no init_worker_by_lua* phase is defined
--- config
    location /t {
        content_by_lua_block {
            test_sa_restart()
        }
    }



=== TEST 4: lua_sa_restart on (default) - SA_RESTART is effective in rewrite_by_lua*
--- config
    location /t {
        rewrite_by_lua_block {
            test_sa_restart()
        }

        echo ok;
    }



=== TEST 5: lua_sa_restart on (default) - SA_RESTART is effective in access_by_lua*
--- config
    location /t {
        access_by_lua_block {
            test_sa_restart()
        }

        echo ok;
    }



=== TEST 6: lua_sa_restart on (default) - SA_RESTART is effective in content_by_lua*
--- config
    location /t {
        content_by_lua_block {
            test_sa_restart()
        }
    }



=== TEST 7: lua_sa_restart on (default) - SA_RESTART is effective in header_filter_by_lua*
--- config
    location /t {
        echo ok;

        header_filter_by_lua_block {
            test_sa_restart()
        }
    }



=== TEST 8: lua_sa_restart on (default) - SA_RESTART is effective in body_filter_by_lua*
--- config
    location /t {
        echo ok;

        body_filter_by_lua_block {
            test_sa_restart()
        }
    }



=== TEST 9: lua_sa_restart on (default) - SA_RESTART is effective in log_by_lua*
--- config
    location /t {
        echo ok;

        log_by_lua_block {
            test_sa_restart()
        }
    }



=== TEST 10: lua_sa_restart on (default) - SA_RESTART is effective in timer phase
--- config
    location /t {
        echo ok;

        log_by_lua_block {
            ngx.timer.at(0, test_sa_restart)
        }
    }
