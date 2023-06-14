/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef NGX_COMM_SHM_H
#define NGX_COMM_SHM_H

#include <ngx_core.h>
#include <ngx_buf.h>
#include <ngx_queue.h>

/**
 * @brief shared memory allocator
 * @note Continuous allocation of memory, does not provide partial memory release, only all allocated memory can be released
 */
typedef struct {
    u_char * base;
    u_char * pos;
    u_char * last;

    ngx_int_t out_of_memory;
} ngx_shm_pool_t;

/**
 * @brief Create a shared memory pool, which has a fixed size and allocates memory continuously
 * 
 * @param addr shared memory address
 * @param size shared memory size
 * @return ngx_shm_pool_t* Returns the memory pool address
 * @retval NULL Creation failed
 * @warning The size of the memory pool that can be allocated is size - sizeof(ngx_shm_pool_t)
 */
ngx_shm_pool_t * ngx_shm_create_pool(u_char * addr, size_t size);

/**
 * @brief allocate memory from memory pool
 * 
 * @param pool memory pool
 * @param size Required memory allocation size
 * @return void* 
 * @warning Must be used in the process of creating the memory pool
 */
void *ngx_shm_pool_calloc(ngx_shm_pool_t * pool, size_t size);

/**
 * @brief Check for insufficient memory
 * 
 * @param pool pool memory pool
 * @return ngx_int_t 1 Not enough storage
 *                   0 sufficient memory
 */
ngx_int_t ngx_shm_pool_out_of_memory(ngx_shm_pool_t * pool);

/**
 * @brief allocate ngx_str_t
 * 
 * @param pool memory pool
 * @param str_size String data required size
 * @return ngx_str_t* Returns the allocated string
 * @note data data is the memory space of str_size size, len is 0
 * @warning Must be used in the process of creating the memory pool
 */
ngx_str_t *ngx_shm_pool_calloc_str(ngx_shm_pool_t * pool, size_t str_size);

/**
 * @brief Reset the pool, freeing all allocated memory
 * 
 * @param pool shared memory pool
 * @warning Must be used in the process of creating the memory pool
 */
void ngx_shm_pool_reset(ngx_shm_pool_t * pool);

/**
 * @brief Get the memory space size of the memory pool
 * 
 * @param pool shared memory pool
 * @return ngx_int_t 共享内存总大小
 * @note contains allocated space
 */
ngx_int_t ngx_shm_pool_size(ngx_shm_pool_t * pool);

/**
 * @brief Get the memory size that can be allocated by the memory pool
 * 
 * @param pool shared memory pool
 * @return ngx_int_t Allocatable memory size
 */
ngx_int_t ngx_shm_pool_free_size(ngx_shm_pool_t * pool);

/**
 * @brief Get shared memory usage percentage
 * 
 * @param pool shared memory size
 * @return ngx_int_t memory usage percentage [0-100]
 */
ngx_int_t ngx_shm_pool_used_rate(ngx_shm_pool_t * pool);


/**
 * @brief shared memory array
 * @note Fixed element size and fixed number
 */
typedef struct {
    void        *elts;
    ngx_uint_t   nelts;
    size_t       size;
    ngx_uint_t   nalloc;
} ngx_shm_array_t;

/**
 * @brief Create shared memory array
 * 
 * @param pool shared memory pool
 * @param max_n Maximum number of elements
 * @param size Each element size
 * @return ngx_shm_array_t* shared memory array
 * @retval NULL creation failed
 */
ngx_shm_array_t* ngx_shm_array_create(ngx_shm_pool_t * pool, ngx_int_t max_n, ngx_int_t size);

/**
 * @brief add array element
 * 
 * @param a shared memory array
 * @return void* return element address
 * @retval NULL failed to add element
 * @warning Does not support process safety, must be used in the process that creates the array
 */
void *ngx_shm_array_push(ngx_shm_array_t *a);

/**
 * @brief add n array elements
 * 
 * @param a shared memory array
 * @param n number of elements added
 * @return void* return element address
 * @retval NULL failed to add element
 * @warning Does not support process safety, must be used in the process that creates the array
 */
void *ngx_shm_array_push_n(ngx_shm_array_t *a, ngx_uint_t n);

/**
 * @brief element comparison function
 */
typedef int (*ngx_shm_compar_func)(const void *, const void*);

/**
 * @brief Sort array elements
 * 
 * @param a array
 * @param c comparison function
 */
void ngx_shm_sort_array(ngx_shm_array_t *a, ngx_shm_compar_func c);

/**
 * @brief Retrieve an element in an ordered array
 * 
 * @param a ordered array
 * @param key the key to retrieve
 * @param c comparison function
 * @return void* retrieved elements
 */
void * ngx_shm_search_array(ngx_shm_array_t *a, const void * key, ngx_shm_compar_func c);


/**
 * @brief Hash function
 */
typedef ngx_uint_t (*ngx_shm_hash_calc_func)(const void *);


/**
 * @brief Shared Memory Hash Table
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

    ngx_shm_hash_t * table = ngx_shm_hash_create(pool, 11701, hash, compare);

    node * node1 = ngx_shm_pool_calloc(pool, sizeof(node));
    strcpy(node1->key, "testkey1");
    
    ngx_shm_hash_add(table, node1);

    node * node2 = ngx_shm_hash_get(table, node1);
 * @endcode
 */

typedef struct {
    ngx_int_t                bucket_size;
    ngx_shm_hash_calc_func   hash_func;
    ngx_shm_compar_func      compar_func;
    ngx_shm_pool_t          *pool;
    ngx_queue_t              buckets[0];
} ngx_shm_hash_t;

/**
 * @brief Create a shared memory hash table
 * 
 * @param pool memory pool
 * @param bucket_size Hash bucket size
 * @param hash_func Hash function
 * @param compar_func comparison function
 * @return ngx_shm_hash_t* Hash table address
 * @retval NULL Creation failed
 */
ngx_shm_hash_t *ngx_shm_hash_create(ngx_shm_pool_t * pool,
    ngx_int_t bucket_size,
    ngx_shm_hash_calc_func hash_func,
    ngx_shm_compar_func compar_func);

/**
 * @brief Add Hash element
 * 
 * @param table Hash table
 * @param elem element pointer
 * @return ngx_int_t result
 * @retval NGX_OK success
 * @retval NGX_ERROR fail
 * @warning The element memory space must be created in advance using shared memory
 */
ngx_int_t ngx_shm_hash_add(ngx_shm_hash_t * table, void * elem);

/**
 * @brief Delete the Hash element
 * 
 * @param table Hash table
 * @param elem pointer to the element to be deleted
 * @return ngx_int_t result
 * @retval NGX_OK Success (deletion is successful if it does not exist)
 * @retval NGX_ERROR exception error, such as table is NULL
 */
ngx_int_t
ngx_shm_hash_del(ngx_shm_hash_t * table, void * elem);

/**
 * @brief Get the Hash element
 * 
 * @param table Hash table
 * @param elem The retrieved target Key
 * @return void* Element address in Hash table
 */
void * ngx_shm_hash_get(ngx_shm_hash_t * table, void * elem);


/**
 * @brief copy string
 * @param pool  memory pool
 * @param dst   destination string
 * @param src   source string
 * @return  result
 * @retval NGX_OK success
 * @retval NGX_ERROR fail
 * @note dst must exist, applicable to the ngx_str_t structure exists but the data memory space does not exist
 */
ngx_int_t ngx_shm_str_copy(ngx_shm_pool_t * pool, ngx_str_t * dst, ngx_str_t * src);


#endif // NGX_COMM_SHM_H
