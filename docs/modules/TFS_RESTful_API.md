#TFS RESTful API

NOTE: <b>bold</b> words are fixed and reserved for API, <i>italics</i> words are input arguments.

##Raw TFS

###WRITE

####Description

The implementation of WRITE operation stores data as a TFS file. File name is returned in JSON format.

####Syntax

>POST /<b>v1</b>/<i>appkey</i> HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Content-Length: <i>length</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database. If you are not using RcServer, use <b>tfs</b> as appkey.

####Request Parameters

<table>
	<tr align="left">
		<th>parameter</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>suffix</td>
		<td>file suffix</td>
	</tr>
	<tr align="left">
		<td>simple_name</td>
		<td>whether require the right suffix to access the file<br>1: require the right suffix to access<br>0: no such restrict</td>
	</tr>
	<tr align="left">
		<td>large_file</td>
		<td>whether save as large file(file name will start with 'L')<br>1: save as large file<br>0: do not save as large file</td>
	</tr>
</table>

####Response

<table>
	<tr align="left">
		<th>name</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>TFS_FILE_NAME</td>
		<td>TFS file name returned</td>
	</tr>
</table>

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 OK</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>bad request</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey to write a TFS file without suffix:
<pre>
POST /v1/tfs HTTP/1.1
Host: 10.0.0.1:7500
Content-Length: 22
Date: Fri, 30 Nov 2012 03:05:00 GMT

[data]
</pre>

The corresponding response will be:

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

The following request will use tfs as appkey to write a TFS file with ".jpg" as its suffix. Access with this suffix is required.

<pre>
POST /v1/tfs?suffix=.jpg&simple_name=1 HTTP/1.1
Host: 10.0.0.1:7500
Content-Length: 22
Date: Fri, 30 Nov 2012 03:05:00 GMT

[data]
</pre>

The corresponding response will be:

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

###UPDATE

####Description

The implementation of UPDATE updates a existing TFS file. Also a TFS file name will returned in JSON format.

####Syntax

>PUT /<b>v1</b>/<i>appkey</i>/<i>TfsFileName</i> HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Content-Length: <i>length</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database. If you are not using RcServer, use <b>tfs</b> as appkey.

####Request Parameters

<table>
	<tr align="left">
		<th>parameter</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>suffix</td>
		<td>file suffix</td>
	</tr>
	<tr align="left">
		<td>simple_name</td>
		<td>whether require the right suffix to access the file<br>1: require the right suffix to access<br>0: no such restrict</td>
	</tr>
</table>

####Response

<table>
	<tr align="left">
		<th>name</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>TFS_FILE_NAME</td>
		<td>TFS file name returned</td>
	</tr>
</table>

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 OK</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>bad request</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey to update the TFS file T1FOZHB4ET1RCvBVdK:
<pre>
PUT /v1/tfs/T1FOZHB4ET1RCvBVdK HTTP/1.1
Host: 10.0.0.1:7500
Content-Length: 22
Date: Fri, 30 Nov 2012 03:05:00 GMT

[data]
</pre>

The corresponding response will be:

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

###READ

####Description

The implementation of READ reads data from a TFS file.

####Syntax
>GET /<b>v1</b>/<i>appkey</i>/<i>TfsFileName</i> HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database. If you are not using RcServer, use <b>tfs</b> as appkey.

####Request Parameters

<table>
	<tr align="left">
		<th>parameter</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>suffix</td>
		<td>file suffix<br>NOTE: If this parameter is given, and there is another different suffix in TfsFileName, then the access will fail.</td>
	</tr>
	<tr align="left">
		<td>offset</td>
		<td>offset to read in the file</td>
	</tr>
	<tr align="left">
		<td>size</td>
		<td>size to read</td>
	</tr>
</table>


####Response

<table>
	<tr align="left">
		<th>name</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>data</td>
		<td>data readed</td>
	</tr>
</table>

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 OK</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>bad request</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>file not found</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey to read file T1FOZHB4ET1RCvBVdK:

<pre>
GET /v1/tfs/T1FOZHB4ET1RCvBVdK HTTP/1.1
Host: 10.0.0.1:7500
Date: Fri, 30 Nov 2012 03:05:00 GMT
</pre>

The corresponding response will be:

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Fri, 30 Nov 2012 03:05:00 GMT
Last-Modified: Thu, 29 Nov 2012 03:05:00 GMT
Transfer-Encoding: chunked
Connection: keep-alive

[data]
</pre>

The following request will use tfs as appkey to read file T1FOZHB4ET1RCvBVdK.jpg:

<pre>
GET /v1/tfs/T1FOZHB4ET1RCvBVdK.jpg HTTP/1.1
Host: 10.0.0.1:7500
Date: Fri, 30 Nov 2012 03:05:00 GMT
</pre>

The corresponding response will be:

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Fri, 30 Nov 2012 03:05:00 GMT
Last-Modified: Thu, 29 Nov 2012 03:05:00 GMT
Transfer-Encoding: chunked
Connection: keep-alive

[data]
</pre>

###DELETE

####Description

The implementation of DELETE deletes or conceal a TFS file.

####Syntax

>DELETE /<b>v1</b>/<i>appkey</i>/<i>TfsFileName</i> HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database. If you are not using RcServer, use <b>tfs</b> as appkey.

####Request Parameters

<table>
	<tr align="left">
		<th>parameter</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>suffix</td>
		<td>file suffix<br>NOTE: If this parameter is given, and there is another different suffix in TfsFileName, then the access will fail.</td>
	</tr>
	<tr align="left">
		<td>hide</td>
		<td>specify the operation of conceal:<br>1: conceal<br>0: reveal</td>
	</tr>
</table>

####Response

No

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 OK</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>bad request</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>file not found</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey to delete file T1FOZHB4ET1RCvBVdK:

<pre>
DELETE /v1/tfs/T1FOZHB4ET1RCvBVdK HTTP/1.1
Host: 10.0.0.1:7500
Date: Fri, 30 Nov 2012 03:05:00 GMT
</pre>

The corresponding response will be:

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Fri, 30 Nov 2012 03:05:00 GMT
Content-Length: 0
Connection: keep-alive
</pre>

The following request will use tfs as appkey to conceal file T1FOZHB4ET1RCvBVdK.jpg:

<pre>
DELETE /v1/tfs/T1FOZHB4ET1RCvBVdK.jpg?hide=1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Fri, 30 Nov 2012 03:05:00 GMT
</pre>

The corresponding response will be:

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Fri, 30 Nov 2012 03:05:00 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###STAT

####Description

The implementation of STAT achieve the meta data of a TFS file. The meta data will be returned in JSON format.

####Syntax

>GET /<b>v1</b>/<i>appkey</i>/<b>metadata</b>/<i>TfsFileName</i> HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database. If you are not using RcServer, use <b>tfs</b> as appkey.

####Request Parameters

<table>
	<tr align="left">
		<th>parameter</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>suffix</td>
		<td>file suffix<br>NOTE: If this parameter is given, and there is another different suffix in TfsFileName, then the access will fail.</td>
	</tr>
	<tr align="left">
		<td>type</td>
		<td>achieve type:<br>0: normal, will fail if file is deleted or concealed.<br>1: force, will success even if file is deleted or concealed.</td>
	</tr>
</table>

####Response

<table>
	<tr align="left">
		<th>name</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>FILE_NAME</td>
		<td>file name</td>
	</tr>
	<tr align="left">
		<td>BLOCK_ID</td>
		<td>id of the block that contains this file</td>
	</tr>
	<tr align="left">
		<td>FILE_ID</td>
		<td>file id</td>
	</tr>
	<tr align="left">
		<td>OFFSET</td>
		<td>file offset inside the block</td>
	</tr>
	<tr align="left">
		<td>SIZE</td>
		<td>file size</td>
	</tr>
	<tr align="left">
		<td>OCCUPY_SIZE</td>
		<td>occupy size of file</td>
	</tr>
	<tr align="left">
		<td>MODIFY_TIME</td>
		<td>modify time</td>
	</tr>
	<tr align="left">
		<td>CREATE_TIME</td>
		<td>create time</td>
	</tr>
	<tr align="left">
		<td>STATUS</td>
		<td>status of file<br>0: normal<br>1: deleted<br>4: concealed<br>5: concealed and deleted</td>
	</tr>
	<tr align="left">
		<td>CRC</td>
		<td>crc of file data</td>
	</tr>
</table>

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 OK</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>bad request</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>file not found</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey to stat file T1FOZHB4ET1RCvBVdK:

<pre>
GET /v1/tfs/metadata/T1FOZHB4ET1RCvBVdK HTTP/1.1
Host: 10.0.0.1:7500
Date: Fri, 30 Nov 2012 03:05:00 GMT
</pre>

The corresponding response will be:

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

##Custom TFS

###GET_APPID

####Description

The implementation of GET_APPID gets appid of the specified TFS application. Appid is returned in JSON format. Each application can get a unique appid corresponding to its appkdy. This appid is a required paramter in each Custom TFS operation. You can consider this as a namespace in TFS.

####Syntax

>GET /<b>v2</b>/<i>appkey</i>/<i>appid</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database.

####Request Parameters

No

####Response

<table>
	<tr align="left">
		<th>name</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>APP_ID</td>
		<td>appid of application</td>
	</tr>
</table>

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 OK</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>bad request</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>login failed(maybe this appkey is not configured in RcServer database) or internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will query the appid of appkey tfs:

<pre>
GET /v2/tfs/appid HTTP/1.1
Host: 10.0.0.1:7500
Date: Thu, 28 Jun 2012 08:00:26 GMT

</pre>

The corresponding response will be:

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

###CREATE_DIR

####Description

The implementation of CREATE_DIR creates a dir.

####Syntax

>POST /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>dir</b>/<i>dir_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database.

Appid can be achieved by the API <b>GET_APPID</b>.

Uid is short for user id, each appid and uid makes a unique namespace in TFS.

####Request Parameters

<table>
	<tr align="left">
		<th>parameter</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>recursive</td>
		<td>1: recursively create parent dirs<br>0: do not recursively create parent dirs</td>
	</tr>
</table>

####Response

No

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>201 Created</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>invalid dir name</td>
	</tr>
	<tr align="left">
		<td>401 Unauthorized</td>
		<td>do not have permission(each application is only allowed to modify its namespace(under its appid))</td>
	</tr>
	<tr align="left">
		<td>403 Forbidden</td>
		<td>subdir count/subfile count/dir depth exceeds the restrict</td>
	</tr>
	<tr align="left">
		<td>409 Conflict</td>
		<td>dir already exists</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey, create "/dir_1" under the namespace of appid 1 and uid 1234:

<pre>
POST /v2/tfs/1/1234/dir/dir_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Fri, 30 Nov 2012 03:05:00 GMT
</pre>

The corresponding response will be:

<pre>
HTTP/1.1 201 Created
Server: Tengine/1.3.0
Date: Wed, 27 Jun 2012 14:59:27 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###RM_DIR

####Description

The implementation of RM_DIR removes a dir.

####Syntax

>DELETE /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>dir</b>/<i>dir_name</i> HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database.

Appid can be achieved by the API <b>GET_APPID</b>.

Uid is short for user id, each appid and uid makes a unique namespace in TFS.

####Request Parameters

No

####Response

No

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>invalid dir name</td>
	</tr>
	<tr align="left">
		<td>401 Unauthorized</td>
		<td>do not have permission(each application is only allowed to modify its namespace(under its appid))</td>
	</tr>
	<tr align="left">
		<td>403 Forbidden</td>
		<td>dir is not empty</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>dir or parent dir not exist</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs appkey, remove "/dir_1" under the namespace of appid 1 uid 1234:

<pre>
DELETE /v2/tfs/1/1234/dir/dir_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Thu, 28 Jun 2012 08:12:13 GMT
</pre>

The corresponding response will be:

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Thu, 28 Jun 2012 08:12:13 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###MV_DIR

####Description

The implementation of MV_DIR moves or renames a dir.

####Syntax

>POST /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>dir</b>/<i>dest_dir_name</i> HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

>x-ali-move-source: /<i>src_dir_name</i>

<i>appkey</i> is an id of an application configured in RcServer database.

Appid can be achieved by the API <b>GET_APPID</b>.

Uid is short for user id, each appid and uid makes a unique namespace in TFS.

A custom HTTP request header is needed here to specify the src dir.

####Request Parameters

<table>
	<tr align="left">
		<th>parameter</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>recursive</td>
		<td>1: recursively create parent dirs of the dest dir<br>0: do not recursively create parent dirs of the dest dir</td>
	</tr>
</table>

####Response

No

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>invalid dir name</td>
	</tr>
	<tr align="left">
		<td>401 Unauthorized</td>
		<td>do not have permission(each application is only allowed to modify its namespace(under its appid))</td>
	</tr>
	<tr align="left">
		<td>403 Forbidden</td>
		<td>move to subdir</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>src dir or parent dir not exist, or dest dir already exists, or parent dir of dest dir not exist</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey, rename "/dir_src" as "/dir_dest" under the namespace of appid 1 uid 1234:

<pre>
POST /v2/tfs/1/1234/dir/dir_dest HTTP/1.1
Host: 10.0.0.1:7500
Date: Sat, 30 Jun 2012 05:33:05 GMT
x-ali-move-source: /dir_src
</pre>

The corresponding response will be:

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Sat, 30 Jun 2012 05:33:05 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###LS_DIR

####Description

The implementation of LS_DIR lists all subdirs and subfiles. Subdirs and subfiles are returned in JSON format.

####Syntax

>GET /<b>v2</b>/<i>appkey</i>/<b>metadata</b>/<i>appid</i>/<i>uid</i>/<b>dir</b>/<i>dir_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database.

Appid can be achieved by the API <b>GET_APPID</b>.

Uid is short for user id, each appid and uid makes a unique namespace in TFS.

####Request Parameters

No

####Response

<table>
	<tr align="left">
		<th>name</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>NAME</td>
		<td>file/dir name/td>
	</tr>
	<tr align="left">
		<td>PID</td>
		<td>if of the parent dir of file/dir</td>
	</tr>
	<tr align="left">
		<td>ID</td>
		<td>if of file/dir</td>
	</tr>
	<tr align="left">
		<td>SIZE</td>
		<td>file size</td>
	</tr>
	<tr align="left">
		<td>IS_FILE</td>
		<td>is file or not</td>
	</tr>
	<tr align="left">
		<td>CREATE_TIME</td>
		<td>create time</td>
	</tr>
	<tr align="left">
		<td>MODIFY_TIME</td>
		<td>modify time/td>
	</tr>
	<tr align="left">
		<td>VER_NO</td>
		<td>version no of file/dir</td>
	</tr>
</table>

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>invalid dir name</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>dir or parent dir not exist</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey, list all subdirs and subfiles of the dir "/" under the namespace of appid 1 and uid 1234:

<pre>
GET /v2/tfs/metadata/1/1234/dir/ HTTP/1.1
Host: 10.0.0.1:7500
Date: Sat, 30 Jun 2012 05:42:25 GMT
</pre>

The corresponding response will be:

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

###IS_DIR_EXIST

####Description

The implementation of IS_DIR_EXIST checks if the specified dir exists.

####Syntax

>HEAD /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>dir</b>/<i>dir_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database.

Appid can be achieved by the API <b>GET_APPID</b>.

Uid is short for user id, each appid and uid makes a unique namespace in TFS.

####Request Parameters

No

####Response

No

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>dir exists</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>invalid dir name</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>dir not exist</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey, check whether dir "/dir_1" exists under the namespace of appid 1 uid 1234:

<pre>
HEAD /v2/tfs/1/1234/dir/dir_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Sat, 30 Jun 2012 05:42:25 GMT
</pre>

If dir exists, the corresponding response will be:

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Sat, 30 Jun 2012 05:42:25 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###CREATE_FILE

####Description

The implementation of CREATE_FILE creates a file.

####Syntax
>POST /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>file</b>/<i>file_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database.

Appid can be achieved by the API <b>GET_APPID</b>.

Uid is short for user id, each appid and uid makes a unique namespace in TFS.

####Request Parameters

<table>
	<tr align="left">
		<th>parameter</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>recursive</td>
		<td>1: recursively create parent dirs<br>0: do not recursively create parent dirs</td>
	</tr>
</table>

####Response

No

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>201 Created</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>invalid file name</td>
	</tr>
	<tr align="left">
		<td>401 Unauthorized</td>
		<td>do not have permission(each application is only allowed to modify its namespace(under its appid))</td>
	</tr>
	<tr align="left">
		<td>403 Forbidden</td>
		<td>subdir count/subfile count/dir depth exceeds the restrict</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>parent dir not exist</td>
	</tr>
	<tr align="left">
		<td>409 Conflict</td>
		<td>file already exists</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey, create "/file_1" under the namespace of appid 1 uid 1234:

<pre>
POST /v2/tfs/1/1234/file/file_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Fri, 30 Nov 2012 03:05:00 GMT
</pre>

The corresponding response will be:

<pre>
HTTP/1.1 201 Created
Server: Tengine/1.3.0
Date: Wed, 27 Jun 2012 14:59:27 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###WRITE_FILE

####Description

The implementation of WRITE_FILE write data to a file. PWRITE is supported. File hole is also supported. Append is used by default.

NOTE: in-place update is not supported.

####Syntax

>PUT /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>file</b>/<i>file_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Content-Length: <i>length</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database.

Appid can be achieved by the API <b>GET_APPID</b>.

Uid is short for user id, each appid and uid makes a unique namespace in TFS.

####Request Parameters

<table>
	<tr align="left">
		<th>parameter</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>offset</td>
		<td>offset to write</td>
	</tr>
	<tr align="left">
		<td>size</td>
		<td>data size to write</td>
	</tr>
</table>

####Response

No

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>invalid file name or parameter</td>
	</tr>
	<tr align="left">
		<td>401 Unauthorized</td>
		<td>do not have permission(each application is only allowed to modify its namespace(under its appid))</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>file not found</td>
	</tr>
	<tr align="left">
		<td>409 Conflict</td>
		<td>data already exists in write offset(in-place update)</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey, write data to "/file_1" under the namespace of appid 1 uid 1234:

<pre>
PUT /v2/tfs/1/1234/file/file_1 HTTP/1.1
Host: 10.0.0.1:7500
Content-Length: 222
Date: Wed, 27 Jun 2012 14:59:27 GMT

[Data]
</pre>

The corresponding response will be:

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Wed, 27 Jun 2012 14:59:27 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###READ_FILE

####Description

The implementation of READ_FILE reads data from a file.

####Syntax

>GET /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>file</b>/<i>file_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database.

Appid can be achieved by the API <b>GET_APPID</b>.

Uid is short for user id, each appid and uid makes a unique namespace in TFS.

####Request Parameters

<table>
	<tr align="left">
		<th>parameter</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>offset</td>
		<td>offset to read</td>
	</tr>
	<tr align="left">
		<td>size</td>
		<td>data size to read</td>
	</tr>
</table>

####Response

<table>
	<tr align="left">
		<th>name</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>data</td>
		<td>data readed</td>
	</tr>
</table>

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>invalid file name or parameter</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>file not found</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey, read data from "/file_1"(whole file) under the namespace of appid 1 uid 1234:

<pre>
GET /v2/tfs/1/1234/file/file_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Wed, 27 Jun 2012 14:59:27 GMT
</pre>

The corresponding response will be:

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Wed, 27 Jun 2012 14:59:27 GMT
Content-Length: 222
Connection: keep-alive

[data]
</pre>

###RM_FILE

####Description

The implementation of RM_FILE removes a file.

####Syntax

>DELETE /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>file</b>/<i>file_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database.

Appid can be achieved by the API <b>GET_APPID</b>.

Uid is short for user id, each appid and uid makes a unique namespace in TFS.

####Request Parameters

No

####Response

No

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>invalid file name</td>
	</tr>
	<tr align="left">
		<td>401 Unauthorized</td>
		<td>do not have permission(each application is only allowed to modify its namespace(under its appid))</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>file not found</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey, remove "/file_1" under the namespace of appid 1 uid 1234:

<pre>
DELETE /v2/tfs/1/1234/file/file_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Thu, 28 Jun 2012 08:12:13 GMT
</pre>

The corresponding response will be:

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Thu, 28 Jun 2012 08:12:13 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###MV_FILE

####Description

The implementation of MV_FILE move or rename a file.

####Syntax

>POST /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>file</b>/<i>dest_file_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

>x-ali-move-source: /<i>src_file_name</i>

<i>appkey</i> is an id of an application configured in RcServer database.

Appid can be achieved by the API <b>GET_APPID</b>.

Uid is short for user id, each appid and uid makes a unique namespace in TFS.

A custom HTTP request header is needed here to specify the src file.

####Request Parameters

<table>
	<tr align="left">
		<th>parameter</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>recursive</td>
		<td>1: recursively create parent dirs of the dest file<br>0: do not recursively create parent dirs of the dest file</td>
	</tr>
</table>

####Response

No

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>invalid file name or src file and dest file are the same file</td>
	</tr>
	<tr align="left">
		<td>401 Unauthorized</td>
		<td>do not have permission(each application is only allowed to modify its namespace(under its appid))</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>src file not exist, or dest file already exists, or parent dir of dest file not exist</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey, rename "/file_src" to "/file_dest" under the namespace of appid 1 uid 1234:

<pre>
POST /v2/tfs/1/1234/file/file_dest HTTP/1.1
Host: 10.0.0.1:7500
Date: Sat, 30 Jun 2012 05:33:05 GMT
x-ali-move-source: /file_src
</pre>

The corresponding response will be:

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Sat, 30 Jun 2012 05:33:05 GMT
Content-Length: 0
Connection: keep-alive
</pre>

###LS_FILE

####Description

The implementation of LS_FILE achieves the meta data of the file.

####Syntax

>GET /<b>v2</b>/<i>appkey</i>/<b>metadata</b>/<i>appid</i>/<i>uid</i>/<b>file</b>/<i>file_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database.

Appid can be achieved by the API <b>GET_APPID</b>.

Uid is short for user id, each appid and uid makes a unique namespace in TFS.

####Request Parameters

No

####Response

<table>
	<tr align="left">
		<th>name</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>NAME</td>
		<td>file name(absolute path)</td>
	</tr>
	<tr align="left">
		<td>PID</td>
		<td>id of the parent dir of the file</td>
	</tr>
	<tr align="left">
		<td>ID</td>
		<td>id of the file</td>
	</tr>
	<tr align="left">
		<td>SIZE</td>
		<td>file size</td>
	</tr>
	<tr align="left">
		<td>IS_FILE</td>
		<td>is file or not</td>
	</tr>
	<tr align="left">
		<td>CREATE_TIME</td>
		<td>create time</td>
	</tr>
	<tr align="left">
		<td>MODIFY_TIME</td>
		<td>modify time</td>
	</tr>
	<tr align="left">
		<td>VER_NO</td>
		<td>version no of file</td>
	</tr>
</table>

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>operation success</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>invalid file name</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>file not found</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey, achieve the meta data of "/file_1" under the namespace of appid 1 uid 1234:

<pre>
GET /v2/tfs/metadata/1/1234/file/file_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Sat, 30 Jun 2012 05:42:25 GMT
</pre>

The corresponding response will be:

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

###IS_FILE_EXIST

####Description

The implementation of IS_FILE_EXIST checks if file exists.

####Syntax

>HEAD /<b>v2</b>/<i>appkey</i>/<i>appid</i>/<i>uid</i>/<b>file</b>/<i>file_name</i>  HTTP/1.1

>Host: <i>10.0.0.1:7500</i>

>Date: <i>date</i>

<i>appkey</i> is an id of an application configured in RcServer database.

Appid can be achieved by the API <b>GET_APPID</b>.

Uid is short for user id, each appid and uid makes a unique namespace in TFS.

####Request Parameters

No

####Response

No

####Status code

<table>
	<tr align="left">
		<th>HTTP status code</th>
		<th>description</th>
	</tr>
	<tr align="left">
		<td>200 Ok</td>
		<td>file exist</td>
	</tr>
	<tr align="left">
		<td>400 Bad Request</td>
		<td>invalid file name</td>
	</tr>
	<tr align="left">
		<td>404 Not Found</td>
		<td>file not found</td>
	</tr>
	<tr align="left">
		<td>500 Internal Server Error</td>
		<td>internal server error in tfs or nginx server</td>
	</tr>
</table>

####Examples

The following request will use tfs as appkey, check if "/file_1" exists under the namespace of appid 1 uid 1234:

<pre>
HEAD /v2/tfs/1/1234/file/file_1 HTTP/1.1
Host: 10.0.0.1:7500
Date: Sat, 30 Jun 2012 05:42:25 GMT
</pre>

If file exists, the corresponding response will be:

<pre>
HTTP/1.1 200 OK
Server: Tengine/1.3.0
Date: Sat, 30 Jun 2012 05:42:25 GMT
Content-Length: 0
Connection: keep-alive
</pre>
