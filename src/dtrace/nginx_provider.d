typedef struct { int dummy; } ngx_http_request_t;
typedef struct { int dummy; } ngx_str_t;


provider nginx {
    probe http__subrequest__cycle(ngx_http_request_t *pr, ngx_str_t *uri, ngx_str_t *args);
    probe http__subrequest__start(ngx_http_request_t *r);
};

