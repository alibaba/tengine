
/*
 * Copyright (C) 2010-2013 Alibaba Group Holding Limited
 */

#include <ngx_core.h>
#include <ngx_config.h>


void
ngx_ebtree_delete(ngx_ebtree_node_t *node)
{
    ngx_int_t          pside, gpside, sibyte;
    ngx_ebtree_node_t *parent, *gparent, *temp;

    if (!node->leaf) {
        return;
    }

    pside = ngx_eb_gettag(node->leaf);
    parent = ngx_eb_untag(node->leaf, pside);

    if (ngx_eb_clrtag(parent->branches[NGX_EB_RIGHT]) == NULL) {
        parent->branches[NGX_EB_RIGHT] = NULL;
        goto finish;
    }

    gpside = ngx_eb_gettag(parent->node);
    gparent = ngx_eb_untag(parent->node, gpside);

    gparent->branches[gpside] = pside == NGX_EB_LEFT
                                ? parent->branches[NGX_EB_RIGHT]
                                : parent->branches[NGX_EB_LEFT];

    sibyte = ngx_eb_gettag(gparent->branches[gpside]);

    temp = ngx_eb_untag(gparent->branches[gpside], sibyte);
    if (sibyte == NGX_EB_LEAF) {
        temp->leaf = ngx_eb_dotag(gparent, gpside);
    } else {
        temp->node = ngx_eb_dotag(gparent, gpside);
    }

    parent->node = NULL;

    if (!node->node) {
        goto finish;
    }

    parent->node = node->node;
    parent->branches[0] = node->branches[0];
    parent->branches[1] = node->branches[1];
    parent->bit = node->bit;

    gpside = ngx_eb_gettag(parent->node);
    gparent = ngx_eb_untag(parent->node, gpside);
    parent->branches[gpside] = ngx_eb_dotag(parent, NGX_EB_NODE);

    if (ngx_eb_gettag(parent->branches[NGX_EB_LEFT]) == NGX_EB_NODE) {
        temp = ngx_eb_untag(parent->branches[NGX_EB_LEFT], NGX_EB_NODE);
        temp->node = ngx_eb_dotag(parent, NGX_EB_LEFT);

    } else {
        temp = ngx_eb_untag(parent->branches[NGX_EB_LEFT], NGX_EB_LEAF);
        temp->leaf = ngx_eb_dotag(parent, NGX_EB_LEFT);
    }

    if (ngx_eb_gettag(parent->branches[NGX_EB_RIGHT]) == NGX_EB_NODE) {
        temp = ngx_eb_untag(parent->branches[NGX_EB_RIGHT], NGX_EB_NODE);
        temp->node = ngx_eb_dotag(parent, NGX_EB_RIGHT);

    } else {
        temp = ngx_eb_untag(parent->branches[NGX_EB_RIGHT], NGX_EB_LEAF);
        temp->leaf = ngx_eb_dotag(parent, NGX_EB_RIGHT);
    }

finish:
    node->leaf = NULL;
    return;
}


static ngx_ebtree_node_t *
ngx_ebtree_insert_dup(ngx_ebtree_node_t *sub, ngx_ebtree_node_t *node)
{
    ngx_int_t          side;
    ngx_ebtree_node_t *head, *last, *left, *right, *leaf;
    head = sub;
    left = ngx_eb_dotag(node, NGX_EB_LEFT);
    right = ngx_eb_dotag(node, NGX_EB_RIGHT);
    leaf = ngx_eb_dotag(node, NGX_EB_LEAF);

    while (ngx_eb_gettag(head->branches[NGX_EB_RIGHT]) != NGX_EB_LEAF) {
        last = head;
        head = ngx_eb_untag(head->branches[NGX_EB_RIGHT], NGX_EB_NODE);
        if (head->bit > last->bit + 1) {
            sub = head;
        }
    }

    if (head->bit < -1) {
        node->bit = -1;
        sub = ngx_eb_untag(head->branches[NGX_EB_RIGHT], NGX_EB_LEAF);
        head->branches[NGX_EB_RIGHT] = ngx_eb_dotag(node, NGX_EB_NODE);

        node->node = sub->leaf;
        node->leaf = right;
        sub->leaf = left;
        node->branches[NGX_EB_LEFT] = ngx_eb_dotag(sub, NGX_EB_LEAF);
        node->branches[NGX_EB_RIGHT] = leaf;

    } else {
        node->bit = sub->bit - 1;
        side = ngx_eb_gettag(sub->node);
        head = ngx_eb_untag(sub->node, side);
        head->branches[side] = ngx_eb_dotag(node, NGX_EB_NODE);

        node->node = sub->node;
        node->leaf = right;
        sub->node = left;
        node->branches[NGX_EB_LEFT] = ngx_eb_dotag(sub, NGX_EB_NODE);
        node->branches[NGX_EB_RIGHT] = leaf;

    }

    return node;
}


ngx_ebtree_node_t *
ngx_ebtree_insert(ngx_ebtree_t *tree, ngx_ebtree_node_t *node)
{
    char               bit;
    uint32_t           key;
    ngx_int_t          side;
    ngx_ebtree_node_t *root, *troot, **ptr, *old;
    ngx_ebtree_node_t *leaf, *left, *right;

    root = tree->root[NGX_EB_LEFT];
    side = NGX_EB_LEFT;
    troot = root->branches[NGX_EB_LEFT];

    if (troot == NULL) {
        root->branches[NGX_EB_LEFT] = ngx_eb_dotag(node, NGX_EB_LEAF);
        node->leaf = ngx_eb_dotag(root, NGX_EB_LEFT);
        node->node = NULL;
        return node;
    }

    key = node->key;

    while(1) {
        if (ngx_eb_gettag(troot) == NGX_EB_LEAF) {
            old = ngx_eb_untag(troot, NGX_EB_LEAF);
            node->node = old->leaf;
            ptr = &old->leaf;
            break;
        }

        old = ngx_eb_untag(troot, NGX_EB_NODE);
        bit = old->bit;

        if (bit < 0
            || (((node->key ^ old->key) >> bit) >= NGX_EB_NODE_BRANCHES))
        {
            node->node = old->node;
            ptr = &old->node;
            break;
        }

        root = old;
        side = (key >> bit) & NGX_EB_NODE_BRACH_MASK;
        troot = root->branches[side];
    }

    left = ngx_eb_dotag(node, NGX_EB_LEFT);
    right = ngx_eb_dotag(node, NGX_EB_RIGHT);
    leaf = ngx_eb_dotag(node, NGX_EB_LEAF);

    node->bit = ngx_ebtree_flsnz(node->key ^ old->key) - NGX_EB_NODE_BITS;

    if (node->key == old->key) {
        node->bit = -1;
        if (ngx_eb_gettag(troot) != NGX_EB_LEAF) {
            return ngx_ebtree_insert_dup(old, node);
        }
    }
    
    if (node->key >= old->key) {
        node->branches[NGX_EB_LEFT] = troot;
        node->branches[NGX_EB_RIGHT] = leaf;
        node->leaf = right;
        *ptr = left;

    } else {
        node->branches[NGX_EB_LEFT] = leaf;
        node->branches[NGX_EB_RIGHT] = troot;
        *ptr = right;
    }

    root->branches[side] = ngx_eb_dotag(node, NGX_EB_NODE);
    return node;
}


ngx_ebtree_node_t *
ngx_ebtree_lookup(ngx_ebtree_t *tree, uint32_t key)
{
    char               bit;
    uint32_t           t;
    ngx_ebtree_node_t *root, *node;

    root = tree->root[NGX_EB_LEFT]->branches[NGX_EB_LEFT];
    if (root == NULL) {
        return NULL;
    }

    while (1) {
        if (ngx_eb_gettag(root) == NGX_EB_LEAF) {
            node = ngx_eb_untag(root, NGX_EB_LEAF);
            if (node->key == key) {
                return node;
            } else {
                return NULL;
            }
        }

        node = ngx_eb_untag(root, NGX_EB_NODE);
        bit = node->bit;

        t = node->key ^ key;

        if (!t) {
            if (bit < 0) {
                root = node->branches[NGX_EB_LEFT];
                while (ngx_eb_gettag(root) != NGX_EB_LEAF) {
                    root = ngx_eb_untag(root, NGX_EB_NODE);
                    root = root->branches[NGX_EB_LEFT];
                }

                node = ngx_eb_untag(root, NGX_EB_LEAF);
            }
            return node;
        }

        if ((t >> bit) >= NGX_EB_NODE_BRANCHES) {
            return NULL;
        }

        root = node->branches[(key >> bit) & NGX_EB_NODE_BRACH_MASK];
    }

    return NULL;
}


static ngx_inline ngx_ebtree_node_t *
ngx_ebtree_walk_down(ngx_ebtree_node_t *root, ngx_int_t side)
{
    ngx_ebtree_node_t *temp;
    while (ngx_eb_gettag(root) == NGX_EB_NODE) {
        temp = ngx_eb_untag(root, NGX_EB_NODE);
        root = temp->branches[side];
    }

    return ngx_eb_untag(root, NGX_EB_LEAF); 
}


ngx_ebtree_node_t *
ngx_ebtree_le(ngx_ebtree_t *tree, uint32_t key)
{
    ngx_ebtree_node_t *root, *node, *temp;

    root = tree->root[NGX_EB_LEFT]->branches[NGX_EB_LEFT];
    if (root == NULL) {
        return NULL;
    }

    while (1) {
        if (ngx_eb_gettag(root) == NGX_EB_LEAF) {
            node = ngx_eb_untag(root, NGX_EB_LEAF);
            if (node->key <= key) {
                return node;
            }

            root = node->leaf;
            break;
        }

        node = ngx_eb_untag(root, NGX_EB_NODE);

        if (node->bit < 0) {
            if (node->key <= key) {
                root = node->branches[NGX_EB_RIGHT];
                while (ngx_eb_gettag(root) != NGX_EB_LEAF) {
                    temp = ngx_eb_untag(root, NGX_EB_NODE);
                    root = temp->branches[NGX_EB_RIGHT];
                }

                return ngx_eb_untag(root, NGX_EB_LEAF);
            }

            root = node->node;
            break;
        }

        if (((key ^ node->key) >> node->bit) >= NGX_EB_NODE_BRANCHES) {
            if ((node->key >> node->bit) < (key >> node->bit)) {
                root = node->branches[NGX_EB_RIGHT];
                return ngx_ebtree_walk_down(root, NGX_EB_RIGHT);
            }

            root = node->node;
            break;
        }
        root = node->branches[(key >> node->bit) & NGX_EB_NODE_BRACH_MASK];
    }

    while (ngx_eb_gettag(root) == NGX_EB_LEFT) {
        temp = ngx_eb_untag(root, NGX_EB_LEFT);
        if (temp == NULL) {
            return NULL;
        }

        root = temp->node;
        temp = temp->branches[NGX_EB_RIGHT];
        temp = ngx_eb_clrtag(temp);
        if (temp == NULL) {
            return NULL;
        }
    }

    root = ngx_eb_untag(root, NGX_EB_RIGHT);
    root = root->branches[NGX_EB_LEFT];
    return ngx_ebtree_walk_down(root, NGX_EB_RIGHT);
}


ngx_ebtree_node_t *
ngx_ebtree_ge(ngx_ebtree_t *tree, uint32_t key)
{
    ngx_ebtree_node_t *root, *node, *temp;

    root = tree->root[NGX_EB_LEFT]->branches[NGX_EB_LEFT];
    if (root == NULL) {
        return NULL;
    }

    while (1) {
        if (ngx_eb_gettag(root) == NGX_EB_LEAF) {
            node = ngx_eb_untag(root, NGX_EB_LEAF);
            if (node->key >= key) {
                return node;
            }
            root = node->leaf;
            break;
        }

        node = ngx_eb_untag(root, NGX_EB_NODE);
        if (node->bit < 0) {
            if (node->key >= key) {
                root = node->branches[NGX_EB_LEFT];
                while (ngx_eb_gettag(root) != NGX_EB_LEAF) {
                    temp = ngx_eb_untag(root, NGX_EB_NODE);
                    root = temp->branches[NGX_EB_LEFT];
                }
                return ngx_eb_untag(root, NGX_EB_LEAF);
            }
            root = node->node;
            break;
        }

        if (((key ^ node->key) >> node->bit) >= NGX_EB_NODE_BRANCHES) {
            if ((node->key >> node->bit) > (key >> node->bit)) {
                root = node->branches[NGX_EB_LEFT];
                return ngx_ebtree_walk_down(root, NGX_EB_LEFT);
            }

            root = node->node;
            break;
        }

        root = node->branches[(key >> node->bit) & NGX_EB_NODE_BRACH_MASK];
    }

    while (ngx_eb_gettag(root) != NGX_EB_LEFT) {
        temp = ngx_eb_untag(root, NGX_EB_RIGHT);
        root = temp->node;
    }

    temp = ngx_eb_untag(root, NGX_EB_LEFT);
    if (ngx_eb_clrtag(temp) == NULL) {
        return NULL;
    }

    root = temp->branches[NGX_EB_RIGHT];
    if (ngx_eb_clrtag(root) == NULL) {
        return NULL;
    }

    return ngx_ebtree_walk_down(root, NGX_EB_LEFT);
}
