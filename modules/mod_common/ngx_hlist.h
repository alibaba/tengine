/**
 * Copied from include/linux/list.h
 **/

#ifndef _NGX_HLIST_H_
#define _NGX_HLIST_H_


#include <stdio.h>


/*
 * Double linked lists with a single pointer list head.
 * Mostly useful for hash tables where the two pointer list head is
 * too wasteful.
 * You lose the ability to access the tail in O(1).
 */

struct hlist_node {
    struct hlist_node  *next;
    struct hlist_node **pprev;
};

struct hlist_head {
    struct hlist_node  *first;
};


#define HLIST_HEAD_INIT { .first = NULL }
#define HLIST_HEAD(name) struct hlist_head name = { .first = NULL }
#define INIT_HLIST_HEAD(ptr) ((ptr)->first = NULL)


static inline void
INIT_HLIST_NODE(struct hlist_node *h)
{
    h->next = NULL;
    h->pprev = NULL;
}


static inline int
hlist_unhashed(const struct hlist_node *h)
{
    return !h->pprev;
}


static inline int
hlist_empty(const struct hlist_head *h)
{
    return !h->first;
}


static inline void
__hlist_del(struct hlist_node *n)
{
    struct hlist_node *next = n->next;
    struct hlist_node **pprev = n->pprev;

    *pprev = next;
    if (next) {
        next->pprev = pprev;
    }
}


static inline void
hlist_del(struct hlist_node *n)
{
    __hlist_del(n);
    n->next = NULL;
    n->pprev = NULL;
}


static inline void
hlist_del_init(struct hlist_node *n)
{
    if (!hlist_unhashed(n)) {
        __hlist_del(n);
        INIT_HLIST_NODE(n);
    }
}


static inline void
hlist_add_head(struct hlist_node *n, struct hlist_head *h)
{
    struct hlist_node *first = h->first;
    n->next = first;
    if (first) {
        first->pprev = &n->next;
    }
    h->first = n;
    n->pprev = &h->first;
}


/* next must be != NULL */
static inline void
hlist_add_before(struct hlist_node *n, struct hlist_node *next)
{
    n->pprev = next->pprev;
    n->next = next;
    next->pprev = &n->next;
    *(n->pprev) = n;
}


static inline void
hlist_add_after(struct hlist_node *n, struct hlist_node *next)
{
    next->next = n->next;
    n->next = next;
    next->pprev = &n->next;

    if(next->next) {
        next->next->pprev  = &next->next;
    }
}


/*
 * Move a list from one list head to another. Fixup the pprev
 * reference of the first entry if it exists.
 */
static inline void
hlist_move_list(struct hlist_head *old, struct hlist_head *nnew)
{
    nnew->first = old->first;
    if (nnew->first) {
        nnew->first->pprev = &nnew->first;
    }
    old->first = NULL;
}


#define container_of(ptr, type, member) ({ \
     const typeof( ((type *) 0)->member ) *__mptr = (ptr); \
     (type *) ( (char *) __mptr - offsetof(type, member) ); })

#define hlist_entry(ptr, type, member) container_of(ptr, type, member)

#define hlist_for_each(pos, head) \
    for (pos = (head)->first; pos; pos = pos->next)


#endif
