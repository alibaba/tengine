/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_string.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_args.h"
#include "ngx_crc32.h"

#if (NGX_HAVE_SHA1)
#include "ngx_sha1.h"
#endif

#include "ngx_md5.h"

#if (NGX_OPENSSL)
#include <openssl/evp.h>
#include <openssl/hmac.h>
#endif


#ifndef SHA_DIGEST_LENGTH
#define SHA_DIGEST_LENGTH 20
#endif


static uintptr_t ngx_http_lua_ngx_escape_sql_str(u_char *dst, u_char *src,
        size_t size);
static int ngx_http_lua_ngx_escape_uri(lua_State *L);
static int ngx_http_lua_ngx_unescape_uri(lua_State *L);
static int ngx_http_lua_ngx_quote_sql_str(lua_State *L);
static int ngx_http_lua_ngx_md5(lua_State *L);
static int ngx_http_lua_ngx_md5_bin(lua_State *L);

#if (NGX_HAVE_SHA1)
static int ngx_http_lua_ngx_sha1_bin(lua_State *L);
#endif

static int ngx_http_lua_ngx_decode_base64(lua_State *L);
static int ngx_http_lua_ngx_encode_base64(lua_State *L);
static int ngx_http_lua_ngx_crc32_short(lua_State *L);
static int ngx_http_lua_ngx_crc32_long(lua_State *L);
static int ngx_http_lua_ngx_encode_args(lua_State *L);
static int ngx_http_lua_ngx_decode_args(lua_State *L);
#if (NGX_OPENSSL)
static int ngx_http_lua_ngx_hmac_sha1(lua_State *L);
#endif


void
ngx_http_lua_inject_string_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_escape_uri);
    lua_setfield(L, -2, "escape_uri");

    lua_pushcfunction(L, ngx_http_lua_ngx_unescape_uri);
    lua_setfield(L, -2, "unescape_uri");

    lua_pushcfunction(L, ngx_http_lua_ngx_encode_args);
    lua_setfield(L, -2, "encode_args");

    lua_pushcfunction(L, ngx_http_lua_ngx_decode_args);
    lua_setfield(L, -2, "decode_args");

    lua_pushcfunction(L, ngx_http_lua_ngx_quote_sql_str);
    lua_setfield(L, -2, "quote_sql_str");

    lua_pushcfunction(L, ngx_http_lua_ngx_decode_base64);
    lua_setfield(L, -2, "decode_base64");

    lua_pushcfunction(L, ngx_http_lua_ngx_encode_base64);
    lua_setfield(L, -2, "encode_base64");

    lua_pushcfunction(L, ngx_http_lua_ngx_md5_bin);
    lua_setfield(L, -2, "md5_bin");

    lua_pushcfunction(L, ngx_http_lua_ngx_md5);
    lua_setfield(L, -2, "md5");

#if (NGX_HAVE_SHA1)
    lua_pushcfunction(L, ngx_http_lua_ngx_sha1_bin);
    lua_setfield(L, -2, "sha1_bin");
#endif

    lua_pushcfunction(L, ngx_http_lua_ngx_crc32_short);
    lua_setfield(L, -2, "crc32_short");

    lua_pushcfunction(L, ngx_http_lua_ngx_crc32_long);
    lua_setfield(L, -2, "crc32_long");

#if (NGX_OPENSSL)
    lua_pushcfunction(L, ngx_http_lua_ngx_hmac_sha1);
    lua_setfield(L, -2, "hmac_sha1");
#endif
}


static int
ngx_http_lua_ngx_escape_uri(lua_State *L)
{
    size_t                   len, dlen;
    uintptr_t                escape;
    u_char                  *src, *dst;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    if (lua_isnil(L, 1)) {
        lua_pushliteral(L, "");
        return 1;
    }

    src = (u_char *) luaL_checklstring(L, 1, &len);

    if (len == 0) {
        return 1;
    }

    escape = 2 * ngx_http_lua_escape_uri(NULL, src, len,
                                         NGX_ESCAPE_URI_COMPONENT);

    if (escape) {
        dlen = escape + len;
        dst = lua_newuserdata(L, dlen);
        ngx_http_lua_escape_uri(dst, src, len, NGX_ESCAPE_URI_COMPONENT);
        lua_pushlstring(L, (char *) dst, dlen);
    }

    return 1;
}


static int
ngx_http_lua_ngx_unescape_uri(lua_State *L)
{
    size_t                   len, dlen;
    u_char                  *p;
    u_char                  *src, *dst;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    if (lua_isnil(L, 1)) {
        lua_pushliteral(L, "");
        return 1;
    }

    src = (u_char *) luaL_checklstring(L, 1, &len);

    /* the unescaped string can only be smaller */
    dlen = len;

    p = lua_newuserdata(L, dlen);

    dst = p;

    ngx_http_lua_unescape_uri(&dst, &src, len, NGX_UNESCAPE_URI_COMPONENT);

    lua_pushlstring(L, (char *) p, dst - p);

    return 1;
}


static int
ngx_http_lua_ngx_quote_sql_str(lua_State *L)
{
    size_t                   len, dlen, escape;
    u_char                  *p;
    u_char                  *src, *dst;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    src = (u_char *) luaL_checklstring(L, 1, &len);

    if (len == 0) {
        dst = (u_char *) "''";
        dlen = sizeof("''") - 1;
        lua_pushlstring(L, (char *) dst, dlen);
        return 1;
    }

    escape = ngx_http_lua_ngx_escape_sql_str(NULL, src, len);

    dlen = sizeof("''") - 1 + len + escape;

    p = lua_newuserdata(L, dlen);

    dst = p;

    *p++ = '\'';

    if (escape == 0) {
        p = ngx_copy(p, src, len);

    } else {
        p = (u_char *) ngx_http_lua_ngx_escape_sql_str(p, src, len);
    }

    *p++ = '\'';

    if (p != dst + dlen) {
        return NGX_ERROR;
    }

    lua_pushlstring(L, (char *) dst, p - dst);

    return 1;
}


static uintptr_t
ngx_http_lua_ngx_escape_sql_str(u_char *dst, u_char *src, size_t size)
{
    ngx_uint_t               n;

    if (dst == NULL) {
        /* find the number of chars to be escaped */
        n = 0;
        while (size) {
            /* the highest bit of all the UTF-8 chars
             * is always 1 */
            if ((*src & 0x80) == 0) {
                switch (*src) {
                    case '\0':
                    case '\b':
                    case '\n':
                    case '\r':
                    case '\t':
                    case 26:  /* \Z */
                    case '\\':
                    case '\'':
                    case '"':
                        n++;
                        break;
                    default:
                        break;
                }
            }
            src++;
            size--;
        }

        return (uintptr_t) n;
    }

    while (size) {
        if ((*src & 0x80) == 0) {
            switch (*src) {
                case '\0':
                    *dst++ = '\\';
                    *dst++ = '0';
                    break;

                case '\b':
                    *dst++ = '\\';
                    *dst++ = 'b';
                    break;

                case '\n':
                    *dst++ = '\\';
                    *dst++ = 'n';
                    break;

                case '\r':
                    *dst++ = '\\';
                    *dst++ = 'r';
                    break;

                case '\t':
                    *dst++ = '\\';
                    *dst++ = 't';
                    break;

                case 26:
                    *dst++ = '\\';
                    *dst++ = 'Z';
                    break;

                case '\\':
                    *dst++ = '\\';
                    *dst++ = '\\';
                    break;

                case '\'':
                    *dst++ = '\\';
                    *dst++ = '\'';
                    break;

                case '"':
                    *dst++ = '\\';
                    *dst++ = '"';
                    break;

                default:
                    *dst++ = *src;
                    break;
            }
        } else {
            *dst++ = *src;
        }
        src++;
        size--;
    } /* while (size) */

    return (uintptr_t) dst;
}


static int
ngx_http_lua_ngx_md5(lua_State *L)
{
    u_char                  *src;
    size_t                   slen;

    ngx_md5_t                md5;
    u_char                   md5_buf[MD5_DIGEST_LENGTH];
    u_char                   hex_buf[2 * sizeof(md5_buf)];

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    if (lua_isnil(L, 1)) {
        src = (u_char *) "";
        slen = 0;

    } else {
        src = (u_char *) luaL_checklstring(L, 1, &slen);
    }

    ngx_md5_init(&md5);
    ngx_md5_update(&md5, src, slen);
    ngx_md5_final(md5_buf, &md5);

    ngx_hex_dump(hex_buf, md5_buf, sizeof(md5_buf));

    lua_pushlstring(L, (char *) hex_buf, sizeof(hex_buf));

    return 1;
}


static int
ngx_http_lua_ngx_md5_bin(lua_State *L)
{
    u_char                  *src;
    size_t                   slen;

    ngx_md5_t                md5;
    u_char                   md5_buf[MD5_DIGEST_LENGTH];

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    if (lua_isnil(L, 1)) {
        src     = (u_char *) "";
        slen    = 0;

    } else {
        src = (u_char *) luaL_checklstring(L, 1, &slen);
    }

    dd("slen: %d", (int) slen);

    ngx_md5_init(&md5);
    ngx_md5_update(&md5, src, slen);
    ngx_md5_final(md5_buf, &md5);

    lua_pushlstring(L, (char *) md5_buf, sizeof(md5_buf));

    return 1;
}


#if (NGX_HAVE_SHA1)
static int
ngx_http_lua_ngx_sha1_bin(lua_State *L)
{
    u_char                  *src;
    size_t                   slen;

    ngx_sha1_t               sha;
    u_char                   sha_buf[SHA_DIGEST_LENGTH];

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    if (lua_isnil(L, 1)) {
        src     = (u_char *) "";
        slen    = 0;

    } else {
        src = (u_char *) luaL_checklstring(L, 1, &slen);
    }

    dd("slen: %d", (int) slen);

    ngx_sha1_init(&sha);
    ngx_sha1_update(&sha, src, slen);
    ngx_sha1_final(sha_buf, &sha);

    lua_pushlstring(L, (char *) sha_buf, sizeof(sha_buf));

    return 1;
}
#endif


static int
ngx_http_lua_ngx_decode_base64(lua_State *L)
{
    ngx_str_t                p, src;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument");
    }

    if (lua_type(L, 1) != LUA_TSTRING) {
        return luaL_error(L, "string argument only");
    }

    src.data = (u_char *) luaL_checklstring(L, 1, &src.len);

    p.len = ngx_base64_decoded_length(src.len);

    p.data = lua_newuserdata(L, p.len);

    if (ngx_decode_base64(&p, &src) == NGX_OK) {
        lua_pushlstring(L, (char *) p.data, p.len);

    } else {
        lua_pushnil(L);
    }

    return 1;
}


static void
ngx_http_lua_encode_base64(ngx_str_t *dst, ngx_str_t *src, int no_padding)
{
    u_char         *d, *s;
    size_t          len;
    static u_char   basis[] =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    len = src->len;
    s = src->data;
    d = dst->data;

    while (len > 2) {
        *d++ = basis[(s[0] >> 2) & 0x3f];
        *d++ = basis[((s[0] & 3) << 4) | (s[1] >> 4)];
        *d++ = basis[((s[1] & 0x0f) << 2) | (s[2] >> 6)];
        *d++ = basis[s[2] & 0x3f];

        s += 3;
        len -= 3;
    }

    if (len) {
        *d++ = basis[(s[0] >> 2) & 0x3f];

        if (len == 1) {
            *d++ = basis[(s[0] & 3) << 4];
            if (!no_padding) {
                *d++ = '=';
            }

        } else {
            *d++ = basis[((s[0] & 3) << 4) | (s[1] >> 4)];
            *d++ = basis[(s[1] & 0x0f) << 2];
        }

        if (!no_padding) {
            *d++ = '=';
        }
    }

    dst->len = d - dst->data;
}


static size_t
ngx_http_lua_base64_encoded_length(size_t n, int no_padding)
{
    return no_padding ? (n * 8 + 5) / 6 : ngx_base64_encoded_length(n);
}


static int
ngx_http_lua_ngx_encode_base64(lua_State *L)
{
    int                      n;
    int                      no_padding = 0;
    ngx_str_t                p, src;

    n = lua_gettop(L);
    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting one or two arguments");
    }

    if (lua_isnil(L, 1)) {
        src.data = (u_char *) "";
        src.len = 0;

    } else {
        src.data = (u_char *) luaL_checklstring(L, 1, &src.len);
    }

    if (n == 2) {
        /* get the 2nd optional argument */
        luaL_checktype(L, 2, LUA_TBOOLEAN);
        no_padding = lua_toboolean(L, 2);
    }

    p.len = ngx_http_lua_base64_encoded_length(src.len, no_padding);

    p.data = lua_newuserdata(L, p.len);

    ngx_http_lua_encode_base64(&p, &src, no_padding);

    lua_pushlstring(L, (char *) p.data, p.len);

    return 1;
}


static int
ngx_http_lua_ngx_crc32_short(lua_State *L)
{
    u_char                  *p;
    size_t                   len;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument, but got %d",
                          lua_gettop(L));
    }

    p = (u_char *) luaL_checklstring(L, 1, &len);

    lua_pushnumber(L, (lua_Number) ngx_crc32_short(p, len));
    return 1;
}


static int
ngx_http_lua_ngx_crc32_long(lua_State *L)
{
    u_char                  *p;
    size_t                   len;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one argument, but got %d",
                          lua_gettop(L));
    }

    p = (u_char *) luaL_checklstring(L, 1, &len);

    lua_pushnumber(L, (lua_Number) ngx_crc32_long(p, len));
    return 1;
}


static int
ngx_http_lua_ngx_encode_args(lua_State *L)
{
    ngx_str_t                    args;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting 1 argument but seen %d",
                          lua_gettop(L));
    }

    luaL_checktype(L, 1, LUA_TTABLE);
    ngx_http_lua_process_args_option(NULL, L, 1, &args);
    lua_pushlstring(L, (char *) args.data, args.len);
    return 1;
}


static int
ngx_http_lua_ngx_decode_args(lua_State *L)
{
    u_char                      *buf;
    u_char                      *tmp;
    size_t                       len = 0;
    int                          n;
    int                          max;

    n = lua_gettop(L);

    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting 1 or 2 arguments but seen %d", n);
    }

    buf = (u_char *) luaL_checklstring(L, 1, &len);

    if (n == 2) {
        max = luaL_checkint(L, 2);
        lua_pop(L, 1);

    } else {
        max = NGX_HTTP_LUA_MAX_ARGS;
    }

    tmp = lua_newuserdata(L, len);
    ngx_memcpy(tmp, buf, len);

    lua_createtable(L, 0, 4);

    return ngx_http_lua_parse_args(L, tmp, tmp + len, max);
}


#if (NGX_OPENSSL)
static int
ngx_http_lua_ngx_hmac_sha1(lua_State *L)
{
    u_char                  *sec, *sts;
    size_t                   lsec, lsts;
    unsigned int             md_len;
    unsigned char            md[EVP_MAX_MD_SIZE];
    const EVP_MD            *evp_md;

    if (lua_gettop(L) != 2) {
        return luaL_error(L, "expecting 2 arguments, but got %d",
                          lua_gettop(L));
    }

    sec = (u_char *) luaL_checklstring(L, 1, &lsec);
    sts = (u_char *) luaL_checklstring(L, 2, &lsts);

    evp_md = EVP_sha1();

    HMAC(evp_md, sec, lsec, sts, lsts, md, &md_len);

    lua_pushlstring(L, (char *) md, md_len);

    return 1;
}
#endif


#ifndef NGX_LUA_NO_FFI_API
void
ngx_http_lua_ffi_md5_bin(const u_char *src, size_t len, u_char *dst)
{
    ngx_md5_t     md5;

    ngx_md5_init(&md5);
    ngx_md5_update(&md5, src, len);
    ngx_md5_final(dst, &md5);
}


void
ngx_http_lua_ffi_md5(const u_char *src, size_t len, u_char *dst)
{
    ngx_md5_t           md5;
    u_char              md5_buf[MD5_DIGEST_LENGTH];

    ngx_md5_init(&md5);
    ngx_md5_update(&md5, src, len);
    ngx_md5_final(md5_buf, &md5);

    ngx_hex_dump(dst, md5_buf, sizeof(md5_buf));
}


int
ngx_http_lua_ffi_sha1_bin(const u_char *src, size_t len, u_char *dst)
{
#if (NGX_HAVE_SHA1)
    ngx_sha1_t               sha;

    ngx_sha1_init(&sha);
    ngx_sha1_update(&sha, src, len);
    ngx_sha1_final(dst, &sha);

    return 1;
#else
    return 0;
#endif
}


size_t
ngx_http_lua_ffi_encode_base64(const u_char *src, size_t slen, u_char *dst,
    int no_padding)
{
    ngx_str_t      in, out;

    in.data = (u_char *) src;
    in.len = slen;

    out.data = dst;

    ngx_http_lua_encode_base64(&out, &in, no_padding);

    return out.len;
}


int
ngx_http_lua_ffi_decode_base64(const u_char *src, size_t slen, u_char *dst,
    size_t *dlen)
{
    ngx_int_t      rc;
    ngx_str_t      in, out;

    in.data = (u_char *) src;
    in.len = slen;

    out.data = dst;

    rc = ngx_decode_base64(&out, &in);

    *dlen = out.len;

    return rc == NGX_OK;
}


size_t
ngx_http_lua_ffi_unescape_uri(const u_char *src, size_t len, u_char *dst)
{
    u_char      *p = dst;

    ngx_http_lua_unescape_uri(&p, (u_char **) &src, len,
                              NGX_UNESCAPE_URI_COMPONENT);
    return p - dst;
}


size_t
ngx_http_lua_ffi_uri_escaped_length(const u_char *src, size_t len)
{
    return len + 2 * ngx_http_lua_escape_uri(NULL, (u_char *) src, len,
                                             NGX_ESCAPE_URI_COMPONENT);
}


void
ngx_http_lua_ffi_escape_uri(const u_char *src, size_t len, u_char *dst)
{
    ngx_http_lua_escape_uri(dst, (u_char *) src, len, NGX_ESCAPE_URI_COMPONENT);
}

#endif

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
