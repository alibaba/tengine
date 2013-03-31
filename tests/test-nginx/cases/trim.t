use lib 'lib';
use Test::Nginx::Socket;

plan tests => 2 * blocks();
run_tests();

__DATA__

=== TEST 1: do not trim within 'textarea' 'pre' 'script' 'style' 'ie-comment'
--- config
    trim on;
    trim_comment off;
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
    GET /trim.html
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
    trim_comment off;
--- user_files
>>> trim.html
<body>hello   world,   it
   is good  to     see you   </body>
--- request
    GET /trim.html
--- response_body
<body>hello world, it
is good to see you </body>

=== TEST 3: trim within non-ie comment
--- config
    trim on;
    trim_comment on;
--- user_files
>>> trim.html
<body>hello <!--world--></body>
<!--[if IE]> hello    world    ! <![endif]-->
   <!-- hello world! -->
<!--[if !IE ]>--> hello    world  ! <!--<![endif]-->

--- request
    GET /trim.html
--- response_body
<body>hello </body>
<!--[if IE]> hello    world    ! <![endif]-->
<!--[if !IE ]>--> hello    world  ! <!--<![endif]-->

=== TEST 4: trim within tag value
--- config
    trim on;
    trim_comment off;
--- user_files
>>> trim.html
<body
    style="text-align:   center;">hello   world,   it
   is good  to     see you   </body>
--- request
    GET /trim.html
--- response_body
<body style="text-align:   center;">hello world, it
is good to see you </body>

=== TEST 5: trim newline
--- config
    trim on;
    trim_comment on;
--- user_files
>>> trim.html


    

<html>


<body>hello   world!<body>         
   <!-- --->
         <html>


   

                  
--- request
    GET /trim.html
--- response_body
<html>
<body>hello world!<body> 
<html>

=== TEST 6:  return zero size
--- config
    trim on;
    trim_comment on;
--- user_files
>>> trim.html
 	   
  <!-- hello  world -->    
  <!-- ---->
--- request
    GET /trim.html
--- response_body eval
''
--- error_code: 200

=== TEST 7: trim all
--- config
    trim on;
    trim_comment on;
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
    
<a
     href='hello  world    !'> hello     world   ! 
     </a>
   </body>
    </html>
    
<!--[if IE]> ie comment <![endif]-->

<!----- non-ie comment------>
     <!-- -->   <!--  ---->     	

<!--[if !IE ]>--> non-ie html code <!--<![endif]-->                  
--- request
    GET /trim.html
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
