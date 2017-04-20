# concat 模块

## 介绍

该模块类似于apache中的modconcat模块，用于合并多个文件在一个响应报文中。

请求参数需要用两个问号（'?'）例如：

    http://example.com/??style1.css,style2.css,foo/style3.css
    
如果参数中包含'?'，'?'表示文件的版本，例如：

    http://example.com/??style1.css,style2.css,foo/style3.css?v=102234

## 配置

    location ^~ /static {
        location ~* /static/css/css_[[:alnum:]]+\.css$ {
            concat on;
            concat_max_files 20;
        }
        
        location ~* /static/js/js_[[:alnum:]]+\.js$ {
            concat on;
            concat_max_files 30;
        }
    } 

## 指令

**concat** `on` | `off`

**默认:** `concat off`

**上下文:** `http, server, location`
在配置的地方使模块有效（失效）

<br/>
<br/>

**concat_types** `MIME types`

**默认:** `concat_types: text/css application/x-javascript`

**上下文:** `http, server, location`

定义哪些[MIME types](http://en.wikipedia.org/wiki/MIME_type)是可以被接受

<br/>
<br/>

**concat_unique** `on` | `off`

**默认:** `concat_unique on`

**上下文:** `http, server, location`

定义是否只接受在[MIME types]中的相同类型的文件，例如：

    http://example.com/static/??foo.css,bar/foobaz.js
如果配置为 'concat_unique on' 那么将返回400，如果配置为'concat_unique off'
那么将合并两个文件。

<br/>
<br/>

**concat\_max\_files** `number`p

**默认:** `concat_max_files 10`

**上下文:** `http, server, location`

定义最大能接受的文件数量。

<br/>
<br/>

**concat_delimiter** string
**默认:**  无 
**上下文** 'http, server, location'
定义在文件之间添加分隔符

<br/>
<br/>

**concat_ignore_file_error** 'on | off'
**默认** 'concat_ignore_file_error off'
**上下文** 'http, server, location'

定义模块是否忽略文件不存在（404）或者没有权限（403）错误

## 安装

 1. 获取代码
     
        git clone git://github.com/taobao/nginx-http-concat.git

 2. 添加configure选项
    `--add-module=/path/to/nginx-http-concat`.

 3. 编译nginx
 
 4. 安装nginx
 
 5. 配置concat的配置项
 
 6. 运行
