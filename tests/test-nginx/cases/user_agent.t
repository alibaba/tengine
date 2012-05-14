use lib 'lib';
use Test::Nginx::Socket;
plan tests => blocks() * 2;
run_tests();
__DATA__

=== TEST 2:2
--- http_config
   user_agent $browser {
       default                                    1;
       greedy                                     safari;
       greedy                                     Safari;

       Chrome         12.0.742.112~15.0.872.0       4;
       Firefox        5.0+                          5;
       Opera          12.00-                        6;
       MSIE           9.0                           7;
   }
--- config
       location /exact {
           if ($browser = 1) {
               echo "msie6";
           }

           if ($browser = 4) {
               echo "Chrome";
           }

           if ($browser = 5) {
               echo "Firefox";
           }

           if ($browser = 6) {
               echo "Opera";
           }

           if ($browser = 7) {
               echo "msie9";
           }
       }
--- request
   GET /exact
--- more_headers
User-Agent: Mozilla/5.0 (X11; Linux i686; rv:6.0) Gecko/20100101 Firefox/6.0
--- response_body
Firefox

=== TEST 3:3
--- http_config
   user_agent $browser {
       default                                     1;
       greedy                                      safari;
       greedy                                      Safari;

       Chrome         12.0.742.112~15.0.872.0       4;
       Firefox        5.0+                          5;
       Opera          12.00-                        6;
       MSIE           9.0                           7;
   }
--- config
       location /exact {
           if ($browser = 1) {
               echo "msie6";
           }

           if ($browser = 4) {
               echo "Chrome";
           }

           if ($browser = 5) {
               echo "Firefox";
           }

           if ($browser = 6) {
               echo "Opera";
           }

           if ($browser = 7) {
               echo "msie9";
           }
       }
--- request
   GET /exact
--- more_headers
User-Agent:     Mozilla/5.0 (X11; Linux i686; rv:6.0) Gecko/20100101 Firefox/4.0
--- response_body
msie6


=== TEST 4:4
--- http_config
   user_agent $browser {
       default                                      1;
       greedy                                       safari;
       greedy                                       Safari;

       Chrome         12.0.742.112~15.0.872.0       4;
       Firefox        5.0+                          5;
       Opera          12.00-                        6;
       MSIE           9.0                           7;
   }
--- config
       location /exact {
           if ($browser = 1) {
               echo "msie6";
           }

           if ($browser = 4) {
               echo "Chrome";
           }

           if ($browser = 5) {
               echo "Firefox";
           }

           if ($browser = 6) {
               echo "Opera";
           }

           if ($browser = 7) {
               echo "msie9";
           }
       }
--- request
   GET /exact
--- more_headers
User-Agent: Opera/9.80 (Windows NT 6.1; U; pl) Presto/2.6.31 Version/10.70
--- response_body
Opera

=== TEST 5:5
--- http_config
   user_agent $browser {
       default                                      1;
       greedy                                       safari;
       greedy                                       Safari;

       Chrome         12.0.742.112~15.0.872.0       4;
       Firefox        5.0+                          5;
       Opera          12.00-                        6;
       MSIE           9.0                           7;
   }
--- config
       location /exact {
           if ($browser = 1) {
               echo "msie6";
           }

           if ($browser = 4) {
               echo "Chrome";
           }

           if ($browser = 5) {
               echo "Firefox";
           }

           if ($browser = 6) {
               echo "Opera";
           }

           if ($browser = 7) {
               echo "msie9";
           }
       }
--- request
   GET /exact
--- more_headers
User-Agent: Opera/13.80 (Windows NT 6.1; U; pl) Presto/2.6.31 Version/10.70
--- response_body
msie6

=== TEST 6:6
--- http_config
   user_agent $browser {
       default                                      1;
       greedy                                       safari;
       greedy                                       Safari;

       Chrome         12.0.742.112~15.0.872.0       4;
       Firefox        5.0+                          5;
       Opera          12.00-                        6;
       MSIE           9.0                           7;
   }
--- config
       location /exact {
           if ($browser = 1) {
               echo "msie6";
           }

           if ($browser = 4) {
               echo "Chrome";
           }

           if ($browser = 5) {
               echo "Firefox";
           }

           if ($browser = 6) {
               echo "Opera";
           }

           if ($browser = 7) {
               echo "msie9";
           }
       }
--- request
   GET /exact
--- more_headers
User-Agent: curl/7.15.5 (x86_64-redhat-linux-gnu) libcurl/7.15.5 OpenSSL/0.9.8b zlib/1.2.3 l    ibidn/0.6.5
--- response_body
msie6

=== TEST 7:7
--- http_config
   user_agent $browser {
       default                                      1;
       greedy                                       safari;
       greedy                                       Safari;

       Chrome         12.0.742.112~15.0.872.0       4;
       Chrome         6~8                           8;
       Firefox        5.0+                          5;
       Opera          12.00-                        6;
       MSIE           9.0                           7;
   }
--- config
       location /exact {
           if ($browser = 1) {
               echo "msie6";
           }

           if ($browser = 4) {
               echo "Chrome1";
           }

           if ($browser = 8) {
               echo "Chrome2";
           }

           if ($browser = 5) {
               echo "Firefox";
           }

           if ($browser = 6) {
               echo "Opera";
           }

           if ($browser = 7) {
               echo "msie9";
           }
       }
--- request
   GET /exact
--- more_headers
User-Agent: Mozilla/5.0 (X11; Linux i686) AppleWebKit/535.1 (KHTML, like Gecko) Ubuntu/10.04 Chromium/14.0.808.0 Chrome/7.0.808.0 Safari/535.1
--- response_body
Chrome2

=== TEST 8:8
--- http_config
   user_agent $browser {
       default                                      1;
       greedy                                       safari;
       greedy                                       Safari;

       Chrome         12.0.742.112~15.0.872.0       4;
       Chrome         6~8                           8;
       Chrome         5                             9;
       Firefox        5.0+                          5;
       Opera          12.00-                        6;
       MSIE           9.0                           7;
   }
--- config
       location /exact {
           if ($browser = 1) {
               echo "msie6";
           }

           if ($browser = 4) {
               echo "Chrome1";
           }

           if ($browser = 8) {
               echo "Chrome2";
           }

           if ($browser = 5) {
               echo "Firefox";
           }

           if ($browser = 6) {
               echo "Opera";
           }

           if ($browser = 7) {
               echo "msie9";
           }
       }
--- request
   GET /exact
--- more_headers
User-Agent: Mozilla/4.0 (compatible; MSIE 9; Windows NT 6.1; Trident/5.0)
--- response_body
msie9

=== TEST 9:9
--- http_config
   user_agent $browser {
       default                                      1;
       greedy                                       safari;
       greedy                                       Safari;

       Chrome         12.0.742.112~15.0.872.0       4;
       Chrome         6~8                           8;
       Chrome         5                             9;
       Firefox        5.0+                          5;
       Opera          12.00-                        6;
       MSIE           9.0=                          7;
   }
--- config
       location /exact {
           if ($browser = 1) {
               echo "msie6";
           }

           if ($browser = 4) {
               echo "Chrome1";
           }

           if ($browser = 8) {
               echo "Chrome2";
           }

           if ($browser = 5) {
               echo "Firefox";
           }

           if ($browser = 9) {
               echo "Chrome3";
           }

           if ($browser = 6) {
               echo "Opera";
           }

           if ($browser = 7) {
               echo "msie9";
           }
       }
--- request
   GET /exact
--- more_headers
User-Agent: Mozilla/5.0 (Windows NT 5.1) AppleWebKit/535.2 (KHTML, like Gecko) Chrome/5 Safari/535.2
--- response_body
Chrome3

=== TEST 10:10
--- http_config
   user_agent $browser {
       default                                      1;
       greedy                                       safari;
       greedy                                       Safari;

       Chrome         12.0.742.112~15.0.872.0       4;
       Chrome         6~8                           8;
       Chrome         5                             9;
       Firefox        5.0+                          5;
       Opera          12.00-                        6;
       MSIE                                         7;
   }
--- config
       location /exact {
           if ($browser = 1) {
               echo "msie6";
           }

           if ($browser = 4) {
               echo "Chrome1";
           }

           if ($browser = 8) {
               echo "Chrome2";
           }

           if ($browser = 5) {
               echo "Firefox";
           }

           if ($browser = 6) {
               echo "Opera";
           }

           if ($browser = 7) {
               echo "msie9";
           }
       }
--- request
   GET /exact
--- more_headers
User-Agent: Mozilla/4.0 (compatible; MSIE 9.0.1.0; Windows NT 6.1; Trident/5.0)
--- response_body
msie9
