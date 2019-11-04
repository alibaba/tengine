
/*
 * Copyright (C) Mengqi Wu (Pull)
 * Copyright (C) 2017-2019 Alibaba Group Holding Limited
 */

#include <string>
#include <memory>
#include <objects.h>
#include <utils.h>
#include <hessian2_output.h>
#include <hessian2_input.h>

#ifdef __cplusplus
extern "C" {
#endif

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>

#include <ngx_dubbo.h>

using namespace std;
using namespace hessian;

ngx_int_t ngx_dubbo_hessian2_encode_str(ngx_pool_t *pool, ngx_str_t *in, ngx_str_t *out)
{
    try {
        string str;
        hessian2_output hout(&str);
        hout.write_utf8_string((const char*)in->data, in->len);

        out->data = (u_char*)ngx_palloc(pool, str.length());
        if (out->data == NULL) {
            return NGX_ERROR;
        }

        ngx_memcpy(out->data, str.c_str(), str.length());
        out->len = str.length();

        return NGX_OK;
    } catch (io_exception e) {
        ngx_log_error(NGX_LOG_ERR, pool->log, 0, "dubbo: parse exception failed %s", e.what());
        return NGX_ERROR;
    } catch (...) {
        return NGX_ERROR;
    }
}

ngx_int_t ngx_dubbo_hessian2_encode_map(ngx_pool_t *pool, ngx_array_t *in, ngx_str_t *out)
{
    try {
        string str;
        hessian2_output hout(&str);

        Map strMap;
        ngx_keyval_t *kv = (ngx_keyval_t*)in->elts;
        for (size_t i=0; i<in->nelts; i++) {
            string key((const char*)kv[i].key.data, kv[i].key.len);
            string value((const char*)kv[i].value.data, kv[i].value.len);
            ObjectValue key_obj(key);
            ObjectValue value_obj(value);
            strMap.put(key_obj, value_obj);
        }
        hout.write_object(&strMap);

        out->data = (u_char*)ngx_palloc(pool, str.length());
        if (out->data == NULL) {
            return NGX_ERROR;
        }

        ngx_memcpy(out->data, str.c_str(), str.length());
        out->len = str.length();

        return NGX_OK;
    } catch (io_exception e) {
        ngx_log_error(NGX_LOG_ERR, pool->log, 0, "dubbo: parse exception failed %s", e.what());
        return NGX_ERROR;
    } catch (...) {
        return NGX_ERROR;
    }
}

ngx_int_t ngx_dubbo_hessian2_encode_payload_map(ngx_pool_t *pool, ngx_array_t *in, ngx_str_t *out)
{
    try {
        string str;
        hessian2_output hout(&str);

        Map strMap;
        ngx_keyval_t *kv = (ngx_keyval_t*)in->elts;
        for (size_t i=0; i<in->nelts; i++) {
            string key((const char*)kv[i].key.data, kv[i].key.len);
            if (0 == (key.compare("body"))) {
                ByteArray *tmp = new ByteArray((const char*)kv[i].value.data, kv[i].value.len);
                ObjectValue key_obj(key);
                ObjectValue value_obj((Object*)tmp);
                strMap.put(key_obj, value_obj);
            } else {
                string value((const char*)kv[i].value.data, kv[i].value.len);
                ObjectValue key_obj(key);
                ObjectValue value_obj(value);
                strMap.put(key_obj, value_obj);

            }
        }
        hout.write_object(&strMap);

        out->data = (u_char*)ngx_palloc(pool, str.length());
        if (out->data == NULL) {
            return NGX_ERROR;
        }

        ngx_memcpy(out->data, str.c_str(), str.length());
        out->len = str.length();

        return NGX_OK;
    } catch (io_exception e) {
        ngx_log_error(NGX_LOG_ERR, pool->log, 0, "dubbo: parse exception failed %s", e.what());
        return NGX_ERROR;
    } catch (...) {
        return NGX_ERROR;
    }
}


ngx_int_t
ngx_dubbo_hessian2_decode_payload_map(ngx_pool_t *pool, ngx_str_t *in, ngx_array_t **result, ngx_log_t *log)
{
    ngx_array_t     *pres;
    ngx_keyval_t    *kv;

    try {
        hessian2_input hin((const char*)in->data, in->len);
        //int attachment = hin.read_int32();
        hin.read_int32(); //attachment


        std::pair<Object*, bool> ret = hin.read_object();

        Map* pmap = (Map*)(ret.first);

        if (pmap == NULL) {
            ngx_log_error(NGX_LOG_ERR, log, 0, "dubbo: parse result map failed %V", in);
            return NGX_ERROR;
        }

        Safeguard<Map> safeguard(pmap);

        pres = ngx_array_create(pool, pmap->size(), sizeof(ngx_keyval_t));
        if (pres == NULL) {
            return NGX_ERROR;
        }
        *result = pres;

        Map::data_type& dmap = (Map::data_type&)pmap->data();

        for (Map::data_type::iterator it = dmap.begin(); it != dmap.end(); it++) {
            String *sKey = (String*)it->first;
            String *sValue = NULL;
            ByteArray *bValue = NULL;

            kv = (ngx_keyval_t*)ngx_array_push(pres);
            if (kv == NULL) {
                return NGX_ERROR;
            }
            if (sKey) {
                string p = sKey->to_string();
                kv->key.data = (u_char*)ngx_palloc(pool, sKey->size());
                if (kv->key.data == NULL) {
                    return NGX_ERROR;
                }
                ngx_memcpy(kv->key.data, p.c_str(), p.length());
                kv->key.len = p.length();

                if (0 == p.compare("body")) {
                    bValue = (ByteArray*)it->second;
                } else {
                    sValue = (String*)it->second;
                }
            }

            if (sValue) {
                string p = sValue->to_string();
                kv->value.data = (u_char*)ngx_palloc(pool, sValue->size());
                if (kv->value.data == NULL) {
                    return NGX_ERROR;
                }
                ngx_memcpy(kv->value.data, p.c_str(), p.length());
                kv->value.len = p.length();
            }

            if (bValue) {
                string p = bValue->to_string();
                kv->value.data = (u_char*)ngx_palloc(pool, bValue->size());
                if (kv->value.data == NULL) {
                    return NGX_ERROR;
                }
                ngx_memcpy(kv->value.data, p.c_str(), p.length());
                kv->value.len = p.length();
            }
        }

        return NGX_OK;
    } catch (io_exception e) {
        ngx_log_error(NGX_LOG_ERR, log, 0, "dubbo: parse exception failed %s", e.what());
        return NGX_ERROR;
    } catch (...) {
        ngx_log_error(NGX_LOG_ERR, log, 0, "dubbo: parse result failed %V", in);
        return NGX_ERROR;
    }
}

//ngx_int_t ngx_dubbo_hessian2_encode_req_props(ngx_pool_t *pool, ngx_str_t *traceid, ngx_str_t *rpcid, ngx_str_t *userdata, ngx_str_t *out);

#ifdef __cplusplus
}
#endif
