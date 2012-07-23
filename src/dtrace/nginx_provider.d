typedef struct { int dummy; } ngx_http_request_t;
typedef struct { int dummy; } ngx_str_t;
typedef int64_t ngx_int_t;


provider nginx {
    /* probes for subrequests */
    probe http__subrequest__cycle(ngx_http_request_t *pr, ngx_str_t *uri, ngx_str_t *args);
    probe http__subrequest__start(ngx_http_request_t *r);
    probe http__subrequest__finalize_writing(ngx_http_request_t *r);
    probe http__subrequest__finalize_nonactive(ngx_http_request_t *r);
    probe http__subrequest__wake__parent(ngx_http_request_t *r);
    probe http__subrequest__done(ngx_http_request_t *r);
    probe http__subrequest__post__start(ngx_http_request_t *r, ngx_int_t rc);
    probe http__subrequest__post__done(ngx_http_request_t *r, ngx_int_t rc);
};

