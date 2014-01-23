# Ngx_http_trim_filter module

The ngx_http_trim_filter module is a filter that modifies a response by removing unnecessary whitespaces 
(spaces, tabs, newlines) and comments from HTML (including inline javascript and css). Trim module parses 
HTML with a state machine.


## Example Configuration

    location / {
        trim on;
        trim_js on;
        trim_css on;
    }

## Directives

**trim** `on` | `off`

**Default:** `trim off`

**Context:** `http, server, location` 
     
Enable or disable module trim for pure HTML.  
This module will not modify contents enclosed by the tag `pre`,`textarea`,`script` and `style`,as well as IE/SSI/ESI comments.  
<br/>


**trim_js** `on` | `off`

**Default:** `trim_js off`

**Context:** `http, server, location` 
     
Enable or disable module trim for inline javascript.  
<br/>


**trim_css** `on` | `off`

**Default:** `trim_css off`

**Context:** `http, server, location` 
     
Enable or disable module trim for inline css.  
<br/>


**trim_types** `MIME types`

**Default:** `trim_types: text/html`

**Context:** `http, server, location`

Enable module trim for the specified MIME types in addition to "text/html",responses with the “text/html” type are always processed.  
<br/>


## Debug

Trim module will retain the original content unchanged when requested by the url with arg "http_trim=off".   
e.g.  `http://www.xxx.com/index.html?http_trim=off`  

## Sample
original:

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

