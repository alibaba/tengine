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
<br/>


**trim_js** `on` | `off`

**Default:** `trim_js off`

**Context:** `http, server, location` 
     
Enable or disable trim module for inline javascript.  
<br/>


**trim_css** `on` | `off`

**Default:** `trim_css off`

**Context:** `http, server, location` 
     
Enable or disable trim module for inline css.  
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

### html
##### whitespace
+ remove '\r'.
+ replace '\t' with space.
+ replace multiple spaces with a single space.
+ replace multiple '\n' with a single '\n'.
+ replace multiple '\n' and '\t' with a single space in tag.
+ not trim quoted strings in tag.
+ not trim the contents that enclosed by the tag `pre`,`textarea`,`script` and `style`,as well as IE/SSI/ESI comments.  

##### comment
+ remove html comment(`<!-- -->`)  except for IE/SSI/ESI comments.  
  IE comment: `<!--[if  <![endif]-->`  
  SSI comment: `<!--#  -->`  
  ESI comment: `<!--esi  -->`  


### javascript
`<script type="text/javascript">` or `<script>` will be identified as javascript.

##### whitespace
+ remove '\r'.
+ remove '\t','\n' and space that behind '(' ',' '=' ':' '[' '!' '&' '|' '?' ';' '>' '~' '*' '{'.
+ replace multiple spaces with a single space.
+ not trim quoted strings and regular expression literals.

##### comment
+ remove single comment. `//`
+ remove multi comment. `/*  */`


### css
`<style type="text/css">` or `<style>` will be identified as css.

##### whiltespace
+ remove '\r'.
+ remove '\t','\n' and space that around ';' '>' '{' '}' ':' ','.
+ replace multiple '\n' and spaces with a single space.
+ not trim quoted strings.

##### comment
+ remove css comment(`/* */`)  except for child seletor and IE5 /Mac hack comments.  
   child seletor hack: `html>/**/body p{color:blue}`  
   IE5 /Mac hack: `/*\*/.selector{color:khaki}/**/`  
