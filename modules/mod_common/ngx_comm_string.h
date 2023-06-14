/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef NGX_COMM_STRING_H
#define NGX_COMM_STRING_H

#include <ngx_core.h>
#include <ngx_buf.h>


/**
 * @brief split string
 * 
 * @param out       split string array
 * @param out_len   The size of the split string array
 * @param in        The character string to be split, the original value will not be changed after splitting
 * @param terminate delimiter
 * @return Return the size of the array, if out_len is too small, it will be truncated to return the maximum size that can be accommodated
 */
ngx_int_t
comm_split_string(ngx_str_t * out, ngx_int_t out_len, ngx_str_t * in, u_char terminate);

/**
 * @brief String to integer (negative numbers are not supported)
 * 
 * @param line  input string
 * @param n     input string size
 * @return  Returns an integer, or NGX_ERROR if the rule is not met
 */
long long int
comm_atoll(u_char *line, size_t n);

/**
 * @brief String to integer (negative numbers are not supported, and blank characters are removed from input)
 * 
 * @param line  input string
 * @param n     input string size
 * @return  Returns an integer, or NGX_ERROR if the rule is not met
 */
long long int
comm_atoll_with_trim(u_char *line, size_t n);

/**
 * @brief compare ngx_str_t content
 * 
 * @param src  source string
 * @param dst  destination string
 * @return  Returns an integer, equal returns 0, src<dst returns a negative number, src>dst returns a positive number
 */
ngx_int_t ngx_comm_strcasecmp(ngx_str_t * src, ngx_str_t * dst);

/**
 * @brief String copy and convert to uppercase
 * 
 * @param dst destination string (make sure there is enough space)
 * @param src source string
 * @param n   the number of bytes to copy
 */
void ngx_strupper(u_char *dst, u_char *src, size_t n);

/**
 * @brief compare ngx_str_t content
 * 
 * @param src  input string
 * @param dst  output string
 * @return  Returns an integer, equal returns 0, src<dst returns a negative number, src>dst returns a positive number
 */
int ngx_comm_strcmp(const ngx_str_t * v1, const ngx_str_t * v2);

/**
 * @brief copy string
 * @param pool  memory pool
 * @param src   source string
 * @return  Returns the copied string, or NULL on failure
 */
ngx_str_t *ngx_comm_str_dup(ngx_pool_t * pool, ngx_str_t * src);


/**
 * @brief compare c string and ngx_str content
 * 
 * @param src       source c string
 * @param src_len   source c string length
 * @param dst       destination string
 * @return  Returns an integer, equal returns 0, src<dst returns a negative number, src>dst returns a positive number
 */
int ngx_comm_cstr_casecmp(const char * src, size_t src_len, ngx_str_t * dst);

/**
 * @brief Count character occurrences
 * 
 * @param pos  starting point
 * @param last end position (not included)
 * @param c The target character to find
 * @return int The number of occurrences
 */
int ngx_comm_count_character(u_char * pos, u_char * last, char c);

/**
 * @brief Find a single character in a string
 * 
 * @param pos   starting point
 * @param last  end position (not included)
 * @param c     The target character to find
 * @return u_char*  The first occurrence of the character, if not found, returns NULL
 */
u_char *ngx_comm_strchr(u_char * pos, u_char * last, char c);

/**
 * @brief split string
 * 
 * @param arr           result array
 * @param n             The length of the result array (need to ensure that the length is sufficient)
 * @param pos           string starting position
 * @param last          end of string (exclusive)
 * @param terminate     split character
 * @return ngx_int_t    Return the size of the result array (if the length of the array is not enough, it will be truncated and only the maximum size that can be carried will be returned)
 */
ngx_int_t ngx_comm_split_string(ngx_str_t * arr, ngx_int_t n,
    u_char * pos, u_char * last, u_char terminate);

/**
 * @brief Remove leading and trailing whitespace characters
 * 
 * @param source [in,out] destination string
 * @return ngx_int_t source string
 */
ngx_int_t ngx_comm_trim_string(ngx_str_t * source);

/**
 * @brief deep copy string
 * @param pool  pool for alloc memory
 * @param dst   destination string
 * @param src   source string
 * @return  Returns NGX_OK on success, NGX_ERROR on failure
 */
ngx_int_t ngx_comm_strcpy(ngx_pool_t * pool, ngx_str_t * dst, ngx_str_t * src);

/**
 * @brief Parse the key-value in a string
 * @param line      input string
 * @param key       key
 * @param value     return value
 * @param terminate Delimiter, such as key1=value1,key2=value2 delimiter is,
 * @return Returns NGX_OK on success, NGX_ERROR on failure
 */
ngx_int_t ngx_comm_parse_string_value(ngx_str_t *line, ngx_str_t *key, ngx_str_t *value, u_char terminate);

/**
 * @brief Parse the key-value in a row
 * @param line      input line
 * @param key       key
 * @param value     return value
 * @param terminate Delimiter, such as key1=value1,key2=value2 delimiter is,
 * @return Successfully returns the parsed value successfully, fails to return NGX_ERROR
 */
ngx_int_t ngx_comm_parse_int_value(ngx_str_t *line, ngx_str_t *key, u_char terminate);


/**
 * @brief Suffix comparison, case insensitive
 * 
 * @param src  source string
 * @param suffix  matching suffix
 * @return  Returns an integer, returns NGX_OK if the match is successful, and NGX_ERROR indicates no match
 */
ngx_int_t ngx_comm_suffix_casecmp(ngx_str_t * src, ngx_str_t * suffix);

/**
 * @brief Prefix comparison, case insensitive
 * 
 * @param src  source string
 * @param prefix  matching prefix
 * @return  Returns an integer, returns NGX_OK if the match is successful, and NGX_ERROR indicates no match
 */
ngx_int_t ngx_comm_prefix_casecmp(ngx_str_t * src, ngx_str_t * prefix);


/**
 * @brief Prefix comparison, case sensitive
 * 
 * @param src  source string
 * @param prefix  matching prefix
 * @return  Returns an integer, returns NGX_OK if the match is successful, and NGX_ERROR indicates no match
 */
ngx_int_t ngx_comm_prefix_cmp(ngx_str_t * src, ngx_str_t * prefix);

/**
 * @brief String comparison, for use with qsort
 */
int
ngx_comm_str_compare(const void *c1, const void *c2);

#endif // NGX_COMM_STRING_H


