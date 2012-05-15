/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#include <nginx.h>
#include "ngx_http_lua_clfactory.h"


typedef struct {
    int sent_begin;
    int sent_end;
    int extraline;
    FILE *f;
    char buff[LUAL_BUFFERSIZE];
} clfactory_file_ctx_t;


typedef struct {
    int         sent_begin;
    int         sent_end;
    const char *s;
    size_t      size;

} clfactory_buffer_ctx_t;


static const char *clfactory_getF(lua_State *L, void *ud, size_t *size);
static int clfactory_errfile(lua_State *L, const char *what, int fname_index);
static const char *clfactory_getS(lua_State *L, void *ud, size_t *size);


int
ngx_http_lua_clfactory_loadfile(lua_State *L, const char *filename)
{
    clfactory_file_ctx_t        lf;
    int                         status, readstatus;
    int                         c;

    /* index of filename on the stack */
    int                         fname_index;

    fname_index = lua_gettop(L) + 1;

    lf.extraline = 0;

    if (filename == NULL) {
        lua_pushliteral(L, "=stdin");
        lf.f = stdin;

    } else {
        lua_pushfstring(L, "@%s", filename);
        lf.f = fopen(filename, "r");

        if (lf.f == NULL)
            return clfactory_errfile(L, "open", fname_index);
    }

    c = getc(lf.f);

    if (c == '#') {  /* Unix exec. file? */
        lf.extraline = 1;

        while ((c = getc(lf.f)) != EOF && c != '\n') {
            /* skip first line */
        }

        if (c == '\n') {
            c = getc(lf.f);
        }
    }

    if (c == LUA_SIGNATURE[0] && filename) {  /* binary file? */
        /* no binary file supported as closure factory code needs to be */
        /* compiled to bytecode along with user code */
        return clfactory_errfile(L, "load binary file", fname_index);
    }

    ungetc(c, lf.f);

    lf.sent_begin = lf.sent_end = 0;
    status = lua_load(L, clfactory_getF, &lf, lua_tostring(L, -1));

    readstatus = ferror(lf.f);

    if (filename)
        fclose(lf.f);  /* close file (even in case of errors) */

    if (readstatus) {
        lua_settop(L, fname_index);  /* ignore results from `lua_load' */
        return clfactory_errfile(L, "read", fname_index);
    }

    lua_remove(L, fname_index);

    return status;
}


int
ngx_http_lua_clfactory_loadstring(lua_State *L, const char *s)
{
    return ngx_http_lua_clfactory_loadbuffer(L, s, strlen(s), s);
}


int
ngx_http_lua_clfactory_loadbuffer(lua_State *L, const char *buff,
        size_t size, const char *name)
{
    clfactory_buffer_ctx_t ls;

    ls.s = buff;
    ls.size = size;
    ls.sent_begin = ls.sent_end = 0;

    return lua_load(L, clfactory_getS, &ls, name);
}


static const char *
clfactory_getF(lua_State *L, void *ud, size_t *size)
{
    clfactory_file_ctx_t        *lf;

    lf = (clfactory_file_ctx_t *) ud;

    if (lf->sent_begin == 0) {
        lf->sent_begin = 1;
        *size = CLFACTORY_BEGIN_SIZE;
        return CLFACTORY_BEGIN_CODE;
    }

    if (lf->extraline) {
        lf->extraline = 0;
        *size = 1;
        return "\n";
    }

    if (feof(lf->f)) {
        if (lf->sent_end == 0) {
            lf->sent_end = 1;
            *size = CLFACTORY_END_SIZE;
            return CLFACTORY_END_CODE;
        }

        return NULL;
    }

    *size = fread(lf->buff, 1, sizeof(lf->buff), lf->f);

    return (*size > 0) ? lf->buff : NULL;
}


static int
clfactory_errfile(lua_State *L, const char *what, int fname_index)
{
    const char      *serr;
    const char      *filename;

    serr = strerror(errno);
    filename = lua_tostring(L, fname_index) + 1;

    lua_pushfstring(L, "cannot %s %s: %s", what, filename, serr);
    lua_remove(L, fname_index);

    return LUA_ERRFILE;
}


static const char *
clfactory_getS(lua_State *L, void *ud, size_t *size)
{
    clfactory_buffer_ctx_t      *ls;

    ls = (clfactory_buffer_ctx_t *) ud;

    if (ls->sent_begin == 0) {
        ls->sent_begin = 1;
        *size = CLFACTORY_BEGIN_SIZE;

        return CLFACTORY_BEGIN_CODE;
    }

    if (ls->size == 0) {
        if (ls->sent_end == 0) {
            ls->sent_end = 1;
            *size = CLFACTORY_END_SIZE;
            return CLFACTORY_END_CODE;
        }

        return NULL;
    }

    *size = ls->size;
    ls->size = 0;

    return ls->s;
}

