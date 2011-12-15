# Unit tests for Test::Nginx::Socket::parse_request
use Test::Nginx::Socket tests => 8;

my $name = "GET only default";
is_deeply(Test::Nginx::Socket::parse_request($name, \"GET"),
          {method => 'GET', url=> '/', http_ver =>'HTTP/1.1', content => '',
           skipped_before_method => 0, method_size => 3, skipped_after_method => 0,
           url_size => 0, skipped_after_url => 0,
           http_ver_size => 0, skipped_after_http_ver => 0, content_size => 0
          },
          $name);
$name = "GET with URL";
is_deeply(Test::Nginx::Socket::parse_request($name, \"GET /foo"),
          {method => 'GET', url=> '/foo', http_ver =>'HTTP/1.1', content => '',
           skipped_before_method => 0, method_size => 3, skipped_after_method => 1,
           url_size => 4, skipped_after_url => 0,
           http_ver_size => 0, skipped_after_http_ver => 0, content_size => 0
          },
          $name);
$name = "GET with URL and version";
is_deeply(Test::Nginx::Socket::parse_request($name, \"GET /foo HTTP/7.33"),
          {method => 'GET', url=> '/foo', http_ver =>'HTTP/7.33', content => '',
           skipped_before_method => 0, method_size => 3, skipped_after_method => 1,
           url_size => 4, skipped_after_url => 1,
           http_ver_size => 9, skipped_after_http_ver => 0, content_size => 0
          },
          $name);
$name = "Playing with spaces";
is_deeply(Test::Nginx::Socket::parse_request($name, \"GET   /foo  HTTP/7.33  "),
          {method => 'GET', url=> '/foo', http_ver =>'HTTP/7.33', content => '',
           skipped_before_method => 0, method_size => 3, skipped_after_method => 3,
           url_size => 4, skipped_after_url => 2,
           http_ver_size => 9, skipped_after_http_ver => 2, content_size => 0
          },
          $name);
$name = "Content";
is_deeply(Test::Nginx::Socket::parse_request($name, \"POST /foo HTTP/1.1\r\nABC"),
          {method => 'POST', url=> '/foo', http_ver =>'HTTP/1.1', content => 'ABC',
           skipped_before_method => 0, method_size => 4, skipped_after_method => 1,
           url_size => 4, skipped_after_url => 1,
           http_ver_size => 8, skipped_after_http_ver => 2, content_size => 3
          },
          $name);
$name = "Content with only LF";
is_deeply(Test::Nginx::Socket::parse_request($name, \"POST /foo HTTP/1.1\nABC"),
          {method => 'POST', url=> '/foo', http_ver =>'HTTP/1.1', content => 'ABC',
           skipped_before_method => 0, method_size => 4, skipped_after_method => 1,
           url_size => 4, skipped_after_url => 1,
           http_ver_size => 8, skipped_after_http_ver => 1, content_size => 3
          },
          $name);
$name = "Content without version";
is_deeply(Test::Nginx::Socket::parse_request($name, \"POST /foo\r\nABC"),
          {method => 'POST', url=> '/foo', http_ver =>'HTTP/1.1', content => 'ABC',
           skipped_before_method => 0, method_size => 4, skipped_after_method => 1,
           url_size => 4, skipped_after_url => 0,
           http_ver_size => 0, skipped_after_http_ver => 2, content_size => 3
          },
          $name);
$name = "Leading spaces";
is_deeply(Test::Nginx::Socket::parse_request($name, \"    HEAD /rrd"),
          {method => 'HEAD', url=> '/rrd', http_ver =>'HTTP/1.1', content => '',
           skipped_before_method => 4, method_size => 4, skipped_after_method => 1,
           url_size => 4, skipped_after_url => 0,
           http_ver_size => 0, skipped_after_http_ver => 0, content_size => 0
          },
          $name);
