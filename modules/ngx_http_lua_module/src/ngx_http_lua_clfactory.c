
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include <nginx.h>
#include "ngx_http_lua_clfactory.h"


#ifndef OPENRESTY_LUAJIT
#define CLFACTORY_BEGIN_CODE "return function() "
#define CLFACTORY_BEGIN_SIZE (sizeof(CLFACTORY_BEGIN_CODE) - 1)

#define CLFACTORY_END_CODE "\nend"
#define CLFACTORY_END_SIZE (sizeof(CLFACTORY_END_CODE) - 1)
#endif


/*
 * taken from chaoslawful:
 * Lua bytecode header        Luajit bytecode header
 * --------------              --------------
 * |  \033Lua   | 0-3          |  \033LJ    | 0-2
 * --------------              --------------
 * |    LuaC    | 4            |  bytecode  | 3
 * |   Version  |              |   version  |
 * --------------              --------------
 * |    LuaC    | 5            |  misc flag | 4 [F|S|B]
 * |   Format   |              --------------
 * --------------              |  chunkname | ULEB128 var-len
 * |   Endian   | 6            |     len    | encoded uint32
 * --------------              --------------
 * |   size of  | 7            |  chunkname |
 * |     int    |              |  str no \0 |
 * --------------              --------------
 * |   size of  | 8
 * |    size_t  |
 * --------------
 * |   size of  | 9
 * | instruction|
 * --------------
 * |   size of  | 10
 * |   number   |
 * --------------
 * |   number   | 11
 * |   is int?  |
 * --------------
*/


/*
 * CLOSURE 0 0 RETURN 0 2 RETURN 0 1
 * length(Instruction) = 4 or 8
 * little endian or big endian
*/
#ifndef OPENRESTY_LUAJIT
#define    LUA_LITTLE_ENDIAN_4BYTES_CODE                                     \
    "\x24\x00\x00\x00\x1e\x00\x00\x01\x1e\x00\x80\x00"
#define    LUA_LITTLE_ENDIAN_8BYTES_CODE                                     \
    "\x24\x00\x00\x00\x00\x00\x00\x00\x1e\x00\x00\x01"                       \
    "\x00\x00\x00\x00\x1e\x00\x80\x00\x00\x00\x00\x00"
#define    LUA_BIG_ENDIAN_4BYTES_CODE                                        \
    "\x00\x00\x00\x24\x01\x00\x00\x1e\x00\x08\x00\x1e"
#define    LUA_BIG_ENDIAN_8BYTES_CODE                                        \
    "\x00\x00\x00\x00\x00\x00\x00\x24\x00\x00\x00\x00"                       \
    "\x01\x00\x00\x1e\x00\x00\x00\x00\x00\x08\x00\x1e"
#define    LUA_LITTLE_ENDIAN_4BYTES_CODE_LEN        (4 + 4 + 4)
#define    LUA_LITTLE_ENDIAN_8BYTES_CODE_LEN        (8 + 8 + 8)
#define    LUA_BIG_ENDIAN_4BYTES_CODE_LEN           (4 + 4 + 4)
#define    LUA_BIG_ENDIAN_8BYTES_CODE_LEN           (8 + 8 + 8)
#define    LUAC_HEADERSIZE         12
#define    LUAC_VERSION            0x51
#endif /* OPENRESTY_LUAJIT */


/*
 * taken from chaoslawful:
 *  Lua Proto
 * ---------------------
 * | String            | Can be empty string
 * | [source]          | (stripped or internal function)
 * ---------------------
 * | Int               | At which line this function is defined
 * | [linedefined]     |
 * ---------------------
 * | Int               | At while line this function definition ended
 * | [lastlinedefined] |
 * ---------------------
 * | Char              | Number of upvalues referenced by this function
 * | [nups]            |
 * ---------------------
 * | Char              | Number of parameters of this function
 * | [numparams]       |
 * ---------------------
 * | Char              | Does this function has variable number of arguments?
 * | [is_var_arg]      | main function always set to VARARG_ISVARARG (2)
 * ---------------------
 * | Char              | Maximum stack size this function used
 * | [maxstacksize]    | Initially set to 2
 * ---------------------
 * | Vector(instr)     | Code instructions of this function
 * | [code]            |
 * ---------------------
 * | Int               | Number of constants referenced by this function
 * | [sizek]           |
 * ---------------------
 * | Char              | ------------------------------------
 * | type of [k[i]]    |  The type and content of constants |
 * ---------------------                                    |-> repeat for i in
 * | Char if boolean   |  No content part if type is NIL    |   [1..sizek]
 * | Number if number  | ------------------------------------
 * | String if string  |
 * ---------------------
 * | Int               | Number of internal functions
 * | [sizep]           |
 * ---------------------
 * | Function          | -> repeat for i in [1..sizep]
 * | at [p[i]]         |
 * ---------------------
 * | Vector            | Debug lineinfo vector
 * | [lineinfo]        | Empty vector here if debug info is stripped
 * ---------------------
 * | Int               | Number of local variable in this function
 * | [sizelocvars]     | 0 if debug info is stripped
 * ---------------------
 * | String            | ------------------------------------
 * | [locvars[i]]      |  Name of local var i               |
 * |  .varname]        |                                    |
 * ---------------------                                    |
 * | Int               |  instruction counter               |
 * | [locvars[i]]      |  where local var i start to be     |-> repeat for i in
 * |  .startpc]        |  referenced                        |  [0..sizelocvars]
 * ---------------------                                    |
 * | Int               |  instruction counter, where local  |
 * | [locvars[i]]      |  var i ceased to be referenced     |
 * |  .endpc]          | ------------------------------------
 * ---------------------
 * | Int               | Number of upvalues referenced by this function,
 * | [sizeupvalues]    | 0 if stripped
 * ---------------------
 * | String            | -> repeat for i in[0..sizeupvalues]
 * | [upvalues[i]]     |
 * ---------------------
*/

#ifndef OPENRESTY_LUAJIT
#define    POS_SOURCE_STR_LEN      LUAC_HEADERSIZE
#define    POS_START_LINE          (POS_SOURCE_STR_LEN + sizeof(size_t))
#define    POS_LAST_LINE           (POS_START_LINE + sizeof(int))
#define    POS_NUM_OF_UPVS         (POS_LAST_LINE + sizeof(int))
#define    POS_NUM_OF_PARA         (POS_NUM_OF_UPVS + sizeof(char))
#define    POS_IS_VAR_ARG          (POS_NUM_OF_PARA + sizeof(char))
#define    POS_MAX_STACK_SIZE      (POS_IS_VAR_ARG + sizeof(char))
#define    POS_NUM_OF_INST         (POS_MAX_STACK_SIZE +sizeof(char))
#define    POS_BYTECODE            (POS_NUM_OF_INST + sizeof(int))
#define    MAX_BEGIN_CODE_SIZE                                               \
    (POS_BYTECODE + LUA_LITTLE_ENDIAN_8BYTES_CODE_LEN                        \
    + sizeof(int) + sizeof(int))
#define    MAX_END_CODE_SIZE       (sizeof(int) + sizeof(int) + sizeof(int))
#endif /* OPENRESTY_LUAJIT */

/*
 * taken from chaoslawful:
 * Luajit bytecode format
 * ---------------------
 * | HEAD              | Luajit bytecode head
 * ---------------------
 * | Internal          | All internal functions
 * | functions         |
 * ---------------------
 * | ULEB128           | Rest data total length of this function
 * | [Date len of      | (not include itself)
 * |  this function]   |
 * ---------------------
 * | Char              | F(ffi) | V(vararg)| C(has internal funcs)
 * | [func flag]       |
 * ---------------------
 * | Char              | Number of parameters of this function
 * | [numparams]       |
 * ---------------------
 * | Char              |
 * | [framesize]       |
 * ---------------------
 * | Char              | Number of upvalues referenced by this function
 * | [sizeupvalues]    |
 * ---------------------
 * | ULEB128           | Number of collectable constants referenced
 * | [sizekgc]         | by this function
 * ---------------------
 * | ULEB128           | Number of lua number constants referenced
 * | [sizekn]          | by this function
 * ---------------------
 * | ULEB128           | Number of bytecode instructions of this function
 * | [sizebc]m1        | minus 1 to omit the BC_FUNCV/BC_FUNCF header bytecode
 * ---------------------
 * | ULEB128           |
 * | [size of dbg      | Size of debug lineinfo map, available when not stripped
 * |  lineinfo]        |
 * ---------------------
 * | ULEB128           | Available when not stripped
 * | [firstline]       | The first line of this function's definition
 * ---------------------
 * | ULEB128           | Available when not stripped
 * | [numline]         | The number of lines of this function's definition
 * ---------------------
 * | [bytecode]        | Bytecode instructions of this function
 * ---------------------
 * |[upvalue ref slots]| [sizeupvalues] * 2
 * ---------------------
 * | [collectable      | [sizekgc] elems, variable length
 * |  constants]       |
 * ---------------------
 * | [lua number       | [sizekn] elems, variable length
 * |  constants]       |
 * ---------------------
 * | [debug lineinfo   | Length is the calculated size of debug lineinfo above
 * |                   | Only available if not stripped
 * ---------------------
 * | Char              |
 * | [\x00]            | Footer
 * ---------------------
*/

/* bytecode for luajit 2.0 */

#ifndef OPENRESTY_LUAJIT
#define    LJ20_LITTLE_ENDIAN_CODE_STRIPPED                                  \
    "\x14\x03\x00\x01\x00\x01\x00\x03"                                       \
    "\x31\x00\x00\x00\x30\x00\x00\x80\x48\x00\x02\x00"                       \
    "\x00\x00"

#define    LJ20_BIG_ENDIAN_CODE_STRIPPED                                     \
    "\x14\x03\x00\x01\x00\x01\x00\x03"                                       \
    "\x00\x00\x00\x31\x80\x00\x00\x30\x00\x02\x00\x48"                       \
    "\x00\x00"

#define    LJ20_LITTLE_ENDIAN_CODE                                           \
    "\x15\x03\x00\x01\x00\x01\x00\x03\x00"                                   \
    "\x31\x00\x00\x00\x30\x00\x00\x80\x48\x00\x02\x00"                       \
    "\x00\x00"

#define    LJ20_BIG_ENDIAN_CODE                                              \
    "\x15\x03\x00\x01\x00\x01\x00\x03\x00"                                   \
    "\x00\x00\x00\x31\x80\x00\x00\x30\x00\x02\x00\x48"                       \
    "\x00\x00"

/* bytecode for luajit 2.1 */

#define    LJ21_LITTLE_ENDIAN_CODE_STRIPPED                                  \
    "\x14\x03\x00\x01\x00\x01\x00\x03"                                       \
    "\x33\x00\x00\x00\x32\x00\x00\x80\x4c\x00\x02\x00"                       \
    "\x00\x00"

#define    LJ21_BIG_ENDIAN_CODE_STRIPPED                                     \
    "\x14\x03\x00\x01\x00\x01\x00\x03"                                       \
    "\x00\x00\x00\x33\x80\x00\x00\x32\x00\x02\x00\x4c"                       \
    "\x00\x00"

#define    LJ21_LITTLE_ENDIAN_CODE                                           \
    "\x15\x03\x00\x01\x00\x01\x00\x03\x00"                                   \
    "\x33\x00\x00\x00\x32\x00\x00\x80\x4c\x00\x02\x00"                       \
    "\x00\x00"

#define    LJ21_BIG_ENDIAN_CODE                                              \
    "\x15\x03\x00\x01\x00\x01\x00\x03\x00"                                   \
    "\x00\x00\x00\x33\x80\x00\x00\x32\x00\x02\x00\x4c"                       \
    "\x00\x00"

#define    LJ_CODE_LEN              23
#define    LJ_CODE_LEN_STRIPPED     22
#define    LJ_HEADERSIZE            5
#define    LJ_BCDUMP_F_BE           0x01
#define    LJ_BCDUMP_F_STRIP        0x02
#define    LJ21_BCDUMP_VERSION        2
#define    LJ20_BCDUMP_VERSION        1
#define    LJ_SIGNATURE             "\x1b\x4c\x4a"
#endif /* OPENRESTY_LUAJIT */


typedef enum {
    NGX_LUA_TEXT_FILE,
    NGX_LUA_BT_LUA,
    NGX_LUA_BT_LJ,
} ngx_http_lua_clfactory_file_type_e;


enum {
    NGX_LUA_READER_BUFSIZE = 4096,
};


typedef struct {
    ngx_http_lua_clfactory_file_type_e file_type;

    int         extraline;
    FILE       *f;
#ifndef OPENRESTY_LUAJIT
    int         sent_begin;
    int         sent_end;
    size_t      begin_code_len;
    size_t      end_code_len;
    size_t      rest_len;
    union {
        char   *ptr;
        char    str[MAX_BEGIN_CODE_SIZE];
    }           begin_code;
    union {
        char   *ptr;
        char    str[MAX_END_CODE_SIZE];
    }           end_code;
#endif /* OPENRESTY_LUAJIT */
    char        buff[NGX_LUA_READER_BUFSIZE];
} ngx_http_lua_clfactory_file_ctx_t;


typedef struct {
#ifndef OPENRESTY_LUAJIT
    int         sent_begin;
    int         sent_end;
#endif
    const char *s;
    size_t      size;
} ngx_http_lua_clfactory_buffer_ctx_t;


static const char *ngx_http_lua_clfactory_getF(lua_State *L, void *ud,
    size_t *size);
static int ngx_http_lua_clfactory_errfile(lua_State *L, const char *what,
    int fname_index);
static const char *ngx_http_lua_clfactory_getS(lua_State *L, void *ud,
    size_t *size);
#ifndef OPENRESTY_LUAJIT
static long ngx_http_lua_clfactory_file_size(FILE *f);
#endif


#ifndef OPENRESTY_LUAJIT
int
ngx_http_lua_clfactory_bytecode_prepare(lua_State *L,
    ngx_http_lua_clfactory_file_ctx_t *lf, int fname_index)
{
    int                 x = 1, size_of_int, size_of_size_t, little_endian,
                        size_of_inst, version, stripped;
    static int          num_of_inst = 3, num_of_inter_func = 1;
    const char         *emsg, *serr, *bytecode;
    size_t              size, bytecode_len;
    long                fsize;

    serr = NULL;

    *lf->begin_code.str = LUA_SIGNATURE[0];

    if (lf->file_type == NGX_LUA_BT_LJ) {
        size = fread(lf->begin_code.str + 1, 1, LJ_HEADERSIZE - 1, lf->f);

        if (size != LJ_HEADERSIZE - 1) {
            serr = strerror(errno);
            emsg = "cannot read header";
            goto error;
        }

        version = *(lf->begin_code.str + 3);

        dd("version: %d", (int) version);

        if (ngx_memcmp(lf->begin_code.str, LJ_SIGNATURE,
                       sizeof(LJ_SIGNATURE) - 1))
        {
            emsg = "bad byte-code header";
            goto error;
        }

#if defined(DDEBUG) && (DDEBUG)
        {
            dd("==LJ_BT_HEADER==");
            size_t i;
            for (i = 0; i < LJ_HEADERSIZE; i++) {
                dd("%ld: 0x%02X", i, (unsigned)(u_char) lf->begin_code.str[i]);
            }
            dd("==LJ_BT_HEADER_END==");
        }
#endif

        lf->begin_code_len = LJ_HEADERSIZE;
        little_endian = !((*(lf->begin_code.str + 4)) & LJ_BCDUMP_F_BE);
        stripped = (*(lf->begin_code.str + 4)) & LJ_BCDUMP_F_STRIP;

        dd("stripped: %d", (int) stripped);

        if (version == LJ21_BCDUMP_VERSION) {
            if (stripped) {
                if (little_endian) {
                    lf->end_code.ptr = LJ21_LITTLE_ENDIAN_CODE_STRIPPED;

                } else {
                    lf->end_code.ptr = LJ21_BIG_ENDIAN_CODE_STRIPPED;
                }

                lf->end_code_len = LJ_CODE_LEN_STRIPPED;

            } else {
                if (little_endian) {
                    lf->end_code.ptr = LJ21_LITTLE_ENDIAN_CODE;

                } else {
                    lf->end_code.ptr = LJ21_BIG_ENDIAN_CODE;
                }

                lf->end_code_len = LJ_CODE_LEN;
            }

        } else if (version == LJ20_BCDUMP_VERSION) {
            if (stripped) {
                if (little_endian) {
                    lf->end_code.ptr = LJ20_LITTLE_ENDIAN_CODE_STRIPPED;

                } else {
                    lf->end_code.ptr = LJ20_BIG_ENDIAN_CODE_STRIPPED;
                }

                lf->end_code_len = LJ_CODE_LEN_STRIPPED;

            } else {
                if (little_endian) {
                    lf->end_code.ptr = LJ20_LITTLE_ENDIAN_CODE;

                } else {
                    lf->end_code.ptr = LJ20_BIG_ENDIAN_CODE;
                }

                lf->end_code_len = LJ_CODE_LEN;
            }

        } else {
            emsg = "bytecode format version unsupported";
            goto error;
        }

        fsize = ngx_http_lua_clfactory_file_size(lf->f);
        if (fsize < 0) {
            serr = strerror(errno);
            emsg = "cannot fseek/ftell";
            goto error;
        }

        lf->rest_len = fsize - LJ_HEADERSIZE;

#if defined(DDEBUG) && (DDEBUG)
        {
        size_t i = 0;
        dd("==LJ_END_CODE: %ld rest_len: %ld==", lf->end_code_len,
           lf->rest_len);

        for (i = 0; i < lf->end_code_len; i++) {
            dd("%ld: 0x%02X", i, (unsigned) ((u_char) lf->end_code.ptr[i]));
        }
        dd("==LJ_END_CODE_END==");
        }
#endif

    } else {
        size = fread(lf->begin_code.str + 1, 1, LUAC_HEADERSIZE - 1, lf->f);

        if (size != LUAC_HEADERSIZE - 1) {
            serr = strerror(errno);
            emsg = "cannot read header";
            goto error;
        }

        version = *(lf->begin_code.str + 4);
        little_endian = *(lf->begin_code.str + 6);
        size_of_int = *(lf->begin_code.str + 7);
        size_of_size_t = *(lf->begin_code.str + 8);
        size_of_inst = *(lf->begin_code.str + 9);

#if defined(DDEBUG) && (DDEBUG)
        {
        dd("==LUA_BT_HEADER==");
        size_t i;
        for (i = 0; i < LUAC_HEADERSIZE; i++) {
            dd("%ld, 0x%02X", i, (unsigned)(u_char) lf->begin_code.str[i]);
        }
        dd("==LUA_BT_HEADER_END==");
        }
#endif

        if (ngx_memcmp(lf->begin_code.str, LUA_SIGNATURE,
                       sizeof(LUA_SIGNATURE) -1)
            || version != LUAC_VERSION
            || little_endian != (int) (*(char *) &x)
            || size_of_int != sizeof(int)
            || size_of_size_t != sizeof(size_t)
            || (size_of_inst != 4 && size_of_inst != 8))
        {
            emsg = "bad byte-code header";
            goto error;
        }

        /* clear the following fields to zero:
         * - source string length
         * - start line
         * - last line
         */
        ngx_memzero(lf->begin_code.str + POS_SOURCE_STR_LEN,
                    sizeof(size_t) + sizeof(int) * 2);
        /* number of upvalues */
        *(lf->begin_code.str + POS_NUM_OF_UPVS) = 0;
        /* number of parameters */
        *(lf->begin_code.str + POS_NUM_OF_PARA) = 0;
        /* is var-argument function? */
        *(lf->begin_code.str + POS_IS_VAR_ARG) = 2;
        /* max stack size */
        *(lf->begin_code.str + POS_MAX_STACK_SIZE) = 2;
        /* number of bytecode instructions */
        ngx_memcpy(lf->begin_code.str + POS_NUM_OF_INST, &num_of_inst,
                   sizeof(int));

        lf->begin_code_len = POS_BYTECODE;

        if (little_endian) {
            if (size_of_inst == 4) {
                bytecode = LUA_LITTLE_ENDIAN_4BYTES_CODE;
                bytecode_len = LUA_LITTLE_ENDIAN_4BYTES_CODE_LEN;

            } else {
                bytecode = LUA_LITTLE_ENDIAN_8BYTES_CODE;
                bytecode_len = LUA_LITTLE_ENDIAN_8BYTES_CODE_LEN;
            }

        } else {
            if (size_of_inst == 4) {
                bytecode = LUA_BIG_ENDIAN_4BYTES_CODE;
                bytecode_len = LUA_BIG_ENDIAN_4BYTES_CODE_LEN;

            } else {
                bytecode = LUA_BIG_ENDIAN_8BYTES_CODE;
                bytecode_len = LUA_BIG_ENDIAN_8BYTES_CODE_LEN;
            }
        }

        /* bytecode */
        ngx_memcpy(lf->begin_code.str + POS_BYTECODE, bytecode, bytecode_len);

        /* number of consts */
        ngx_memzero(lf->begin_code.str + POS_BYTECODE + bytecode_len,
                    sizeof(int));
        /* number of internal functions */
        ngx_memcpy(lf->begin_code.str + POS_BYTECODE + bytecode_len
                   + sizeof(int), &num_of_inter_func, sizeof(int));

        lf->begin_code_len += bytecode_len + sizeof(int) + sizeof(int);

#if defined(DDEBUG) && (DDEBUG)
        {
        size_t i = 0;
        dd("==LUA_BEGIN_CODE: %ld==", lf->begin_code_len);
        for (i = 0; i < lf->begin_code_len; i++) {
            dd("%ld: 0x%02X", i, (unsigned) ((u_char) lf->begin_code.str[i]));
        }
        dd("==LUA_BEGIN_CODE_END==");
        }
#endif

        /* clear the following fields to zero:
         * - lineinfo vector size
         * - number of local vars
         * - number of upvalues
         */
        ngx_memzero(lf->end_code.str, sizeof(int) * 3);

        lf->end_code_len = sizeof(int) + sizeof(int) + sizeof(int);

#if defined(DDEBUG) && (DDEBUG)
        {
        size_t i = 0;
        dd("==LUA_END_CODE: %ld==", lf->end_code_len);
        for (i = 0; i < lf->end_code_len; i++) {
            dd("%ld: 0x%02X", i, (unsigned) ((u_char) lf->end_code.str[i]));
        }
        dd("==LUA_END_CODE_END==");
        }
#endif

    }

    return 0;

error:

    fclose(lf->f);  /* close file (even in case of errors) */

    if (serr) {
        lua_pushfstring(L, "%s: %s", emsg, serr);

    } else {
        lua_pushstring(L, emsg);
    }

    lua_remove(L, fname_index);

    return LUA_ERRFILE;
}
#endif /* OPENRESTY_LUAJIT */


ngx_int_t
ngx_http_lua_clfactory_loadfile(lua_State *L, const char *filename)
{
    int                         c, status, readstatus;
    ngx_flag_t                  sharp;

    ngx_http_lua_clfactory_file_ctx_t        lf;

    /* index of filename on the stack */
    int                         fname_index;

    sharp = 0;
    fname_index = lua_gettop(L) + 1;

    lf.extraline = 0;
    lf.file_type = NGX_LUA_TEXT_FILE;

#ifndef OPENRESTY_LUAJIT
    lf.begin_code.ptr = CLFACTORY_BEGIN_CODE;
    lf.begin_code_len = CLFACTORY_BEGIN_SIZE;
    lf.end_code.ptr = CLFACTORY_END_CODE;
    lf.end_code_len = CLFACTORY_END_SIZE;
#endif

    lua_pushfstring(L, "@%s", filename);

    lf.f = fopen(filename, "r");
    if (lf.f == NULL) {
        return ngx_http_lua_clfactory_errfile(L, "open", fname_index);
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

        sharp = 1;
    }

    if (c == LUA_SIGNATURE[0] && filename) {  /* binary file? */
        lf.f = freopen(filename, "rb", lf.f);  /* reopen in binary mode */

        if (lf.f == NULL) {
            return ngx_http_lua_clfactory_errfile(L, "reopen", fname_index);
        }

        /* check whether lib jit exists */
        luaL_findtable(L, LUA_REGISTRYINDEX, "_LOADED", 1);
        lua_getfield(L, -1, "jit");  /* get _LOADED["jit"] */

        if (lua_istable(L, -1)) {
            lf.file_type = NGX_LUA_BT_LJ;

        } else {
            lf.file_type = NGX_LUA_BT_LUA;
        }

        lua_pop(L, 2);

        /*
         * Loading bytecode with an extra header is disabled for security
         * reasons. This may circumvent the usual check for bytecode vs.
         * Lua code by looking at the first char. Since this is a potential
         * security violation no attempt is made to echo the chunkname either.
         */
        if (lf.file_type == NGX_LUA_BT_LJ && sharp) {

            if (filename) {
                fclose(lf.f);  /* close file (even in case of errors) */
            }

            filename = lua_tostring(L, fname_index) + 1;
            lua_pushfstring(L, "bad byte-code header in %s", filename);
            lua_remove(L, fname_index);

            return LUA_ERRFILE;
        }

        while ((c = getc(lf.f)) != EOF && c != LUA_SIGNATURE[0]) {
            /* skip eventual `#!...' */
        }

#ifndef OPENRESTY_LUAJIT
        status = ngx_http_lua_clfactory_bytecode_prepare(L, &lf, fname_index);

        if (status != 0) {
            return status;
        }
#endif

        lf.extraline = 0;
    }

#ifndef OPENRESTY_LUAJIT
    if (lf.file_type == NGX_LUA_TEXT_FILE) {
        ungetc(c, lf.f);
    }

    lf.sent_begin = lf.sent_end = 0;

#else
    ungetc(c, lf.f);
#endif
    status = lua_load(L, ngx_http_lua_clfactory_getF, &lf,
                      lua_tostring(L, -1));

    readstatus = ferror(lf.f);

    if (filename) {
        fclose(lf.f);  /* close file (even in case of errors) */
    }

    if (readstatus) {
        lua_settop(L, fname_index);  /* ignore results from `lua_load' */
        return ngx_http_lua_clfactory_errfile(L, "read", fname_index);
    }

    lua_remove(L, fname_index);

    return status;
}


ngx_int_t
ngx_http_lua_clfactory_loadbuffer(lua_State *L, const char *buff,
    size_t size, const char *name)
{
    ngx_http_lua_clfactory_buffer_ctx_t     ls;

    ls.s = buff;
    ls.size = size;
#ifndef OPENRESTY_LUAJIT
    ls.sent_begin = 0;
    ls.sent_end = 0;
#endif

    return lua_load(L, ngx_http_lua_clfactory_getS, &ls, name);
}


static const char *
ngx_http_lua_clfactory_getF(lua_State *L, void *ud, size_t *size)
{
#ifndef OPENRESTY_LUAJIT
    char                        *buf;
#endif
    size_t                       num;

    ngx_http_lua_clfactory_file_ctx_t        *lf;

    lf = (ngx_http_lua_clfactory_file_ctx_t *) ud;

    if (lf->extraline) {
        lf->extraline = 0;
        *size = 1;
        return "\n";
    }

#ifndef OPENRESTY_LUAJIT
    if (lf->sent_begin == 0) {
        lf->sent_begin = 1;
        *size = lf->begin_code_len;

        if (lf->file_type == NGX_LUA_TEXT_FILE) {
            buf = lf->begin_code.ptr;

        } else {
            buf = lf->begin_code.str;
        }

        return buf;
    }
#endif /* OPENRESTY_LUAJIT */

    num = fread(lf->buff, 1, sizeof(lf->buff), lf->f);

    dd("fread returned %d", (int) num);

    if (num == 0) {
#ifndef OPENRESTY_LUAJIT
        if (lf->sent_end == 0) {
            lf->sent_end = 1;
            *size = lf->end_code_len;

            if (lf->file_type == NGX_LUA_BT_LUA) {
                buf = lf->end_code.str;

            } else {
                buf = lf->end_code.ptr;
            }

            return buf;
        }
#endif /* OPENRESTY_LUAJIT */

        *size = 0;
        return NULL;
    }

#ifndef OPENRESTY_LUAJIT
    if (lf->file_type == NGX_LUA_BT_LJ) {
        /* skip the footer(\x00) in luajit */

        lf->rest_len -= num;

        if (lf->rest_len == 0) {
            if (--num == 0 && lf->sent_end == 0) {
                lf->sent_end = 1;
                buf = lf->end_code.ptr;
                *size = lf->end_code_len;

                return buf;
            }
        }
    }
#endif /* OPENRESTY_LUAJIT */

    *size = num;
    return lf->buff;
}


static int
ngx_http_lua_clfactory_errfile(lua_State *L, const char *what, int fname_index)
{
    const char      *serr;
    const char      *filename;

    filename = lua_tostring(L, fname_index) + 1;

    if (errno) {
        serr = strerror(errno);
        lua_pushfstring(L, "cannot %s %s: %s", what, filename, serr);

    } else {
        lua_pushfstring(L, "cannot %s %s", what, filename);
    }

    lua_remove(L, fname_index);

    return LUA_ERRFILE;
}


static const char *
ngx_http_lua_clfactory_getS(lua_State *L, void *ud, size_t *size)
{
    ngx_http_lua_clfactory_buffer_ctx_t      *ls = ud;

#ifndef OPENRESTY_LUAJIT
    if (ls->sent_begin == 0) {
        ls->sent_begin = 1;
        *size = CLFACTORY_BEGIN_SIZE;

        return CLFACTORY_BEGIN_CODE;
    }
#endif

    if (ls->size == 0) {
#ifndef OPENRESTY_LUAJIT
        if (ls->sent_end == 0) {
            ls->sent_end = 1;
            *size = CLFACTORY_END_SIZE;
            return CLFACTORY_END_CODE;
        }
#endif

        return NULL;
    }

    *size = ls->size;
    ls->size = 0;

    return ls->s;
}


#ifndef OPENRESTY_LUAJIT
static long
ngx_http_lua_clfactory_file_size(FILE *f)
{
    long              cur_pos, len;

    cur_pos = ftell(f);
    if (cur_pos == -1) {
        return -1;
    }

    if (fseek(f, 0, SEEK_END) != 0) {
        return -1;
    }

    len = ftell(f);
    if (len == -1) {
        return -1;
    }

    if (fseek(f, cur_pos, SEEK_SET) != 0) {
        return -1;
    }

    return len;
}
#endif /* OPENRESTY_LUAJIT */


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
