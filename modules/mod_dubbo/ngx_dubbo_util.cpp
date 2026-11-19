
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
    } catch (io_exception &e) {
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
    } catch (io_exception &e) {
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
    } catch (io_exception &e) {
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

        /*
         * read_object() returns the decoded object with its real dynamic
         * type.  Casting it straight to Map* -- as this code used to do --
         * is a type confusion: for any non-map payload (Boolean, String,
         * Integer, ...) Map::size() reads the std::map member out of a much
         * smaller allocation, which is an out-of-bounds read and, on an
         * ordinary build, a SIGSEGV in the worker.  Validate the type with
         * instance_of<Map>() before casting; it also returns false for a
         * NULL pointer, so the explicit NULL test is no longer needed.
         */
        if (!instance_of<Map>(ret.first)) {
            ngx_log_error(NGX_LOG_ERR, log, 0,
                          "dubbo: parse result map failed, unexpected object "
                          "type %ui, %V",
                          ret.first ? (ngx_uint_t) ret.first->type_id() : 0,
                          in);

            if (ret.second && ret.first != NULL) {
                delete ret.first;
            }

            return NGX_ERROR;
        }

        Map* pmap = (Map*)(ret.first);

        Safeguard<Map> safeguard(pmap);

        pres = ngx_array_create(pool, pmap->size(), sizeof(ngx_keyval_t));
        if (pres == NULL) {
            return NGX_ERROR;
        }
        *result = pres;

        Map::data_type& dmap = (Map::data_type&)pmap->data();

        for (Map::data_type::iterator it = dmap.begin(); it != dmap.end(); it++) {
            /*
             * Keys and values come from the same unchecked decoder, so they
             * carry their real dynamic type as well.  A backend (or an
             * attacker who controls it) can put an Integer key or a List
             * value into the map; casting those to String or ByteArray and
             * calling to_string() on them is the same type confusion as
             * above.  Check with instance_of<>() and skip entries whose key
             * is not a string, rather than pushing an uninitialized
             * ngx_keyval_t into the result.
             */
            if (!instance_of<String>(it->first)) {
                ngx_log_error(NGX_LOG_WARN, log, 0,
                              "dubbo: skipping map entry with non-string key "
                              "type %ui",
                              it->first ? (ngx_uint_t) it->first->type_id() : 0);
                continue;
            }

            String *sKey = (String*)it->first;
            Object *oValue = NULL;
            ByteArray *bValue = NULL;

            kv = (ngx_keyval_t*)ngx_array_push(pres);
            if (kv == NULL) {
                return NGX_ERROR;
            }
            ngx_memzero(kv, sizeof(ngx_keyval_t));

            string p = sKey->to_string();
            kv->key.data = (u_char*)ngx_palloc(pool, p.length());
            if (kv->key.data == NULL) {
                return NGX_ERROR;
            }
            ngx_memcpy(kv->key.data, p.c_str(), p.length());
            kv->key.len = p.length();

            if (0 == p.compare("body")) {
                /*
                 * "body" is expected to be a ByteArray.  If it is not, fall
                 * back to the generic Object path so that a well-typed but
                 * unexpected value still decodes via Object::to_string()
                 * instead of being cast blindly.
                 */
                if (instance_of<ByteArray>(it->second)) {
                    bValue = (ByteArray*)it->second;
                } else {
                    oValue = it->second;
                }
            } else {
                oValue = it->second;
            }

            if (oValue) {
                string p = oValue->to_string();
                kv->value.data = (u_char*)ngx_palloc(pool, p.length());
                if (kv->value.data == NULL) {
                    return NGX_ERROR;
                }
                ngx_memcpy(kv->value.data, p.c_str(), p.length());
                kv->value.len = p.length();
            }

            if (bValue) {
                string p = bValue->to_string();
                kv->value.data = (u_char*)ngx_palloc(pool, p.length());
                if (kv->value.data == NULL) {
                    return NGX_ERROR;
                }
                ngx_memcpy(kv->value.data, p.c_str(), p.length());
                kv->value.len = p.length();
            }
        }

        return NGX_OK;
    } catch (io_exception &e) {
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
