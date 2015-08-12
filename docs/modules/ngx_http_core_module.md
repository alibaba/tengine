# Name #

**ngx\_http\_core\_module**

Tengine added some enhancements to this module. The new directives are listed below.


# Directives #

## client\_body\_buffers ##

Syntax: **client\_body\_buffers** `number size`

Default: 16 4k/8k

Context: `http, server, location`
                                 
Specify the number and size of buffers used when reading non buffered client request body, all the buffers are stored in the memory. Buffers are allocated only on demand. By default, the buffer size is equal to your OS's pagesize. The total buffer size should be larger than `client_body_postpone_size`, otherwise, it will be enlarged by force.

## client\_body\_postpone\_size ##

Syntax: **client\_body\_postpone\_size** `size`

Default: 64k

Context: `http, server, location`

When you turn off the `proxy_request_buffering` or `fastcgi_request_buffering`, Tengine will send the body to backend either it receives more than `size` data or the whole request body has been received. It can save the connection and reduce the network system call number with backend. 
                                 
## proxy\_request\_buffering ##

Syntax: **proxy\_request\_buffering** `on | off`

Default: `on`

Context: `http, server, location`

Specify the request body will be buffered to the disk or not. If it's off, the request body will be stored in the memory and sent to backend after Tengine receives more than `client_body_postpone_size` data. It can avoid the disk IO with large request body.

By default in the buffered mode, the whole request body larger than the `client_body_buffer_size` will always be saved into the disk. This behavior may increase the server load greatly with heavy upload application.

Note that, if you turn it off, the nginx retry mechanism with unsuccessful response will be broken after you sent part of the request to backend. It just returns 500 directly when it encounters an unsuccessful response. This directive also breaks these variables: $request_body, $request_body_file. You should not use them any more while their values are incomplete.

Also note that, enabling spdy will prevent `proxy_request_buffering off` from taking effect.

## fastcgi\_request\_buffering ##

Syntax: **fastcgi\_request\_buffering** `on | off`

Default: `on`

Context: `http, server, location`

The same as `proxy_request_buffering`.

## gzip\_clear\_etag ##

Syntax: **gzip\_clear\_etag** `on | off`

Default: `on`

Context: `http, server, location`

Determines whether gzip module should clear the “ETag” response header field.
