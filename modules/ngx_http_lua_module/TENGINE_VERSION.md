# Tengine 集成版本记录

## 依赖版本

| 组件 | 版本 | 来源 | 说明 |
|------|------|------|------|
| lua-nginx-module | v0.10.27 | openresty/lua-nginx-module | PCRE2 支持，稳定 release 版本 |
| LuaJIT | 2.1.1773724885 | openresty/luajit2 | OpenResty 维护分支 |
| lua-resty-core | v0.1.27 | openresty/lua-resty-core | 配套 resty 库 |
| lua-resty-lrucache | latest | openresty/lua-resty-lrucache | LRU 缓存支持 |

## Tengine 特有修改

本模块在标准 `lua-nginx-module v0.10.27` 基础上添加了以下 xquic 支持：

### 修改文件清单

1. **src/ngx_http_lua_accessby.c** - HTTP/3 access phase 处理
2. **src/ngx_http_lua_contentby.c** - HTTP/3 content phase 处理  
3. **src/ngx_http_lua_headers.c** - HTTP/3 请求头限制
4. **src/ngx_http_lua_rewriteby.c** - HTTP/3 rewrite phase 处理
5. **src/ngx_http_lua_socket_tcp.c** - HTTP/3 socket 操作限制
6. **src/ngx_http_lua_ssl_certby.c** - HTTP/3 SSL 证书回调支持
7. **src/ngx_http_lua_subrequest.c** - HTTP/3 子请求处理
8. **src/ngx_http_lua_util.c** - HTTP/3 连接状态检查

### 编译要求

```bash
export LUAJIT_LIB=/path/to/luajit/lib
export LUAJIT_INC=/path/to/luajit/include/luajit-2.1
./configure --add-module=./modules/ngx_http_lua_module ...
```

### 注意事项

- ⚠️ HTTP/3 (xquic) 请求下部分 Lua API 暂不支持
- ✅ 标准 HTTP/1.1 和 HTTP/2 功能完全兼容
- ✅ PCRE2 原生支持（无需 pcre-devel）

---
*最后更新: 2026-03-26*
