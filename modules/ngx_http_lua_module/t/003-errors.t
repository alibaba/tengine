# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(1);

plan tests => blocks() * repeat_each() * 2;

#$ENV{LUA_PATH} = $ENV{HOME} . '/work/JSON4Lua-0.9.30/json/?.lua';

no_long_string();

run_tests();

__DATA__

=== TEST 1: syntax error in lua code chunk
--- config
    location /lua {
        set_by_lua $res "local a
            a = a+;
            return a";
        echo $res;
    }
--- request
GET /lua
--- error_code: 500
--- response_body_like: 500 Internal Server Error



=== TEST 2: syntax error in lua file
--- config
    location /lua {
        set_by_lua_file $res 'html/test.lua';
        echo $res;
    }
--- user_files
>>> test.lua
local a
a = 3 +;
return a
--- request
GET /lua
--- error_code: 500
--- response_body_like: 500 Internal Server Error



=== TEST 3: syntax error in lua file (from Guang Feng)
--- config
    location /lua {
        set $res '[{"a":32},{"b":64}]';
        #set $res '[{"friend_userid":1750146},{"friend_userid":1750150},{"friend_userid":1750153},{"friend_userid":1750166},{"friend_userid":1750181},{"friend_userid":1750186},{"friend_userid":1750195},{"friend_userid":1750232}]';
        set_by_lua_file $list 'html/test.lua' $res;
        #set_by_lua_file $list 'html/feed.lua' $res;
        echo $list;
    }
--- user_files
>>> test.lua
-- local j = require('json')
local p = ngx.arg[1]
return p
>>> feed.lua
local s = require("json")
local function explode(d,p)
   local t, ll
   t={}
   ll=0
   if(#p == 1) then return p end
       while true do
       l=string.find(p,d,ll+1,true) 
           if l~=nil then 
         table.insert(t, string.sub(p,ll,l-1)) 
         ll=l+1 
           else
         table.insert(t, string.sub(p,ll)) 
         break 
         end
     end
return t
 end

local a = explode(',', string.sub(ngx.arg[1], 2, -1))
local x = {}
for i,v in ipairs(a) do table.insert(x,s.decode(v).friend_userid) end
return table.concat(x,',')
--- request
GET /lua
--- response_body
[{"a":32},{"b":64}]



=== TEST 4: 500 in subrequest
--- config
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/err")
            ngx.say(res.status);
        ';
    }
    location /err {
        return 500;
    }
--- request
GET /main
--- response_body
500



=== TEST 5: drizzle_pass 500 in subrequest
--- config
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/err")
            ngx.say(res.status);
        ';
    }
    location /err {
        set $back 'blah-blah';
        drizzle_pass $back;
    }
--- request
GET /main
--- response_body
500
