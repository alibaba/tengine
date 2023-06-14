/*
 * Copyright (C) 2020-2023 Alibaba Group Holding Limited
 */

#ifndef NGX_COMM_SERIALIZE_H
#define NGX_COMM_SERIALIZE_H

#include <ngx_core.h>
#include <ngx_string.h>

/**
 * @brief Serialize 1-byte integer to target address
 * 
 * @param pos the current position of the write
 * @param left remaining bytes
 * @param value value to write
 * @return ngx_inline
 *                  NGX_OK Success
 *                  NGX_ERROR failed
 */
ngx_int_t ngx_serialize_write_uint8(u_char **pos, uint32_t * left, uint8_t value);

/**
 * @brief Serialize 2-byte integer to target address, network byte order
 * 
 * @param pos the current position of the write
 * @param left remaining bytes
 * @param value value to write
 * @return ngx_inline
 *                  NGX_OK Success
 *                  NGX_ERROR failed
 */
ngx_int_t ngx_serialize_write_uint16(u_char **pos, uint32_t * left, uint16_t value);

/**
 * @brief Serialize 4-byte integer to target address, network byte order
 * 
 * @param pos the current position of the write
 * @param left remaining bytes
 * @param value value to write
 * @return ngx_inline
 *                  NGX_OK Success
 *                  NGX_ERROR failed
 */
ngx_int_t ngx_serialize_write_uint32(u_char **pos, uint32_t * left, uint32_t value);

/**
 * @brief Serialize a buffer to the target address
 * 
 * @param pos the current position of the write
 * @param left remaining bytes
 * @param value value to write
 * @param len value to write
 * @return 
 *                  NGX_OK Success
 *                  NGX_ERROR failed
 */
ngx_int_t ngx_serialize_write_data(u_char **pos, uint32_t * left, void* value, uint32_t len);

/**
 * @brief Serialize a section of 1 byte length + buffer to the target address
 * 
 * @param pos the current position of the write
 * @param left remaining bytes
 * @param value value to write
 * @param len value to write
 * @return 
 *                  NGX_OK Success
 *                  NGX_ERROR failed
 */
ngx_int_t ngx_serialize_write_uint8_data(u_char **pos, uint32_t * left, void* value, uint8_t len);

/**
 * @brief Serialize a 2-byte length + string to the target address
 * 
 * @param pos the current position of the write
 * @param left remaining bytes
 * @param str the string to write
 * @return 
 *                  NGX_OK Success
 *                  NGX_ERROR failed
 */
ngx_int_t ngx_serialize_write_uint16_string(u_char **pos, uint32_t * left, ngx_str_t * str);

/**
 * @brief Deserialize 1-byte from source memory
 * 
 * @param pos Read the current position of the data
 * @param left remaining bytes
 * @param value deserialized value
 * @return 
 *                  NGX_OK Success
 *                  NGX_ERROR failed
 */
ngx_int_t  ngx_serialize_read_uint8(u_char **pos, uint32_t *left, uint8_t *value);

/**
 * @brief Deserialize 2-bytes from source memory
 * 
 * @param pos Read the current position of the data
 * @param left remaining bytes
 * @param value deserialized value
 * @return 
 *                  NGX_OK Success
 *                  NGX_ERROR failed
 */
ngx_int_t ngx_serialize_read_uint16(u_char **pos, uint32_t * left, uint16_t * value);

/**
 * @brief Deserialize 4-bytes from source memory
 * 
 * @param pos Read the current position of the data
 * @param left remaining bytes
 * @param value deserialized value
 * @return 
 *                  NGX_OK Success
 *                  NGX_ERROR failed
 */
ngx_int_t ngx_serialize_read_uint32(u_char **pos, uint32_t * left, uint32_t * value);

/**
 * @brief Deserialize string from source memory (including 1 byte length + content)
 * 
 * @param pos Read the current position of the data
 * @param left remaining bytes
 * @param str deserialized value
 * @return 
 *                  NGX_OK Success
 *                  NGX_ERROR failed
 */
ngx_int_t  ngx_serialize_read_uint8_string(u_char **pos, uint32_t * left, ngx_str_t * str);

/**
 * @brief Deserialize string from source memory (including 2 bytes length + content)
 * 
 * @param pos Read the current position of the data
 * @param left remaining bytes
 * @param str deserialized value
 * @return 
 *                  NGX_OK Success
 *                  NGX_ERROR failed
 */
ngx_int_t ngx_serialize_read_uint16_string(u_char **pos, uint32_t * left, ngx_str_t * str);

/**
 * @brief Deserialize a buffer from the source memory
 * 
 * @param pos Read the current position of the data
 * @param left remaining bytes
 * @param value deserialized value
 * @param len The length to be deserialized
 * @return 
 *                  NGX_OK Success
 *                  NGX_ERROR failed
 */
ngx_int_t ngx_serialize_read_data(u_char **pos, uint32_t * left, void* value, uint32_t len);

/**
 * @brief Deserialize 8-bytes from source memory
 * 
 * @param pos Read the current position of the data
 * @param left remaining bytes
 * @param value deserialized value
 * @return 
 *                  NGX_OK Success
 *                  NGX_ERROR failed
 */
ngx_int_t ngx_serialize_read_uint64(u_char **pos, uint32_t * left, uint64_t * value);

#endif // NGX_COMM_SERIALIZE_H
