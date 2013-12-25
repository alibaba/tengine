use lib 'lib';
use Test::Nginx::Socket;

log_level('debug');
plan tests => 2 * blocks();

$ENV{TEST_NGINX_TRIM_PORT} ||= "1984";

run_tests();

# etcproxy 1986 1984
# TEST_NGINX_TRIM_PORT=1986 prove ../cases/trim.t

__DATA__

=== TEST 1: do not trim within 'textarea' 'pre' 'ie-comment'
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<textarea>
   hello
        world!
</textarea>

     <pre>
  hello     world!
    </pre>

<!--[if IE]> hello    world    ! <![endif]-->
    <!-- hello     world   ! -->
<!--[if !IE ]>--> hello    world  ! <!--<![endif]-->
--- request
    GET /t/trim.html
--- response_body eval
'<!DOCTYPE html>
<textarea>
   hello
        world!
</textarea> <pre>
  hello     world!
    </pre> <!--[if IE]> hello    world    ! <![endif]--> <!--[if !IE ]>--> hello    world  ! <!--<![endif]--> '

=== TEST 2: trim within other tags
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<body>hello   world,   it
is good  to     see you   </body>

<body>hello   world,   it
     is good  to     see you   </body>
--- request
    GET /t/trim.html
--- response_body eval
'<!DOCTYPE html>
<body>hello world, it is good to see you </body> <body>hello world, it is good to see you </body> '

=== TEST 3: trim within non-ie comment
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<body>hello <!--world--></body>
<!--[if IE]> hello    world    ! <![endif]-->
   <!-- hello world! -->
<!--[if !IE ]>--> hello    world  ! <!--<![endif]-->

--- request
    GET /t/trim.html
--- response_body eval
'<!DOCTYPE html>
<body>hello </body> <!--[if IE]> hello    world    ! <![endif]--> <!--[if !IE ]>--> hello    world  ! <!--<![endif]--> '

=== TEST 4: do not trim within tag quote
--- config
    trim on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<body
style="text-align:   center;">hello   world,   it
   is good  to     see you   </body>
--- request
    GET /t/trim.html
--- response_body eval
'<!DOCTYPE html>
<body
style="text-align:   center;">hello world, it is good to see you </body> '

=== TEST 5: trim newline
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html


    
<!DOCTYPE html>

<html>


<body>hello   world!<body>         
   <!-- --->
         <html>


   

                  
--- request
    GET /t/trim.html
--- response_body eval
'
<!DOCTYPE html> <html> <body>hello world!<body> <html> '

=== TEST 6: return zero size 
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html


--- request
    GET /t/trim.html
--- response_body eval
''

=== TEST 7: trim more tags
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<      <PRE>hello     world  ! </pre>
<2     <pre>hello     world  ! </pre>
<<<    <pre>hello     world  ! </pre>
<   <  <pre>hello     world  ! </pre>
<     <<pre>hello     world  ! </pre>
<x    <<pre>hello     world  ! </pre>
<     <<<!doctype   html>
                  
--- request
    GET /t/trim.html
--- response_body eval
'<!DOCTYPE html>
< <PRE>hello     world  ! </pre> <2 <pre>hello     world  ! </pre> <<< <pre>hello     world  ! </pre> < < <pre>hello     world  ! </pre> < <<pre>hello     world  ! </pre> <x <<pre>hello world ! </pre> < <<<!doctype html> '

=== TEST 8: trim Chinese characters
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<title>世界      你好  !</title>
                  
--- request
    GET /t/trim.html
--- response_body eval
'<title>世界 你好 !</title>
'

=== TEST 9: sendfile on
--- config
    sendfile on;
    trim on;
    trim_jscss on;
--- user_files
>>> trim.html
<!DOCTYPE html>
<body>hello   world,   it
   is good  to     see you   </body>
<!-- trimoff -->
--- request
    GET /trim.html
--- response_body eval
'<!DOCTYPE html>
<body>hello world, it is good to see you </body> '

=== TEST 10: if $arg_http_trim is off, trim off.
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<body>hello   world,   it
   is good  to     see you   </body>
<!-- trimoff -->
--- request
    GET /t/trim.html?http_trim=off&hello=world
--- response_body
<!DOCTYPE html>
<body>hello   world,   it
   is good  to     see you   </body>
<!-- trimoff -->

=== TEST 11: trim javascript comment
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<script>
//// single comment
document.write("hello world");
</script>
<script type="text/javascript">
/***  muitl comment 
      !             ***/
</script>
<script type="text/vbscript">
/* no javscript code !*/
</script>

--- request
    GET /t/trim.html
--- response_body eval
'<!DOCTYPE html>
<script>document.write("hello world");</script> <script type="text/javascript"></script> <script type="text/vbscript">
/* no javscript code !*/
</script> '

=== TEST 12: do not tirm javascript quote and RE 
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<script>
document.write("hello      world");
document.write("hello  \"  world");
var reg=/hello  \/   world /g;
var reg=  /hello  \/   world /g;
str.replace(/    /,"hello");
str.replace(  /    /,"hello");
</script>

--- request
    GET /t/trim.html
--- response_body eval
'<!DOCTYPE html>
<script>document.write("hello      world");document.write("hello  \"  world");var reg=/hello  \/   world /g;var reg=/hello  \/   world /g;str.replace(/    /,"hello");str.replace(/    /,"hello");</script> '

=== TEST 13: trim css comment
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<style type="text/css">
/*** css comment
                 ! ***/
body {
     background-color: black;
     }
</style>
--- request
    GET /t/trim.html
--- response_body eval
'<!DOCTYPE html>
<style type="text/css">body {background-color:black;}</style> '

=== TEST 14: do not trim css quote
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<style type="text/css">
"hello      world");
"hello  \"  world");
"hello  \\\"  world");
</style>
--- request
    GET /t/trim.html
--- response_body eval
'<!DOCTYPE html>
<style type="text/css">"hello      world");"hello  \"  world");"hello  \\\\\"  world");</style> '

=== TEST 15 trim aplus.js
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<script type="text/javascript">
(function (d) {
var t=d.createElement("script");t.type="text/javascript";t.async=true;t.id="tb-beacon-aplus";
t.setAttribute("exparams","category=&userid=&aplus");
t.src=("https:"==d.location.protocol?"https://s":"http://a")+".tbcdn.cn/s/aplus_v2.js";
d.getElementsByTagName("head")[0].appendChild(t);
})(document);
</script>

--- request
    GET /t/trim.html
--- response_body eval
'<!DOCTYPE html>
<script type="text/javascript">(function (d) {var t=d.createElement("script");t.type="text/javascript";t.async=true;t.id="tb-beacon-aplus";t.setAttribute("exparams","category=&userid=&aplus");t.src=("https:"==d.location.protocol?"https://s":"http://a")+".tbcdn.cn/s/aplus_v2.js";d.getElementsByTagName("head")[0].appendChild(t);})(document);</script> '

=== TEST 15: do not trim css comment of child selector hack
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<style type="text/css">
html >/**/ body p {
    color: blue;
}
</style>
--- request
    GET /t/trim.html
--- response_body eval
'<!DOCTYPE html>
<style type="text/css">html >/**/ body p {color:blue;}</style> '

=== TEST 16: do not trim css comment of IE5/Mac hack
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<style type="text/css">
/* Ignore the next rule in IE mac \*/
.selector {
    color: khaki;
}
/* Stop ignoring in IE mac */
</style>
--- request
    GET /t/trim.html
--- response_body eval
'<!DOCTYPE html>
<style type="text/css">/*\\*/
.selector {
    color: khaki;
}
/**/
</style> '

=== TEST 17: comment of javascript
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<script type="text/javascript">// <![CDATA[
   return   true;
// ]]></script></head><body id="loginform"><div id="page_content">
--- request
    GET /t/trim.html
--- response_body eval
'<!DOCTYPE html>
<script type="text/javascript">return true;</script></head><body id="loginform"><div id="page_content"> '

=== TEST 18: do not trim html comment of ssi/esi
--- config
    trim on;
    trim_jscss on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<!-- hello -->
<!--# ssi  -->
<!--esi    -->
<!-- world -->
<!---->
<!--e    -->
<!-------->
<!--[if  ie  <![endif]-->
--- request
    GET /t/trim.html
--- response_body eval
'<!DOCTYPE html>
<!--# ssi  --> <!--esi    --> <!--e    --> <!--[if  ie  <![endif]--> '
