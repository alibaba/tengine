# Name
**ngx\_http\_upstream\_session\_sticky\_module**

This module is a load balancing module. It sticks the session between client and backend server via cookie. In such case, it guarantees that requests from the same client are distributed to the same server.

# Example 1#

    # default: cookie=route mode=insert fallback=on
    upstream foo {
       server 192.168.0.1;
       server 192.168.0.2;
       session_sticky;
    }

    server {
        location / {
            proxy_pass http://foo;
        }
    }

# Example 2#

    # insert + indirect mode:
    upstream test {
      session_sticky session_sticky cookie=uid domain=www.xxx.com fallback=on path=/ mode=insert option=indirect;
      server  127.0.0.1:8080;
    }

    server {
      location / {
        # You need configure session_sticky_hide_cookie in insert + indirect mode or prefix mode.
        # It removes the cookie before sending to backend server, and the backend server will not
	# receive and process this extra cookie.
        session_sticky_hide_cookie upstream=test;
        proxy_pass http://test;
      }
    }

# Directive #

## session_sticky ##

Syntax: **session_sticky** `[cookie=name] [domain=your_domain] [path=your_path] [maxage=time] [mode=insert|rewrite|prefix] [option=indirect] [maxidle=time] [maxlife=time] [fallback=on|off] [hash=plain|md5]`

Default: `session_sticky cookie=route mode=insert fallback=on`

Context: `upstream`

Description:

This directive will turn on the session sticky module. Specific parameters are as follows:

+ `cookie` sets name of session cookie.
+ `domain` sets domain of cookie. It is not set by default.
+ `path` sets url path of cookie. The default value is '/'.
+ `maxage` set lifetime of cookie (cookie max-age attribute). If not set, it's a session cookie. It expires when the browser is closed.
+ `mode` sets mode of cookie:
    - **insert**: This mode inserts cookie into http response via Set-Cookie header.
    - **prefix**: This mode doesn't generate new cookie, but it inserts specific prefix ahead of cookie value of http response (e.g. "Cookie: NAME=SRV~VALUE"). When client(browser) requests next time with this specific cookie, it will delete inserted prefix before passing request to backend server. The operation is transparent to backend server which will get origin cookie .
    - **rewrite**: In this mode, backend server can set cookie of session sticky itself. If backend server doesn't set this cookie in response, it disables session sticky for this request. In this mode, backend server manages which request needs sesstion sticky.

+ `option` sets option value(indirect and direct) for cookie of session sticky. If setting indirect, it hides cookie of session sticky from backend server, otherwise the opposite.
+ `maxidle` sets max idle time of session.
+ `maxlife` sets max lifetime of session.
+ `fallback` sets whether it can retry others when current backend server is down.
+ `hash` sets whether server flag in cookie is passed through plaintext or md5. By default, md5 is used.

## session\_sticky\_hide\_cookie ##

Syntax: **session\_sticky\_hide\_cookie** upstream=name;

Default: none

Context: server, location

Description:

This directive works with proxy_pass directive. It deletes cookie used as session sticky in insert+indirect and prefix mode, in which case cookie will be hidden from backend server. Upstream name specifies which upstream this directive takes effect in.
