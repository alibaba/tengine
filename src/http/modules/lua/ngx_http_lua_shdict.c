
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_shdict.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_api.h"


static int ngx_http_lua_shdict_set(lua_State *L);
static int ngx_http_lua_shdict_safe_set(lua_State *L);
static int ngx_http_lua_shdict_get(lua_State *L);
static int ngx_http_lua_shdict_get_stale(lua_State *L);
static int ngx_http_lua_shdict_get_helper(lua_State *L, int get_stale);
static int ngx_http_lua_shdict_expire(ngx_http_lua_shdict_ctx_t *ctx,
    ngx_uint_t n);
static ngx_int_t ngx_http_lua_shdict_lookup(ngx_shm_zone_t *shm_zone,
    ngx_uint_t hash, u_char *kdata, size_t klen,
    ngx_http_lua_shdict_node_t **sdp);
static int ngx_http_lua_shdict_set_helper(lua_State *L, int flags);
static int ngx_http_lua_shdict_add(lua_State *L);
static int ngx_http_lua_shdict_safe_add(lua_State *L);
static int ngx_http_lua_shdict_replace(lua_State *L);
static int ngx_http_lua_shdict_incr(lua_State *L);
static int ngx_http_lua_shdict_delete(lua_State *L);
static int ngx_http_lua_shdict_flush_all(lua_State *L);
static int ngx_http_lua_shdict_flush_expired(lua_State *L);
static int ngx_http_lua_shdict_get_keys(lua_State *L);


#define NGX_HTTP_LUA_SHDICT_ADD         0x0001
#define NGX_HTTP_LUA_SHDICT_REPLACE     0x0002
#define NGX_HTTP_LUA_SHDICT_SAFE_STORE  0x0004


ngx_int_t
ngx_http_lua_shdict_init_zone(ngx_shm_zone_t *shm_zone, void *data)
{
    ngx_http_lua_shdict_ctx_t  *octx = data;

    size_t                      len;
    ngx_http_lua_shdict_ctx_t  *ctx;
    ngx_http_lua_main_conf_t   *lmcf;

    dd("init zone");

    ctx = shm_zone->data;

    if (octx) {
        ctx->sh = octx->sh;
        ctx->shpool = octx->shpool;

        goto done;
    }

    ctx->shpool = (ngx_slab_pool_t *) shm_zone->shm.addr;

    if (shm_zone->shm.exists) {
        ctx->sh = ctx->shpool->data;

        goto done;
    }

    ctx->sh = ngx_slab_alloc(ctx->shpool, sizeof(ngx_http_lua_shdict_shctx_t));
    if (ctx->sh == NULL) {
        return NGX_ERROR;
    }

    ctx->shpool->data = ctx->sh;

    ngx_rbtree_init(&ctx->sh->rbtree, &ctx->sh->sentinel,
                    ngx_http_lua_shdict_rbtree_insert_value);

    ngx_queue_init(&ctx->sh->queue);

    len = sizeof(" in lua_shared_dict zone \"\"") + shm_zone->shm.name.len;

    ctx->shpool->log_ctx = ngx_slab_alloc(ctx->shpool, len);
    if (ctx->shpool->log_ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_sprintf(ctx->shpool->log_ctx, " in lua_shared_dict zone \"%V\"%Z",
                &shm_zone->shm.name);

done:
    dd("get lmcf");

    lmcf = ctx->main_conf;

    dd("lmcf->lua: %p", lmcf->lua);

    lmcf->shm_zones_inited++;

    if (lmcf->shm_zones_inited == lmcf->shm_zones->nelts
        && lmcf->init_handler)
    {
        if (lmcf->init_handler(ctx->log, lmcf, lmcf->lua) != 0) {
            /* an error happened */
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


void
ngx_http_lua_shdict_rbtree_insert_value(ngx_rbtree_node_t *temp,
    ngx_rbtree_node_t *node, ngx_rbtree_node_t *sentinel)
{
    ngx_rbtree_node_t          **p;
    ngx_http_lua_shdict_node_t   *sdn, *sdnt;

    for ( ;; ) {

        if (node->key < temp->key) {

            p = &temp->left;

        } else if (node->key > temp->key) {

            p = &temp->right;

        } else { /* node->key == temp->key */

            sdn = (ngx_http_lua_shdict_node_t *) &node->color;
            sdnt = (ngx_http_lua_shdict_node_t *) &temp->color;

            p = ngx_memn2cmp(sdn->data, sdnt->data, sdn->key_len,
                             sdnt->key_len) < 0 ? &temp->left : &temp->right;
        }

        if (*p == sentinel) {
            break;
        }

        temp = *p;
    }

    *p = node;
    node->parent = temp;
    node->left = sentinel;
    node->right = sentinel;
    ngx_rbt_red(node);
}


static ngx_int_t
ngx_http_lua_shdict_lookup(ngx_shm_zone_t *shm_zone, ngx_uint_t hash,
    u_char *kdata, size_t klen, ngx_http_lua_shdict_node_t **sdp)
{
    ngx_int_t                    rc;
    ngx_time_t                  *tp;
    uint64_t                     now;
    int64_t                      ms;
    ngx_rbtree_node_t           *node, *sentinel;
    ngx_http_lua_shdict_ctx_t   *ctx;
    ngx_http_lua_shdict_node_t  *sd;

    ctx = shm_zone->data;

    node = ctx->sh->rbtree.root;
    sentinel = ctx->sh->rbtree.sentinel;

    while (node != sentinel) {

        if (hash < node->key) {
            node = node->left;
            continue;
        }

        if (hash > node->key) {
            node = node->right;
            continue;
        }

        /* hash == node->key */

        sd = (ngx_http_lua_shdict_node_t *) &node->color;

        rc = ngx_memn2cmp(kdata, sd->data, klen, (size_t) sd->key_len);

        if (rc == 0) {
            ngx_queue_remove(&sd->queue);
            ngx_queue_insert_head(&ctx->sh->queue, &sd->queue);

            *sdp = sd;

            dd("node expires: %lld", (long long) sd->expires);

            if (sd->expires != 0) {
                tp = ngx_timeofday();

                now = (uint64_t) tp->sec * 1000 + tp->msec;
                ms = sd->expires - now;

                dd("time to live: %lld", (long long) ms);

                if (ms < 0) {
                    dd("node already expired");
                    return NGX_DONE;
                }
            }

            return NGX_OK;
        }

        node = (rc < 0) ? node->left : node->right;
    }

    *sdp = NULL;

    return NGX_DECLINED;
}


static int
ngx_http_lua_shdict_expire(ngx_http_lua_shdict_ctx_t *ctx, ngx_uint_t n)
{
    ngx_time_t                  *tp;
    uint64_t                     now;
    ngx_queue_t                 *q;
    int64_t                      ms;
    ngx_rbtree_node_t           *node;
    ngx_http_lua_shdict_node_t  *sd;
    int                          freed = 0;

    tp = ngx_timeofday();

    now = (uint64_t) tp->sec * 1000 + tp->msec;

    /*
     * n == 1 deletes one or two expired entries
     * n == 0 deletes oldest entry by force
     *        and one or two zero rate entries
     */

    while (n < 3) {

        if (ngx_queue_empty(&ctx->sh->queue)) {
            return freed;
        }

        q = ngx_queue_last(&ctx->sh->queue);

        sd = ngx_queue_data(q, ngx_http_lua_shdict_node_t, queue);

        if (n++ != 0) {

            if (sd->expires == 0) {
                return freed;
            }

            ms = sd->expires - now;
            if (ms > 0) {
                return freed;
            }
        }

        ngx_queue_remove(q);

        node = (ngx_rbtree_node_t *)
                   ((u_char *) sd - offsetof(ngx_rbtree_node_t, color));

        ngx_rbtree_delete(&ctx->sh->rbtree, node);

        ngx_slab_free_locked(ctx->shpool, node);

        freed++;
    }

    return freed;
}


void
ngx_http_lua_inject_shdict_api(ngx_http_lua_main_conf_t *lmcf, lua_State *L)
{
    ngx_http_lua_shdict_ctx_t   *ctx;
    ngx_uint_t                   i;
    ngx_shm_zone_t             **zone;

    if (lmcf->shm_zones != NULL) {
        lua_createtable(L, 0, lmcf->shm_zones->nelts /* nrec */);
                /* ngx.shared */

        lua_createtable(L, 0 /* narr */, 13 /* nrec */); /* shared mt */

        lua_pushcfunction(L, ngx_http_lua_shdict_get);
        lua_setfield(L, -2, "get");

        lua_pushcfunction(L, ngx_http_lua_shdict_get_stale);
        lua_setfield(L, -2, "get_stale");

        lua_pushcfunction(L, ngx_http_lua_shdict_set);
        lua_setfield(L, -2, "set");

        lua_pushcfunction(L, ngx_http_lua_shdict_safe_set);
        lua_setfield(L, -2, "safe_set");

        lua_pushcfunction(L, ngx_http_lua_shdict_add);
        lua_setfield(L, -2, "add");

        lua_pushcfunction(L, ngx_http_lua_shdict_safe_add);
        lua_setfield(L, -2, "safe_add");

        lua_pushcfunction(L, ngx_http_lua_shdict_replace);
        lua_setfield(L, -2, "replace");

        lua_pushcfunction(L, ngx_http_lua_shdict_incr);
        lua_setfield(L, -2, "incr");

        lua_pushcfunction(L, ngx_http_lua_shdict_delete);
        lua_setfield(L, -2, "delete");

        lua_pushcfunction(L, ngx_http_lua_shdict_flush_all);
        lua_setfield(L, -2, "flush_all");

        lua_pushcfunction(L, ngx_http_lua_shdict_flush_expired);
        lua_setfield(L, -2, "flush_expired");

        lua_pushcfunction(L, ngx_http_lua_shdict_get_keys);
        lua_setfield(L, -2, "get_keys");

        lua_pushvalue(L, -1); /* shared mt mt */
        lua_setfield(L, -2, "__index"); /* shared mt */

        zone = lmcf->shm_zones->elts;

        for (i = 0; i < lmcf->shm_zones->nelts; i++) {
            ctx = zone[i]->data;

            lua_pushlstring(L, (char *) ctx->name.data, ctx->name.len);
                /* shared mt key */

            lua_pushlightuserdata(L, zone[i]); /* shared mt key ud */
            lua_pushvalue(L, -3); /* shared mt key ud mt */
            lua_setmetatable(L, -2); /* shared mt key ud */
            lua_rawset(L, -4); /* shared mt */
        }

        lua_pop(L, 1); /* shared */

    } else {
        lua_newtable(L);    /* ngx.shared */
    }

    lua_setfield(L, -2, "shared");
}


static int
ngx_http_lua_shdict_get(lua_State *L)
{
  return ngx_http_lua_shdict_get_helper(L, 0 /* stale */);
}


static int
ngx_http_lua_shdict_get_stale(lua_State *L)
{
  return ngx_http_lua_shdict_get_helper(L, 1 /* stale */);
}


static int
ngx_http_lua_shdict_get_helper(lua_State *L, int get_stale)
{
    int                          n;
    ngx_str_t                    name;
    ngx_str_t                    key;
    uint32_t                     hash;
    ngx_int_t                    rc;
    ngx_http_lua_shdict_ctx_t   *ctx;
    ngx_http_lua_shdict_node_t  *sd;
    ngx_str_t                    value;
    int                          value_type;
    double                       num;
    u_char                       c;
    ngx_shm_zone_t              *zone;
    uint32_t                     user_flags = 0;

    n = lua_gettop(L);

    if (n != 2) {
        return luaL_error(L, "expecting exactly two arguments, "
                          "but only seen %d", n);
    }

    zone = lua_touserdata(L, 1);
    if (zone == NULL) {
        return luaL_error(L, "bad \"zone\" argument");
    }

    ctx = zone->data;
    name = ctx->name;

    if (lua_isnil(L, 2)) {
        lua_pushnil(L);
        lua_pushliteral(L, "nil key");
        return 2;
    }

    key.data = (u_char *) luaL_checklstring(L, 2, &key.len);

    if (key.len == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "empty key");
        return 2;
    }

    if (key.len > 65535) {
        lua_pushnil(L);
        lua_pushliteral(L, "key too long");
        return 2;
    }

    hash = ngx_crc32_short(key.data, key.len);

#if (NGX_DEBUG)
    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ctx->log, 0,
                   "fetching key \"%V\" in shared dict \"%V\"", &key, &name);
#endif /* NGX_DEBUG */

    ngx_shmtx_lock(&ctx->shpool->mutex);

#if 1
    if (!get_stale) {
        ngx_http_lua_shdict_expire(ctx, 1);
    }
#endif

    rc = ngx_http_lua_shdict_lookup(zone, hash, key.data, key.len, &sd);

    dd("shdict lookup returns %d", (int) rc);

    if (rc == NGX_DECLINED || (rc == NGX_DONE && !get_stale)) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);
        lua_pushnil(L);
        return 1;
    }

    /* rc == NGX_OK || (rc == NGX_DONE && get_stale) */

    value_type = sd->value_type;

    dd("data: %p", sd->data);
    dd("key len: %d", (int) sd->key_len);

    value.data = sd->data + sd->key_len;
    value.len = (size_t) sd->value_len;

    switch (value_type) {
    case LUA_TSTRING:

        lua_pushlstring(L, (char *) value.data, value.len);
        break;

    case LUA_TNUMBER:

        if (value.len != sizeof(double)) {

            ngx_shmtx_unlock(&ctx->shpool->mutex);

            return luaL_error(L, "bad lua number value size found for key %s "
                              "in shared_dict %s: %lu", key.data, name.data,
                              (unsigned long) value.len);
        }

        num = *(double *) value.data;

        lua_pushnumber(L, num);
        break;

    case LUA_TBOOLEAN:

        if (value.len != sizeof(u_char)) {

            ngx_shmtx_unlock(&ctx->shpool->mutex);

            return luaL_error(L, "bad lua boolean value size found for key %s "
                              "in shared_dict %s: %lu", key.data, name.data,
                              (unsigned long) value.len);
        }

        c = *value.data;

        lua_pushboolean(L, c ? 1 : 0);
        break;

    default:

        ngx_shmtx_unlock(&ctx->shpool->mutex);

        return luaL_error(L, "bad value type found for key %s in "
                          "shared_dict %s: %d", key.data, name.data,
                          value_type);
    }

    user_flags = sd->user_flags;

    ngx_shmtx_unlock(&ctx->shpool->mutex);

    if (get_stale) {

        /* always return value, flags, stale */

        if (user_flags) {
            lua_pushinteger(L, (lua_Integer) user_flags);

        } else {
            lua_pushnil(L);
        }

        lua_pushboolean(L, rc == NGX_DONE);
        return 3;
    }

    if (user_flags) {
        lua_pushinteger(L, (lua_Integer) user_flags);
        return 2;
    }

    return 1;
}


static int
ngx_http_lua_shdict_delete(lua_State *L)
{
    int             n;

    n = lua_gettop(L);

    if (n != 2) {
        return luaL_error(L, "expecting 2 arguments, "
                          "but only seen %d", n);
    }

    lua_pushnil(L);

    return ngx_http_lua_shdict_set_helper(L, 0);
}


static int
ngx_http_lua_shdict_flush_all(lua_State *L)
{
    ngx_queue_t                 *q;
    ngx_http_lua_shdict_node_t  *sd;
    int                          n;
    ngx_http_lua_shdict_ctx_t   *ctx;
    ngx_shm_zone_t              *zone;

    n = lua_gettop(L);

    if (n != 1) {
        return luaL_error(L, "expecting 1 argument, but seen %d", n);
    }

    luaL_checktype(L, 1, LUA_TLIGHTUSERDATA);

    zone = lua_touserdata(L, 1);
    if (zone == NULL) {
        return luaL_error(L, "bad user data for the ngx_shm_zone_t pointer");
    }

    ctx = zone->data;

    ngx_shmtx_lock(&ctx->shpool->mutex);

    for (q = ngx_queue_head(&ctx->sh->queue);
         q != ngx_queue_sentinel(&ctx->sh->queue);
         q = ngx_queue_next(q))
    {
        sd = ngx_queue_data(q, ngx_http_lua_shdict_node_t, queue);
        sd->expires = 1;
    }

    ngx_http_lua_shdict_expire(ctx, 0);

    ngx_shmtx_unlock(&ctx->shpool->mutex);

    return 0;
}


static int
ngx_http_lua_shdict_flush_expired(lua_State *L)
{
    ngx_queue_t                 *q, *prev;
    ngx_http_lua_shdict_node_t  *sd;
    ngx_http_lua_shdict_ctx_t   *ctx;
    ngx_shm_zone_t              *zone;
    ngx_time_t                  *tp;
    int                          freed = 0;
    int                          attempts = 0;
    ngx_rbtree_node_t           *node;
    uint64_t                     now;
    int                          n;

    n = lua_gettop(L);

    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting 1 or 2 argument(s), but saw %d", n);
    }

    luaL_checktype(L, 1, LUA_TLIGHTUSERDATA);

    zone = lua_touserdata(L, 1);
    if (zone == NULL) {
        return luaL_error(L, "bad user data for the ngx_shm_zone_t pointer");
    }

    if (n == 2) {
        attempts = luaL_checkint(L, 2);
    }

    ctx = zone->data;

    ngx_shmtx_lock(&ctx->shpool->mutex);

    if (ngx_queue_empty(&ctx->sh->queue)) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);
        lua_pushnumber(L, 0);
        return 1;
    }

    tp = ngx_timeofday();

    now = (uint64_t) tp->sec * 1000 + tp->msec;

    q = ngx_queue_last(&ctx->sh->queue);

    while (q != ngx_queue_sentinel(&ctx->sh->queue)) {
        prev = ngx_queue_prev(q);

        sd = ngx_queue_data(q, ngx_http_lua_shdict_node_t, queue);

        if (sd->expires != 0 && sd->expires <= now) {
            ngx_queue_remove(q);

            node = (ngx_rbtree_node_t *)
                ((u_char *) sd - offsetof(ngx_rbtree_node_t, color));

            ngx_rbtree_delete(&ctx->sh->rbtree, node);
            ngx_slab_free_locked(ctx->shpool, node);
            freed++;

            if (attempts && freed == attempts) {
                break;
            }
        }

        q = prev;
    }

    ngx_shmtx_unlock(&ctx->shpool->mutex);

    lua_pushnumber(L, freed);
    return 1;
}


/*
 * This trades CPU for memory. This is potentially slow. O(2n)
 */

static int
ngx_http_lua_shdict_get_keys(lua_State *L)
{
    ngx_queue_t                 *q, *prev;
    ngx_http_lua_shdict_node_t  *sd;
    ngx_http_lua_shdict_ctx_t   *ctx;
    ngx_shm_zone_t              *zone;
    ngx_time_t                  *tp;
    int                          total = 0;
    int                          attempts = 1024;
    uint64_t                     now;
    int                          n;

    n = lua_gettop(L);

    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting 1 or 2 argument(s), "
                          "but saw %d", n);
    }

    luaL_checktype(L, 1, LUA_TLIGHTUSERDATA);

    zone = lua_touserdata(L, 1);
    if (zone == NULL) {
        return luaL_error(L, "bad user data for the ngx_shm_zone_t pointer");
    }

    if (n == 2) {
        attempts = luaL_checkint(L, 2);
    }

    ctx = zone->data;

    ngx_shmtx_lock(&ctx->shpool->mutex);

    if (ngx_queue_empty(&ctx->sh->queue)) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);
        lua_createtable(L, 0, 0);
        return 1;
    }

    tp = ngx_timeofday();

    now = (uint64_t) tp->sec * 1000 + tp->msec;

    /* first run through: get total number of elements we need to allocate */

    q = ngx_queue_last(&ctx->sh->queue);

    while (q != ngx_queue_sentinel(&ctx->sh->queue)) {
        prev = ngx_queue_prev(q);

        sd = ngx_queue_data(q, ngx_http_lua_shdict_node_t, queue);

        if (sd->expires == 0 || sd->expires > now) {
            total++;
            if (attempts && total == attempts) {
                break;
            }
        }

        q = prev;
    }

    lua_createtable(L, total, 0);

    /* second run through: add keys to table */

    total = 0;
    q = ngx_queue_last(&ctx->sh->queue);

    while (q != ngx_queue_sentinel(&ctx->sh->queue)) {
        prev = ngx_queue_prev(q);

        sd = ngx_queue_data(q, ngx_http_lua_shdict_node_t, queue);

        if (sd->expires == 0 || sd->expires > now) {
            lua_pushlstring(L, (char *) sd->data, sd->key_len);
            lua_rawseti(L, -2, ++total);
            if (attempts && total == attempts) {
                break;
            }
        }

        q = prev;
    }

    ngx_shmtx_unlock(&ctx->shpool->mutex);

    /* table is at top of stack */
    return 1;
}


static int
ngx_http_lua_shdict_add(lua_State *L)
{
    return ngx_http_lua_shdict_set_helper(L, NGX_HTTP_LUA_SHDICT_ADD);
}


static int
ngx_http_lua_shdict_safe_add(lua_State *L)
{
    return ngx_http_lua_shdict_set_helper(L, NGX_HTTP_LUA_SHDICT_ADD
                                          |NGX_HTTP_LUA_SHDICT_SAFE_STORE);
}


static int
ngx_http_lua_shdict_replace(lua_State *L)
{
    return ngx_http_lua_shdict_set_helper(L, NGX_HTTP_LUA_SHDICT_REPLACE);
}


static int
ngx_http_lua_shdict_set(lua_State *L)
{
    return ngx_http_lua_shdict_set_helper(L, 0);
}


static int
ngx_http_lua_shdict_safe_set(lua_State *L)
{
    return ngx_http_lua_shdict_set_helper(L, NGX_HTTP_LUA_SHDICT_SAFE_STORE);
}


static int
ngx_http_lua_shdict_set_helper(lua_State *L, int flags)
{
    int                          i, n;
    ngx_str_t                    key;
    uint32_t                     hash;
    ngx_int_t                    rc;
    ngx_http_lua_shdict_ctx_t   *ctx;
    ngx_http_lua_shdict_node_t  *sd;
    ngx_str_t                    value;
    int                          value_type;
    double                       num;
    u_char                       c;
    lua_Number                   exptime = 0;
    u_char                      *p;
    ngx_rbtree_node_t           *node;
    ngx_time_t                  *tp;
    ngx_shm_zone_t              *zone;
    int                          forcible = 0;
                         /* indicates whether to foricibly override other
                          * valid entries */
    int32_t                      user_flags = 0;

    n = lua_gettop(L);

    if (n != 3 && n != 4 && n != 5) {
        return luaL_error(L, "expecting 3, 4 or 5 arguments, "
                          "but only seen %d", n);
    }

    zone = lua_touserdata(L, 1);
    if (zone == NULL) {
        return luaL_error(L, "bad \"zone\" argument");
    }

    ctx = zone->data;

    if (lua_isnil(L, 2)) {
        lua_pushnil(L);
        lua_pushliteral(L, "nil key");
        return 2;
    }

    key.data = (u_char *) luaL_checklstring(L, 2, &key.len);

    if (key.len == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "empty key");
        return 2;
    }

    if (key.len > 65535) {
        lua_pushnil(L);
        lua_pushliteral(L, "key too long");
        return 2;
    }

    hash = ngx_crc32_short(key.data, key.len);

    value_type = lua_type(L, 3);

    switch (value_type) {
    case LUA_TSTRING:
        value.data = (u_char *) lua_tolstring(L, 3, &value.len);
        break;

    case LUA_TNUMBER:
        value.len = sizeof(double);
        num = lua_tonumber(L, 3);
        value.data = (u_char *) &num;
        break;

    case LUA_TBOOLEAN:
        value.len = sizeof(u_char);
        c = lua_toboolean(L, 3) ? 1 : 0;
        value.data = &c;
        break;

    case LUA_TNIL:
        if (flags & (NGX_HTTP_LUA_SHDICT_ADD|NGX_HTTP_LUA_SHDICT_REPLACE)) {
            lua_pushnil(L);
            lua_pushliteral(L, "attempt to add or replace nil values");
            return 2;
        }

        value.len = 0;
        value.data = NULL;
        break;

    default:
        lua_pushnil(L);
        lua_pushliteral(L, "bad value type");
        return 2;
    }

    if (n >= 4) {
        exptime = luaL_checknumber(L, 4);
        if (exptime < 0) {
            exptime = 0;
        }
    }

    if (n == 5) {
        user_flags = (uint32_t) luaL_checkinteger(L, 5);
    }

    ngx_shmtx_lock(&ctx->shpool->mutex);

#if 1
    ngx_http_lua_shdict_expire(ctx, 1);
#endif

    rc = ngx_http_lua_shdict_lookup(zone, hash, key.data, key.len, &sd);

    dd("shdict lookup returned %d", (int) rc);

    if (flags & NGX_HTTP_LUA_SHDICT_REPLACE) {

        if (rc == NGX_DECLINED || rc == NGX_DONE) {
            ngx_shmtx_unlock(&ctx->shpool->mutex);

            lua_pushboolean(L, 0);
            lua_pushliteral(L, "not found");
            lua_pushboolean(L, forcible);
            return 3;
        }

        /* rc == NGX_OK */

        goto replace;
    }

    if (flags & NGX_HTTP_LUA_SHDICT_ADD) {

        if (rc == NGX_OK) {
            ngx_shmtx_unlock(&ctx->shpool->mutex);

            lua_pushboolean(L, 0);
            lua_pushliteral(L, "exists");
            lua_pushboolean(L, forcible);
            return 3;
        }

        if (rc == NGX_DONE) {
            /* exists but expired */

            dd("go to replace");
            goto replace;
        }

        /* rc == NGX_DECLINED */

        dd("go to insert");
        goto insert;
    }

    if (rc == NGX_OK || rc == NGX_DONE) {

        if (value_type == LUA_TNIL) {
            goto remove;
        }

replace:
        if (value.data && value.len == (size_t) sd->value_len) {

            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ctx->log, 0,
                           "lua shared dict set: found old entry and value "
                           "size matched, reusing it");

            ngx_queue_remove(&sd->queue);
            ngx_queue_insert_head(&ctx->sh->queue, &sd->queue);

            sd->key_len = (u_short) key.len;

            if (exptime > 0) {
                tp = ngx_timeofday();
                sd->expires = (uint64_t) tp->sec * 1000 + tp->msec
                              + (uint64_t) (exptime * 1000);

            } else {
                sd->expires = 0;
            }

            sd->user_flags = user_flags;

            sd->value_len = (uint32_t) value.len;

            dd("setting value type to %d", value_type);

            sd->value_type = (uint8_t) value_type;

            p = ngx_copy(sd->data, key.data, key.len);
            ngx_memcpy(p, value.data, value.len);

            ngx_shmtx_unlock(&ctx->shpool->mutex);

            lua_pushboolean(L, 1);
            lua_pushnil(L);
            lua_pushboolean(L, forcible);
            return 3;
        }

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ctx->log, 0,
                       "lua shared dict set: found old entry bug value size "
                       "NOT matched, removing it first");

remove:
        ngx_queue_remove(&sd->queue);

        node = (ngx_rbtree_node_t *)
                   ((u_char *) sd - offsetof(ngx_rbtree_node_t, color));

        ngx_rbtree_delete(&ctx->sh->rbtree, node);

        ngx_slab_free_locked(ctx->shpool, node);

    }

insert:
    /* rc == NGX_DECLINED or value size unmatch */

    if (value.data == NULL) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);

        lua_pushboolean(L, 1);
        lua_pushnil(L);
        lua_pushboolean(L, 0);
        return 3;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ctx->log, 0,
                   "lua shared dict set: creating a new entry");

    n = offsetof(ngx_rbtree_node_t, color)
        + offsetof(ngx_http_lua_shdict_node_t, data)
        + key.len
        + value.len;

    node = ngx_slab_alloc_locked(ctx->shpool, n);

    if (node == NULL) {

        if (flags & NGX_HTTP_LUA_SHDICT_SAFE_STORE) {
            ngx_shmtx_unlock(&ctx->shpool->mutex);

            lua_pushboolean(L, 0);
            lua_pushliteral(L, "no memory");
            return 2;
        }

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ctx->log, 0,
                       "lua shared dict set: overriding non-expired items "
                       "due to memory shortage for entry \"%V\"", &key);

        for (i = 0; i < 30; i++) {
            if (ngx_http_lua_shdict_expire(ctx, 0) == 0) {
                break;
            }

            forcible = 1;

            node = ngx_slab_alloc_locked(ctx->shpool, n);
            if (node != NULL) {
                goto allocated;
            }
        }

        ngx_shmtx_unlock(&ctx->shpool->mutex);

        lua_pushboolean(L, 0);
        lua_pushliteral(L, "no memory");
        lua_pushboolean(L, forcible);
        return 3;
    }

allocated:
    sd = (ngx_http_lua_shdict_node_t *) &node->color;

    node->key = hash;
    sd->key_len = (u_short) key.len;

    if (exptime > 0) {
        tp = ngx_timeofday();
        sd->expires = (uint64_t) tp->sec * 1000 + tp->msec
                      + (uint64_t) (exptime * 1000);

    } else {
        sd->expires = 0;
    }

    sd->user_flags = user_flags;

    sd->value_len = (uint32_t) value.len;

    dd("setting value type to %d", value_type);

    sd->value_type = (uint8_t) value_type;

    p = ngx_copy(sd->data, key.data, key.len);
    ngx_memcpy(p, value.data, value.len);

    ngx_rbtree_insert(&ctx->sh->rbtree, node);

    ngx_queue_insert_head(&ctx->sh->queue, &sd->queue);

    ngx_shmtx_unlock(&ctx->shpool->mutex);

    lua_pushboolean(L, 1);
    lua_pushnil(L);
    lua_pushboolean(L, forcible);
    return 3;
}


static int
ngx_http_lua_shdict_incr(lua_State *L)
{
    int                          n;
    ngx_str_t                    key;
    uint32_t                     hash;
    ngx_int_t                    rc;
    ngx_http_lua_shdict_ctx_t   *ctx;
    ngx_http_lua_shdict_node_t  *sd;
    double                       num;
    u_char                      *p;
    ngx_shm_zone_t              *zone;
    double                       value;

    n = lua_gettop(L);

    if (n != 3) {
        return luaL_error(L, "expecting 3 arguments, but only seen %d", n);
    }

    if (lua_type(L, 1) != LUA_TLIGHTUSERDATA) {
        return luaL_error(L, "bad \"zone\" argument");
    }

    zone = lua_touserdata(L, 1);
    if (zone == NULL) {
        return luaL_error(L, "bad user data for the ngx_shm_zone_t pointer");
    }

    ctx = zone->data;

    if (lua_isnil(L, 2)) {
        lua_pushnil(L);
        lua_pushliteral(L, "nil key");
        return 2;
    }

    key.data = (u_char *) luaL_checklstring(L, 2, &key.len);

    if (key.len == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "empty key");
        return 2;
    }

    if (key.len > 65535) {
        lua_pushnil(L);
        lua_pushliteral(L, "key too long");
        return 2;
    }

    hash = ngx_crc32_short(key.data, key.len);

    value = luaL_checknumber(L, 3);

    dd("looking up key %.*s in shared dict %.*s", (int) key.len, key.data,
       (int) ctx->name.len, ctx->name.data);

    ngx_shmtx_lock(&ctx->shpool->mutex);

#if 1
    ngx_http_lua_shdict_expire(ctx, 1);
#endif

    rc = ngx_http_lua_shdict_lookup(zone, hash, key.data, key.len, &sd);

    dd("shdict lookup returned %d", (int) rc);

    if (rc == NGX_DECLINED || rc == NGX_DONE) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);

        lua_pushnil(L);
        lua_pushliteral(L, "not found");
        return 2;
    }

    /* rc == NGX_OK */

    if (sd->value_type != LUA_TNUMBER || sd->value_len != sizeof(double)) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);

        lua_pushnil(L);
        lua_pushliteral(L, "not a number");
        return 2;
    }

    ngx_queue_remove(&sd->queue);
    ngx_queue_insert_head(&ctx->sh->queue, &sd->queue);

    dd("setting value type to %d", (int) sd->value_type);

    p = sd->data + key.len;

    num = *(double *) p;
    num += value;

    ngx_memcpy(p, (double *) &num, sizeof(double));

    ngx_shmtx_unlock(&ctx->shpool->mutex);

    lua_pushnumber(L, num);
    lua_pushnil(L);
    return 2;
}


ngx_int_t
ngx_http_lua_shared_dict_get(ngx_shm_zone_t *zone, u_char *key_data,
    size_t key_len, ngx_http_lua_value_t *value)
{
    u_char                      *data;
    size_t                       len;
    uint32_t                     hash;
    ngx_int_t                    rc;
    ngx_http_lua_shdict_ctx_t   *ctx;
    ngx_http_lua_shdict_node_t  *sd;

    if (zone == NULL) {
        return NGX_ERROR;
    }

    hash = ngx_crc32_short(key_data, key_len);

    ctx = zone->data;

    ngx_shmtx_lock(&ctx->shpool->mutex);

    rc = ngx_http_lua_shdict_lookup(zone, hash, key_data, key_len, &sd);

    dd("shdict lookup returned %d", (int) rc);

    if (rc == NGX_DECLINED || rc == NGX_DONE) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);

        return rc;
    }

    /* rc == NGX_OK */

    value->type = sd->value_type;

    dd("type: %d", (int) value->type);

    data = sd->data + sd->key_len;
    len = (size_t) sd->value_len;

    switch (value->type) {
    case LUA_TSTRING:

        if (value->value.s.data == NULL || value->value.s.len == 0) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "no string buffer "
                          "initialized");
            return NGX_ERROR;
        }

        if (len > value->value.s.len) {
            len = value->value.s.len;

        } else {
            value->value.s.len = len;
        }

        ngx_memcpy(value->value.s.data, data, len);
        break;

    case LUA_TNUMBER:

        if (len != sizeof(double)) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "bad lua number "
                          "value size found for key %*s: %lu", key_len,
                          key_data, (unsigned long) len);

            ngx_shmtx_unlock(&ctx->shpool->mutex);
            return NGX_ERROR;
        }

        ngx_memcpy(&value->value.b, data, len);
        break;

    case LUA_TBOOLEAN:

        if (len != sizeof(u_char)) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "bad lua boolean "
                          "value size found for key %*s: %lu", key_len,
                          key_data, (unsigned long) len);

            ngx_shmtx_unlock(&ctx->shpool->mutex);
            return NGX_ERROR;
        }

        value->value.b = *data;
        break;

    default:
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0, "bad lua value type "
                      "found for key %*s: %d", key_len, key_data,
                      (int) value->type);

        ngx_shmtx_unlock(&ctx->shpool->mutex);
        return NGX_ERROR;
    }

    ngx_shmtx_unlock(&ctx->shpool->mutex);
    return NGX_OK;
}


ngx_shm_zone_t *
ngx_http_lua_find_zone(u_char *name_data, size_t name_len)
{
    ngx_str_t                       *name;
    ngx_uint_t                       i;
    ngx_shm_zone_t                  *zone;
    volatile ngx_list_part_t        *part;

    part = &ngx_cycle->shared_memory.part;
    zone = part->elts;

    for (i = 0; /* void */ ; i++) {

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            zone = part->elts;
            i = 0;
        }

        name = &zone[i].shm.name;

        dd("name: [%.*s] %d", (int) name->len, name->data, (int) name->len);
        dd("name2: [%.*s] %d", (int) name_len, name_data, (int) name_len);

        if (name->len == name_len
            && ngx_strncmp(name->data, name_data, name_len) == 0)
        {
            return zone;
        }
    }

    return NULL;
}


#ifndef NGX_HTTP_LUA_NO_FFI_API
int
ngx_http_lua_ffi_shdict_store(ngx_shm_zone_t *zone, int op, u_char *key,
    size_t key_len, int value_type, u_char *str_value_buf,
    size_t str_value_len, double num_value, int exptime, int user_flags,
    char **errmsg, int *forcible)
{
    int                          i, n;
    u_char                       c, *p;
    uint32_t                     hash;
    ngx_int_t                    rc;
    ngx_time_t                  *tp;
    ngx_rbtree_node_t           *node;
    ngx_http_lua_shdict_ctx_t   *ctx;
    ngx_http_lua_shdict_node_t  *sd;

    if (zone == NULL) {
        return NGX_ERROR;
    }

    dd("exptime: %d", exptime);

    ctx = zone->data;

    *forcible = 0;

    hash = ngx_crc32_short(key, key_len);

    switch (value_type) {
    case LUA_TSTRING:
        /* do nothing */
        break;

    case LUA_TNUMBER:
        dd("num value: %lf", num_value);
        str_value_buf = (u_char *) &num_value;
        str_value_len = sizeof(double);
        break;

    case LUA_TBOOLEAN:
        c = num_value ? 1 : 0;
        str_value_buf = &c;
        str_value_len = sizeof(u_char);
        break;

    case LUA_TNIL:
        if (op & (NGX_HTTP_LUA_SHDICT_ADD|NGX_HTTP_LUA_SHDICT_REPLACE)) {
            *errmsg = "attempt to add or replace nil values";
            return NGX_ERROR;
        }

        str_value_buf = NULL;
        str_value_len = 0;
        break;

    default:
        *errmsg = "unsupported value type";
        return NGX_ERROR;
    }

    ngx_shmtx_lock(&ctx->shpool->mutex);

#if 1
    ngx_http_lua_shdict_expire(ctx, 1);
#endif

    rc = ngx_http_lua_shdict_lookup(zone, hash, key, key_len, &sd);

    dd("lookup returns %d", (int) rc);

    if (op & NGX_HTTP_LUA_SHDICT_REPLACE) {

        if (rc == NGX_DECLINED || rc == NGX_DONE) {
            ngx_shmtx_unlock(&ctx->shpool->mutex);
            *errmsg = "not found";
            return NGX_DECLINED;
        }
        /* rc == NGX_OK */

        goto replace;
    }

    if (op & NGX_HTTP_LUA_SHDICT_ADD) {

        if (rc == NGX_OK) {
            ngx_shmtx_unlock(&ctx->shpool->mutex);
            *errmsg = "exists";
            return NGX_DECLINED;
        }

        if (rc == NGX_DONE) {
            /* exists but expired */

            dd("go to replace");
            goto replace;
        }

        /* rc == NGX_DECLINED */

        dd("go to insert");
        goto insert;
    }

    if (rc == NGX_OK || rc == NGX_DONE) {

        if (value_type == LUA_TNIL) {
            goto remove;
        }

replace:
        if (str_value_buf && str_value_len == (size_t) sd->value_len) {

            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ctx->log, 0,
                           "lua shared dict set: found old entry and value "
                           "size matched, reusing it");

            ngx_queue_remove(&sd->queue);
            ngx_queue_insert_head(&ctx->sh->queue, &sd->queue);

            sd->key_len = (u_short) key_len;

            if (exptime > 0) {
                tp = ngx_timeofday();
                sd->expires = (uint64_t) tp->sec * 1000 + tp->msec
                              + (uint64_t) exptime;

            } else {
                sd->expires = 0;
            }

            sd->user_flags = user_flags;

            sd->value_len = (uint32_t) str_value_len;

            dd("setting value type to %d", value_type);

            sd->value_type = (uint8_t) value_type;

            p = ngx_copy(sd->data, key, key_len);
            ngx_memcpy(p, str_value_buf, str_value_len);

            ngx_shmtx_unlock(&ctx->shpool->mutex);

            return NGX_OK;
        }

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ctx->log, 0,
                       "lua shared dict set: found old entry bug value size "
                       "NOT matched, removing it first");

remove:
        ngx_queue_remove(&sd->queue);

        node = (ngx_rbtree_node_t *)
                   ((u_char *) sd - offsetof(ngx_rbtree_node_t, color));

        ngx_rbtree_delete(&ctx->sh->rbtree, node);

        ngx_slab_free_locked(ctx->shpool, node);

    }

insert:
    /* rc == NGX_DECLINED or value size unmatch */

    if (str_value_buf == NULL) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);
        return NGX_OK;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ctx->log, 0,
                   "lua shared dict set: creating a new entry");

    n = offsetof(ngx_rbtree_node_t, color)
        + offsetof(ngx_http_lua_shdict_node_t, data)
        + key_len
        + str_value_len;

    node = ngx_slab_alloc_locked(ctx->shpool, n);

    if (node == NULL) {

        if (op & NGX_HTTP_LUA_SHDICT_SAFE_STORE) {
            ngx_shmtx_unlock(&ctx->shpool->mutex);

            *errmsg = "no memory";
            return NGX_ERROR;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ctx->log, 0,
                       "lua shared dict set: overriding non-expired items "
                       "due to memory shortage for entry \"%*s\"", key_len,
                       key);

        for (i = 0; i < 30; i++) {
            if (ngx_http_lua_shdict_expire(ctx, 0) == 0) {
                break;
            }

            *forcible = 1;

            node = ngx_slab_alloc_locked(ctx->shpool, n);
            if (node != NULL) {
                goto allocated;
            }
        }

        ngx_shmtx_unlock(&ctx->shpool->mutex);

        *errmsg = "no memory";
        return NGX_ERROR;
    }

allocated:
    sd = (ngx_http_lua_shdict_node_t *) &node->color;

    node->key = hash;
    sd->key_len = (u_short) key_len;

    if (exptime > 0) {
        tp = ngx_timeofday();
        sd->expires = (uint64_t) tp->sec * 1000 + tp->msec
                      + (uint64_t) exptime;

    } else {
        sd->expires = 0;
    }

    sd->user_flags = user_flags;
    sd->value_len = (uint32_t) str_value_len;
    dd("setting value type to %d", value_type);
    sd->value_type = (uint8_t) value_type;

    p = ngx_copy(sd->data, key, key_len);
    ngx_memcpy(p, str_value_buf, str_value_len);

    ngx_rbtree_insert(&ctx->sh->rbtree, node);
    ngx_queue_insert_head(&ctx->sh->queue, &sd->queue);
    ngx_shmtx_unlock(&ctx->shpool->mutex);

    return NGX_OK;
}


int
ngx_http_lua_ffi_shdict_get(ngx_shm_zone_t *zone, u_char *key,
    size_t key_len, int *value_type, u_char **str_value_buf,
    size_t *str_value_len, double *num_value, int *user_flags,
    int get_stale, int *is_stale)
{
    ngx_str_t                    name;
    uint32_t                     hash;
    ngx_int_t                    rc;
    ngx_http_lua_shdict_ctx_t   *ctx;
    ngx_http_lua_shdict_node_t  *sd;
    ngx_str_t                    value;

    if (zone == NULL) {
        return NGX_ERROR;
    }

    ctx = zone->data;
    name = ctx->name;

    hash = ngx_crc32_short(key, key_len);

#if (NGX_DEBUG)
    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ctx->log, 0,
                   "fetching key \"%*s\" in shared dict \"%V\"", key_len,
                   key, &name);
#endif /* NGX_DEBUG */

    ngx_shmtx_lock(&ctx->shpool->mutex);

#if 1
    if (!get_stale) {
        ngx_http_lua_shdict_expire(ctx, 1);
    }
#endif

    rc = ngx_http_lua_shdict_lookup(zone, hash, key, key_len, &sd);

    dd("shdict lookup returns %d", (int) rc);

    if (rc == NGX_DECLINED || (rc == NGX_DONE && !get_stale)) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);
        *value_type = LUA_TNIL;
        return NGX_OK;
    }

    /* rc == NGX_OK || (rc == NGX_DONE && get_stale) */

    *value_type = sd->value_type;

    dd("data: %p", sd->data);
    dd("key len: %d", (int) sd->key_len);

    value.data = sd->data + sd->key_len;
    value.len = (size_t) sd->value_len;

    if (*str_value_len < (size_t) value.len) {
        if (*value_type != LUA_TSTRING) {
            return NGX_ERROR;
        }

        *str_value_buf = malloc(value.len);
        if (*str_value_buf == NULL) {
            ngx_shmtx_unlock(&ctx->shpool->mutex);
            return NGX_ERROR;
        }
    }

    *str_value_len = value.len;

    switch (*value_type) {
    case LUA_TSTRING:
        ngx_memcpy(*str_value_buf, value.data, value.len);
        break;

    case LUA_TNUMBER:

        if (value.len != sizeof(double)) {
            ngx_shmtx_unlock(&ctx->shpool->mutex);
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                          "bad lua number value size found for key %*s "
                          "in shared_dict %V: %z", key_len, key,
                          &name, value.len);
            return NGX_ERROR;
        }

        *num_value = *(double *) value.data;
        break;

    case LUA_TBOOLEAN:

        if (value.len != sizeof(u_char)) {
            ngx_shmtx_unlock(&ctx->shpool->mutex);
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                          "bad lua boolean value size found for key %*s "
                          "in shared_dict %V: %z", key_len, key, &name,
                          value.len);
            return NGX_ERROR;
        }

        ngx_memcpy(*str_value_buf, value.data, value.len);
        break;

    default:

        ngx_shmtx_unlock(&ctx->shpool->mutex);
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "bad value type found for key %*s in "
                      "shared_dict %V: %d", key_len, key, &name,
                      *value_type);
    }

    *user_flags = sd->user_flags;
    dd("user flags: %d", *user_flags);

    ngx_shmtx_unlock(&ctx->shpool->mutex);

    if (get_stale) {

        /* always return value, flags, stale */

        *is_stale = (rc == NGX_DONE);
        return NGX_OK;
    }

    return NGX_OK;
}


int
ngx_http_lua_ffi_shdict_incr(ngx_shm_zone_t *zone, u_char *key,
    size_t key_len, double *value, char **err)
{
    uint32_t                     hash;
    ngx_int_t                    rc;
    ngx_http_lua_shdict_ctx_t   *ctx;
    ngx_http_lua_shdict_node_t  *sd;
    double                       num;
    u_char                      *p;

    ctx = zone->data;
    hash = ngx_crc32_short(key, key_len);

    dd("looking up key %.*s in shared dict %.*s", (int) key_len, key,
       (int) ctx->name.len, ctx->name.data);

    ngx_shmtx_lock(&ctx->shpool->mutex);
#if 1
    ngx_http_lua_shdict_expire(ctx, 1);
#endif
    rc = ngx_http_lua_shdict_lookup(zone, hash, key, key_len, &sd);

    dd("shdict lookup returned %d", (int) rc);

    if (rc == NGX_DECLINED || rc == NGX_DONE) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);
        *err = "not found";
        return NGX_ERROR;
    }

    /* rc == NGX_OK */

    if (sd->value_type != LUA_TNUMBER || sd->value_len != sizeof(double)) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);
        *err = "not a number";
        return NGX_ERROR;
    }

    ngx_queue_remove(&sd->queue);
    ngx_queue_insert_head(&ctx->sh->queue, &sd->queue);

    dd("setting value type to %d", (int) sd->value_type);

    p = sd->data + key_len;

    num = *(double *) p;
    num += *value;

    ngx_memcpy(p, (double *) &num, sizeof(double));

    ngx_shmtx_unlock(&ctx->shpool->mutex);

    *value = num;
    return NGX_OK;
}
#endif /* NGX_HTTP_LUA_NO_FFI_API */


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
