/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#include <sys/ipc.h>
#include <sys/shm.h>

#include <sys/file.h>

#include "ngx_ingress_protobuf.h"

#include <ngx_comm_serialize.h>
#include <ngx_ingress_module.h>

ngx_int_t
ngx_ingress_shared_memory_init(ngx_ingress_shared_memory_t * shared, ngx_str_t *shm_name, ngx_uint_t shm_size, ngx_str_t *lock_file)
{
    int shm_fd = 0;
	int flag = 0600;
    
    if((shm_fd = shm_open((const char*)shm_name->data, O_RDWR, flag)) < 0) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|shared shmget failed|");
		return NGX_ERROR;
	}

    shared->base_address = (u_char *) mmap(NULL, shm_size, PROT_READ|PROT_WRITE, MAP_SHARED, shm_fd, 0);
    if(shared->base_address == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|shared shmat failed|");
        close(shm_fd);
		return NGX_ERROR;
	}

    shared->shm_size = shm_size;
    shared->shm_fd = shm_fd;
    shared->lock_fd = ngx_open_file(lock_file->data, NGX_FILE_RDWR, NGX_FILE_OPEN,
                                   NGX_FILE_DEFAULT_ACCESS);

    if (shared->lock_fd == NGX_INVALID_FILE) {
        ngx_log_error(NGX_LOG_EMERG, ngx_cycle->log, ngx_errno,
                    "|ingress|open lock file \"%s\" failed|", lock_file);
        close(shm_fd);
        return NGX_ERROR;
    }

    return NGX_OK;
}

void
ngx_ingress_shared_memory_uninit(ngx_ingress_shared_memory_t *shared)
{
    if (shared->base_address != NULL) {
        munmap(shared->base_address, shared->shm_size);
        shared->base_address = NULL;
    }
    if (shared->shm_fd > 0) {
        close(shared->shm_fd);
    }
    
    if (shared->lock_fd != NGX_INVALID_FILE) {
        ngx_close_file(shared->lock_fd);
        shared->lock_fd = NGX_INVALID_FILE;
    }
}

ngx_ingress_shared_memory_t *
ngx_ingress_shared_memory_create(ngx_str_t *shm_name, ngx_uint_t shm_size, ngx_str_t *lock_file)
{
    ngx_ingress_shared_memory_t *shared = NULL;

    shared = ngx_calloc(sizeof(ngx_ingress_shared_memory_t), ngx_cycle->log);
    if (shared == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|shared alloc failed|");
        return NULL;
    }

    ngx_int_t rc = ngx_ingress_shared_memory_init(shared, shm_name, shm_size, lock_file);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|shared memory init failed|");
        ngx_free(shared);
        return NULL;
    }

    return shared;
}

void
ngx_ingress_shared_memory_free(ngx_ingress_shared_memory_t *shared)
{
    ngx_ingress_shared_memory_uninit(shared);
    ngx_free(shared);
}


ngx_int_t
ngx_ingress_shared_memory_write_status(
    ngx_ingress_shared_memory_t *shared,
    ngx_ingress_shared_memory_status_e status)
{
    u_char      *pos = shared->base_address;
    uint32_t     left = shared->shm_size;
    ngx_int_t    rc;
    ngx_int_t    err;

    /* 加锁 */
    err = flock(shared->lock_fd, LOCK_EX|LOCK_NB);
    if (err != 0) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|trylock failed|%d|%i|", err, shared->lock_fd);
        return NGX_AGAIN;
    }

    /* write status */
    rc = ngx_serialize_write_uint32(&pos, &left, (uint32_t)status);

    flock(shared->lock_fd, LOCK_UN);

    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|shared write status failed|");
    }
    
    return rc;
}

ngx_int_t
ngx_ingress_shared_memory_read_pb_locked(
    ngx_ingress_shared_memory_t *shared,
    ngx_ingress_shared_memory_config_t *shm_pb_config,
    ngx_ingress_pb_read_mode_e mode)
{
    ngx_int_t rc;

    uint32_t status, type, length, left;
    u_char *pos = shared->base_address;

    ngx_str_t src;
    u_char md5_hex[NGX_COMM_MD5_HEX_LEN];

    left = shared->shm_size;

    shm_pb_config->pbconfig = NULL;

    /* read Status */
    rc = ngx_serialize_read_uint32(&pos, &left, &status);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|shared read status failed|");
        return NGX_ERROR;
    }

    /* read version */
    rc = ngx_serialize_read_uint64(&pos, &left, &shm_pb_config->version);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|shared read version failed|");
        return NGX_ERROR;
    }

    if (mode == ngx_ingress_pb_read_version) {
        return NGX_OK;
    }

    /* read Config-Type */
    rc = ngx_serialize_read_uint32(&pos, &left, &type);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|shared read config type failed|");
        return NGX_ERROR;
    }
    shm_pb_config->type = type;

    if (shm_pb_config->type != NGX_INGRESS_SHARED_MEMORY_TYPE_SERVICE) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|unknown config type|%d|", shm_pb_config->type);
        return NGX_ERROR;
    }

    /* read Config-MD5 */
    rc = ngx_serialize_read_data(&pos, &left, shm_pb_config->md5_digit, NGX_COMM_MD5_HEX_LEN);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|shared read config md5 failed|");
        return NGX_ERROR;
    }

    /* read Config-Length */
    rc = ngx_serialize_read_uint32(&pos, &left, &length);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|shared read config len failed|");
        return NGX_ERROR;
    }

    /* check Configs MD5 */
    if (left < length) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|shared pb len too small|");
        return NGX_ERROR;
    }
    src.data = pos;
    src.len = length;

    ngx_comm_md5_string(&src, md5_hex);
    if (memcmp(md5_hex, shm_pb_config->md5_digit, NGX_COMM_MD5_HEX_LEN) != 0) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|shared md5 not equal|");
        return NGX_ERROR;
    }

    /* parse PB */
    Ingress__Config * pbconfig = ingress__config__unpack(NULL, src.len, src.data);
    if (pbconfig == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|shared parse pb failed|");
        return NGX_ERROR;
    }

    shm_pb_config->pbconfig = pbconfig;

    return NGX_OK;
}

ngx_int_t
ngx_ingress_shared_memory_read_pb(
    ngx_ingress_shared_memory_t *shared,
    ngx_ingress_shared_memory_config_t *shm_pb_config,
    ngx_ingress_pb_read_mode_e mode)
{
    ngx_int_t rc;
    int err;

    err = flock(shared->lock_fd, LOCK_EX|LOCK_NB);
    if (err != 0) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|trylock failed|%d|%i|", err, shared->lock_fd);
        return NGX_AGAIN;
    }

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                  "|ingress|trylock success|%d|%i|", err, shared->lock_fd);

    rc = ngx_ingress_shared_memory_read_pb_locked(shared, shm_pb_config, mode);
    
    flock(shared->lock_fd, LOCK_UN);

    return rc;
}

void
ngx_ingress_shared_memory_free_pb(ngx_ingress_shared_memory_config_t *shm_pb_config)
{
    if (shm_pb_config->pbconfig != NULL) {
        ingress__config__free_unpacked(shm_pb_config->pbconfig, NULL);
    }
}

static int
ngx_ingress_host_compare(const void * p1, const void* p2) {
    ngx_ingress_host_router_t * v1 = (ngx_ingress_host_router_t*)p1;
    ngx_ingress_host_router_t * v2 = (ngx_ingress_host_router_t*)p2;

    return ngx_comm_strcasecmp(&v1->host, &v2->host);
}

static ngx_uint_t
ngx_ingress_host_hash(const void * p) {
    ngx_uint_t hash;
    ngx_ingress_host_router_t * v1 = (ngx_ingress_host_router_t*)p;

    hash = ngx_hash_key_lc(v1->host.data, v1->host.len);

    return hash;
}

static int
ngx_ingress_service_compare(const void * p1, const void* p2) {
    ngx_ingress_service_t * v1 = (ngx_ingress_service_t*)p1;
    ngx_ingress_service_t * v2 = (ngx_ingress_service_t*)p2;

    return ngx_comm_strcmp(&v1->name, &v2->name);
}

static ngx_uint_t
ngx_ingress_service_hash(const void * p) {
    ngx_uint_t hash;
    ngx_ingress_service_t * v1 = (ngx_ingress_service_t*)p;

    hash = ngx_hash_key(v1->name.data, v1->name.len);

    return hash;
}

static ngx_ingress_service_t *
ngx_ingress_get_service(ngx_ingress_t *ingress, char* service_name)
{
    ngx_ingress_service_t service_key;
    ngx_ingress_service_t *service;

    if (service_name == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|service is null|");
        return NULL;
    }

    service_key.name.len = ngx_strlen(service_name);
    service_key.name.data = (u_char*)service_name;
    service = (ngx_ingress_service_t *)ngx_shm_hash_get(ingress->service_map, &service_key);
    if (service == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|service not found|%V|", &service_key.name);
        return NULL;
    }

    return service;
}

int
ngx_ingress_metadata_compare(const void *c1, const void *c2)
{
    ngx_ingress_metadata_t *meta1 = (ngx_ingress_metadata_t*)c1;
    ngx_ingress_metadata_t *meta2 = (ngx_ingress_metadata_t*)c2;

    return ngx_comm_str_compare(&meta1->key, &meta2->key);
}

static ngx_int_t
ngx_ingress_update_shm_service(ngx_ingress_t *ingress,
    ngx_ingress_service_t *shm_service,
    Ingress__VirtualService *pbservice
    )
{
    size_t                  i;
    ngx_int_t               weight, start;

    /* name */
    if (pbservice->service_name == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                        "|ingress|pb service name is null|");
        return NGX_ERROR;
    }

    ngx_int_t len = strlen(pbservice->service_name);
    shm_service->name.data = ngx_shm_pool_calloc(ingress->pool, len);
    if (shm_service->name.data == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                        "|ingress|alloc service name failed|");
        return NGX_ERROR;
    }
    shm_service->name.len = len;
    ngx_memcpy(shm_service->name.data, pbservice->service_name, len);

    /* force https */
    if (pbservice->has_force_https) {
        shm_service->force_https = pbservice->force_https;
    }
    
    /* timeout */
    if (pbservice->timeout_ms != NULL) {
        if (pbservice->timeout_ms->has_connect_timeout) {
            shm_service->timeout.connect_timeout = pbservice->timeout_ms->connect_timeout;
        } else {
            shm_service->timeout.connect_timeout = NGX_CONF_UNSET_MSEC;
        }

        if (pbservice->timeout_ms->has_read_timeout) {
            shm_service->timeout.read_timeout = pbservice->timeout_ms->read_timeout;
        } else {
            shm_service->timeout.read_timeout = NGX_CONF_UNSET_MSEC;
        }

        if (pbservice->timeout_ms->has_write_timeout) {
            shm_service->timeout.write_timeout = pbservice->timeout_ms->write_timeout;
        } else {
            shm_service->timeout.write_timeout = NGX_CONF_UNSET_MSEC;
        }
    }

    /* upstreams */
    if (pbservice->n_upstreams == 0) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|service no upstream|service=%V|", &shm_service->name);
        return NGX_ERROR;
    }

    shm_service->upstreams = ngx_shm_array_create(ingress->pool, pbservice->n_upstreams, sizeof(ngx_ingress_upstream_t));
    if (shm_service->upstreams == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|alloc upstreams failed|service=%V|", &shm_service->name);
        return NGX_ERROR;
    }

    weight = 0;
    start = 0;

    Ingress__Upstream **upstreams = pbservice->upstreams;
    for (i = 0; i < pbservice->n_upstreams; i++) {
        ngx_ingress_upstream_t *shm_ups = ngx_shm_array_push(shm_service->upstreams);
        if (shm_ups == NULL) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|shm_ups push array failed|service=%V|", &shm_service->name);
            return NGX_ERROR;
        }
        if (upstreams[i]->has_weight) {
            weight += upstreams[i]->weight;
            shm_ups->start = start;
            start += upstreams[i]->weight;
            shm_ups->end = start;
        }

        if (upstreams[i]->target == NULL) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|target is null|service=%V|", &shm_service->name);
            return NGX_ERROR;
        }

        ngx_int_t target_len = strlen(upstreams[i]->target);
        shm_ups->target.data = ngx_shm_pool_calloc(ingress->pool, target_len);
        if (shm_ups->target.data == NULL) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|alloc target failed|service=%V|", &shm_service->name);
            return NGX_ERROR;
        }
        shm_ups->target.len = target_len;
        ngx_memcpy(shm_ups->target.data, upstreams[i]->target, target_len);

        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                      "|ingress|shm_ups weight|%i|%i|%V|", shm_ups->start, shm_ups->end, &shm_ups->target);
    }
    shm_service->upstream_weight = weight;

    /* metadata */
    Ingress__Metadata **pb_metadata = pbservice->metadata;

    shm_service->metadata = ngx_shm_array_create(ingress->pool, pbservice->n_metadata, sizeof(ngx_ingress_metadata_t));
    if (shm_service->metadata == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|alloc metadata failed|service=%V|", &shm_service->name);
        return NGX_ERROR;
    }

    for (i = 0; i < pbservice->n_metadata; i++) {
        ngx_ingress_metadata_t *metadata = ngx_shm_array_push(shm_service->metadata);
        if (metadata == NULL) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|alloc metadata failed|service=%V|", &shm_service->name);
            return NGX_ERROR;
        }

        if (pb_metadata[i]->key == NULL || pb_metadata[i]->value == NULL) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|meta data key or value is null|service=%V|", &shm_service->name);
            return NGX_ERROR;
        }

        ngx_int_t len = ngx_strlen(pb_metadata[i]->key);
        metadata->key.data = ngx_shm_pool_calloc(ingress->pool, len);
        if (metadata->key.data == NULL) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|alloc metadata key failed|");
            return NGX_ERROR;
        }
        metadata->key.len = len;
        ngx_memcpy(metadata->key.data, pb_metadata[i]->key, len);

        len = ngx_strlen(pb_metadata[i]->value);
        metadata->value.data = ngx_shm_pool_calloc(ingress->pool, len);
        if (metadata->value.data == NULL) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|alloc metadata value failed|");
            return NGX_ERROR;
        }
        metadata->value.len = len;
        ngx_memcpy(metadata->value.data, pb_metadata[i]->value, len);
    }

    ngx_shm_sort_array(shm_service->metadata, ngx_ingress_metadata_compare);

    return NGX_OK;
}

static int
ngx_path_prefix_compare(const void *c1, const void *c2)
{
    ngx_ingress_path_router_t *router1 = (ngx_ingress_path_router_t*)c1;
    ngx_ingress_path_router_t *router2 = (ngx_ingress_path_router_t*)c2;

    /* Shorter prefixes match first */
    if (router1->prefix.len > router2->prefix.len) {
        return -1;
    } else if (router1->prefix.len < router2->prefix.len) {
        return 1;
    }

    return ngx_comm_str_compare(&router1->prefix, &router2->prefix);
}

static ngx_int_t
ngx_ingress_update_shm_tag_routers(ngx_ingress_t *ingress,
    size_t n_tags, Ingress__TagRouter **pb_tag_routers,
    ngx_shm_array_t **pptags)
{
    size_t                  i, j, k;
    ngx_shm_array_t        *ptags = NULL;
    ngx_int_t               key_len, value_len;

#if 0

#define MAX_TAG_ROUTE_NUMS      2
#define MAX_TAG_RULE_NUMS       2
#define MAX_TAG_ITEM_NUMS       2

    Ingress__TagRouter      tag_route[MAX_TAG_ROUTE_NUMS];
    Ingress__TagRouter     *p_tag_route[MAX_TAG_ROUTE_NUMS];
    Ingress__TagRule        tag_rule[MAX_TAG_RULE_NUMS];
    Ingress__TagRule       *p_tag_rule[MAX_TAG_RULE_NUMS];
    Ingress__TagItem        tag_item[MAX_TAG_ITEM_NUMS];
    Ingress__TagItem       *p_tag_item[MAX_TAG_ITEM_NUMS];
    char                   *service_names[MAX_TAG_ROUTE_NUMS] = {"*.wap.keruyun.test/",
                    "100x100w.heyi.test/", "127.api.taobao.net/", "110.daily.taobao.net/"};
    char                   *keys[MAX_TAG_ITEM_NUMS] = {"appkey", "x-appkey", "Appkey", "X-Appkey"};
    char                   *values[MAX_TAG_ITEM_NUMS] = {"21646297", "21380790", "23524755", "25005935"};
    pb_tag_routers = &p_tag_route;
    n_tags = MAX_TAG_ROUTE_NUMS;

    for (i = 0; i < MAX_TAG_ROUTE_NUMS; i++) {
        tag_route[i].n_rules = MAX_TAG_RULE_NUMS;
        tag_route[i].service_name = service_names[i];
        tag_route[i].rules = &p_tag_rule;
        p_tag_route[i] = &tag_route[i];
    }

    for (j = 0; j < MAX_TAG_RULE_NUMS; j++) {
        tag_rule[j].n_items = MAX_TAG_ITEM_NUMS;
        tag_rule[j].items = &p_tag_item;
        p_tag_rule[j] = &tag_rule[j];
    }

    for (k = 0; k < MAX_TAG_ITEM_NUMS; k++) {
        tag_item[k].has_location = 1;
        tag_item[k].has_match_type = 1;
        tag_item[k].location = INGRESS__LOCATION_TYPE__LocHttpHeader;
        tag_item[k].match_type = INGRESS__MATCH_TYPE__WholeMatch;
        tag_item[k].key = keys[k];
        tag_item[k].value = values[k];
        p_tag_item[k] = &tag_item[k];
    }
#endif

    if (n_tags) {
        ptags = ngx_shm_array_create(ingress->pool, n_tags, sizeof(ngx_ingress_tag_router_t));
        if (ptags == NULL) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|tag router array alloc failed|");
            return NGX_ERROR;
        }

        /* Traverse and process each Tag Route */
        for (i = 0; i < n_tags; i++) {

            /* Each tag route must clearly indicate the target service */
            if (pb_tag_routers[i]->service_name == NULL) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                                "|ingress|pb service name is null|");
                return NGX_ERROR;
            }

            /* Each tag route must have clear matching rules */
            if (pb_tag_routers[i]->n_rules == 0) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                                "|ingress|pb rules is empty|");
                return NGX_ERROR;
            }

            ngx_ingress_tag_router_t *shm_tag = ngx_shm_array_push(ptags);

            if (shm_tag == NULL) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                        "|ingress|tag router alloc failed|");
                return NGX_ERROR;
            }

            shm_tag->rules = ngx_shm_array_create(ingress->pool, pb_tag_routers[i]->n_rules, sizeof(ngx_ingress_tag_rule_t));

            if (shm_tag->rules == NULL) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                        "|ingress|tag rule array alloc failed|");
                return NGX_ERROR;
            }

            /* Traverse and process each Tag Rule */
            for (j = 0; j < pb_tag_routers[i]->n_rules; j++) {

                Ingress__TagRule ** pb_rules = pb_tag_routers[i]->rules;
                ngx_ingress_tag_rule_t *shm_rule = ngx_shm_array_push(shm_tag->rules);
                if (shm_rule == NULL) {
                    ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|tag rule alloc failed|");
                    return NGX_ERROR;
                }

                /* Each tag rule must have an explicit match */
                if (pb_rules[j]->n_items == 0) {
                    ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                                    "|ingress|pb rules is empty|");
                    return NGX_ERROR;
                }

                shm_rule->items = ngx_shm_array_create(ingress->pool, pb_rules[j]->n_items, sizeof(ngx_ingress_tag_item_t));
                if (shm_rule->items == NULL) {
                    ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|tag item array alloc failed|");
                    return NGX_ERROR;
                }

                /* Traverse and process each Tag Item */
                for (k = 0; k < pb_rules[j]->n_items; k++) {

                    Ingress__TagItem ** pb_items = pb_rules[j]->items;
                    ngx_ingress_tag_item_t *shm_item = ngx_shm_array_push(shm_rule->items);
                    if (shm_item == NULL) {
                        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                                "|ingress|tag item alloc failed|");
                        return NGX_ERROR;
                    }

                    if (pb_items[k]->has_location && pb_items[k]->has_match_type) {

                        shm_item->location = pb_items[k]->location;
                        shm_item->match_type = pb_items[k]->match_type;

                        key_len = strlen(pb_items[k]->key);
                        value_len = strlen(pb_items[k]->value);

                        shm_item->key.data = ngx_shm_pool_calloc(ingress->pool, key_len);
                        shm_item->value.data = ngx_shm_pool_calloc(ingress->pool, value_len);
                        if ((shm_item->key.data == NULL)
                            || (shm_item->value.data == NULL))
                        {
                            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                                            "|ingress|k-v alloc failed|");
                            return NGX_ERROR;
                        }

                        shm_item->key.len = key_len;
                        shm_item->value.len = value_len;

                        ngx_memcpy(shm_item->key.data, pb_items[k]->key, key_len);
                        ngx_memcpy(shm_item->value.data, pb_items[k]->value, value_len);

                    } else {
                        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                                "|ingress|miss loc type or match type|");
                        return NGX_ERROR;
                    }
                }
            }

            /* matched service */
            shm_tag->service = ngx_ingress_get_service(ingress, pb_tag_routers[i]->service_name);
            if (shm_tag->service == NULL) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                                "|ingress|service not exist|");
                return NGX_ERROR;
            }
        }

        *pptags = ptags;

    } else {
        *pptags = NULL;
    }

    return NGX_OK;
}

static ngx_int_t
ngx_ingress_update_shm_host(ngx_ingress_t *ingress,
    ngx_ingress_host_router_t *shm_host,
    Ingress__HostRouter *pbrouter,
    ngx_str_t *remove_prefix
    )
{
    size_t                  i;
    ngx_int_t               rc = NGX_ERROR;

    if (pbrouter->host == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                        "|ingress|pbhost is null|");
        return NGX_ERROR;
    }

    /* host */
    ngx_int_t len = ngx_strlen(pbrouter->host) - remove_prefix->len;
    shm_host->host.data = ngx_shm_pool_calloc(ingress->pool, len);
    if (shm_host->host.data == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                        "|ingress|host alloc failed|");
        return NGX_ERROR;
    }
    shm_host->host.len = len;
    ngx_strlow(shm_host->host.data, (u_char*)pbrouter->host + remove_prefix->len, len);

    ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                  "|ingress|add host|%V|%V|", &shm_host->host, remove_prefix);

    /* path */
    shm_host->paths = ngx_shm_array_create(ingress->pool, pbrouter->n_paths, sizeof(ngx_ingress_path_router_t));
    if (shm_host->paths == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                        "|ingress|path alloc failed|host=%V|", &shm_host->host);
        return NGX_ERROR;
    }

    Ingress__PathRouter **pbpath = pbrouter->paths;
    for (i = 0; i < pbrouter->n_paths; i++) {
        ngx_ingress_path_router_t *shm_path = ngx_shm_array_push(shm_host->paths);
        if (shm_path == NULL) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                        "|ingress|prefix router alloc failed|host=%V|", &shm_host->host);
            return NGX_ERROR;
        }

        if (pbpath[i]->prefix == NULL) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                        "|ingress|path prefix is null|host=%V|", &shm_host->host);
            return NGX_ERROR; 
        }

        len = ngx_strlen(pbpath[i]->prefix);
        shm_path->prefix.data = ngx_shm_pool_calloc(ingress->pool, len);
        if (shm_path->prefix.data == NULL) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                        "|ingress|prefix data alloc failed|host=%V|", &shm_host->host);
            return NGX_ERROR;
        }
        shm_path->prefix.len = len;
        ngx_strlow(shm_path->prefix.data, (u_char*)pbpath[i]->prefix, len);

        shm_path->service = ngx_ingress_get_service(ingress, pbpath[i]->service_name);
        if (shm_path->service == NULL) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                            "|ingress|service not exist|host=%V|prefix=%V|", &shm_host->host, &shm_path->prefix);
            return NGX_ERROR;
        }
        ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                      "|ingress|prefix service|host=%V|prefix=%V|%p|", &shm_host->host, &shm_path->prefix, shm_path->service);

        /* Subdivided PATH granularity, different tags match routes */
        rc = ngx_ingress_update_shm_tag_routers(ingress, pbpath[i]->n_tags, pbpath[i]->tags, &shm_path->tags);
        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                        "|ingress|update path tag routes failed|%V|%V|", &shm_host->host, &shm_path->prefix);
            return NGX_ERROR;
        }
    }

    ngx_shm_sort_array(shm_host->paths, ngx_path_prefix_compare);

    /* Under the host granularity, different tags match routes */
    rc = ngx_ingress_update_shm_tag_routers(ingress, pbrouter->n_tags, pbrouter->tags, &shm_host->tags);
    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                    "|ingress|update path tag routes failed|%V|", &shm_host->host);
        return NGX_ERROR;
    }

    /* service */
    if (pbrouter->service_name == NULL || ngx_strlen(pbrouter->service_name) == 0) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|host service is null|");
        return NGX_ERROR;
    }

    shm_host->service = ngx_ingress_get_service(ingress, pbrouter->service_name);
    if (shm_host->service == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                        "|ingress|service not exist|host=%V|", &shm_host->host);
        
        return NGX_ERROR;
    }

    return NGX_OK;
}

ngx_int_t
ngx_ingress_update_shm_by_pb(ngx_ingress_gateway_t *gateway, ngx_ingress_shared_memory_config_t *shm_pb_config, ngx_ingress_t *ingress)
{
    size_t                          i;
    ngx_int_t                       rc;

    ingress->service_map = ngx_shm_hash_create(ingress->pool, gateway->hash_size, ngx_ingress_service_hash, ngx_ingress_service_compare);
    if (ingress->service_map == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|service map create failed|gateway=%V|", &gateway->name);
        return NGX_ERROR;
    }

    Ingress__VirtualService **pbservice = shm_pb_config->pbconfig->services;
    /* service */
    for (i = 0; i < shm_pb_config->pbconfig->n_services; i++) {
        ngx_ingress_service_t *shm_service = ngx_shm_pool_calloc(ingress->pool, sizeof(ngx_ingress_service_t));
        if (shm_service == NULL) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                          "|ingress|alloc service failed|gateway=%V|", &gateway->name);
            return NGX_ERROR;
        }

        rc = ngx_ingress_update_shm_service(ingress, shm_service, pbservice[i]);
        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                          "|ingress|update service failed|gateway=%V|", &gateway->name);
            return NGX_ERROR;
        }

        rc = ngx_shm_hash_add(ingress->service_map, shm_service);
        if (rc != NGX_OK) {
            ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                          "|ingress|service ngx_shm_hash_add failed|service=%V|", &shm_service->name);
            return NGX_ERROR;
        }
    }

    /* router */
    ingress->host_map = ngx_shm_hash_create(ingress->pool, gateway->hash_size, ngx_ingress_host_hash, ngx_ingress_host_compare);
    if (ingress->host_map == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|host map create failed|gateway=%V|", &gateway->name);
        return NGX_ERROR;
    }
    ingress->wildcard_host_map = ngx_shm_hash_create(ingress->pool, gateway->hash_size, ngx_ingress_host_hash, ngx_ingress_host_compare);
    if (ingress->wildcard_host_map == NULL) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "|ingress|wildcard_host_map create failed|gateway=%V|", &gateway->name);
        return NGX_ERROR;
    }

    Ingress__Router **pbrouter = shm_pb_config->pbconfig->routers;

    for (i = 0; i < shm_pb_config->pbconfig->n_routers; i++) {
        if (pbrouter[i]->host_router != NULL) {
            Ingress__HostRouter *pb_host_router = pbrouter[i]->host_router;

            ngx_str_t wildcard_prefix = ngx_string("*.");
            ngx_str_t remove_prefix = ngx_null_string;

            ngx_ingress_host_router_t *shm_host = ngx_shm_pool_calloc(ingress->pool, sizeof(ngx_ingress_host_router_t));
            if (shm_host == NULL) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                              "|ingress|host router alloc failed|gateway=%V|", &gateway->name);
                return NGX_ERROR;
            }

            ngx_shm_hash_t *host_map = ingress->host_map;
            if (pb_host_router->host != NULL
                && ngx_strncmp(pb_host_router->host, wildcard_prefix.data, wildcard_prefix.len) == 0)
            {
                ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                              "|ingress|match wildcard|host=%s|", pb_host_router->host);

                host_map = ingress->wildcard_host_map;
                remove_prefix = wildcard_prefix;
            }

            rc = ngx_ingress_update_shm_host(ingress, shm_host, pb_host_router, &remove_prefix);
            if (rc != NGX_OK) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                              "|ingress|update host router failed|gateway=%V|", &gateway->name);
                return NGX_ERROR;
            }

            rc = ngx_shm_hash_add(host_map, shm_host);
            if (rc != NGX_OK) {
                ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                              "|ingress|host ngx_shm_hash_add failed|host=%V", &shm_host->host);
                return NGX_ERROR;
            }

            ngx_log_error(NGX_LOG_DEBUG, ngx_cycle->log, 0,
                          "|ingress|host add succ|host=%V", &shm_host->host);
        }
    }

    return NGX_OK;
}
