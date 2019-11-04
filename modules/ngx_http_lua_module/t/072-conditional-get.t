# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;
use t::StapThread;

our $GCScript = $t::StapThread::GCScript;
our $StapScript = $t::StapThread::StapScript;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: If-Modified-Since true
--- config
    location /lua {
        content_by_lua '
            ngx.header.last_modified = "Thu, 10 May 2012 07:50:59 GMT"
            ngx.say("hello")
        ';
    }
--- request
GET /lua
--- more_headers
If-Modified-Since: Thu, 10 May 2012 07:50:59 GMT
--- response_body
--- error_code: 304
--- no_error_log
[error]



=== TEST 2: If-Modified-Since true
--- config
    location /lua {
        if_modified_since before;
        content_by_lua '
            ngx.header.last_modified = "Thu, 10 May 2012 07:50:48 GMT"
            ngx.say("hello")
        ';
    }
--- request
GET /lua
--- more_headers
If-Modified-Since: Thu, 10 May 2012 07:50:59 GMT
--- response_body
--- error_code: 304
--- no_error_log
[error]



=== TEST 3: If-Unmodified-Since false
--- config
    location /lua {
        #if_modified_since before;
        content_by_lua '
            ngx.header.last_modified = "Thu, 10 May 2012 07:50:48 GMT"
            local ok, err = ngx.say("hello")
            if not ok then
                ngx.log(ngx.WARN, "say failed: ", err)
            end
        ';
    }
--- request
GET /lua
--- more_headers
If-Unmodified-Since: Thu, 10 May 2012 07:50:47 GMT

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
terminate 1: ok
delete thread 1

--- response_body_like: 412 Precondition Failed
--- error_code: 412
--- error_log
say failed: nginx output filter error
--- no_error_log
[error]
