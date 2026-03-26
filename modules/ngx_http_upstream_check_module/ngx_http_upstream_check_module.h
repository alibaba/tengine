#define NGX_HAVE_HTTP_UPSTREAM_CHECK

#if (NGX_HTTP_UPSTREAM_CHECK)
ngx_uint_t ngx_http_upstream_check_peer_down(ngx_uint_t index);
void ngx_http_upstream_check_delete_dynamic_peer(ngx_str_t *name,
    ngx_addr_t *peer_addr);
#endif
