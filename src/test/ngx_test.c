#include <ngx_core.h>
#include <ngx_test.h>
#include <ngx_config.h>


#ifdef NGX_UNIT_TEST

static ngx_int_t ngx_test_run_case(ngx_rbtree_t *tree,
    ngx_rbtree_node_t *node);
static ngx_int_t ngx_test_count_case(ngx_rbtree_t *tree,
    ngx_rbtree_node_t *node);
static ngx_int_t ngx_test_count_test(ngx_rbtree_t *tree,
    ngx_rbtree_node_t *node);
static void ngx_test_log_fail_case(ngx_rbtree_t *tree,
    ngx_rbtree_node_t *node);

ngx_int_t   ngx_test_res;

static ngx_log_t         ngx_test_log;
static ngx_pool_t       *ngx_test_temp_pool;
static ngx_open_file_t   ngx_test_log_file;


static ngx_rbtree_t      ngx_test_cases;
static ngx_rbtree_node_t ngx_test_rbtree_sentinel;


__attribute__((constructor(101))) void ngx_test_init() {

    ngx_memzero(&ngx_test_log, sizeof(ngx_log_t));
    ngx_memzero(&ngx_test_log_file, sizeof(ngx_open_file_t));

    ngx_test_log.file = &ngx_test_log_file;
    ngx_test_log_file.fd = ngx_stderr;

    ngx_test_temp_pool = ngx_create_pool(4096, &ngx_test_log);
    if (ngx_test_temp_pool == NULL) {
        exit(1);
    }

    ngx_rbtree_init(&ngx_test_cases, &ngx_test_rbtree_sentinel,
                    ngx_str_rbtree_insert_value);
}


__attribute__((destructor)) void ngx_test_finalizer() {
    if (ngx_test_temp_pool != NULL) {
        ngx_destroy_pool(ngx_test_temp_pool);
    }
}


ngx_int_t
ngx_regist_test(const char *c, const char *f, ngx_test_handler_pt h) {
    uint32_t             hash;
    ngx_str_t            s;
    ngx_test_t          *t;
    ngx_str_node_t      *node;
    ngx_test_case_t     *ca;

    s.len = (size_t) ngx_strlen(c);
    s.data = (u_char *) c;

    hash = ngx_crc32_long(s.data, s.len);

    node = ngx_str_rbtree_lookup(&ngx_test_cases, &s, hash);
    if (node == NULL) {
        ca = ngx_pcalloc(ngx_test_temp_pool, sizeof(ngx_test_case_t));
        if (ca == NULL) {
            return NGX_ERROR;
        }

        ca->sn.str = s;
        ca->sn.node.key = hash;
        ngx_rbtree_insert(&ngx_test_cases, &ca->sn.node);
    } else {
        ca = (ngx_test_case_t *) ((u_char *) node
                                  - offsetof(ngx_test_case_t, sn));
    }

    if (ca->tests == NULL) {
        ca->tests = ngx_array_create(ngx_test_temp_pool, 4, sizeof(ngx_test_t));
        if (ca->tests == NULL) {
            return NGX_ERROR;
        }
    }

    t = ngx_array_push(ca->tests);
    if (t == NULL) {
        return NGX_ERROR;
    }

    t->handler = h;
    t->name.data = (u_char *) f;
    t->name.len = (size_t) ngx_strlen(f);
    t->rc = NGX_OK;

    return NGX_OK;
}


ngx_int_t
ngx_test_run_cases()
{
    ngx_int_t       failes, cases, tests;
    ngx_uint_t      st, en;
    struct timeval  tv;

    failes = 0;
    ngx_test_log_color(NGX_TEST_GREEN, "[==========]");

    cases = ngx_test_count_case(&ngx_test_cases, ngx_test_cases.root);
    tests = ngx_test_count_test(&ngx_test_cases, ngx_test_cases.root);
    
    ngx_test_log_color(NGX_TEST_GREEN, " Running %d tests from %d cases\n",
                       tests, cases);

    ngx_gettimeofday(&tv);
    st = tv.tv_sec * 1000 + tv.tv_usec / 1000;

    failes = ngx_test_run_case(&ngx_test_cases, ngx_test_cases.root);

    ngx_gettimeofday(&tv);
    en = tv.tv_sec * 1000 + tv.tv_usec / 1000;

    ngx_test_log_color(NGX_TEST_GREEN,
                      "[==========] %d tests ran. (%ud ms total)\n",
                      tests, en - st);

    ngx_test_log_color(NGX_TEST_GREEN, "[  PASSED  ] %d tests.\n",
                       tests - failes);

    if (failes != 0) {
        ngx_test_log_color(NGX_TEST_RED,
                           "[  FAILED  ] %d tests, listed below:\n",
                           failes);

        ngx_test_log_fail_case(&ngx_test_cases, ngx_test_cases.root);
    }
    return NGX_OK;
}


#if (NGX_HAVE_VARIADIC_MACROS)

void
ngx_test_log_color(ngx_int_t color, const char *fmt, ...)

#else

void
ngx_test_log_color(ngx_int_t color, const char *fmt, va_list args)

#endif
{
#if (NGX_HAVE_VARIADIC_MACROS)
    va_list     args;
#endif
    u_char     *p, *last, *end;
    size_t      len;
    u_char      str[NGX_MAX_ERROR_STR];

    end = str + NGX_MAX_ERROR_STR;

#if (NGX_HAVE_VARIADIC_MACROS)
    va_start(args, fmt);
#endif

    len = sizeof("\033[0;3m\033[m") + ngx_strlen(fmt);
    p = ngx_alloc(len + 1, &ngx_test_log);
    if (p == NULL) {
        return;
    }

    ngx_snprintf(p, len, "\033[0;3%dm%s\033[m", color, fmt);
    *(p + len) = '\0';

    last = ngx_vslprintf(str, end, (const char *) p, args);
    (void) ngx_write_console(ngx_stderr, str, last - str);

#if (NGX_HAVE_VARIADIC_MACROS)
    va_end(args);
#endif

}


static ngx_int_t
ngx_test_run_case(ngx_rbtree_t *tree, ngx_rbtree_node_t *node)
{
    ngx_int_t        failes;
    ngx_uint_t       st, en, i, total;
    ngx_test_t      *t;
    struct timeval   tv;
    ngx_test_case_t *c;

    if (node == tree->sentinel) {
        return 0;
    }

    failes = 0;

    c = (ngx_test_case_t *) ((u_char *) node - offsetof(ngx_test_case_t, sn));
    if (c->tests == NULL) {
        goto next;
    }

    t = c->tests->elts;

    ngx_test_log_color(NGX_TEST_GREEN, " Running %ud tests from %V\n",
                       c->tests->nelts, &c->sn.str);

    for (i = 0; i < c->tests->nelts; i++, t++) {
        if (t->handler == NULL) {
            continue;
        }

        ngx_test_res = NGX_OK;

        ngx_test_log_color(NGX_TEST_GREEN, "[ RUN      ] %V.%V",
                           &c->sn.str, &t->name);

        ngx_gettimeofday(&tv);

        st = tv.tv_sec * 1000 + tv.tv_usec / 1000;
        t->handler();

        ngx_gettimeofday(&tv);

        en = tv.tv_sec * 1000 + tv.tv_usec / 1000;

        if (ngx_test_res != NGX_OK) {
            t->rc = NGX_ERROR;
            failes++;
            ngx_test_log_color(NGX_TEST_RED, " [  FAILED  ]");

        } else {
            ngx_test_log_color(NGX_TEST_GREEN, " [       OK ]");
        }

        ngx_test_log_color(NGX_TEST_YELLOW, " %V.%V (%ud ms)\n",
                           &c->sn.str, &t->name, en - st);
        total += (en - st);
    }

    ngx_test_log_color(NGX_TEST_GREEN, "[----------] %ud tests from %V\n\n",
                       c->tests->nelts, &c->sn.str);

next:

    if (node->left != tree->sentinel) {
        failes += ngx_test_run_case(tree, node->left);
    }

    if (node->right != tree->sentinel) {
        failes += ngx_test_run_case(tree, node->right);
    }

    return failes;
}


static ngx_int_t
ngx_test_count_case(ngx_rbtree_t *tree, ngx_rbtree_node_t *node)
{
    ngx_int_t cases;

    if (node == tree->sentinel) {
        return 0;
    }

    cases = 1;
    if (node->left != tree->sentinel) {
        cases += ngx_test_count_case(tree, node->left);
    }

    if (node->right != tree->sentinel) {
        cases += ngx_test_count_case(tree, node->right);
    }

    return cases;
}


static ngx_int_t
ngx_test_count_test(ngx_rbtree_t *tree, ngx_rbtree_node_t *node)
{
    ngx_int_t        tests;
    ngx_test_case_t *c;

    if (node == tree->sentinel) {
        return 0;
    }

    c = (ngx_test_case_t *) ((u_char *) node - offsetof(ngx_test_case_t, sn));
    if (c->tests == NULL) {
        tests = 0;

    } else {
        tests = (ngx_int_t) c->tests->nelts;
    }

    if (node->left != tree->sentinel) {
        tests += ngx_test_count_test(tree, node->left);
    }

    if (node->right != tree->sentinel) {
        tests += ngx_test_count_test(tree, node->right);
    }

    return tests;
}


static void
ngx_test_log_fail_case(ngx_rbtree_t *tree, ngx_rbtree_node_t *node)
{
    ngx_uint_t       i;
    ngx_test_t      *t;
    ngx_test_case_t *c;

    if (node == tree->sentinel) {
        return;
    }

    c = (ngx_test_case_t *) ((u_char *) node - offsetof(ngx_test_case_t, sn));
    if (c->tests == NULL) {
        goto next;
    }

    t = c->tests->elts;
    for (i = 0; i < c->tests->nelts; i++, t++) {
        if (t->handler == NULL) {
            continue;
        }

        if (t->rc != NGX_OK) {
            ngx_test_log_color(NGX_TEST_RED, "[  FAILED  ] %V.%V\n",
                               &c->sn.str, &t->name);
        }
    }

next:

    if (node->left != tree->sentinel) {
        ngx_test_log_fail_case(tree, node->left);
    }

    if (node->right != tree->sentinel) {
        ngx_test_log_fail_case(tree, node->right);
    }
}

#endif /* NGX_UNIT_TEST */
