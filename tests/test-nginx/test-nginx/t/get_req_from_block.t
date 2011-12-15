# Unit tests for Test::Nginx::Socket::get_req_from_block
use Test::Nginx::Socket tests => 7;

my @block_list = blocks();
my $i = 0;  # Use $i to make copy/paste of tests easier.
is_deeply(Test::Nginx::Socket::get_req_from_block($block_list[$i]),
          [[{value => "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: Close\r\n\r\n"}]],
          $block_list[$i++]->name);
is_deeply(Test::Nginx::Socket::get_req_from_block($block_list[$i]),
          [[{value => "POST /rrd/taratata HTTP/1.1\r\nHost: localhost\r\nConnection: Close"
            ."\r\nContent-Length: 15\r\n\r\nvalue=N%3A12345"}]],
          $block_list[$i++]->name);
is_deeply(Test::Nginx::Socket::get_req_from_block($block_list[$i]),
          [[{ value => "HEAD /foo HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n".
            "GET /bar HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"}]],
          $block_list[$i++]->name);
is_deeply(Test::Nginx::Socket::get_req_from_block($block_list[$i]),
          [[{ value => "POST /foo HTTP/1.1\r
Host: localhost\r
Connection: Close\r
Content-Type: application/x-www-form-urlencoded\r
Content-Length:3\r\n\r\nA"}, {value =>"B"},
{value =>"C"}]],
          $block_list[$i++]->name);
is_deeply(Test::Nginx::Socket::get_req_from_block($block_list[$i]),
          [[{value =>"POST /foo HTTP/7.33 whatever\r\n".
                     "noheader\r\n\r\nrub my face in the dirt"}]],
          $block_list[$i++]->name);
is_deeply(Test::Nginx::Socket::get_req_from_block($block_list[$i]),
          [[{value =>"POST /foo HTTP/1.1\r\nHost: localhost\r\nConnection: Close\r\nContent-Length: 15\r\n\r\nv"},
            {value =>"alue=N%3A12345"}],
           [{value =>"GET /foo HTTP/1.1\r\nHost: localhost\r\nConnection: Close\r\n\r\n"}]],
          $block_list[$i++]->name);
is_deeply(Test::Nginx::Socket::get_req_from_block($block_list[$i]),
          [[{value =>"POST /foo HTTP/1.1\r\nHost: localhost\r\nConnection: Close\r\nContent-Length: 15\r\n\r\n"},
            {value =>"value=N%3A12345", delay_before => 3}],
           [{value =>"GET "},
            {value =>"/foo HTTP/1.1\r\nHost: localhost\r\nConnection: Close\r\n\r\n"}]],
          $block_list[$i++]->name);
__DATA__

=== request: basic string
--- request
GET /
=== request: with eval
--- request eval
use URI::Escape;
"POST /rrd/taratata
value=".uri_escape("N:12345")
=== pipelined_requests: simple array
--- pipelined_requests eval
["HEAD /foo", "GET /bar"]
=== raw_request: array
--- raw_request eval
["POST /foo HTTP/1.1\r
Host: localhost\r
Connection: Close\r
Content-Type: application/x-www-form-urlencoded\r
Content-Length:3\r\n\r\nA",
"B",
"C"]
=== raw_request: string
--- raw_request eval
"POST /foo HTTP/7.33 whatever\r
noheader\r
\r
rub my face in the dirt"
=== request: an array of requests without delays.
--- request eval
[["POST /foo\r\nv", "alue=N%3A12345"], "GET /foo"]
=== request: an array of requests with delays.
--- request eval
[["POST /foo\r\n", {value => "value=N%3A12345", delay_before =>3}],
 [{value => "GET "}, {value => "/foo"}]]
