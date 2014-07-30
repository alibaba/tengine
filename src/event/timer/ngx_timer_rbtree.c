

#include <ngx_event.h>

static ngx_thread_volatile ngx_rbtree_t  ngx_timer_rbtree;
static ngx_rbtree_node_t                 ngx_timer_rbtree_sentinel;

static inline ngx_int_t
ngx_timer_rbtree_tree_init(ngx_cycle_t *cycle)
{
    ngx_rbtree_init(&ngx_timer_rbtree, &ngx_timer_rbtree_sentinel, ngx_rbtree_insert_timer_value);
    return NGX_OK;
}

#define NGX_TREE_INIT               ngx_timer_rbtree_tree_init
#define NGX_TREE_DELETE(timer)      ngx_rbtree_delete(&ngx_timer_rbtree, (ngx_rbtree_node_t *)timer)
#define NGX_TREE_INSERT(timer)      ngx_rbtree_insert(&ngx_timer_rbtree, (ngx_rbtree_node_t *)timer)
#define NGX_TREE_MIN()              ngx_rbtree_min(ngx_timer_rbtree.root, ngx_timer_rbtree.sentinel)
#define NGX_TREE_EMPTY()           (ngx_timer_rbtree.root == &ngx_timer_rbtree_sentinel)

#define NGX_TIMER_TREE_PREFIX       ngx_timer_rbtree
#include <ngx_timer_tree_template.h>

ngx_timer_actions_t  ngx_timer_rbtree_actions = {
    ngx_string("rbtree"),

    NGX_TIMER_TREE_ADD,
    NGX_TIMER_TREE_DEL,
    NGX_TIMER_TREE_EMPTY,

    NGX_TIMER_TREE_FIND_MIN,
    NGX_TIMER_TREE_EXPIRE_TIMERS,

    NGX_TIMER_TREE_INIT,
};

