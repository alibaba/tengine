use lib 'lib';
use Test::Nginx::Socket;

log_level('debug');
plan tests => 2 * blocks();

$ENV{TEST_NGINX_TRIM_PORT} ||= "1984";

run_tests();

__DATA__

=== TEST 1: do not trim within 'textarea' 'pre' 'script' 'style' 'ie-comment'
--- config
    trim on;
    trim_comment off;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<textarea>
   hello
        world!
</textarea>

     <pre>
  hello     world!
    </pre>

<script type="text/javascript">
       hello
world !

</script>

<style>
 hello     world   !
</style>


<!--[if IE]> hello    world    ! <![endif]-->
    <!-- hello     world   ! -->
<!--[if !IE ]>--> hello    world  ! <!--<![endif]-->
--- request
    GET /t/trim.html
--- response_body
<textarea>
   hello
        world!
</textarea>
<pre>
  hello     world!
    </pre>
<script type="text/javascript">
       hello
world !

</script>
<style>
 hello     world   !
</style>
<!--[if IE]> hello    world    ! <![endif]-->
<!-- hello world ! -->
<!--[if !IE ]>--> hello    world  ! <!--<![endif]-->

=== TEST 2: trim within other tags
--- config
    trim on;
    trim_comment on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<body>hello   world,   it
   is good  to     see you   </body>
--- request
    GET /t/trim.html
--- response_body
<body>hello world, it
is good to see you </body>

=== TEST 3: trim within non-ie comment
--- config
    trim on;
    trim_comment on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<body>hello <!--world--></body>
<!--[if IE]> hello    world    ! <![endif]-->
   <!-- hello world! -->
<!--[if !IE ]>--> hello    world  ! <!--<![endif]-->

--- request
    GET /t/trim.html
--- response_body
<body>hello </body>
<!--[if IE]> hello    world    ! <![endif]-->
<!--[if !IE ]>--> hello    world  ! <!--<![endif]-->

=== TEST 4: trim within tag value
--- config
    trim on;
    trim_comment on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<body
    style="text-align:   center;">hello   world,   it
   is good  to     see you   </body>
--- request
    GET /t/trim.html
--- response_body
<body
style="text-align:   center;">hello world, it
is good to see you </body>

=== TEST 5: trim newline
--- config
    trim on;
    trim_comment on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html


    

<html>


<body>hello   world!<body>         
   <!-- --->
         <html>


   

                  
--- request
    GET /t/trim.html
--- response_body
<html>
<body>hello world!<body> 
<html>

=== TEST 6:  return zero size
--- config
    trim on;
    trim_comment on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
 	   
  <!-- hello  world -->    
  <!-- ---->
--- request
    GET /t/trim.html
--- response_body eval
''
--- error_code: 200

=== TEST 7: trim all
--- config
    sendfile on;
    trim on;
    trim_comment on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<html>
    <head>trim   test <!-- hello world  !--> </head>
<body 
     style="text-align:    center;"   >
<pre> 

         hello world    !
    </pre>


     <textarea class="trim">
hello    world  
   !
   </textarea>

<p>
     hello    world   !
   </p>

   <style>
    hello
    world !

</style>
           <script type="text/javascript"> 
   hello world    !
</script>
    
<a   href='hello  world    !'> hello     world   ! 
     </a>
   </body>
    </html>
    
<!--[if IE]> ie comment <![endif]-->

<!----- non-ie comment------>
     <!-- -->   <!--  ---->     	

<!--[if !IE ]>--> non-ie html code <!--<![endif]-->                  
--- request
    GET /t/trim.html
--- response_body
<html>
<head>trim test </head>
<body style="text-align:    center;" >
<pre> 

         hello world    !
    </pre>
<textarea class="trim">
hello    world  
   !
   </textarea>
<p>
hello world !
</p>
<style>
    hello
    world !

</style>
<script type="text/javascript"> 
   hello world    !
</script>
<a href='hello  world    !'> hello world ! 
</a>
</body>
</html>
<!--[if IE]> ie comment <![endif]-->
<!--[if !IE ]>--> non-ie html code <!--<![endif]--> 

=== TEST 8: trim more tags
--- config
    trim on;
    trim_comment on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<      <PRE>hello     world  ! </pre>
<2     <pre>hello     world  ! </pre>
<<<    <pre>hello     world  ! </pre>
<   <  <pre>hello     world  ! </pre>
<     <<pre>hello     world  ! </pre>
<x    <<pre>hello     world  ! </pre>
<     <<<!doctype   html>
                  
--- request
    GET /t/trim.html
--- response_body
< <PRE>hello     world  ! </pre>
<2 <pre>hello     world  ! </pre>
<<< <pre>hello     world  ! </pre>
< < <pre>hello     world  ! </pre>
< <<pre>hello     world  ! </pre>
<x <<pre>hello world ! </pre>
< <<<!doctype html>

=== TEST 9: trim Chinese characters
--- config
    trim on;
    trim_comment on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<title>世界      你好  !</title>
                  
--- request
    GET /t/trim.html
--- response_body
<title>世界 你好 !</title>

=== TEST 10: home page of tengine
--- config
    sendfile on;
    trim on;
    trim_comment on;
--- user_files
>>> trim.html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to tengine!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to tengine!</h1>
<p>If you see this page, the tengine web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://tengine.taobao.org/">tengine.taobao.org</a>.</p>

<p><em>Thank you for using tengine.</em></p>
</body>
</html>

--- request
    GET /trim.html
--- response_body
<!DOCTYPE html>
<html>
<head>
<title>Welcome to tengine!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to tengine!</h1>
<p>If you see this page, the tengine web server is successfully installed and
working. Further configuration is required.</p>
<p>For online documentation and support please refer to
<a href="http://tengine.taobao.org/">tengine.taobao.org</a>.</p>
<p><em>Thank you for using tengine.</em></p>
</body>
</html>
