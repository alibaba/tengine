
#ifndef NGX_COMM_SHM_H
#define NGX_COMM_SHM_H

#include <ngx_core.h>
#include <ngx_buf.h>
#include <ngx_hlist.h>

/**
 * @brief 共享内存分配器
 * @note 内存连续分配，不提供部分内存释放，只可全部释放已分配内存
 */
typedef struct {
    u_char * base;
    u_char * pos;
    u_char * last;

    ngx_int_t out_of_memory;
} ngx_shm_pool_t;

/**
 * @brief 创建共享内存池，此内存池固定大小，连续分配内存
 * 
 * @param addr 共享内存地址 
 * @param size 共享内存大小
 * @return ngx_shm_pool_t* 返回内存池地址，
 * @retval NULL 创建失败
 * @warning 内存池可分配内存大小为 size - sizeof(ngx_shm_pool_t)
 */
ngx_shm_pool_t * ngx_shm_create_pool(u_char * addr, size_t size);

/**
 * @brief 从内存池分配内存
 * 
 * @param pool 内存池
 * @param size 所需分配内存大小
 * @return void* 
 * @warning 必须在创建内存池的进程使用
 */
void *ngx_shm_pool_calloc(ngx_shm_pool_t * pool, size_t size);

/**
 * @brief 检查是否内存不足
 * 
 * @param pool 内存池
 * @return ngx_int_t 1 内存不足
 *                   0 内存充足
 */
ngx_int_t ngx_shm_pool_out_of_memory(ngx_shm_pool_t * pool);

/**
 * @brief 分配ngx_str_t
 * 
 * @param pool 内存池
 * @param str_size 字符串data所需大小
 * @return ngx_str_t* 返回分配完成的字符串
 * @note data 为 str_size大小的内存空间，len 为 0
 * @warning 必须在创建内存池的进程使用
 */
ngx_str_t *ngx_shm_pool_calloc_str(ngx_shm_pool_t * pool, size_t str_size);

/**
 * @brief 重置pool，释放已经分配的所有内存
 * 
 * @param pool 共享内存池
 * @warning 必须在创建内存池的进程使用
 */
void ngx_shm_pool_reset(ngx_shm_pool_t * pool);

/**
 * @brief 获取内存池内存空间大小
 * 
 * @param pool 共享内存池
 * @return ngx_int_t 共享内存总大小
 * @note 包含已经分配的空间
 */
ngx_int_t ngx_shm_pool_size(ngx_shm_pool_t * pool);

/**
 * @brief 获取内存池可分配内存大小
 * 
 * @param pool 共享内存池
 * @return ngx_int_t 可分配内存大小
 */
ngx_int_t ngx_shm_pool_free_size(ngx_shm_pool_t * pool);

/**
 * @brief 获取共享内存使用率百分比
 * 
 * @param pool 共享内存大小
 * @return ngx_int_t 内存使用百分比[0-100]
 */
ngx_int_t ngx_shm_pool_used_rate(ngx_shm_pool_t * pool);


/**
 * @brief 共享内存数组
 * @note 固定元素大小和固定个数
 */
typedef struct {
    void        *elts;
    ngx_uint_t   nelts;
    size_t       size;
    ngx_uint_t   nalloc;
} ngx_shm_array_t;

/**
 * @brief 创建共享内存数组
 * 
 * @param pool 共享内存池
 * @param max_n 最大元素个数
 * @param size 每个元素大小
 * @return ngx_shm_array_t* 共享内存数组
 * @retval NULL 创建失败
 */
ngx_shm_array_t* ngx_shm_array_create(ngx_shm_pool_t * pool, ngx_int_t max_n, ngx_int_t size);

/**
 * @brief 添加数组元素
 * 
 * @param a 共享内存数组
 * @return void* 返回元素地址
 * @retval NULL 添加元素失败
 * @warning 不支持进程安全，必须在创建数组的进程使用
 */
void *ngx_shm_array_push(ngx_shm_array_t *a);

/**
 * @brief 添加n个数组元素
 * 
 * @param a 共享内存数组
 * @param n 添加元素数量
 * @return void* 返回元素地址
 * @retval NULL 添加元素失败
 * @warning 不支持进程安全，必须在创建数组的进程使用
 */
void *ngx_shm_array_push_n(ngx_shm_array_t *a, ngx_uint_t n);

/**
 * @brief 元素比较函数
 */
typedef int (*ngx_shm_compar_func)(const void *, const void*);

/**
 * @brief 数组元素排序
 * 
 * @param a 数组
 * @param c 比较函数
 */
void ngx_shm_sort_array(ngx_shm_array_t *a, ngx_shm_compar_func c);

/**
 * @brief 有序数组内检索元素
 * 
 * @param a 有序数组
 * @param key 要检索的key
 * @param c 比较函数
 * @return void* 检索到的元素
 */
void * ngx_shm_search_array(ngx_shm_array_t *a, const void * key, ngx_shm_compar_func c);


/**
 * @brief Hash函数
 */
typedef ngx_uint_t (*ngx_shm_hash_calc_func)(const void *);


/**
 * @brief 共享内存Hash表
 * @code
    typedef struct {
        char key[255];
        char data[1024];
    } node;

    int compare(const void * p1, const void* p2) {
        node * n1 = p1;
        node * n2 = p2;
        return strcmp(n1.key, n2.key);
    }
    int hash(const void * p) {
        node * n = p;
        return ngx_hash_key(n->key, strlen(n->key));
    }

    ngx_shm_pool_t * pool = ngx_shm_create_pool(shm(size), size);

    ngx_shm_hash_t * table = ngx_shm_hash_create(pool, 11701, sizeof(node), hash, compare);

    node * node1 = ngx_shm_pool_calloc(pool, sizeof(node));
    strcpy(node1->key, "testkey1");
    
    ngx_shm_hash_add(table, node1);

    node * node2 = ngx_shm_hash_get(table, node1);
 * @endcode
 */
typedef struct {
    ngx_int_t bucket_size;
    ngx_shm_hash_calc_func hash_func;
    ngx_shm_compar_func compar_func;
    ngx_shm_pool_t *pool;
    struct hlist_head buckets[0];
} ngx_shm_hash_t;

/**
 * @brief 创建共享内存Hash表
 * 
 * @param pool 内存池
 * @param bucket_size Hash桶大小
 * @param hash_func Hash函数
 * @param compar_func 比较函数
 * @return ngx_shm_hash_t* Hash表地址
 * @retval NULL 创建失败
 */
ngx_shm_hash_t *ngx_shm_hash_create(ngx_shm_pool_t * pool,
    ngx_int_t bucket_size,
    ngx_shm_hash_calc_func hash_func,
    ngx_shm_compar_func compar_func);

/**
 * @brief 添加Hash元素
 * 
 * @param table Hash表
 * @param elem 元素指针
 * @return ngx_int_t 结果
 * @retval NGX_OK 成功
 * @retval NGX_ERROR 失败
 * @warning 元素内存空间必须事先使用共享内存创建
 */
ngx_int_t ngx_shm_hash_add(ngx_shm_hash_t * table, void * elem);

/**
 * @brief 删除Hash元素
 * 
 * @param table Hash表
 * @param elem 待删除元素指针
 * @return ngx_int_t 结果
 * @retval NGX_OK 成功（不存在也为删除成功）
 * @retval NGX_ERROR 异常错误，如 table 为 NULL
 */
ngx_int_t
ngx_shm_hash_del(ngx_shm_hash_t * table, void * elem);

/**
 * @brief 获取Hash元素
 * 
 * @param table Hash表
 * @param elem 检索的目标Key
 * @return void* Hash表中的元素地址
 */
void *ngx_shm_hash_get(ngx_shm_hash_t * table, void * elem);

/**
 * @brief 通过 bucket node 获取 Hash 元素，遍历 hash 表时使用
 * 
 * @param node bucket list node
 * @return void* Hash表中的元素地址
 */
void *ngx_shm_hash_get_by_node(struct hlist_node *node);

/**
 * @brief 复制字符串
 * @param pool  内存池
 * @param src   目的字符串
 * @param src   源字符串
 * @return  结果
 * @retval NGX_OK 成功
 * @retval NGX_ERROR 失败
 * @note dst本身需要存在，适用于ngx_str_t结构存在，但data内存空间没有的场景
 */
ngx_int_t ngx_shm_str_copy(ngx_shm_pool_t * pool, ngx_str_t * dst, ngx_str_t * src);



/*******************************
 *       一写多读hash表
 *******************************/

/**
 * @brief 共享内存Hash表
 * @code
    typedef struct {
        char key[255];
        char data[1024];
    } node;

    int compare(const void * p1, const void* p2) {
        node * n1 = p1;
        node * n2 = p2;
        return strcmp(n1.key, n2.key);
    }
    int hash(const void * p) {
        node * n = p;
        return ngx_hash_key(n->key, strlen(n->key));
    }

    ngx_shm_pool_t * pool = ngx_shm_create_pool(shm(size), size);

    ngx_shm_hash_t * table = ngx_shm_hash_create(pool, 11701, sizeof(node), hash, compare);

    node * node1 = ngx_shm_pool_calloc(pool, sizeof(node));
    strcpy(node1->key, "testkey1");
    
    ngx_shm_hash_add(table, node1);

    node * node2 = ngx_shm_hash_get(table, node1);
 * @endcode
 */

struct ngx_shm_lockless_hash_node_s {
    struct ngx_shm_lockless_hash_node_s *next;
    void *data;
};
typedef struct ngx_shm_lockless_hash_node_s ngx_shm_lockless_hash_node_t;

typedef struct {
    ngx_shm_lockless_hash_node_t *head;
    ngx_atomic_t count;
} ngx_shm_lockless_hash_bucket_t;

typedef struct {
    ngx_int_t bucket_size;
    ngx_shm_hash_calc_func hash_func;
    ngx_shm_compar_func compar_func;
    ngx_shm_pool_t *pool;

    ngx_int_t max_n;
    ngx_int_t used_n;
    
    ngx_shm_lockless_hash_bucket_t buckets[0];
} ngx_shm_lockless_hash_t;

/**
 * @brief 创建共享内存Hash表
 * 
 * @param pool 内存池
 * @param bucket_size Hash桶大小
 * @param max_n 最大元素个数
 * @param hash_func Hash函数
 * @param compar_func 比较函数
 * @return ngx_shm_lockless_hash_t* Hash表地址
 * @retval NULL 创建失败
 */
ngx_shm_lockless_hash_t *ngx_shm_lockless_hash_create(ngx_shm_pool_t * pool,
    ngx_int_t bucket_size,
    ngx_int_t max_n,
    ngx_shm_hash_calc_func hash_func,
    ngx_shm_compar_func compar_func);

/**
 * @brief 添加Hash元素
 * 
 * @param table Hash表
 * @param elem 元素指针
 * @return ngx_int_t 结果
 * @retval NGX_OK 成功
 * @retval NGX_ERROR 失败
 * @retval NGX_DONE 已经存在没有添加
 * @warning 元素内存空间必须事先使用共享内存创建
 */
ngx_int_t ngx_shm_lockless_hash_add(ngx_shm_lockless_hash_t * table, void * elem);

/**
 * @brief 获取Hash元素
 * 
 * @param table Hash表
 * @param elem 检索的目标Key
 * @return void* Hash表中的元素地址
 */
void * ngx_shm_lockless_hash_get(ngx_shm_lockless_hash_t * table, void * elem);

/**
 * @brief 获取hash表容量信息
 * 
 * @param table Hash表
 * @param elem_rate elem空间使用率
 */
void ngx_shm_lockless_hash_capacity(ngx_shm_lockless_hash_t * table, ngx_int_t *elem_rate);



/*******************************
 *      trie 树结构
 *******************************/

/**
 * @brief trie 树
 * @code
 * @endcode
 */
typedef struct ngx_shm_path_trie_node_s {
    ngx_str_t       segment;
    ngx_shm_hash_t  *hs;
    void            *data;
} ngx_shm_path_trie_node_t;

typedef struct ngx_shm_path_trie_s {
    ngx_shm_pool_t *pool;
    ngx_int_t bucket_size;

    ngx_shm_path_trie_node_t *nodes;
} ngx_shm_path_trie_t;

ngx_shm_path_trie_t *ngx_shm_trie_create(ngx_shm_pool_t *pool, ngx_int_t bucket_size);

ngx_int_t ngx_shm_trie_add(ngx_shm_path_trie_t *trie, ngx_str_t *prefix, void *data);

void* ngx_shm_trie_search(ngx_shm_path_trie_t *trie, ngx_str_t *path);

#endif // NGX_COMM_SHM_H
