
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include <ngx_core.h>
#include <ngx_http.h>
#include <lauxlib.h>
#include "ngx_http_lua_api.h"


ngx_module_t ngx_http_lua_upstream_module;


static ngx_int_t ngx_http_lua_upstream_init(ngx_conf_t *cf);
static int ngx_http_lua_upstream_create_module(lua_State * L);
static int ngx_http_lua_upstream_get_upstreams(lua_State * L);
static int ngx_http_lua_upstream_get_servers(lua_State * L);
static ngx_http_upstream_main_conf_t *
    ngx_http_lua_upstream_get_upstream_main_conf(lua_State *L);
static int ngx_http_lua_upstream_get_primary_peers(lua_State * L);
static int ngx_http_lua_upstream_get_backup_peers(lua_State * L);
static int ngx_http_lua_get_peer(lua_State *L,
    ngx_http_upstream_rr_peer_t *peer, ngx_uint_t id);
static ngx_http_upstream_srv_conf_t *
    ngx_http_lua_upstream_find_upstream(lua_State *L, ngx_str_t *host);
static ngx_http_upstream_rr_peer_t *
    ngx_http_lua_upstream_lookup_peer(lua_State *L);
static int ngx_http_lua_upstream_set_peer_down(lua_State * L);
static int ngx_http_lua_upstream_current_upstream_name(lua_State *L);


static ngx_http_module_t ngx_http_lua_upstream_ctx = {
    NULL,                           /* preconfiguration */
    ngx_http_lua_upstream_init,     /* postconfiguration */
    NULL,                           /* create main configuration */
    NULL,                           /* init main configuration */
    NULL,                           /* create server configuration */
    NULL,                           /* merge server configuration */
    NULL,                           /* create location configuration */
    NULL                            /* merge location configuration */
};


ngx_module_t ngx_http_lua_upstream_module = {
    NGX_MODULE_V1,
    &ngx_http_lua_upstream_ctx,  /* module context */
    NULL,                        /* module directives */
    NGX_HTTP_MODULE,             /* module type */
    NULL,                        /* init master */
    NULL,                        /* init module */
    NULL,                        /* init process */
    NULL,                        /* init thread */
    NULL,                        /* exit thread */
    NULL,                        /* exit process */
    NULL,                        /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_http_lua_upstream_init(ngx_conf_t *cf)
{
    if (ngx_http_lua_add_package_preload(cf, "ngx.upstream",
                                         ngx_http_lua_upstream_create_module)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    return NGX_OK;
}


static int
ngx_http_lua_upstream_create_module(lua_State * L)
{
    lua_createtable(L, 0, 6);

    lua_pushcfunction(L, ngx_http_lua_upstream_get_upstreams);
    lua_setfield(L, -2, "get_upstreams");

    lua_pushcfunction(L, ngx_http_lua_upstream_get_servers);
    lua_setfield(L, -2, "get_servers");

    lua_pushcfunction(L, ngx_http_lua_upstream_get_primary_peers);
    lua_setfield(L, -2, "get_primary_peers");

    lua_pushcfunction(L, ngx_http_lua_upstream_get_backup_peers);
    lua_setfield(L, -2, "get_backup_peers");

    lua_pushcfunction(L, ngx_http_lua_upstream_set_peer_down);
    lua_setfield(L, -2, "set_peer_down");

    lua_pushcfunction(L, ngx_http_lua_upstream_current_upstream_name);
    lua_setfield(L, -2, "current_upstream_name");

    return 1;
}


static int
ngx_http_lua_upstream_get_upstreams(lua_State * L)
{
    ngx_uint_t                            i;
    ngx_http_upstream_srv_conf_t        **uscfp, *uscf;
    ngx_http_upstream_main_conf_t        *umcf;

    if (lua_gettop(L) != 0) {
        return luaL_error(L, "no argument expected");
    }

    umcf = ngx_http_lua_upstream_get_upstream_main_conf(L);
    uscfp = umcf->upstreams.elts;

    lua_createtable(L, umcf->upstreams.nelts, 0);

    for (i = 0; i < umcf->upstreams.nelts; i++) {

        uscf = uscfp[i];

        lua_pushlstring(L, (char *) uscf->host.data, uscf->host.len);
        if (uscf->port) {
            lua_pushfstring(L, ":%d", (int) uscf->port);
            lua_concat(L, 2);

            /* XXX maybe we should also take "default_port" into account
             * here? */
        }

        lua_rawseti(L, -2, i + 1);
    }

    return 1;
}


static int
ngx_http_lua_upstream_get_servers(lua_State * L)
{
    ngx_str_t                             host;
    ngx_uint_t                            i, j, n;
    ngx_http_upstream_server_t           *server;
    ngx_http_upstream_srv_conf_t         *us;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "exactly one argument expected");
    }

    host.data = (u_char *) luaL_checklstring(L, 1, &host.len);

    us = ngx_http_lua_upstream_find_upstream(L, &host);
    if (us == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "upstream not found");
        return 2;
    }

    if (us->servers == NULL || us->servers->nelts == 0) {
        lua_newtable(L);
        return 1;
    }

    server = us->servers->elts;

    lua_createtable(L, us->servers->nelts, 0);

    for (i = 0; i < us->servers->nelts; i++) {

        n = 4;

        if (server[i].name.len) {
            n++;
        }

        if (server[i].backup) {
            n++;
        }

        if (server[i].down) {
            n++;
        }

        lua_createtable(L, 0, n);

        if (server[i].name.len) {
            lua_pushliteral(L, "name");
            lua_pushlstring(L, (char *) server[i].name.data,
                            server[i].name.len);
            lua_rawset(L, -3);
        }

        lua_pushliteral(L, "addr");

        if (server[i].naddrs == 1) {
            lua_pushlstring(L, (char *) server[i].addrs->name.data,
                            server[i].addrs->name.len);

        } else {
            lua_createtable(L, server[i].naddrs, 0);

            for (j = 0; j < server[i].naddrs; j++) {
                lua_pushlstring(L, (char *) server[i].addrs[j].name.data,
                                server[i].addrs[j].name.len);
                lua_rawseti(L, -2, j + 1);
            }
        }

        lua_rawset(L, -3);

        lua_pushliteral(L, "weight");
        lua_pushinteger(L, (lua_Integer) server[i].weight);
        lua_rawset(L, -3);

        lua_pushliteral(L, "max_fails");
        lua_pushinteger(L, (lua_Integer) server[i].max_fails);
        lua_rawset(L, -3);

        lua_pushliteral(L, "fail_timeout");
        lua_pushinteger(L, (lua_Integer) server[i].fail_timeout);
        lua_rawset(L, -3);

        if (server[i].backup) {
            lua_pushliteral(L, "backup");
            lua_pushboolean(L, 1);
            lua_rawset(L, -3);
        }

        if (server[i].down) {
            lua_pushliteral(L, "down");
            lua_pushboolean(L, 1);
            lua_rawset(L, -3);
        }

        lua_rawseti(L, -2, i + 1);
    }

    return 1;
}


static int
ngx_http_lua_upstream_get_primary_peers(lua_State * L)
{
    ngx_str_t                             host;
    ngx_uint_t                            i;
    ngx_http_upstream_rr_peers_t         *peers;
    ngx_http_upstream_srv_conf_t         *us;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "exactly one argument expected");
    }

    host.data = (u_char *) luaL_checklstring(L, 1, &host.len);

    us = ngx_http_lua_upstream_find_upstream(L, &host);
    if (us == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "upstream not found");
        return 2;
    }

    peers = us->peer.data;

    if (peers == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "no peer data");
        return 2;
    }

    lua_createtable(L, peers->number, 0);

    for (i = 0; i < peers->number; i++) {
        ngx_http_lua_get_peer(L, &peers->peer[i], i);
        lua_rawseti(L, -2, i + 1);
    }

    return 1;
}


static int
ngx_http_lua_upstream_get_backup_peers(lua_State * L)
{
    ngx_str_t                             host;
    ngx_uint_t                            i;
    ngx_http_upstream_rr_peers_t         *peers;
    ngx_http_upstream_srv_conf_t         *us;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "exactly one argument expected");
    }

    host.data = (u_char *) luaL_checklstring(L, 1, &host.len);

    us = ngx_http_lua_upstream_find_upstream(L, &host);
    if (us == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "upstream not found");
        return 2;
    }

    peers = us->peer.data;

    if (peers == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "no peer data");
        return 2;
    }

    peers = peers->next;
    if (peers == NULL) {
        lua_newtable(L);
        return 1;
    }

    lua_createtable(L, peers->number, 0);

    for (i = 0; i < peers->number; i++) {
        ngx_http_lua_get_peer(L, &peers->peer[i], i);
        lua_rawseti(L, -2, i + 1);
    }

    return 1;
}


static int
ngx_http_lua_upstream_set_peer_down(lua_State * L)
{
    ngx_http_upstream_rr_peer_t          *peer;

    if (lua_gettop(L) != 4) {
        return luaL_error(L, "exactly 4 arguments expected");
    }

    peer = ngx_http_lua_upstream_lookup_peer(L);
    if (peer == NULL) {
        return 2;
    }

    peer->down = lua_toboolean(L, 4);

    if (!peer->down) {
        peer->fails = 0;
    }

    lua_pushboolean(L, 1);
    return 1;
}


static ngx_http_upstream_rr_peer_t *
ngx_http_lua_upstream_lookup_peer(lua_State *L)
{
    int                                   id, backup;
    ngx_str_t                             host;
    ngx_http_upstream_srv_conf_t         *us;
    ngx_http_upstream_rr_peers_t         *peers;

    host.data = (u_char *) luaL_checklstring(L, 1, &host.len);

    us = ngx_http_lua_upstream_find_upstream(L, &host);
    if (us == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "upstream not found");
        return NULL;
    }

    peers = us->peer.data;

    if (peers == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "no peer data");
        return NULL;
    }

    backup = lua_toboolean(L, 2);
    if (backup) {
        peers = peers->next;
    }

    if (peers == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "no backup peers");
        return NULL;
    }

    id = luaL_checkint(L, 3);
    if (id < 0 || (ngx_uint_t) id >= peers->number) {
        lua_pushnil(L);
        lua_pushliteral(L, "bad peer id");
        return NULL;
    }

    return &peers->peer[id];
}


static int
ngx_http_lua_get_peer(lua_State *L, ngx_http_upstream_rr_peer_t *peer,
    ngx_uint_t id)
{
    ngx_uint_t     n;

    n = 8;

#if (nginx_version >= 1009000)
    n++;
#endif

    if (peer->down) {
        n++;
    }

    if (peer->accessed) {
        n++;
    }

    if (peer->checked) {
        n++;
    }

    lua_createtable(L, 0, n);

    lua_pushliteral(L, "id");
    lua_pushinteger(L, (lua_Integer) id);
    lua_rawset(L, -3);

    lua_pushliteral(L, "name");
    lua_pushlstring(L, (char *) peer->name.data, peer->name.len);
    lua_rawset(L, -3);

    lua_pushliteral(L, "weight");
    lua_pushinteger(L, (lua_Integer) peer->weight);
    lua_rawset(L, -3);

    lua_pushliteral(L, "current_weight");
    lua_pushinteger(L, (lua_Integer) peer->current_weight);
    lua_rawset(L, -3);

    lua_pushliteral(L, "effective_weight");
    lua_pushinteger(L, (lua_Integer) peer->effective_weight);
    lua_rawset(L, -3);

#if (nginx_version >= 1009000)
    lua_pushliteral(L, "conns");
    lua_pushinteger(L, (lua_Integer) peer->conns);
    lua_rawset(L, -3);
#endif

    lua_pushliteral(L, "fails");
    lua_pushinteger(L, (lua_Integer) peer->fails);
    lua_rawset(L, -3);

    lua_pushliteral(L, "max_fails");
    lua_pushinteger(L, (lua_Integer) peer->max_fails);
    lua_rawset(L, -3);

    lua_pushliteral(L, "fail_timeout");
    lua_pushinteger(L, (lua_Integer) peer->fail_timeout);
    lua_rawset(L, -3);

    if (peer->accessed) {
        lua_pushliteral(L, "accessed");
        lua_pushinteger(L, (lua_Integer) peer->accessed);
        lua_rawset(L, -3);
    }

    if (peer->checked) {
        lua_pushliteral(L, "checked");
        lua_pushinteger(L, (lua_Integer) peer->checked);
        lua_rawset(L, -3);
    }

    if (peer->down) {
        lua_pushliteral(L, "down");
        lua_pushboolean(L, 1);
        lua_rawset(L, -3);
    }

    return 0;
}


static ngx_http_upstream_main_conf_t *
ngx_http_lua_upstream_get_upstream_main_conf(lua_State *L)
{
    ngx_http_request_t                   *r;

    r = ngx_http_lua_get_request(L);

    if (r == NULL) {
        return ngx_http_cycle_get_module_main_conf(ngx_cycle,
                                                   ngx_http_upstream_module);
    }

    return ngx_http_get_module_main_conf(r, ngx_http_upstream_module);
}


static ngx_http_upstream_srv_conf_t *
ngx_http_lua_upstream_find_upstream(lua_State *L, ngx_str_t *host)
{
    u_char                               *port;
    size_t                                len;
    ngx_int_t                             n;
    ngx_uint_t                            i;
    ngx_http_upstream_srv_conf_t        **uscfp, *uscf;
    ngx_http_upstream_main_conf_t        *umcf;

    umcf = ngx_http_lua_upstream_get_upstream_main_conf(L);

#if (NGX_HTTP_UPSTREAM_RBTREE)

    ngx_list_part_t                *part;

    uscf = ngx_http_upstream_rbtree_lookup(umcf, host);

    if (uscf != NULL)
    {
        return uscf;
    }

    part = &umcf->implicit_upstreams.part;
    uscfp = part->elts;

    for (i = 0; /* void */ ; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            uscfp = part->elts;
            i = 0;
        }

#else

    uscfp = umcf->upstreams.elts;

    for (i = 0; i < umcf->upstreams.nelts; i++) {

#endif

        uscf = uscfp[i];

        if (uscf->host.len == host->len
            && ngx_memcmp(uscf->host.data, host->data, host->len) == 0)
        {
            return uscf;
        }
    }

    port = ngx_strlchr(host->data, host->data + host->len, ':');
    if (port) {
        port++;
        n = ngx_atoi(port, host->data + host->len - port);
        if (n < 1 || n > 65535) {
            return NULL;
        }

        /* try harder with port */

        len = port - host->data - 1;

#if (NGX_HTTP_UPSTREAM_RBTREE)
        ngx_str_t addr;
        addr.data = host->data;
        addr.len = len;
        uscf = ngx_http_upstream_rbtree_lookup(umcf, &addr);
        if (uscf != NULL && uscf->port
            && uscf->port == n)
        {
            return uscf;
        }
        part = &umcf->implicit_upstreams.part;
        uscfp = part->elts;
        for (i = 0; /* void */ ; i++) {
            if (i >= part->nelts) {
                if (part->next == NULL) {
                    break;
                }
                part = part->next;
                uscfp = part->elts;
                i = 0;
            }
#else
        for (i = 0; i < umcf->upstreams.nelts; i++) {
#endif

            uscf = uscfp[i];

            if (uscf->port
                && uscf->port == n
                && uscf->host.len == len
                && ngx_memcmp(uscf->host.data, host->data, len) == 0)
            {
                return uscf;
            }
        }
    }

    return NULL;
}


static int
ngx_http_lua_upstream_current_upstream_name(lua_State *L)
{
    ngx_http_request_t           *r;
    ngx_http_upstream_t          *us;
    ngx_http_upstream_conf_t     *ucf;
    ngx_http_upstream_srv_conf_t *uscf;

    r = ngx_http_lua_get_request(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    us = r->upstream;
    if (us == NULL) {
        lua_pushnil(L); /* no proxying is being done */
        return 1;
    }

    ucf = us->conf;
    if (ucf == NULL) {
        return luaL_error(L, "no conf for upstream");
    }

    uscf = ucf->upstream;
    if (uscf == NULL) {
        return luaL_error(L, "no srv conf for upstream");
    }

    lua_pushlstring(L, (char *) uscf->host.data, uscf->host.len);

    if (uscf->port) {
        lua_pushfstring(L, ":%d", (int) uscf->port);
        lua_concat(L, 2);
    }

    return 1;
}
