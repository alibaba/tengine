
/*
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_event.h>
#include <ngx_event_quic_connection.h>


/* RFC 9001, 5.4.1.  Header Protection Application: 5-byte mask */
#define NGX_QUIC_HP_LEN               5

#define NGX_QUIC_AES_128_KEY_LEN      16

#ifndef TLS1_3_CK_AES_128_GCM_SHA256
#define TLS1_3_CK_AES_128_GCM_SHA256  0x03001301
#define TLS1_3_CK_AES_256_GCM_SHA384  0x03001302
#define TLS1_3_CK_CHACHA20_POLY1305_SHA256                                   \
                                      0x03001303
#endif


#ifdef OPENSSL_IS_BORINGSSL
#define ngx_quic_cipher_t             EVP_AEAD
#else
#define ngx_quic_cipher_t             EVP_CIPHER
#endif


typedef struct {
    const ngx_quic_cipher_t  *c;
    const EVP_CIPHER         *hp;
    const EVP_MD             *d;
} ngx_quic_ciphers_t;


typedef struct {
    size_t                    out_len;
    u_char                   *out;

    size_t                    prk_len;
    const uint8_t            *prk;

    size_t                    label_len;
    const u_char             *label;
} ngx_quic_hkdf_t;

#define ngx_quic_hkdf_set(label, out, prk)                                    \
    {                                                                         \
        (out)->len, (out)->data,                                              \
        (prk)->len, (prk)->data,                                              \
        (sizeof(label) - 1), (u_char *)(label),                               \
    }


static ngx_int_t ngx_hkdf_expand(u_char *out_key, size_t out_len,
    const EVP_MD *digest, const u_char *prk, size_t prk_len,
    const u_char *info, size_t info_len);
static ngx_int_t ngx_hkdf_extract(u_char *out_key, size_t *out_len,
    const EVP_MD *digest, const u_char *secret, size_t secret_len,
    const u_char *salt, size_t salt_len);

static uint64_t ngx_quic_parse_pn(u_char **pos, ngx_int_t len, u_char *mask,
    uint64_t *largest_pn);
static void ngx_quic_compute_nonce(u_char *nonce, size_t len, uint64_t pn);
static ngx_int_t ngx_quic_ciphers(ngx_uint_t id,
    ngx_quic_ciphers_t *ciphers, enum ssl_encryption_level_t level);

static ngx_int_t ngx_quic_tls_open(const ngx_quic_cipher_t *cipher,
    ngx_quic_secret_t *s, ngx_str_t *out, u_char *nonce, ngx_str_t *in,
    ngx_str_t *ad, ngx_log_t *log);
static ngx_int_t ngx_quic_tls_seal(const ngx_quic_cipher_t *cipher,
    ngx_quic_secret_t *s, ngx_str_t *out, u_char *nonce, ngx_str_t *in,
    ngx_str_t *ad, ngx_log_t *log);
static ngx_int_t ngx_quic_tls_hp(ngx_log_t *log, const EVP_CIPHER *cipher,
    ngx_quic_secret_t *s, u_char *out, u_char *in);
static ngx_int_t ngx_quic_hkdf_expand(ngx_quic_hkdf_t *hkdf,
    const EVP_MD *digest, ngx_log_t *log);

static ngx_int_t ngx_quic_create_packet(ngx_quic_header_t *pkt,
    ngx_str_t *res);
static ngx_int_t ngx_quic_create_retry_packet(ngx_quic_header_t *pkt,
    ngx_str_t *res);


static ngx_int_t
ngx_quic_ciphers(ngx_uint_t id, ngx_quic_ciphers_t *ciphers,
    enum ssl_encryption_level_t level)
{
    ngx_int_t  len;

    if (level == ssl_encryption_initial) {
        id = TLS1_3_CK_AES_128_GCM_SHA256;
    }

    switch (id) {

    case TLS1_3_CK_AES_128_GCM_SHA256:
#ifdef OPENSSL_IS_BORINGSSL
        ciphers->c = EVP_aead_aes_128_gcm();
#else
        ciphers->c = EVP_aes_128_gcm();
#endif
        ciphers->hp = EVP_aes_128_ctr();
        ciphers->d = EVP_sha256();
        len = 16;
        break;

    case TLS1_3_CK_AES_256_GCM_SHA384:
#ifdef OPENSSL_IS_BORINGSSL
        ciphers->c = EVP_aead_aes_256_gcm();
#else
        ciphers->c = EVP_aes_256_gcm();
#endif
        ciphers->hp = EVP_aes_256_ctr();
        ciphers->d = EVP_sha384();
        len = 32;
        break;

    case TLS1_3_CK_CHACHA20_POLY1305_SHA256:
#ifdef OPENSSL_IS_BORINGSSL
        ciphers->c = EVP_aead_chacha20_poly1305();
#else
        ciphers->c = EVP_chacha20_poly1305();
#endif
#ifdef OPENSSL_IS_BORINGSSL
        ciphers->hp = (const EVP_CIPHER *) EVP_aead_chacha20_poly1305();
#else
        ciphers->hp = EVP_chacha20();
#endif
        ciphers->d = EVP_sha256();
        len = 32;
        break;

    default:
        return NGX_ERROR;
    }

    return len;
}


ngx_int_t
ngx_quic_keys_set_initial_secret(ngx_quic_keys_t *keys, ngx_str_t *secret,
    ngx_log_t *log)
{
    size_t              is_len;
    uint8_t             is[SHA256_DIGEST_LENGTH];
    ngx_uint_t          i;
    const EVP_MD       *digest;
    ngx_quic_secret_t  *client, *server;

    static const uint8_t salt[20] =
        "\x38\x76\x2c\xf7\xf5\x59\x34\xb3\x4d\x17"
        "\x9a\xe6\xa4\xc8\x0c\xad\xcc\xbb\x7f\x0a";

    client = &keys->secrets[ssl_encryption_initial].client;
    server = &keys->secrets[ssl_encryption_initial].server;

    /*
     * RFC 9001, section 5.  Packet Protection
     *
     * Initial packets use AEAD_AES_128_GCM.  The hash function
     * for HKDF when deriving initial secrets and keys is SHA-256.
     */

    digest = EVP_sha256();
    is_len = SHA256_DIGEST_LENGTH;

    if (ngx_hkdf_extract(is, &is_len, digest, secret->data, secret->len,
                         salt, sizeof(salt))
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    ngx_str_t iss = {
        .data = is,
        .len = is_len
    };

    ngx_log_debug0(NGX_LOG_DEBUG_EVENT, log, 0,
                   "quic ngx_quic_set_initial_secret");
#ifdef NGX_QUIC_DEBUG_CRYPTO
    ngx_log_debug3(NGX_LOG_DEBUG_EVENT, log, 0,
                   "quic salt len:%uz %*xs", sizeof(salt), sizeof(salt), salt);
    ngx_log_debug3(NGX_LOG_DEBUG_EVENT, log, 0,
                   "quic initial secret len:%uz %*xs", is_len, is_len, is);
#endif

    client->secret.len = SHA256_DIGEST_LENGTH;
    server->secret.len = SHA256_DIGEST_LENGTH;

    client->key.len = NGX_QUIC_AES_128_KEY_LEN;
    server->key.len = NGX_QUIC_AES_128_KEY_LEN;

    client->hp.len = NGX_QUIC_AES_128_KEY_LEN;
    server->hp.len = NGX_QUIC_AES_128_KEY_LEN;

    client->iv.len = NGX_QUIC_IV_LEN;
    server->iv.len = NGX_QUIC_IV_LEN;

    ngx_quic_hkdf_t seq[] = {
        /* labels per RFC 9001, 5.1. Packet Protection Keys */
        ngx_quic_hkdf_set("tls13 client in", &client->secret, &iss),
        ngx_quic_hkdf_set("tls13 quic key",  &client->key,    &client->secret),
        ngx_quic_hkdf_set("tls13 quic iv",   &client->iv,     &client->secret),
        ngx_quic_hkdf_set("tls13 quic hp",   &client->hp,     &client->secret),
        ngx_quic_hkdf_set("tls13 server in", &server->secret, &iss),
        ngx_quic_hkdf_set("tls13 quic key",  &server->key,    &server->secret),
        ngx_quic_hkdf_set("tls13 quic iv",   &server->iv,     &server->secret),
        ngx_quic_hkdf_set("tls13 quic hp",   &server->hp,     &server->secret),
    };

    for (i = 0; i < (sizeof(seq) / sizeof(seq[0])); i++) {
        if (ngx_quic_hkdf_expand(&seq[i], digest, log) != NGX_OK) {
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_quic_hkdf_expand(ngx_quic_hkdf_t *h, const EVP_MD *digest, ngx_log_t *log)
{
    size_t    info_len;
    uint8_t  *p;
    uint8_t   info[20];

    info_len = 2 + 1 + h->label_len + 1;

    info[0] = 0;
    info[1] = h->out_len;
    info[2] = h->label_len;

    p = ngx_cpymem(&info[3], h->label, h->label_len);
    *p = '\0';

    if (ngx_hkdf_expand(h->out, h->out_len, digest,
                        h->prk, h->prk_len, info, info_len)
        != NGX_OK)
    {
        ngx_ssl_error(NGX_LOG_INFO, log, 0,
                      "ngx_hkdf_expand(%*s) failed", h->label_len, h->label);
        return NGX_ERROR;
    }

#ifdef NGX_QUIC_DEBUG_CRYPTO
    ngx_log_debug5(NGX_LOG_DEBUG_EVENT, log, 0,
                   "quic expand \"%*s\" len:%uz %*xs",
                   h->label_len, h->label, h->out_len, h->out_len, h->out);
#endif

    return NGX_OK;
}


static ngx_int_t
ngx_hkdf_expand(u_char *out_key, size_t out_len, const EVP_MD *digest,
    const uint8_t *prk, size_t prk_len, const u_char *info, size_t info_len)
{
#ifdef OPENSSL_IS_BORINGSSL

    if (HKDF_expand(out_key, out_len, digest, prk, prk_len, info, info_len)
        == 0)
    {
        return NGX_ERROR;
    }

    return NGX_OK;

#else

    EVP_PKEY_CTX  *pctx;

    pctx = EVP_PKEY_CTX_new_id(EVP_PKEY_HKDF, NULL);
    if (pctx == NULL) {
        return NGX_ERROR;
    }

    if (EVP_PKEY_derive_init(pctx) <= 0) {
        goto failed;
    }

    if (EVP_PKEY_CTX_hkdf_mode(pctx, EVP_PKEY_HKDEF_MODE_EXPAND_ONLY) <= 0) {
        goto failed;
    }

    if (EVP_PKEY_CTX_set_hkdf_md(pctx, digest) <= 0) {
        goto failed;
    }

    if (EVP_PKEY_CTX_set1_hkdf_key(pctx, prk, prk_len) <= 0) {
        goto failed;
    }

    if (EVP_PKEY_CTX_add1_hkdf_info(pctx, info, info_len) <= 0) {
        goto failed;
    }

    if (EVP_PKEY_derive(pctx, out_key, &out_len) <= 0) {
        goto failed;
    }

    EVP_PKEY_CTX_free(pctx);

    return NGX_OK;

failed:

    EVP_PKEY_CTX_free(pctx);

    return NGX_ERROR;

#endif
}


static ngx_int_t
ngx_hkdf_extract(u_char *out_key, size_t *out_len, const EVP_MD *digest,
    const u_char *secret, size_t secret_len, const u_char *salt,
    size_t salt_len)
{
#ifdef OPENSSL_IS_BORINGSSL

    if (HKDF_extract(out_key, out_len, digest, secret, secret_len, salt,
                     salt_len)
        == 0)
    {
        return NGX_ERROR;
    }

    return NGX_OK;

#else

    EVP_PKEY_CTX  *pctx;

    pctx = EVP_PKEY_CTX_new_id(EVP_PKEY_HKDF, NULL);
    if (pctx == NULL) {
        return NGX_ERROR;
    }

    if (EVP_PKEY_derive_init(pctx) <= 0) {
        goto failed;
    }

    if (EVP_PKEY_CTX_hkdf_mode(pctx, EVP_PKEY_HKDEF_MODE_EXTRACT_ONLY) <= 0) {
        goto failed;
    }

    if (EVP_PKEY_CTX_set_hkdf_md(pctx, digest) <= 0) {
        goto failed;
    }

    if (EVP_PKEY_CTX_set1_hkdf_key(pctx, secret, secret_len) <= 0) {
        goto failed;
    }

    if (EVP_PKEY_CTX_set1_hkdf_salt(pctx, salt, salt_len) <= 0) {
        goto failed;
    }

    if (EVP_PKEY_derive(pctx, out_key, out_len) <= 0) {
        goto failed;
    }

    EVP_PKEY_CTX_free(pctx);

    return NGX_OK;

failed:

    EVP_PKEY_CTX_free(pctx);

    return NGX_ERROR;

#endif
}


static ngx_int_t
ngx_quic_tls_open(const ngx_quic_cipher_t *cipher, ngx_quic_secret_t *s,
    ngx_str_t *out, u_char *nonce, ngx_str_t *in, ngx_str_t *ad,
    ngx_log_t *log)
{

#ifdef OPENSSL_IS_BORINGSSL
    EVP_AEAD_CTX  *ctx;

    ctx = EVP_AEAD_CTX_new(cipher, s->key.data, s->key.len,
                           EVP_AEAD_DEFAULT_TAG_LENGTH);
    if (ctx == NULL) {
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_AEAD_CTX_new() failed");
        return NGX_ERROR;
    }

    if (EVP_AEAD_CTX_open(ctx, out->data, &out->len, out->len, nonce, s->iv.len,
                          in->data, in->len, ad->data, ad->len)
        != 1)
    {
        EVP_AEAD_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_AEAD_CTX_open() failed");
        return NGX_ERROR;
    }

    EVP_AEAD_CTX_free(ctx);
#else
    int              len;
    u_char          *tag;
    EVP_CIPHER_CTX  *ctx;

    ctx = EVP_CIPHER_CTX_new();
    if (ctx == NULL) {
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_CIPHER_CTX_new() failed");
        return NGX_ERROR;
    }

    if (EVP_DecryptInit_ex(ctx, cipher, NULL, NULL, NULL) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_DecryptInit_ex() failed");
        return NGX_ERROR;
    }

    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, s->iv.len, NULL)
        == 0)
    {
        EVP_CIPHER_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0,
                      "EVP_CIPHER_CTX_ctrl(EVP_CTRL_GCM_SET_IVLEN) failed");
        return NGX_ERROR;
    }

    if (EVP_DecryptInit_ex(ctx, NULL, NULL, s->key.data, nonce) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_DecryptInit_ex() failed");
        return NGX_ERROR;
    }

    if (EVP_DecryptUpdate(ctx, NULL, &len, ad->data, ad->len) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_DecryptUpdate() failed");
        return NGX_ERROR;
    }

    if (EVP_DecryptUpdate(ctx, out->data, &len, in->data,
                          in->len - EVP_GCM_TLS_TAG_LEN)
        != 1)
    {
        EVP_CIPHER_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_DecryptUpdate() failed");
        return NGX_ERROR;
    }

    out->len = len;
    tag = in->data + in->len - EVP_GCM_TLS_TAG_LEN;

    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, EVP_GCM_TLS_TAG_LEN, tag)
        == 0)
    {
        EVP_CIPHER_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0,
                      "EVP_CIPHER_CTX_ctrl(EVP_CTRL_GCM_SET_TAG) failed");
        return NGX_ERROR;
    }

    if (EVP_DecryptFinal_ex(ctx, out->data + len, &len) <= 0) {
        EVP_CIPHER_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_DecryptFinal_ex failed");
        return NGX_ERROR;
    }

    out->len += len;

    EVP_CIPHER_CTX_free(ctx);
#endif

    return NGX_OK;
}


static ngx_int_t
ngx_quic_tls_seal(const ngx_quic_cipher_t *cipher, ngx_quic_secret_t *s,
    ngx_str_t *out, u_char *nonce, ngx_str_t *in, ngx_str_t *ad, ngx_log_t *log)
{

#ifdef OPENSSL_IS_BORINGSSL
    EVP_AEAD_CTX  *ctx;

    ctx = EVP_AEAD_CTX_new(cipher, s->key.data, s->key.len,
                           EVP_AEAD_DEFAULT_TAG_LENGTH);
    if (ctx == NULL) {
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_AEAD_CTX_new() failed");
        return NGX_ERROR;
    }

    if (EVP_AEAD_CTX_seal(ctx, out->data, &out->len, out->len, nonce, s->iv.len,
                          in->data, in->len, ad->data, ad->len)
        != 1)
    {
        EVP_AEAD_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_AEAD_CTX_seal() failed");
        return NGX_ERROR;
    }

    EVP_AEAD_CTX_free(ctx);
#else
    int              len;
    EVP_CIPHER_CTX  *ctx;

    ctx = EVP_CIPHER_CTX_new();
    if (ctx == NULL) {
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_CIPHER_CTX_new() failed");
        return NGX_ERROR;
    }

    if (EVP_EncryptInit_ex(ctx, cipher, NULL, NULL, NULL) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_EncryptInit_ex() failed");
        return NGX_ERROR;
    }

    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, s->iv.len, NULL)
        == 0)
    {
        EVP_CIPHER_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0,
                      "EVP_CIPHER_CTX_ctrl(EVP_CTRL_GCM_SET_IVLEN) failed");
        return NGX_ERROR;
    }

    if (EVP_EncryptInit_ex(ctx, NULL, NULL, s->key.data, nonce) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_EncryptInit_ex() failed");
        return NGX_ERROR;
    }

    if (EVP_EncryptUpdate(ctx, NULL, &len, ad->data, ad->len) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_EncryptUpdate() failed");
        return NGX_ERROR;
    }

    if (EVP_EncryptUpdate(ctx, out->data, &len, in->data, in->len) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_EncryptUpdate() failed");
        return NGX_ERROR;
    }

    out->len = len;

    if (EVP_EncryptFinal_ex(ctx, out->data + out->len, &len) <= 0) {
        EVP_CIPHER_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_EncryptFinal_ex failed");
        return NGX_ERROR;
    }

    out->len += len;

    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, EVP_GCM_TLS_TAG_LEN,
                            out->data + in->len)
        == 0)
    {
        EVP_CIPHER_CTX_free(ctx);
        ngx_ssl_error(NGX_LOG_INFO, log, 0,
                      "EVP_CIPHER_CTX_ctrl(EVP_CTRL_GCM_GET_TAG) failed");
        return NGX_ERROR;
    }

    EVP_CIPHER_CTX_free(ctx);

    out->len += EVP_GCM_TLS_TAG_LEN;
#endif
    return NGX_OK;
}


static ngx_int_t
ngx_quic_tls_hp(ngx_log_t *log, const EVP_CIPHER *cipher,
    ngx_quic_secret_t *s, u_char *out, u_char *in)
{
    int              outlen;
    EVP_CIPHER_CTX  *ctx;
    u_char           zero[NGX_QUIC_HP_LEN] = {0};

#ifdef OPENSSL_IS_BORINGSSL
    uint32_t         cnt;

    ngx_memcpy(&cnt, in, sizeof(uint32_t));

    if (cipher == (const EVP_CIPHER *) EVP_aead_chacha20_poly1305()) {
        CRYPTO_chacha_20(out, zero, NGX_QUIC_HP_LEN, s->hp.data, &in[4], cnt);
        return NGX_OK;
    }
#endif

    ctx = EVP_CIPHER_CTX_new();
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    if (EVP_EncryptInit_ex(ctx, cipher, NULL, s->hp.data, in) != 1) {
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_EncryptInit_ex() failed");
        goto failed;
    }

    if (!EVP_EncryptUpdate(ctx, out, &outlen, zero, NGX_QUIC_HP_LEN)) {
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_EncryptUpdate() failed");
        goto failed;
    }

    if (!EVP_EncryptFinal_ex(ctx, out + NGX_QUIC_HP_LEN, &outlen)) {
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "EVP_EncryptFinal_Ex() failed");
        goto failed;
    }

    EVP_CIPHER_CTX_free(ctx);

    return NGX_OK;

failed:

    EVP_CIPHER_CTX_free(ctx);

    return NGX_ERROR;
}


ngx_int_t
ngx_quic_keys_set_encryption_secret(ngx_log_t *log, ngx_uint_t is_write,
    ngx_quic_keys_t *keys, enum ssl_encryption_level_t level,
    const SSL_CIPHER *cipher, const uint8_t *secret, size_t secret_len)
{
    ngx_int_t            key_len;
    ngx_str_t            secret_str;
    ngx_uint_t           i;
    ngx_quic_secret_t   *peer_secret;
    ngx_quic_ciphers_t   ciphers;

    peer_secret = is_write ? &keys->secrets[level].server
                           : &keys->secrets[level].client;

    keys->cipher = SSL_CIPHER_get_id(cipher);

    key_len = ngx_quic_ciphers(keys->cipher, &ciphers, level);

    if (key_len == NGX_ERROR) {
        ngx_ssl_error(NGX_LOG_INFO, log, 0, "unexpected cipher");
        return NGX_ERROR;
    }

    if (sizeof(peer_secret->secret.data) < secret_len) {
        ngx_log_error(NGX_LOG_ALERT, log, 0,
                      "unexpected secret len: %uz", secret_len);
        return NGX_ERROR;
    }

    peer_secret->secret.len = secret_len;
    ngx_memcpy(peer_secret->secret.data, secret, secret_len);

    peer_secret->key.len = key_len;
    peer_secret->iv.len = NGX_QUIC_IV_LEN;
    peer_secret->hp.len = key_len;

    secret_str.len = secret_len;
    secret_str.data = (u_char *) secret;

    ngx_quic_hkdf_t seq[] = {
        ngx_quic_hkdf_set("tls13 quic key", &peer_secret->key, &secret_str),
        ngx_quic_hkdf_set("tls13 quic iv", &peer_secret->iv, &secret_str),
        ngx_quic_hkdf_set("tls13 quic hp", &peer_secret->hp, &secret_str),
    };

    for (i = 0; i < (sizeof(seq) / sizeof(seq[0])); i++) {
        if (ngx_quic_hkdf_expand(&seq[i], ciphers.d, log) != NGX_OK) {
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


ngx_uint_t
ngx_quic_keys_available(ngx_quic_keys_t *keys,
    enum ssl_encryption_level_t level)
{
    return keys->secrets[level].client.key.len != 0;
}


void
ngx_quic_keys_discard(ngx_quic_keys_t *keys,
    enum ssl_encryption_level_t level)
{
    keys->secrets[level].client.key.len = 0;
}


void
ngx_quic_keys_switch(ngx_connection_t *c, ngx_quic_keys_t *keys)
{
    ngx_quic_secrets_t  *current, *next, tmp;

    current = &keys->secrets[ssl_encryption_application];
    next = &keys->next_key;

    tmp = *current;
    *current = *next;
    *next = tmp;
}


ngx_int_t
ngx_quic_keys_update(ngx_connection_t *c, ngx_quic_keys_t *keys)
{
    ngx_uint_t           i;
    ngx_quic_ciphers_t   ciphers;
    ngx_quic_secrets_t  *current, *next;

    current = &keys->secrets[ssl_encryption_application];
    next = &keys->next_key;

    ngx_log_debug0(NGX_LOG_DEBUG_EVENT, c->log, 0, "quic key update");

    if (ngx_quic_ciphers(keys->cipher, &ciphers, ssl_encryption_application)
        == NGX_ERROR)
    {
        return NGX_ERROR;
    }

    next->client.secret.len = current->client.secret.len;
    next->client.key.len = current->client.key.len;
    next->client.iv.len = NGX_QUIC_IV_LEN;
    next->client.hp = current->client.hp;

    next->server.secret.len = current->server.secret.len;
    next->server.key.len = current->server.key.len;
    next->server.iv.len = NGX_QUIC_IV_LEN;
    next->server.hp = current->server.hp;

    ngx_quic_hkdf_t seq[] = {
        ngx_quic_hkdf_set("tls13 quic ku",
                          &next->client.secret, &current->client.secret),
        ngx_quic_hkdf_set("tls13 quic key",
                          &next->client.key, &next->client.secret),
        ngx_quic_hkdf_set("tls13 quic iv",
                          &next->client.iv, &next->client.secret),
        ngx_quic_hkdf_set("tls13 quic ku",
                          &next->server.secret, &current->server.secret),
        ngx_quic_hkdf_set("tls13 quic key",
                          &next->server.key, &next->server.secret),
        ngx_quic_hkdf_set("tls13 quic iv",
                          &next->server.iv, &next->server.secret),
    };

    for (i = 0; i < (sizeof(seq) / sizeof(seq[0])); i++) {
        if (ngx_quic_hkdf_expand(&seq[i], ciphers.d, c->log) != NGX_OK) {
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_quic_create_packet(ngx_quic_header_t *pkt, ngx_str_t *res)
{
    u_char              *pnp, *sample;
    ngx_str_t            ad, out;
    ngx_uint_t           i;
    ngx_quic_secret_t   *secret;
    ngx_quic_ciphers_t   ciphers;
    u_char               nonce[NGX_QUIC_IV_LEN], mask[NGX_QUIC_HP_LEN];

    ad.data = res->data;
    ad.len = ngx_quic_create_header(pkt, ad.data, &pnp);

    out.len = pkt->payload.len + EVP_GCM_TLS_TAG_LEN;
    out.data = res->data + ad.len;

#ifdef NGX_QUIC_DEBUG_CRYPTO
    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, pkt->log, 0,
                   "quic ad len:%uz %xV", ad.len, &ad);
#endif

    if (ngx_quic_ciphers(pkt->keys->cipher, &ciphers, pkt->level) == NGX_ERROR)
    {
        return NGX_ERROR;
    }

    secret = &pkt->keys->secrets[pkt->level].server;

    ngx_memcpy(nonce, secret->iv.data, secret->iv.len);
    ngx_quic_compute_nonce(nonce, sizeof(nonce), pkt->number);

    if (ngx_quic_tls_seal(ciphers.c, secret, &out,
                          nonce, &pkt->payload, &ad, pkt->log)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    sample = &out.data[4 - pkt->num_len];
    if (ngx_quic_tls_hp(pkt->log, ciphers.hp, secret, mask, sample)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    /* RFC 9001, 5.4.1.  Header Protection Application */
    ad.data[0] ^= mask[0] & ngx_quic_pkt_hp_mask(pkt->flags);

    for (i = 0; i < pkt->num_len; i++) {
        pnp[i] ^= mask[i + 1];
    }

    res->len = ad.len + out.len;

    return NGX_OK;
}


static ngx_int_t
ngx_quic_create_retry_packet(ngx_quic_header_t *pkt, ngx_str_t *res)
{
    u_char              *start;
    ngx_str_t            ad, itag;
    ngx_quic_secret_t    secret;
    ngx_quic_ciphers_t   ciphers;

    /* 5.8.  Retry Packet Integrity */
    static u_char     key[16] =
        "\xbe\x0c\x69\x0b\x9f\x66\x57\x5a\x1d\x76\x6b\x54\xe3\x68\xc8\x4e";
    static u_char     nonce[NGX_QUIC_IV_LEN] =
        "\x46\x15\x99\xd3\x5d\x63\x2b\xf2\x23\x98\x25\xbb";
    static ngx_str_t  in = ngx_string("");

    ad.data = res->data;
    ad.len = ngx_quic_create_retry_itag(pkt, ad.data, &start);

    itag.data = ad.data + ad.len;
    itag.len = EVP_GCM_TLS_TAG_LEN;

#ifdef NGX_QUIC_DEBUG_CRYPTO
    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, pkt->log, 0,
                   "quic retry itag len:%uz %xV", ad.len, &ad);
#endif

    if (ngx_quic_ciphers(0, &ciphers, pkt->level) == NGX_ERROR) {
        return NGX_ERROR;
    }

    secret.key.len = sizeof(key);
    ngx_memcpy(secret.key.data, key, sizeof(key));
    secret.iv.len = NGX_QUIC_IV_LEN;

    if (ngx_quic_tls_seal(ciphers.c, &secret, &itag, nonce, &in, &ad, pkt->log)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    res->len = itag.data + itag.len - start;
    res->data = start;

    return NGX_OK;
}


ngx_int_t
ngx_quic_derive_key(ngx_log_t *log, const char *label, ngx_str_t *secret,
    ngx_str_t *salt, u_char *out, size_t len)
{
    size_t         is_len, info_len;
    uint8_t       *p;
    const EVP_MD  *digest;

    uint8_t        is[SHA256_DIGEST_LENGTH];
    uint8_t        info[20];

    digest = EVP_sha256();
    is_len = SHA256_DIGEST_LENGTH;

    if (ngx_hkdf_extract(is, &is_len, digest, secret->data, secret->len,
                         salt->data, salt->len)
        != NGX_OK)
    {
        ngx_ssl_error(NGX_LOG_INFO, log, 0,
                      "ngx_hkdf_extract(%s) failed", label);
        return NGX_ERROR;
    }

    info[0] = 0;
    info[1] = len;
    info[2] = ngx_strlen(label);

    info_len = 2 + 1 + info[2] + 1;

    if (info_len >= 20) {
        ngx_log_error(NGX_LOG_INFO, log, 0,
                      "ngx_quic_create_key label \"%s\" too long", label);
        return NGX_ERROR;
    }

    p = ngx_cpymem(&info[3], label, info[2]);
    *p = '\0';

    if (ngx_hkdf_expand(out, len, digest, is, is_len, info, info_len) != NGX_OK)
    {
        ngx_ssl_error(NGX_LOG_INFO, log, 0,
                      "ngx_hkdf_expand(%s) failed", label);
        return NGX_ERROR;
    }

    return NGX_OK;
}


static uint64_t
ngx_quic_parse_pn(u_char **pos, ngx_int_t len, u_char *mask,
    uint64_t *largest_pn)
{
    u_char    *p;
    uint64_t   truncated_pn, expected_pn, candidate_pn;
    uint64_t   pn_nbits, pn_win, pn_hwin, pn_mask;

    pn_nbits = ngx_min(len * 8, 62);

    p = *pos;
    truncated_pn = *p++ ^ *mask++;

    while (--len) {
        truncated_pn = (truncated_pn << 8) + (*p++ ^ *mask++);
    }

    *pos = p;

    expected_pn = *largest_pn + 1;
    pn_win = 1ULL << pn_nbits;
    pn_hwin = pn_win / 2;
    pn_mask = pn_win - 1;

    candidate_pn = (expected_pn & ~pn_mask) | truncated_pn;

    if ((int64_t) candidate_pn <= (int64_t) (expected_pn - pn_hwin)
        && candidate_pn < (1ULL << 62) - pn_win)
    {
        candidate_pn += pn_win;

    } else if (candidate_pn > expected_pn + pn_hwin
               && candidate_pn >= pn_win)
    {
        candidate_pn -= pn_win;
    }

    *largest_pn = ngx_max((int64_t) *largest_pn, (int64_t) candidate_pn);

    return candidate_pn;
}


static void
ngx_quic_compute_nonce(u_char *nonce, size_t len, uint64_t pn)
{
    nonce[len - 4] ^= (pn & 0xff000000) >> 24;
    nonce[len - 3] ^= (pn & 0x00ff0000) >> 16;
    nonce[len - 2] ^= (pn & 0x0000ff00) >> 8;
    nonce[len - 1] ^= (pn & 0x000000ff);
}


ngx_int_t
ngx_quic_encrypt(ngx_quic_header_t *pkt, ngx_str_t *res)
{
    if (ngx_quic_pkt_retry(pkt->flags)) {
        return ngx_quic_create_retry_packet(pkt, res);
    }

    return ngx_quic_create_packet(pkt, res);
}


ngx_int_t
ngx_quic_decrypt(ngx_quic_header_t *pkt, uint64_t *largest_pn)
{
    u_char              *p, *sample;
    size_t               len;
    uint64_t             pn, lpn;
    ngx_int_t            pnl, rc, key_phase;
    ngx_str_t            in, ad;
    ngx_quic_secret_t   *secret;
    ngx_quic_ciphers_t   ciphers;
    uint8_t              nonce[NGX_QUIC_IV_LEN], mask[NGX_QUIC_HP_LEN];

    if (ngx_quic_ciphers(pkt->keys->cipher, &ciphers, pkt->level) == NGX_ERROR)
    {
        return NGX_ERROR;
    }

    secret = &pkt->keys->secrets[pkt->level].client;

    p = pkt->raw->pos;
    len = pkt->data + pkt->len - p;

    /*
     * RFC 9001, 5.4.2. Header Protection Sample
     *           5.4.3. AES-Based Header Protection
     *           5.4.4. ChaCha20-Based Header Protection
     *
     * the Packet Number field is assumed to be 4 bytes long
     * AES and ChaCha20 algorithms sample 16 bytes
     */

    if (len < EVP_GCM_TLS_TAG_LEN + 4) {
        return NGX_DECLINED;
    }

    sample = p + 4;

    /* header protection */

    if (ngx_quic_tls_hp(pkt->log, ciphers.hp, secret, mask, sample)
        != NGX_OK)
    {
        return NGX_DECLINED;
    }

    pkt->flags ^= mask[0] & ngx_quic_pkt_hp_mask(pkt->flags);

    if (ngx_quic_short_pkt(pkt->flags)) {
        key_phase = (pkt->flags & NGX_QUIC_PKT_KPHASE) != 0;

        if (key_phase != pkt->key_phase) {
            secret = &pkt->keys->next_key.client;
            pkt->key_update = 1;
        }
    }

    lpn = *largest_pn;

    pnl = (pkt->flags & 0x03) + 1;
    pn = ngx_quic_parse_pn(&p, pnl, &mask[1], &lpn);

    pkt->pn = pn;

    ngx_log_debug1(NGX_LOG_DEBUG_EVENT, pkt->log, 0,
                   "quic packet rx clearflags:%xd", pkt->flags);
    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, pkt->log, 0,
                   "quic packet rx number:%uL len:%xi", pn, pnl);

    /* packet protection */

    in.data = p;
    in.len = len - pnl;

    ad.len = p - pkt->data;
    ad.data = pkt->plaintext;

    ngx_memcpy(ad.data, pkt->data, ad.len);
    ad.data[0] = pkt->flags;

    do {
        ad.data[ad.len - pnl] = pn >> (8 * (pnl - 1)) % 256;
    } while (--pnl);

    ngx_memcpy(nonce, secret->iv.data, secret->iv.len);
    ngx_quic_compute_nonce(nonce, sizeof(nonce), pn);

#ifdef NGX_QUIC_DEBUG_CRYPTO
    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, pkt->log, 0,
                   "quic ad len:%uz %xV", ad.len, &ad);
#endif

    pkt->payload.len = in.len - EVP_GCM_TLS_TAG_LEN;
    pkt->payload.data = pkt->plaintext + ad.len;

    rc = ngx_quic_tls_open(ciphers.c, secret, &pkt->payload,
                           nonce, &in, &ad, pkt->log);
    if (rc != NGX_OK) {
        return NGX_DECLINED;
    }

    if (pkt->payload.len == 0) {
        /*
         * RFC 9000, 12.4.  Frames and Frame Types
         *
         * An endpoint MUST treat receipt of a packet containing no
         * frames as a connection error of type PROTOCOL_VIOLATION.
         */
        ngx_log_error(NGX_LOG_INFO, pkt->log, 0, "quic zero-length packet");
        pkt->error = NGX_QUIC_ERR_PROTOCOL_VIOLATION;
        return NGX_ERROR;
    }

    if (pkt->flags & ngx_quic_pkt_rb_mask(pkt->flags)) {
        /*
         * RFC 9000, Reserved Bits
         *
         * An endpoint MUST treat receipt of a packet that has
         * a non-zero value for these bits, after removing both
         * packet and header protection, as a connection error
         * of type PROTOCOL_VIOLATION.
         */
        ngx_log_error(NGX_LOG_INFO, pkt->log, 0,
                      "quic reserved bit set in packet");
        pkt->error = NGX_QUIC_ERR_PROTOCOL_VIOLATION;
        return NGX_ERROR;
    }

#if defined(NGX_QUIC_DEBUG_CRYPTO) && defined(NGX_QUIC_DEBUG_PACKETS)
    ngx_log_debug2(NGX_LOG_DEBUG_EVENT, pkt->log, 0,
                   "quic packet payload len:%uz %xV",
                   pkt->payload.len, &pkt->payload);
#endif

    *largest_pn = lpn;

    return NGX_OK;
}
