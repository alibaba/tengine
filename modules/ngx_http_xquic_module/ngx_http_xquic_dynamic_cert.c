/*
 * xQUIC Integration for Dynamic Certificate Module
 *
 * 本文件为独立编译单元，提供 ngx_http_v3_cert_cb_dynamic 函数。
 * ngx_http_xquic.c 中的 ngx_http_v3_cert_cb 通过前向声明调用此函数。
 *
 * 当 dynamic_cert_enable on 且共享内存就绪时，
 * ngx_http_v3_cert_cb 优先调用此函数，走 C 模块双缓冲 rbtree 证书查找；
 * 若 SNI 未命中动态证书，直接读取 SSL_CTX 中的静态证书兜底返回，
 * 不再 fallback 到 ngx_http_v3_cert_cb_lua。
 *
 * 整个文件受 T_NGX_HAVE_DYNAMIC_CERT 宏保护：
 * 仅当 ngx_http_dynamic_cert_module 编译进来时，本文件的代码才生效。
 */

#include <ngx_config.h>   /* 引入 ngx_auto_config.h，使 T_NGX_HAVE_DYNAMIC_CERT 可见 */

#if (T_NGX_HAVE_DYNAMIC_CERT)

#include "ngx_http_dynamic_cert_module.h"

/* 前向声明：ngx_http_xquic.c 中定义 */
extern ngx_int_t ngx_http_find_virtual_server_inner(ngx_connection_t *c,
    ngx_http_virtual_names_t *virtual_names, ngx_str_t *host,
    ngx_http_request_t *r, ngx_http_core_srv_conf_t **cscfp);

/*
 * ngx_http_v3_cert_cb_dynamic_extract_from_ctx
 *
 * 从 SSL_CTX 中提取证书/私钥/链，通过 chain/cert/key 指针返回给 xQUIC 引擎。
 * 动态证书和静态证书兜底共用此函数。
 *
 * 返回值：XQC_OK 成功，XQC_ERROR 失败。
 */
static xqc_int_t
ngx_http_v3_cert_cb_dynamic_extract_from_ctx(SSL_CTX *ctx,
    void **chain, void **cert, void **key,
    const char *sni, const char *source, ngx_log_t *log)
{
    STACK_OF(X509)  *cert_chain;
    X509            *certificate;
    EVP_PKEY        *private_key;
    int              ssl_ret;

    ssl_ret = SSL_CTX_get0_chain_certs(ctx, &cert_chain);
    if (ssl_ret != 1) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "|dynamic_cert|xquic: SSL_CTX_get0_chain_certs failed|sni=%s|src=%s|err=%d|",
                      sni, source, ssl_ret);
        return XQC_ERROR;
    }

    certificate = SSL_CTX_get0_certificate(ctx);
    if (certificate == NULL) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "|dynamic_cert|xquic: no certificate|sni=%s|src=%s|",
                      sni, source);
        return XQC_ERROR;
    }

    private_key = SSL_CTX_get0_privatekey(ctx);
    if (private_key == NULL) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "|dynamic_cert|xquic: no private key|sni=%s|src=%s|",
                      sni, source);
        return XQC_ERROR;
    }

    *chain = cert_chain;
    *cert  = certificate;
    *key   = private_key;

    return XQC_OK;
}

/*
 * ngx_http_v3_cert_cb_dynamic:
 *
 * 在 xQUIC 握手阶段为 C 模块动态证书路径提供证书。
 *
 * 证书选取顺序：
 *   1. 动态证书：通过 ngx_http_dynamic_cert_lookup_ssl_ctx 按 SNI 查找，
 *      命中后从返回的 SSL_CTX 中提取证书/私钥/链，通过指针返回给 xQUIC 引擎。
 *      不使用 SSL_set_SSL_CTX()，避免破坏 QUIC SSL 对象的 quic_method。
 *   2. 静态证书兜底：动态证书未命中时，直接从当前 server block 的 SSL_CTX 中
 *      读取静态证书，通过 chain/cert/key 指针返回给 xQUIC 引擎。
 *
 * 返回值：
 *   XQC_OK    - 证书已就绪（通过 chain/cert/key 指针返回）
 *   XQC_ERROR - 发生错误
 */
xqc_int_t
ngx_http_v3_cert_cb_dynamic(const char *sni, void **chain,
                             void **cert, void **key, void *conn_user_data)
{
    ngx_int_t                          ret;
    ngx_http_xquic_connection_t       *qc;
    ngx_connection_t                  *c;
    ngx_http_connection_t             *hc;
    ngx_http_core_srv_conf_t          *cscf;
    ngx_http_ssl_srv_conf_t           *sscf;
    ngx_str_t                          host;
    void                              *data;
    SSL_CTX                           *dynamic_ctx;

    qc = (ngx_http_xquic_connection_t *) conn_user_data;
    hc = qc->http_connection;
    c  = qc->connection;

    /*
     * 无 SNI 客户端处理：
     *
     * xquic 库中 xqc_ssl_cert_cb 会检查 SSL_get_servername 的返回值：
     *   - 返回 NULL（ClientHello 无 SNI 扩展）→ 直接返回 XQC_SSL_FAIL，cert_cb 不被调用
     *   - 返回 ""（ClientHello 有 SNI 扩展但值为空字符串）→ 通过 NULL 检查，cert_cb 被调用
     *
     * 因此本函数收到的 sni 可能是 ""（空字符串），此时走端口回退逻辑：
     *   - 尝试用监听端口号作为域名查找证书
     *   - 如果端口回退也失败，返回 NULL，走静态证书兜底
     */
    if (sni != NULL && *sni != '\0') {
        host.data = (u_char *) sni;
        host.len  = ngx_strlen(sni);
    } else {
        /* 无 SNI：不设置 host，后续虚拟主机查找会使用默认配置 */
        host.data = NULL;
        host.len  = 0;

        ngx_log_error(NGX_LOG_INFO, c->log, 0,
                      "|dynamic_cert|xquic: SNI is empty, will try port fallback|");
    }

    /* 根据 SNI 确定虚拟主机配置（仅当有 SNI 时） */
    if (host.data != NULL && host.len > 0) {
        data    = c->data;
        c->data = hc;
        ret = ngx_http_find_virtual_server_inner(c, hc->addr_conf->virtual_names,
                                                 &host, NULL, &cscf);
        c->data = data;

        if (ret == NGX_OK) {
            hc->ssl_servername = ngx_palloc(c->pool, sizeof(ngx_str_t));
            if (hc->ssl_servername == NULL) {
                ngx_log_error(NGX_LOG_ERR, c->log, 0,
                              "|dynamic_cert|xquic: failed to alloc ssl_servername|sni=%s|", sni);
                return XQC_ERROR;
            }
            *hc->ssl_servername = host;
            hc->conf_ctx = cscf->ctx;
        } else {
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                           "xquic dynamic cert: can't find virtual server for \"%s\","
                           " use default", sni);
        }
    }

    /*
     * 尝试动态证书：QUIC 专用查找（不调用 SSL_set_SSL_CTX）。
     *
     * 与 TLS 路径的区别：
     *   TLS 路径使用 ngx_http_dynamic_cert_handler → SSL_set_SSL_CTX() 切换。
     *   QUIC 路径使用 ngx_http_dynamic_cert_lookup_ssl_ctx → 返回 SSL_CTX *，
     *   由本函数从中提取证书/私钥/链，通过指针返回给 xQUIC 引擎。
     *
     * 原因：SSL_set_SSL_CTX() 在 BabaSSL/OpenSSL 中会修改 SSL 对象的 method 指针，
     * 将 QUIC method 切换回 TLS method，导致后续 SSL_do_handshake 走
     * ssl3_do_write 报错 "called a function you should not call"。
     *
     * 注意：不依赖 qc->ssl_conn（cert_cb 阶段尚未赋值，永远为 NULL）。
     * SNI 由 xquic 参数传入，base_ctx 从 sscf->ssl.ctx 获取。
     */
    sscf = ngx_http_get_module_srv_conf(hc->conf_ctx, ngx_http_ssl_module);
    if (sscf == NULL || sscf->ssl.ctx == NULL) {
        ngx_log_error(NGX_LOG_ERR, c->log, 0,
                      "|dynamic_cert|xquic: SSL_CTX not found|sni=%s|", sni);
        return XQC_ERROR;
    }

    dynamic_ctx = ngx_http_dynamic_cert_lookup_ssl_ctx(sni, sscf->ssl.ctx,
                                                       c, c->log);

    if (dynamic_ctx != NULL) {
        /* 动态证书命中：从 SSL_CTX 提取证书/私钥/链返回给 xQUIC */
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "xquic dynamic cert: C module found cert for \"%s\"", sni);

        return ngx_http_v3_cert_cb_dynamic_extract_from_ctx(
            dynamic_ctx, chain, cert, key, sni, "dynamic", c->log);
    }

    /*
     * 动态证书未命中：从 SSL_CTX 读取静态证书兜底。
     * sscf 已在上方获取并校验过，直接复用。
     * 不 fallback 到 ngx_http_v3_cert_cb_lua，避免在 C 模块路径下触发 Lua 逻辑。
     */
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "xquic dynamic cert: no dynamic cert for \"%s\", fallback to static", sni);

    return ngx_http_v3_cert_cb_dynamic_extract_from_ctx(
        sscf->ssl.ctx, chain, cert, key, sni, "static", c->log);
}

#endif /* T_NGX_HAVE_DYNAMIC_CERT */
