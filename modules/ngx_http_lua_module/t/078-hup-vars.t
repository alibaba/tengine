# vim:set ft= ts=4 sw=4 et fdm=marker:

our $SkipReason;

BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use Test::Nginx::Socket::Lua $SkipReason ? (skip_all => $SkipReason) : ();

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('debug');

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

#no_diff();
#no_long_string();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: nginx variable hup bug (step 1)
http://mailman.nginx.org/pipermail/nginx-devel/2012-May/002223.html
--- config
    location /t {
        set $vv $http_host;
        set_by_lua $i 'return ngx.var.http_host';
        echo $i;
    }
--- request
GET /t
--- response_body
localhost
--- no_error_log
[error]



=== TEST 2: nginx variable hup bug (step 2)
http://mailman.nginx.org/pipermail/nginx-devel/2012-May/002223.html
--- config
    location /t {
        #set $vv $http_host;
        set_by_lua $i 'return ngx.var.http_host';
        echo $i;
    }
--- request
GET /t
--- response_body
localhost
--- no_error_log
[error]
