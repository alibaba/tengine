# trim 模块

## 介绍

该模块用于删除 html ， 内嵌 javascript 和 css 中的注释以及重复的空白符。


## 配置

    location / {
        trim on;
        trim_jscss on;
    }

## 指令

**trim** `on` | `off`

**默认:** `trim off`

**上下文:** `http, server, location` 
     
在配置的地方使模块有效（失效），删除 html 的注释以及重复的空白符（/n，/r，/t，' ')。   
例外：对于 `pre`，`textarea`，`ie注释`，`script`，`style` 等标签内的内容不作删除操作。   
<br/>

**trim_jscss** `on` | `off`

**默认:** `trim_jscss off`

**上下文:** `http, server, location` 
     
在配置的地方使模块有效（失效），删除内嵌 javascript 和 css 的注释以及重复的空白符（/n，/r，/t，' ')。   
例外：对于非javascript代码的`script`，非css代码的`style` 等标签内的内容不作删除操作。   
<br/>

**trim_types** `MIME types`

**默认:** `trim_types: text/html`

**上下文:** `http, server, location`

定义哪些[MIME types](http://en.wikipedia.org/wiki/MIME_type)类型的响应可以被处理。

<br/>

## 其他

添加请求参数http_trim=off，将关闭trim功能，返回原始代码，方便对照调试。  
格式如下:  
`http://www.xxx.com/index.html?http_trim=off`
