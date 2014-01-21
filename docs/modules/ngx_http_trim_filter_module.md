# Module ngx_http_trim_filter_module

The ngx_http_trim_filter_module is a filter that modifies a response by removing unnecessary whitespaces 
(spaces, tabs, newlines) and comments from HTML (include inline javascript and css). Trim module parses 
HTML with a state machine.


## Examples Configuration

    location / {
        trim on;
        trim_js on;
        trim_css on;
    }

## Directives

**trim** `on` | `off`

**Default:** `trim off`

**Context:** `http, server, location` 
     
Enables or disables trim for pure HTML.
Disables in tabs of `pre`,`textarea`,`ie/ssi/esi comment`,`script` and `style`. 
<br/>

**trim_js** `on` | `off`

**Default:** `trim_js off`

**Context:** `http, server, location` 
     
Enables or disables trim for inline javascript.
<br/>

**trim_css** `on` | `off`

**Default:** `trim_css off`

**Context:** `http, server, location` 
     
Enables or disables trim for inline css.
<br/>

**trim_types** `MIME types`

**Default:** `trim_types: text/html`

**Context:** `http, server, location`

Enables trim  with the specified MIME types in addition to “text/html”, It shound be a HTML format.

<br/>

## Debug

Add the arg "http_trim=off", return the original content.  
e.g.  `http://www.xxx.com/index.html?http_trim=off`  

## Examples


    <!DOCTYPE html>
    <textarea  >
       trim
            module
    </textarea  >
    <!--remove all-->
    <!--[if IE]> trim module <![endif]-->
    <!--[if !IE ]>--> trim module  <!--<![endif]-->
    <!--# ssi-->
    <!--esi-->
    <pre    style  =
        "color:   blue"  >Welcome    to    nginx!</pre  >
    <script type="text/javascript">
    /***  muitl comment 
                       ***/
    //// single comment
    str.replace(/     /,"hello");
    </script>
    <style   type="text/css"  >
    /*** css comment
                     ! ***/
    body
    {
      font-size:  20px ;
      line-height: 150% ;
    }
    </style>


result:


    <!DOCTYPE html>
    <textarea>
       trim  
            module
    </textarea>
    <!--[if IE]> trim module <![endif]-->
    <!--[if !IE ]>--> trim module  <!--<![endif]-->
    <!--# ssi-->
    <!--esi-->
    <pre style="color:   blue">Welcome    to    nginx!</pre>
    <script type="text/javascript">str.replace(/     /,"hello");</script>
    <style type="text/css">body{font-size:20px;line-height:150%;}</style>





