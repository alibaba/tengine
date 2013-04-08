# trim 模块

## 介绍

该模块用于删除html代码中重复的空白符和注释。


## 配置

    location / {
        trim on;
        trim_comment on;
    }

## 指令

**trim** `on` | `off`

**默认:** `trim off`

**上下文:** `http, server, location` 
     
在配置的地方使模块有效（失效），删除重复的空白符（/n，/f，/r，/t，' ')。  
对于标签 pre，textarea，script，style内的内容不作删除操作。

<br/>
<br/>

**trim_comment** `on` | `off`

**默认:** `trim_comment off`

**上下文:** `http, server, location`

在配置的地方使删除html注释功能有效（失效）， 对于ie注释不作删除处理。  
例如html代码

    <html><!--non-ie comment--><!--[if IE]> ie comment <![endif]--></html>

如果配置为**trim_comment on**，将保留ie注释，处理之后如下：

    <html><!--[if IE]> ie comment <![endif]--></html>
    
<br/>
<br/>

**trim_types** `MIME types`

**默认:** `trim_types: text/html`

**上下文:** `http, server, location`

定义哪些[MIME types](http://en.wikipedia.org/wiki/MIME_type)类型的响应可以被处理。

<br/>
<br/>
