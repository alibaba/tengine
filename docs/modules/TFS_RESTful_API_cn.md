#TFS RESTful API

注：API语法描述中的<b>粗体</b>为API语法规定的保留关键字部分，<i>斜体</i>为用户输入部分

##原生TFS

###写文件

####描述

此API用于将数据保存成一个TFS文件并以JSON格式返回TFS的文件名

####语法

>POST /<b>v1</b>/<i>appkey</i> HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Content-Length: <i>length</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符，若无使用RcServer，使用<b>tfs</b>即可

####请求参数

<table>
	<tr align="left">
		<th>参数名</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>suffix</td>
		<td>文件后缀</td>
	</tr>
	<tr align="left">
		<td>simple_name</td>
		<td>是否要求必须带正确后缀才可访问存入的TFS文件<br>1：要求必须带正确后缀才可访问<br>0：不带后缀也可访问</td>
	</tr>
	<tr align="left">
		<td>large_file</td>
		<td>是否存成大文件（文件名以L开头）<br>1：存成大文件<br>0：不存成大文件</td>
	</tr>
</table>

####应答

<table>
	<tr align="left">
		<th>名称</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>TFS_FILE_NAME</td>
		<td>返回的TFS文件名</td>
	</tr>
</table>

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 OK</td>
		<td>操作成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>错误的请求</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey写一个不带后缀的TFS文件：
<pre>
POST /v1/tfs HTTP/1.1
Host: 10.0.0.1:7500
Content-Length: 22
Date: Fri, 30 Nov 2012 03:05:00 GMT

[data]
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Fri, 30 Nov 2012 03:05:00 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive

{
	"TFS_FILE_NAME": "T1FOZHB4ET1RCvBVdK"
}
</pre>

下面这个请求，将会使用tfs这个appkey写一个带“.jpg”后缀的TFS文件，并且要求必须带该后缀才能访问该文件：

<pre>
POST /v1/tfs?suffix=.jpg&simple_name=1 HTTP/1.1
Host: 10.0.0.1:7500
Content-Length: 22
Date: Fri, 30 Nov 2012 03:05:00 GMT

[data]
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Fri, 30 Nov 2012 03:05:00 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive

{
	"TFS_FILE_NAME": "T1FOZHB4ET1RCvBVdK.jpg"
}
</pre>

###更新文件

####描述

此API用于更新一个已有的TFS文件并以JSON格式返回文件名

####语法

>PUT /<b>v1</b>/<i>appkey</i>/<i>TfsFileName</i> HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Content-Length: <i>length</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符，若无使用RcServer，使用<b>tfs</b>即可

####请求参数

<table>
	<tr align="left">
		<th>参数名</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>suffix</td>
		<td>文件后缀</td>
	</tr>
	<tr align="left">
		<td>simple_name</td>
		<td>是否要求必须带正确后缀才可访问存入的TFS文件<br>1：要求必须带正确后缀才可访问<br>0：不带后缀也可访问</td>
	</tr>
</table>

####应答

<table>
	<tr align="left">
		<th>名称</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>TFS_FILE_NAME</td>
		<td>返回的TFS文件名</td>
	</tr>
</table>

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 OK</td>
		<td>操作成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>错误的请求</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey更新TFS文件T1FOZHB4ET1RCvBVdK：
<pre>
PUT /v1/tfs/T1FOZHB4ET1RCvBVdK HTTP/1.1
Host: 10.0.0.1:7500
Content-Length: 22
Date: Fri, 30 Nov 2012 03:05:00 GMT

[data]
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Fri, 30 Nov 2012 03:05:00 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive

{
	"TFS_FILE_NAME": "T1FOZHB4ET1RCvBVdK"
}
</pre>

###读文件

####描述

此API用于从一个TFS文件中读取数据

####语法
>GET /<b>v1</b>/<i>appkey</i>/<i>TfsFileName</i> HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符，若无使用RcServer，使用<b>tfs</b>即可

TfsFileName是要读取的TFS文件的文件名，可带后缀

####请求参数

<table>
	<tr align="left">
		<th>参数名</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>suffix</td>
		<td>文件后缀<br>注：若指定了此参数，并且TfsFileName中也带了后缀，两者不一致将无法访问文件</td>
	</tr>
	<tr align="left">
		<td>offset</td>
		<td>要读取数据在文件在的偏移</td>
	</tr>
	<tr align="left">
		<td>size</td>
		<td>要读取数据的长度</td>
	</tr>
</table>


####应答

<table>
	<tr align="left">
		<th>名称</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>data</td>
		<td>数据</td>
	</tr>
</table>

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 OK</td>
		<td>操作成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>错误的请求</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>文件不存在</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey读文件T1FOZHB4ET1RCvBVdK：

<pre>
GET /v1/tfs/T1FOZHB4ET1RCvBVdK HTTP/1.1
Host: 10.0.0.1:7500
Date: Fri, 30 Nov 2012 03:05:00 GMT
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Fri, 30 Nov 2012 03:05:00 GMT
Last-Modified: Thu, 29 Nov 2012 03:05:00 GMT
Transfer-Encoding: chunked
Connection: keep-alive

[data]
</pre>

下面这个请求，将会使用tfs这个appkey读文件T1FOZHB4ET1RCvBVdK.jpg：

<pre>
GET /v1/tfs/T1FOZHB4ET1RCvBVdK.jpg HTTP/1.1
Host: 10.0.0.1:7500
Date: Fri, 30 Nov 2012 03:05:00 GMT
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Fri, 30 Nov 2012 03:05:00 GMT
Last-Modified: Thu, 29 Nov 2012 03:05:00 GMT
Transfer-Encoding: chunked
Connection: keep-alive

[data]
</pre>

###删除文件

####描述

此API用于将一个TFS文件删除或隐藏

####语法

>DELETE /<b>v1</b>/<i>appkey</i>/<i>TfsFileName</i> HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符，若无使用RcServer，使用<b>tfs</b>即可

TfsFileName是要读取的TFS文件的文件名，可带后缀

####请求参数

<table>
	<tr align="left">
		<th>参数名</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>suffix</td>
		<td>文件后缀<br>注：若指定了此参数，并且TfsFileName中也带了后缀，两者不一致将无法访问文件</td>
	</tr>
	<tr align="left">
		<td>hide</td>
		<td>指定隐藏操作类型：<br>1：隐藏<br>0：反隐藏</td>
	</tr>
</table>

####应答

无

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 OK</td>
		<td>操作成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>错误的请求</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>文件不存在</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey删除文件T1FOZHB4ET1RCvBVdK：

<pre>
DELETE /v1/tfs/T1FOZHB4ET1RCvBVdK HTTP/1.1
Host: 10.0.0.1:7500
Date: Fri, 30 Nov 2012 03:05:00 GMT
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Fri, 30 Nov 2012 03:05:00 GMT
Content-Length: 0
Connection: keep-alive
</pre>

下面这个请求，将会使用tfs这个appkey隐藏TFS文件T1FOZHB4ET1RCvBVdK.jpg：

<pre>
DELETE /v1/tfs/T1FOZHB4ET1RCvBVdK.jpg?hide=1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Fri, 30 Nov 2012 03:05:00 GMT
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Fri, 30 Nov 2012 03:05:00 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###获取文件元信息(stat)

####描述

此API用于获取一个TFS文件的元信息，将以JSON格式返回

####语法

>GET /<b>v1</b>/<i>appkey</i>/<b>metadata</b>/<i>TfsFileName</i> HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符，若无使用RcServer，使用<b>tfs</b>即可

TfsFileName是要读取的TFS文件的文件名，可带后缀

####请求参数

<table>
	<tr align="left">
		<th>参数名</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>suffix</td>
		<td>文件后缀<br>注：若指定了此参数，并且TfsFileName中也带了后缀，两者不一致将无法访问文件</td>
	</tr>
	<tr align="left">
		<td>type</td>
		<td>是否强制获取：<br>0：正常获取，若文件被删除或隐藏则无法获取<br>1：强制获取，即使文件被删除或隐藏也可获取</td>
	</tr>
</table>

####应答

<table>
	<tr align="left">
		<th>名称</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>FILE_NAME</td>
		<td>文件名</td>
	</tr>
	<tr align="left">
		<td>BLOCK_ID</td>
		<td>文件所在block的id</td>
	</tr>
	<tr align="left">
		<td>FILE_ID</td>
		<td>文件的file id</td>
	</tr>
	<tr align="left">
		<td>OFFSET</td>
		<td>文件在其所在block中的偏移</td>
	</tr>
	<tr align="left">
		<td>SIZE</td>
		<td>文件大小</td>
	</tr>
	<tr align="left">
		<td>OCCUPY_SIZE</td>
		<td>文件真正占用空间</td>
	</tr>
	<tr align="left">
		<td>MODIFY_TIME</td>
		<td>文件的最后修改时间</td>
	</tr>
	<tr align="left">
		<td>CREATE_TIME</td>
		<td>文件的创建时间</td>
	</tr>
	<tr align="left">
		<td>STATUS</td>
		<td>文件的状态<br>0：正常<br>1：删除<br>4：隐藏<br>5: 隐藏且删除</td>
	</tr>
	<tr align="left">
		<td>CRC</td>
		<td>文件的CRC校验码</td>
	</tr>
</table>

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 OK</td>
		<td>操作成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>错误的请求</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>文件不存在</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey获取文件T1FOZHB4ET1RCvBVdK的元信息：

<pre>
GET /v1/tfs/metadata/T1FOZHB4ET1RCvBVdK HTTP/1.1
Host: 10.0.0.1:7500
Date: Fri, 30 Nov 2012 03:05:00 GMT
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Fri, 30 Nov 2012 03:05:00 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive

{
    "FILE_NAME": "T1FOZHB4ET1RCvBVdK",
    "BLOCK_ID": 101,
    "FILE_ID": 9223190836479524436,
    "OFFSET": 69563585,
    "SIZE": 103578,
    "OCCUPY_SIZE": 103614,
    "MODIFY_TIME": "Fri, 09 Mar 2012 13:40:32 UTC+0800",
    "CREATE_TIME": "Fri, 09 Mar 2012 13:40:32 UTC+0800",
    "STATUS": 0,
    "CRC": 3208008078
}
</pre>

##自定义文件名

###获取APPID

####描述

此API用于获取每个TFS应用的appid，以JSON格式返回。每个应用根据自己的appkey，可以获取到一个唯一的appid，这个appid是所有自定义文件名操作所必需的参数。它代表一个应用在TFS中的一个独立的名字空间。

####语法

>GET /<b>v2</b>/<i>appkey</i>/<i>appid</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符

####请求参数

无

####应答

<table>
	<tr align="left">
		<th>名称</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>APP_ID</td>
		<td>应用的appid</td>
	</tr>
</table>

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 OK</td>
		<td>操作成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>错误的请求</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>登录失败（未在RcServer数据库中配置应用），或TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会查询appkey为tfs的应用的appid：

<pre>
GET /v2/tfs/appid HTTP/1.1
Host: 10.0.0.1:7500
Date: Thu, 28 Jun 2012 08:00:26 GMT

</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Thu, 28 Jun 2012 08:00:26 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive

{
    "APP_ID": "1"
}
</pre>

###创建目录(create_dir)

####描述

此API用于创建一个目录

####语法

>POST /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>dir</b>/<i>dir_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符

appid是应用的appkey对应的appid，可通过<b>获取APPID</b>的API获得

uid是用户id，每个appid和uid的组合对应一个独立的名字空间，可以认为是appid对应的名字空间下的子空间

####请求参数

<table>
	<tr align="left">
		<th>参数名</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>recursive</td>
		<td>1：递归创建父目录<br>0：不递归创建父目录</td>
	</tr>
</table>

####应答

无

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>201 Created</td>
		<td>创建成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>目录名不合规范</td>
	</tr>
	<tr align="left">
		<td>401 Unauthorized</td>
		<td>无权限（目前每个应用只对自己的appid下的空间拥有修改权限）</td>
	</tr>
	<tr align="left">
		<td>403 Forbidden</td>
		<td>超过最大子目录数、子文件数或目录深度</td>
	</tr>
	<tr align="left">
		<td>409 Conflict</td>
		<td>目录已存在</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey在appid为1，uid为1234的名字空间下创建一个/dir_1的目录：

<pre>
POST /v2/tfs/1/1234/dir/dir_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Fri, 30 Nov 2012 03:05:00 GMT
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 201 Created
Server: Tengine/1.3.0
Date: Wed, 27 Jun 2012 14:59:27 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###删除目录(rm_dir)

####描述

此API用于删除一个目录

####语法

>DELETE /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>dir</b>/<i>dir_name</i> HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符

appid是应用的appkey对应的appid，可通过<b>获取APPID</b>的API获得

uid是用户id，每个appid和uid的组合对应一个独立的名字空间，可以认为是appid对应的名字空间下的子空间

####请求参数

无

####应答

无

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>删除成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>目录/文件名不合规范</td>
	</tr>
	<tr align="left">
		<td>401 Unauthorized</td>
		<td>无权限（目前每个应用只对自己的appid下的空间拥有修改权限）</td>
	</tr>
	<tr align="left">
		<td>403 Forbidden</td>
		<td>目录非空</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>目录或父目录不存在</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey在appid为1，uid为1234的名字空间下删除/dir_1目录：

<pre>
DELETE /v2/tfs/1/1234/dir/dir_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Thu, 28 Jun 2012 08:12:13 GMT
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Thu, 28 Jun 2012 08:12:13 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###移动/重命名目录（mv_dir）

####描述

此API用于移动或重命名一个目录

####语法

>POST /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>dir</b>/<i>dest_dir_name</i> HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

>x-ali-move-source: /<i>src_dir_name</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符

appid是应用的appkey对应的appid，可通过<b>获取APPID</b>的API获得

uid是用户id，每个appid和uid的组合对应一个独立的名字空间，可以认为是appid对应的名字空间下的子空间

此API需要一个特定的header，指定源目录路径

####请求参数

<table>
	<tr align="left">
		<th>参数名</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>recursive</td>
		<td>1：递归创建目的目录的父目录<br>0：不递归创建目的目录的父目录</td>
	</tr>
</table>

####应答

无

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>操作成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>目录/文件名不合规范</td>
	</tr>
	<tr align="left">
		<td>401 Unauthorized</td>
		<td>无权限（目前每个应用只对自己的appid下的空间拥有修改权限）</td>
	</tr>
	<tr align="left">
		<td>403 Forbidden</td>
		<td>移动到子目录中</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>源目录或父目录不存在，或目的目录已存在，或目的父目录不存在</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey在appid为1，uid为1234的名字空间下将目录/dir_src重命名为/dir_dest：

<pre>
POST /v2/tfs/1/1234/dir/dir_dest HTTP/1.1
Host: 10.0.0.1:7500
Date: Sat, 30 Jun 2012 05:33:05 GMT
x-ali-move-source: /dir_src
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Sat, 30 Jun 2012 05:33:05 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###列目录（ls_dir）

####描述

此API用于列出目录下所有子目录和文件，并以json数组的格式返回。

####语法

>GET /<b>v2</b>/<i>appkey</i>/<b>metadata</b>/<i>appid</i>/<i>uid</i>/<b>dir</b>/<i>dir_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符

appid是应用的appkey对应的appid，可通过<b>获取APPID</b>的API获得

uid是用户id，每个appid和uid的组合对应一个独立的名字空间，可以认为是appid对应的名字空间下的子空间

####请求参数

无

####应答

<table>
	<tr align="left">
		<th>名称</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>NAME</td>
		<td>文件/目录名</td>
	</tr>
	<tr align="left">
		<td>PID</td>
		<td>文件/目录的父目录的id</td>
	</tr>
	<tr align="left">
		<td>ID</td>
		<td>文件/目录的id</td>
	</tr>
	<tr align="left">
		<td>SIZE</td>
		<td>文件的大小</td>
	</tr>
	<tr align="left">
		<td>IS_FILE</td>
		<td>是否是文件</td>
	</tr>
	<tr align="left">
		<td>CREATE_TIME</td>
		<td>文件/目录的创建时间</td>
	</tr>
	<tr align="left">
		<td>MODIFY_TIME</td>
		<td>文件/目录的最后修改时间</td>
	</tr>
	<tr align="left">
		<td>VER_NO</td>
		<td>文件/目录版本号</td>
	</tr>
</table>

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>操作成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>目录/文件名不合规范</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>目录或父目录不存在</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey在appid为1，uid为1234的名字空间下列出目录“/”下的所有子目录和文件：

<pre>
GET /v2/tfs/metadata/1/1234/dir/ HTTP/1.1
Host: 10.0.0.1:7500
Date: Sat, 30 Jun 2012 05:42:25 GMT
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Sat, 30 Jun 2012 05:42:25 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive

[
    {
        "NAME": "d_0",
        "PID": 635213,
        "ID": 635218,
        "SIZE": 0,
        "IS_FILE": false,
        "CREATE_TIME": "Wed, 27 Jun 2012 10:32:04 UTC+0800",
        "MODIFY_TIME": "Wed, 27 Jun 2012 11:29:30 UTC+0800",
        "VER_NO": 0
    },
    {
        "NAME": "d_3",
        "PID": 635213,
        "ID": 635219,
        "SIZE": 0,
        "IS_FILE": false,
        "CREATE_TIME": "Wed, 27 Jun 2012 10:36:17 UTC+0800",
        "MODIFY_TIME": "Sat, 30 Jun 2012 13:32:53 UTC+0800",
        "VER_NO": 0
    },
    {
        "NAME": "file_1",
        "PID": -9223372036854140595,
        "ID": 0,
        "SIZE": 222,
        "IS_FILE": true,
        "CREATE_TIME": "Wed, 27 Jun 2012 17:13:23 UTC+0800",
        "MODIFY_TIME": "Wed, 27 Jun 2012 17:25:03 UTC+0800",
        "VER_NO": 1
    }
]
</pre>

###查看目录是否存在

####描述

此API用于查看指定目录是否存在

####语法

>HEAD /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>dir</b>/<i>dir_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符

appid是应用的appkey对应的appid，可通过<b>获取APPID</b>的API获得

uid是用户id，每个appid和uid的组合对应一个独立的名字空间，可以认为是appid对应的名字空间下的子空间

####请求参数

无

####应答

无

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>目录存在</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>目录名不合规范</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>目录不存在</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey在appid为1，uid为1234的名字空间下查看目录“/dir_1”是否存在：

<pre>
HEAD /v2/tfs/1/1234/dir/dir_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Sat, 30 Jun 2012 05:42:25 GMT
</pre>

假如目录存在，对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Sat, 30 Jun 2012 05:42:25 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###创建文件(create_file)

####描述

此API用于创建一个文件

####语法
>POST /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>file</b>/<i>file_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符

appid是应用的appkey对应的appid，可通过<b>获取APPID</b>的API获得

uid是用户id，每个appid和uid的组合对应一个独立的名字空间，可以认为是appid对应的名字空间下的子空间

####请求参数

<table>
	<tr align="left">
		<th>参数名</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>recursive</td>
		<td>1：递归创建父目录<br>0：不递归创建父目录</td>
	</tr>
</table>

####应答

无

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>201 Created</td>
		<td>创建成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>文件名不合规范</td>
	</tr>
	<tr align="left">
		<td>401 Unauthorized</td>
		<td>无权限（目前每个应用只对自己的appid下的空间拥有修改权限）</td>
	</tr>
	<tr align="left">
		<td>403 Forbidden</td>
		<td>超过最大子目录数、子文件数或目录深度</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>父目录不存在</td>
	</tr>
	<tr align="left">
		<td>409 Conflict</td>
		<td>文件已存在</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey在appid为1，uid为1234的名字空间下创建一个/file_1的文件：

<pre>
POST /v2/tfs/1/1234/file/file_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Fri, 30 Nov 2012 03:05:00 GMT
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 201 Created
Server: Tengine/1.3.0
Date: Wed, 27 Jun 2012 14:59:27 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###写文件(write_file)

####描述

此API用于向一个文件写数据。自定义文件名支持多次写入，支持pwrite（指定偏移写，可通过offset参数指定偏移量，支持文件空洞），默认为追加写。

注：不支持更新已有数据

####语法

>PUT /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>file</b>/<i>file_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Content-Length: <i>length</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符

appid是应用的appkey对应的appid，可通过<b>获取APPID</b>的API获得

uid是用户id，每个appid和uid的组合对应一个独立的名字空间，可以认为是appid对应的名字空间下的子空间

####请求参数

<table>
	<tr align="left">
		<th>参数名</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>offset</td>
		<td>要写入的偏移</td>
	</tr>
	<tr align="left">
		<td>size</td>
		<td>要写入的数据长度</td>
	</tr>
</table>

####应答

无

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>操作成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>文件名不合规范或参数不合法</td>
	</tr>
	<tr align="left">
		<td>401 Unauthorized</td>
		<td>无权限（目前每个应用只对自己的appid下的空间拥有修改权限）</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>文件不存在</td>
	</tr>
	<tr align="left">
		<td>409 Conflict</td>
		<td>写偏移处已存在数据</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey向appid为1，uid为1234的名字空间下的文件/file_1写入数据：

<pre>
PUT /v2/tfs/1/1234/file/file_1 HTTP/1.1
Host: 10.0.0.1:7500
Content-Length: 222
Date: Wed, 27 Jun 2012 14:59:27 GMT

[Data]
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Wed, 27 Jun 2012 14:59:27 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###读文件(read_file)

####描述

此API用于从一个文件中读数据。

####语法

>GET /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>file</b>/<i>file_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符

appid是应用的appkey对应的appid，可通过<b>获取APPID</b>的API获得

uid是用户id，每个appid和uid的组合对应一个独立的名字空间，可以认为是appid对应的名字空间下的子空间

####请求参数

<table>
	<tr align="left">
		<th>参数名</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>offset</td>
		<td>要读取数据在文件中的偏移</td>
	</tr>
	<tr align="left">
		<td>size</td>
		<td>要读取的数据长度</td>
	</tr>
</table>

####应答

<table>
	<tr align="left">
		<th>名称</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>data</td>
		<td>数据</td>
	</tr>
</table>

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>操作成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>文件名不合规范或参数不合法</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>文件不存在</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey从appid为1，uid为1234的名字空间下读取文件/file_1（整个文件）：

<pre>
GET /v2/tfs/1/1234/file/file_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Wed, 27 Jun 2012 14:59:27 GMT
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Wed, 27 Jun 2012 14:59:27 GMT
Content-Length: 222
Connection: keep-alive

[data]
</pre>

###删除文件(rm_file)

####描述

此API用于删除一个文件

####语法

>DELETE /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>file</b>/<i>file_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符

appid是应用的appkey对应的appid，可通过<b>获取APPID</b>的API获得

uid是用户id，每个appid和uid的组合对应一个独立的名字空间，可以认为是appid对应的名字空间下的子空间

####请求参数

无

####应答

无

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>操作成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>文件名不合规范</td>
	</tr>
	<tr align="left">
		<td>401 Unauthorized</td>
		<td>无权限（目前每个应用只对自己的appid下的空间拥有修改权限）</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>文件不存在</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey在appid为1，uid为1234的名字空间下删除/file_1文件：

<pre>
DELETE /v2/tfs/1/1234/file/file_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Thu, 28 Jun 2012 08:12:13 GMT
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Thu, 28 Jun 2012 08:12:13 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###移动/重命名文件（mv_file）

####描述

此API用于移动或重命名一个文件

####语法

>POST /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>file</b>/<i>dest_file_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

>x-ali-move-source: /<i>src_file_name</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符

appid是应用的appkey对应的appid，可通过<b>获取APPID</b>的API获得

uid是用户id，每个appid和uid的组合对应一个独立的名字空间，可以认为是appid对应的名字空间下的子空间

此API需要一个特定的header，指定要移动或重命名的源文件路径

####请求参数

<table>
	<tr align="left">
		<th>参数名</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>recursive</td>
		<td>1：递归创建目的文件的父目录<br>0：不递归创建目的文件的父目录</td>
	</tr>
</table>

####应答

无

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>操作成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>文件名不合规范或源文件和目的文件相同</td>
	</tr>
	<tr align="left">
		<td>401 Unauthorized</td>
		<td>无权限（目前每个应用只对自己的appid下的空间拥有修改权限）</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>源文件不存在，或目的文件已存在，或目的文件父目录不存在</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey在appid为1，uid为1234的名字空间下将文件/file_src重命名为/file\_dest：

<pre>
POST /v2/tfs/1/1234/file/file_dest HTTP/1.1
Host: 10.0.0.1:7500
Date: Sat, 30 Jun 2012 05:33:05 GMT
x-ali-move-source: /file_src
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Sat, 30 Jun 2012 05:33:05 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###列文件元信息（ls_file）

####描述

此API用于列出文件的元信息

####语法

>GET /<b>v2</b>/<i>appkey</i>/<b>metadata</b>/<i>appid</i>/<i>uid</i>/<b>file</b>/<i>file_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符

appid是应用的appkey对应的appid，可通过<b>获取APPID</b>的API获得

uid是用户id，每个appid和uid的组合对应一个独立的名字空间，可以认为是appid对应的名字空间下的子空间

####请求参数

无

####应答

<table>
	<tr align="left">
		<th>名称</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>NAME</td>
		<td>文件名(绝对路径）</td>
	</tr>
	<tr align="left">
		<td>PID</td>
		<td>文件的父目录的id</td>
	</tr>
	<tr align="left">
		<td>ID</td>
		<td>文件的id</td>
	</tr>
	<tr align="left">
		<td>SIZE</td>
		<td>文件的大小</td>
	</tr>
	<tr align="left">
		<td>IS_FILE</td>
		<td>是否是文件</td>
	</tr>
	<tr align="left">
		<td>CREATE_TIME</td>
		<td>文件的创建时间</td>
	</tr>
	<tr align="left">
		<td>MODIFY_TIME</td>
		<td>文件的最后修改时间</td>
	</tr>
	<tr align="left">
		<td>VER_NO</td>
		<td>文件的版本号</td>
	</tr>
</table>

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>操作成功</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>文件名不合规范</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>文件不存在</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey在appid为1，uid为1234的名字空间下列出文件“/file_1”的元信息：

<pre>
GET /v2/tfs/metadata/1/1234/file/file_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Sat, 30 Jun 2012 05:42:25 GMT
</pre>

对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Sat, 30 Jun 2012 05:42:25 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive

{
    "NAME": "/file_1",
    "PID": 635213,
    "ID": 0,
    "SIZE": 298481,
    "IS_FILE": true,
    "CREATE_TIME": "Fri, 15 Jun 2012 09:37:39 UTC+0800",
    "MODIFY_TIME": "Sat, 30 Jun 2012 23:57:38 UTC+0800",
    "VER_NO": 0
}
</pre>

###查看文件是否存在

####描述

此API用于查看指定文件是否存在

####语法

>HEAD /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>file</b>/<i>file_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

其中<i>appkey</i>是在RcServer的数据库中配置的应用的标识符

appid是应用的appkey对应的appid，可通过<b>获取APPID</b>的API获得

uid是用户id，每个appid和uid的组合对应一个独立的名字空间，可以认为是appid对应的名字空间下的子空间

####请求参数

无

####应答

无

####返回的状态码

<table>
	<tr align="left">
		<th>HTTP状态码</th>
		<th>描述</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>文件存在</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>文件名不合规范</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>文件不存在</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>TFS或Nginx服务器内部错误</td>
	</tr>
</table>

####例子

下面这个请求，将会使用tfs这个appkey在appid为1，uid为1234的名字空间下查看文件“/file_1”是否存在：

<pre>
HEAD /v2/tfs/1/1234/file/file_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Sat, 30 Jun 2012 05:42:25 GMT
</pre>

假如文件存在，对应的应答将会是：

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Sat, 30 Jun 2012 05:42:25 GMT
Content-Length: 0
Connection: keep-alive
</pre>
