#ifndef _NGX_TEST_H_INCLUDE_
#define _NGX_TEST_H_INCLUDE_

#ifdef NGX_UNIT_TEST

#include <ngx_core.h>
#include <ngx_config.h>


#define NGX_TEST_FUNC_NAME(c, f)    ngx_testf_##c##_##f

#define NGX_TEST(c, f)                                                        \
    void NGX_TEST_FUNC_NAME(c, f) ();                                         \
    __attribute__((constructor(102))) void ngx_testd_##c##_##f() {            \
        if (ngx_regist_test(#c, #f, NGX_TEST_FUNC_NAME(c, f)) != NGX_OK) {    \
            exit(0);                                                          \
        }                                                                     \
    }                                                                         \
    void NGX_TEST_FUNC_NAME(c, f) ()

#define NGX_TEST_FAIL(fmt, args...)                                           \
    ngx_log_stderr(0, " ERROR at %s:%d TEST_FAIL: " fmt,                      \
            __FILE__, __LINE__, ## args);                                     \
    ngx_test_res = NGX_ERROR;


#define NGX_EXPECT_EQ(a, b)                                                   \
    if (!((a) == (b))) {                                                      \
        ngx_log_stderr(0, " ERROR at %s:%d, NGX_EXPECT_EQ("#a","#b")(a=%d,b=%d)",\
               __FILE__, __LINE__, (ngx_int_t) (a), (ngx_int_t) (b));         \
        ngx_test_res = NGX_ERROR;                                             \
    }


#define NGX_EXPECT_NE(a, b)                                                   \
    if ((a) == (b)) {                                                         \
        ngx_log_stderr(0, " ERROR at %s:%d, NGX_EXPECT_NE("#a","#b")(a=%d,b=%d)", \
                __FILE__, __LINE__, (ngx_int_t) (a), (ngx_int_t) (b));        \
        ngx_test_res = NGX_ERROR;                                             \
    }


#define NGX_EXPECT_STR_EQ(a, b)                                               \
    if ((a)->len != (b)->len                                                  \
        || ngx_strncmp((a)->data, (b)->data, (a)->len) != 0)                  \
    {                                                                         \
        ngx_log_stderr(0, " ERROR at %s:%d, NGX_EXPECT_STR_EQ("#a","#b")(a=%V,b=%V)",\
                       __FILE__, __LINE__, (a), (b));                         \
        ngx_test_res = NGX_ERROR;                                             \
    }


#define NGX_EXPECT_STR_NE(a, b)                                               \
    if ((a)->len == (b)->len                                                  \
        && ngx_strncmp((a)->data, (b)->data, (a)->len) == 0)                  \
    {                                                                         \
        ngx_log_stderr(0, " ERROR at %s:%d, NGX_EXPECT_STR_NE("#a","#b")(a=%V,b=%V)",\
                       __FILE__, __LINE__, (a), (b));                         \
        ngx_test_res = NGX_ERROR;                                             \
    }


#define NGX_EXPECT_NULL(a)                                                    \
    if ((a) != NULL) {                                                        \
        ngx_log_stderr(0, " ERROR at %s:%d, NGX_EXPECT_NULL_PTR("#a")(a=%p)", \
                       __FILE__, __LINE__, (a));                              \
        ngx_test_res = NGX_ERROR;                                             \
    }

#define NGX_EXPECT_NOT_NULL(a)                                                \
    if ((a) == NULL) {                                                        \
        ngx_log_stderr(0, " ERROR at %s:%d, NGX_EXPECT_NOT_NULL("#a")(a=%p)", \
                       __FILE__, __LINE__, (a));                              \
        ngx_test_res = NGX_ERROR;                                             \
    }


extern ngx_int_t ngx_test_res;
typedef struct ngx_test_s ngx_test_t;
typedef struct ngx_test_case_s ngx_test_case_t;
typedef void (*ngx_test_handler_pt)();


struct ngx_test_case_s {
    ngx_int_t               failes;
    ngx_str_node_t          sn;
    ngx_array_t            *tests;
};


struct ngx_test_s {
    ngx_str_t               name;
    ngx_int_t               rc;
    ngx_test_handler_pt     handler;
};

#define NGX_TEST_RED    1
#define NGX_TEST_GREEN  2
#define NGX_TEST_YELLOW 3


#if (NGX_HAVE_VARIADIC_MACROS)

void ngx_test_log_color(ngx_int_t color, const char *fmt, ...);

#else

void ngx_test_log_color(ngx_int_t color, const char *fmt, va_list args);

#endif


ngx_int_t ngx_regist_test(const char *c, const char *f, ngx_test_handler_pt h);
ngx_int_t ngx_test_run_cases();

#endif /* NGX_UNIT_TEST */

#endif /* _NGX_TEST_H_INCLUDE_ */
