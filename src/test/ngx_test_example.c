
#include <ngx_core.h>
#include <ngx_test.h>


NGX_TEST(num, eq) {
    NGX_EXPECT_EQ(1, 1);
}


NGX_TEST(num, ne) {
    NGX_EXPECT_NE(1, 2);
}


NGX_TEST(str, eq) {
    ngx_str_t s1, s2;
    ngx_str_set(&s1, "a");
    ngx_str_set(&s2, "a");
    NGX_EXPECT_STR_EQ(&s1, &s2);
}


NGX_TEST(str, ne) {
    ngx_str_t s1, s2;

    ngx_str_set(&s1, "a");
    ngx_str_set(&s2, "b");
    NGX_EXPECT_STR_NE(&s1, &s2);
}

NGX_TEST(ptr, nil) {
    NGX_EXPECT_NULL(NULL);
}


NGX_TEST(ptr, notnil) {
    char *p = "a";
    NGX_EXPECT_NOT_NULL(p);
}


//#NGX_TEST(num, feq) {
//#    NGX_EXPECT_EQ(1, 2);
//#}
//#
//#NGX_TEST(num, fne) {
//#    NGX_EXPECT_NE(1, 1);
//#}
//#
//#
//#NGX_TEST(str, feq) {
//#    ngx_str_t s1, s2;
//#    ngx_str_set(&s1, "a");
//#    ngx_str_set(&s2, "ab");
//#    NGX_EXPECT_STR_EQ(&s1, &s2);
//#}
//#
//#
//#NGX_TEST(str, fne) {
//#    ngx_str_t s1, s2;
//#
//#    ngx_str_set(&s1, "a");
//#    ngx_str_set(&s2, "a");
//#    NGX_EXPECT_STR_NE(&s1, &s2);
//#}
