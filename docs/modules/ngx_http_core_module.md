# Name #

**ngx\_http\_core\_module**

Tengine added some enhancements with this module. The new directives are listed below.


# Directives #

## client\_body\_postpone\_sending ##

Syntax: **client\_body\_postpone\_sending** `size`

Default: 64k

Context: `http, server, location`

If you specify the `proxy_request_buffering` or `fastcgi_request_buffering` to be off, Tengine will send the body to backend when it receives more than `size` data or the whole request body has been received. It could save the connection and reduce the IO number with backend.

## proxy\_request\_buffering ##

Syntax: **proxy\_request\_buffering** `on | off`

Default: `on`

Context: `http, server, location`

Specify the request body will be buffered to the disk or not. If it's off, the request body will be stored in memory and sent to backend after Tengine receives more than `client_body_postpone_sending` data. It could save the disk IO with large request body.

Note that, if you specify it to be off, the nginx retry mechanism with unsuccessful response will be broken after you sent part of the request to backend. It will just return 500 when it encounters such unsuccessful response. This directive also breaks these variables: $request_body, $request_body_file. You should not use these variables any more while their value are undefined.

## fastcgi\_request\_buffering ##

Syntax: **fastcgi\_request\_buffering** `on | off`

Default: `on`

Context: `http, server, location`

The same as `proxy_request_buffering`.
