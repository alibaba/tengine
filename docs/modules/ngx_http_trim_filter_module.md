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
     
Enable or disable trim module for pure HTML.  
This module will retain some contents unchanged, in case that they are enclosed by the tag `pre`,`textarea`,`script` and `style`,as well as IE/SSI/ESI comments.  
Parameter value can contain variables.  
Example:  

    set $flag "off";
    if ($condition) {
        set $flag "on";
    }
    trim $flag;
<br/>


**trim_js** `on` | `off`

**Default:** `trim_js off`

**Context:** `http, server, location` 
     
Enable or disable trim module for inline javascript.  
Parameter value can contain variables too.  
<br/>


**trim_css** `on` | `off`

**Default:** `trim_css off`

**Context:** `http, server, location` 
     
Enable or disable trim module for inline css.  
Parameter value can contain variables too.  
<br/>


**trim_types** `MIME types`

**Default:** `trim_types: text/html`

**Context:** `http, server, location`

Enable trim module for the specified MIME types in addition to "text/html". Responses with the “text/html” type are always processed.  
<br/>


## Debug

Trim module will be disabled if incoming request has `http_trim=off` parameter in url.   
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


## Trim Rule

### Html
##### Whitespace
+ Remove '\r'.
+ Replace '\t' with space.
+ Replace multiple spaces with a single space.
+ Replace multiple '\n' with a single '\n'.
+ Replace multiple '\n' and '\t' in tag with a single space.
+ Do not trim quoted strings in tag.
+ Do not trim the contents enclosed by the tag `pre`,`textarea`,`script` and `style`.

##### Comment
+ Remove html comment(`<!-- -->`).
+ Do not trim IE/SSI/ESI comments.  
  IE comment: `<!--[if  <![endif]-->`  
  SSI comment: `<!--#  -->`  
  ESI comment: `<!--esi  -->`  


### Javascript
Contents enclosed by `<script type="text/javascript">` or `<script>` will be identified as javascript.

##### Whitespace
+ Remove '\r'.
+ Remove '\t','\n' and space that behind '(',',','=',':','[','!','&','|','?',';','>','~','*','{'.
+ Replace multiple spaces with a single space.
+ Do not trim quoted strings and regular expression literals.

##### Comment
+ Remove single comment. `//`
+ Remove multi comment. `/*  */`


### Css
Contents enclosed by `<style type="text/css">` or `<style>` will be identified as css.

##### Whiltespace
+ Remove '\r'.
+ Remove '\t','\n' and space that around ';','>','{','}',':',','.
+ Replace multiple '\n' and spaces with a single space.
+ Do not trim quoted strings.

##### Comment
+ Remove css comment(`/* */`).
+ Do not remove child seletor and IE5 /Mac hack comments.  
  Child seletor hack: `html>/**/body p{color:blue}`  
  IE5 /Mac hack: `/*\*/.selector{color:khaki}/**/`  
