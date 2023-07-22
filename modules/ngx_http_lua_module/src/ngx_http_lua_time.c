
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_common.h"


double
ngx_http_lua_ffi_now(void)
{
    ngx_time_t              *tp;

    tp = ngx_timeofday();

    return tp->sec + tp->msec / 1000.0;
}


double
ngx_http_lua_ffi_req_start_time(ngx_http_request_t *r)
{
    return r->start_sec + r->start_msec / 1000.0;
}


long
ngx_http_lua_ffi_time(void)
{
    return (long) ngx_time();
}


long
ngx_http_lua_ffi_monotonic_msec(void)
{
    return (long) ngx_current_msec;
}


void
ngx_http_lua_ffi_update_time(void)
{
    ngx_time_update();
}


void
ngx_http_lua_ffi_today(u_char *buf)
{
    ngx_tm_t                 tm;

    ngx_gmtime(ngx_time() + ngx_cached_time->gmtoff * 60, &tm);

    ngx_sprintf(buf, "%04d-%02d-%02d", tm.ngx_tm_year, tm.ngx_tm_mon,
                tm.ngx_tm_mday);
}


void
ngx_http_lua_ffi_localtime(u_char *buf)
{
    ngx_tm_t                 tm;

    ngx_gmtime(ngx_time() + ngx_cached_time->gmtoff * 60, &tm);

    ngx_sprintf(buf, "%04d-%02d-%02d %02d:%02d:%02d", tm.ngx_tm_year,
                tm.ngx_tm_mon, tm.ngx_tm_mday, tm.ngx_tm_hour, tm.ngx_tm_min,
                tm.ngx_tm_sec);
}


void
ngx_http_lua_ffi_utctime(u_char *buf)
{
    ngx_tm_t       tm;

    ngx_gmtime(ngx_time(), &tm);

    ngx_sprintf(buf, "%04d-%02d-%02d %02d:%02d:%02d", tm.ngx_tm_year,
                tm.ngx_tm_mon, tm.ngx_tm_mday, tm.ngx_tm_hour, tm.ngx_tm_min,
                tm.ngx_tm_sec);
}


int
ngx_http_lua_ffi_cookie_time(u_char *buf, long t)
{
    u_char                              *p;

    p = ngx_http_cookie_time(buf, t);
    return p - buf;
}


void
ngx_http_lua_ffi_http_time(u_char *buf, long t)
{
    ngx_http_time(buf, t);
}


void
ngx_http_lua_ffi_parse_http_time(const u_char *str, size_t len,
    long *time)
{
    /* ngx_http_parse_time doesn't modify 'str' actually */
    *time = ngx_http_parse_time((u_char *) str, len);
}


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
