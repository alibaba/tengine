# 模块名 #

**ngx\_http\_core\_module**

Tengine针对此模块进行了增强，下面列出了一些增加的指令。


# 指令 #

## client\_body\_buffers ##

Syntax: **client\_body\_buffers** `number size`

Default: 16 4k/8k

Context: `http, server, location`
                                 
当不缓存上传的请求body到磁盘时，指定每块缓存块大小和数量。所有的缓存块都保存在内存中，并且是按需分配的。默认情况下，缓存块等于系统页的大小。总缓存大小必须大于`client_body_postpone_size`指令的大小。

## client\_body\_postpone\_size ##

Syntax: **client\_body\_postpone\_size** `size`

Default: 64k

Context: `http, server, location`

当打开`proxy_request_buffering`或`fastcgi_request_buffering`指令，设置不缓存请求body到磁盘时，tengine每当接受到大于`client_body_postpone_size`大小的数据或者整个请求都发送完毕，才会往后端发送数据。这可以减少与后端服务器建立的连接数，并减少网络IO的次数。
                                 
## proxy\_request\_buffering ##

Syntax: **proxy\_request\_buffering** `on | off`

Default: `on`

Context: `http, server, location`

指定当上传请求body时是否要将body缓存到磁盘。如果设成off，请求body只会被保存到内存，每当tengine接收到大于`client_body_postpone_size`的数据时，就发送这部分数据到后端服务器。

默认情况下，当请求body大于`client_body_buffer_size`时，就会被保存到磁盘。这会增加磁盘IO，对于上传应用来说，服务器的负载会明显增加。

需要注意的是，如果你配置成off且已经发出部分数据，tengine的重试机制就会失效。如果后端返回异常响应，tengine就会直接返回500。此时$request_body，$request_body_file也会不可用，他们保存的可能是不完整的内容。

额外注意的是，当tengine开启了spdy时，`proxy_request_buffering off`不会起效。

## fastcgi\_request\_buffering ##

Syntax: **fastcgi\_request\_buffering** `on | off`

Default: `on`

Context: `http, server, location`

用法跟`proxy_request_buffering`指令一样。

## gzip\_clear\_etag ##

Syntax: **gzip\_clear\_etag** `on | off`

Default: `on`

Context: `http, server, location`

压缩的时候是否删除"ETag"响应头。

