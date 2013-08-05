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
     
在配置的地方使模块有效（失效），删除 html 的注释以及重复的空白符（\n，\r，\t，' ')。   
例外：对于 `pre`，`textarea`，`ie注释`，`script`，`style` 等标签内的内容不作删除操作。   
<br/>

**trim_jscss** `on` | `off`

**默认:** `trim_jscss off`

**上下文:** `http, server, location` 
     
在配置的地方使模块有效（失效），删除内嵌 javascript 和 css 的注释以及重复的空白符（\n，\r，\t，' ')。   
例外：对于非javascript代码的`script`，非css代码的`style` 等标签内的内容不作删除操作。   
<br/>

**trim_types** `MIME types`

**默认:** `trim_types: text/html`

**上下文:** `http, server, location`

定义哪些[MIME types](http://en.wikipedia.org/wiki/MIME_type)类型的响应可以被处理。  
目前只能处理html格式的页面，js和css只针对于html内嵌的代码，不支持处理单独的js和css页面。  
如果这样配置 `trim_type text/javascript;`，js代码将被作为html代码来处理而出错。
<br/>

## 调试

添加请求参数http_trim=off，将关闭trim功能，返回原始代码，方便对照调试。   
格式如下:  
`http://www.xxx.com/index.html?http_trim=off`

## trim规则

### html
#####  空白符

+ 正文中的 '\r' 直接删除。  
+ 正文中的 '\n' 替换为 '空格', 然后重复 \t' 和 '空格' 保留第一个。 
+ 标签中的 '\r'，'\n'，'\t'，'空格' 保留第一个。  
+ 标签的双引号和单引号内的空白符不做删除。 
\<div class="no &nbsp; &nbsp; &nbsp;  trim"\>
+ 保留第一行DTD声明的 '\n'。  
+ `pre` 和 `texterea` 标签的内容不做删除。  
+ `script` 和 `style` 标签的内容不做删除。  
+ ie条件注释的内容不做删除。 

##### 注释
+ 如果是ie条件注释不做操作。
   判断规则：`<!--[if <![endif]-->`  之间的内容判断为ie条件注释。
+ 正常html注释直接删除.  `<!--  -->`
    
### javascript  
借鉴 jsmin 的处理规则 (http://www.crockford.com/javascript/jsmin.html)  
`<script type="text/javascript">` 或者 `<script>` 标签认为是javascript。  
##### 空白符  
+ '('，'['，'{'，';'，','，'>'，'=' 后的 '\n'，'\t'，'空格' 直接删除。
+ '\r' 直接删除。 
+ 其他情况 重复的 '\n'，'\t'，'空格' 保留第一个。  
+ 单引号和双引号内不删除。  
     如下不做操作：  
     "hello   &nbsp;   \\\\"  &nbsp;   world"   
     'hello  &nbsp;       \'  &nbsp;   world'  
+ 正则表达式的内容不删除。  
     判断规则：'/' 前的非空字符是 ','，'('，'=' 三种的即认为是正则表达式。( 同jsmin的判断)   
     如下不做操作：   
     var re=/1 &nbsp; &nbsp; &nbsp;2/;     
     data.match(/1  &nbsp;  &nbsp; 2/);  

##### 注释  
+ 删除单行注释。  `//`  
+ 删除多行注释。  `/*   */`  
注意：javascript也有一种条件注释，不过貌似用得很少，jsmin直接删除的，trim也是直接删除。  
http://en.wikipedia.org/wiki/Conditional_comment  

### css  
借鉴 YUI Compressor 的处理规则 (http://yui.github.io/yuicompressor/css.html)   
`<style type="text/css">` 或者 `<style>` 标签认为是css.  
##### 空白符  
+ ';'，'>'，'{'，'}'，':'，',' 后的 '\n'，'\t'，'空格' 直接删除。  
+ '\r' 直接删除。 
+ 其他情况 连续的 '\n'， '\t' 和 '空格'  保留第一个。  
+ 单引号和双引号内不删除。  
     如下不做操作：  
     "hello   &nbsp;  \\\\\"  &nbsp;    world"  
      'hello  &nbsp;   \'   &nbsp;  &nbsp;   world' 

##### 注释   
+  child seletor hack的注释不删除。  
      `html>/**/body p{color:blue}`  
+  IE5 /Mac hack 的注释不删除。  
     `/*\*/.selector{color:khaki}/**/`  
+  其他情况删除注释。  `/*    */`  

