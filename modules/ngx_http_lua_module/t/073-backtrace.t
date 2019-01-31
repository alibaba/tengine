# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * 51;

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /lua {
        content_by_lua
        '   local function bar()
                return lua_concat(3)
            end
            local function foo()
                bar()
            end
            foo()
        ';
    }
--- request
GET /lua
--- ignore_response
--- error_log
attempt to call global 'lua_concat'
: in function 'bar'
:5: in function 'foo'
:7: in main chunk



=== TEST 2: error(nil)
--- config
    location /lua {
        content_by_lua
        '   local function bar()
                error(nil)
            end
            local function foo()
                bar()
            end
            foo()
        ';
    }
--- request
GET /lua
--- ignore_response
--- error_log eval
[
'lua entry thread aborted: runtime error: unknown reason',
'stack traceback:',
" in function 'error'",
": in function 'bar'",
":5: in function 'foo'",
qr/:7: in main chunk/,
]



=== TEST 3: deep backtrace in a single coroutine (more than 15)
--- config eval
my $s = "
    location /lua {
        content_by_lua '
";
my $prev;
for my $i (1..18) {
    if (!defined $prev) {
        $s .= "
            local function func$i()
                return error([[blah]])
            end";
    } else {
        $s .= "
            local function func$i()
                local v = func$prev()
                return v
            end";
    }
    $prev = $i;
}
$s .= "
            func$prev()
        ';
    }
";
--- request
GET /lua
--- stap2
probe process("$LIBLUA_PATH").function("lua_concat") {
    println("lua concat")
    //print_ubacktrace()
}
--- stap_out2
--- ignore_response
--- error_log
: blah
: in function 'func1'
:7: in function 'func2'
:11: in function 'func3'
:15: in function 'func4'
:19: in function 'func5'
:23: in function 'func6'
:27: in function 'func7'
:31: in function 'func8'
:35: in function 'func9'
:39: in function 'func10'
:43: in function 'func11'
:47: in function 'func12'
:51: in function 'func13'
:55: in function 'func14'
:59: in function 'func15'
:63: in function 'func16'
:67: in function 'func17'
:71: in function 'func18'
:74: in main chunk



=== TEST 4: deep backtrace in a single coroutine (more than 22)
--- config eval
my $s = "
    location /lua {
        content_by_lua '
";
my $prev;
for my $i (1..23) {
    if (!defined $prev) {
        $s .= "
            local function func$i()
                return error([[blah]])
            end";
    } else {
        $s .= "
            local function func$i()
                local v = func$prev()
                return v
            end";
    }
    $prev = $i;
}
$s .= "
            func$prev()
        ';
    }
";
--- request
GET /lua
--- stap2
probe process("$LIBLUA_PATH").function("lua_concat") {
    println("lua concat")
    //print_ubacktrace()
}
--- stap_out2
--- ignore_response
--- error_log
: blah
: in function 'func1'
:7: in function 'func2'
:11: in function 'func3'
:15: in function 'func4'
:19: in function 'func5'
:23: in function 'func6'
:27: in function 'func7'
:31: in function 'func8'
:35: in function 'func9'
:39: in function 'func10'
:43: in function 'func11'
:47: in function 'func12'
:59: in function 'func15'
:63: in function 'func16'
:67: in function 'func17'
:71: in function 'func18'
:75: in function 'func19'
:79: in function 'func20'
:83: in function 'func21'
...
