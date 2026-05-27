/**
 *  Copyright (C) 2018 Masatoshi Teruya
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to
 *  deal in the Software without restriction, including without limitation the
 *  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 *  sell copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 *  IN THE SOFTWARE.
 *
 *  src/parse.c
 *  lua-net-http
 *  Created by Masatoshi Teruya on 18/06/04.
 */

// project
#include "hwire.h"
// depend
#include "lauxhlib.h"
#include "lua_error.h"
// lua
#include <lauxlib.h>
// system
#include <limits.h>
#include <stdint.h>
#include <string.h>

/**
 * return code: values aligned with HWIRE_* for direct passthrough
 */
#define PARSE_OK       HWIRE_OK        //  0
#define PARSE_EAGAIN   HWIRE_EAGAIN    // -1
#define PARSE_ELEN     HWIRE_ELEN      // -2
#define PARSE_EMETHOD  HWIRE_EMETHOD   // -3
#define PARSE_EVERSION HWIRE_EVERSION  // -4
#define PARSE_EEOL     HWIRE_EEOL      // -5
#define PARSE_EHDRNAME HWIRE_EHDRNAME  // -6
#define PARSE_EHDRVAL  HWIRE_EHDRVALUE // -7
#define PARSE_EHDRLEN  HWIRE_EHDRLEN   // -8
#define PARSE_ESTATUS  HWIRE_ESTATUS   // -9
#define PARSE_EILSEQ   HWIRE_EILSEQ    // -10
#define PARSE_ERANGE   HWIRE_ERANGE    // -11
#define PARSE_EEMPTY   HWIRE_EEXTNAME  // -12
#define PARSE_EHDRNUM  HWIRE_ENOBUFS   // -14
#define PARSE_EURI     HWIRE_EURI      // -17
#define PARSE_EMSG     -100            // no HWIRE equivalent
static int PARSE_ERR_EAGAIN   = LUA_NOREF;
static int PARSE_ERR_EMSG     = LUA_NOREF;
static int PARSE_ERR_ELEN     = LUA_NOREF;
static int PARSE_ERR_EMETHOD  = LUA_NOREF;
static int PARSE_ERR_EVERSION = LUA_NOREF;
static int PARSE_ERR_EEOL     = LUA_NOREF;
static int PARSE_ERR_EHDRNAME = LUA_NOREF;
static int PARSE_ERR_EHDRVAL  = LUA_NOREF;
static int PARSE_ERR_EHDRLEN  = LUA_NOREF;
static int PARSE_ERR_EHDRNUM  = LUA_NOREF;
static int PARSE_ERR_ESTATUS  = LUA_NOREF;
static int PARSE_ERR_EILSEQ   = LUA_NOREF;
static int PARSE_ERR_ERANGE   = LUA_NOREF;
static int PARSE_ERR_EEMPTY   = LUA_NOREF;
static int PARSE_ERR_EURI     = LUA_NOREF;

static void init_error_types(lua_State *L)
{
    int nameidx = lua_gettop(L) + 1;

    lua_error_loadlib(L, 1);

#define create_error_type(name, message)                                       \
    do {                                                                       \
        lua_pushstring(L, "net.http.parse." #name);                            \
        lua_pushinteger(L, PARSE_##name);                                      \
        lua_pushstring(L, (message));                                          \
        lua_error_new_type(L, nameidx);                                        \
        PARSE_ERR_##name = lauxh_ref(L);                                       \
    } while (0)

    create_error_type(EAGAIN, "resource temporarily unavailable");
    create_error_type(EMSG, "invalid message");
    create_error_type(ELEN, "length too large");
    create_error_type(EMETHOD, "method not implemented");
    create_error_type(EVERSION, "version not supported");
    create_error_type(EEOL, "invalid end-of-line terminator");
    create_error_type(EHDRNAME, "invalid header field-name");
    create_error_type(EHDRVAL, "invalid header field-val");
    create_error_type(EHDRLEN, "header-length too large");
    create_error_type(EHDRNUM, "too many headers");
    create_error_type(ESTATUS, "invalid status code");
    create_error_type(EILSEQ, "illegal byte sequence");
    create_error_type(ERANGE, "result too large");
    create_error_type(EEMPTY, "disallow empty definitions");
    create_error_type(EURI, "invalid URI character");

#undef create_error_type
}

static int error_result_ex(lua_State *L, int err, const char *op, int as_bool)
{
    int typeidx = 2;

    lua_settop(L, 0);
    if (as_bool) {
        lua_pushboolean(L, 0);
    } else {
        lua_pushnil(L);
    }

    switch (err) {
    case PARSE_EAGAIN:
        lauxh_pushref(L, PARSE_ERR_EAGAIN);
        break;
    case PARSE_EMSG:
        lauxh_pushref(L, PARSE_ERR_EMSG);
        break;
    case PARSE_ELEN:
        lauxh_pushref(L, PARSE_ERR_ELEN);
        break;
    case PARSE_EMETHOD:
        lauxh_pushref(L, PARSE_ERR_EMETHOD);
        break;
    case PARSE_EVERSION:
        lauxh_pushref(L, PARSE_ERR_EVERSION);
        break;
    case PARSE_EEOL:
        lauxh_pushref(L, PARSE_ERR_EEOL);
        break;
    case PARSE_EHDRNAME:
        lauxh_pushref(L, PARSE_ERR_EHDRNAME);
        break;
    case PARSE_EHDRVAL:
        lauxh_pushref(L, PARSE_ERR_EHDRVAL);
        break;
    case PARSE_EHDRLEN:
        lauxh_pushref(L, PARSE_ERR_EHDRLEN);
        break;
    case PARSE_EHDRNUM:
        lauxh_pushref(L, PARSE_ERR_EHDRNUM);
        break;
    case PARSE_ESTATUS:
        lauxh_pushref(L, PARSE_ERR_ESTATUS);
        break;
    case PARSE_EILSEQ:
        lauxh_pushref(L, PARSE_ERR_EILSEQ);
        break;
    case PARSE_ERANGE:
        lauxh_pushref(L, PARSE_ERR_ERANGE);
        break;
    case PARSE_EEMPTY:
        lauxh_pushref(L, PARSE_ERR_EEMPTY);
        break;
    case HWIRE_EEXTVAL: // invalid extension value → EILSEQ
        lauxh_pushref(L, PARSE_ERR_EILSEQ);
        break;
    case HWIRE_EKEYLEN: // key length exceeded → EHDRLEN
        lauxh_pushref(L, PARSE_ERR_EHDRLEN);
        break;
    case PARSE_EURI:
        lauxh_pushref(L, PARSE_ERR_EURI);
        break;

    default:
        return luaL_error(L, "unknown errtype %d", err);
    }

    if (op) {
        lua_pushnil(L);
        lua_pushstring(L, op);
        lua_error_new_message(L, typeidx + 1);
    }
    lua_error_new_typed_error(L, typeidx);
    return 2;
}
#define error_result_as_false(L, err, op) error_result_ex(L, err, op, 1)
#define error_result_as_nil(L, err, op)   error_result_ex(L, err, op, 0)

typedef struct {
    lua_State *L;
    int tblidx;
    int error;
    int nhdr;
    int request_line_parsed;
    uint64_t chunksize;
    size_t maxmsglen;
    size_t maxhdrlen;
} parse_cb_ctx_t;

static inline double hwire_version_to_double(uint16_t ver)
{
    return (ver >> 8) + (ver & 0xff) * 0.1;
}

/* delimiters */
#define CR        '\r'
#define LF        '\n'
#define HT        '\t'
#define SP        ' '
#define EQ        '='
#define COLON     ':'
#define SEMICOLON ';'
#define DQUOTE    '"'
#define BACKSLASH '\\'

#define DEFAULT_STR_MAXLEN 4096

static int tchar_lua(lua_State *L)
{
    size_t len      = 0;
    const char *str = lauxh_checklstring(L, 1, &len);
    size_t pos      = 0;

    if (!len) {
        return error_result_as_false(L, PARSE_EAGAIN, "tchar");
    } else if (hwire_parse_tchar(str, len, &pos) != len) {
        return error_result_as_false(L, PARSE_EILSEQ, "tchar");
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int vchar_lua(lua_State *L)
{
    size_t len      = 0;
    const char *str = lauxh_checklstring(L, 1, &len);
    size_t pos      = 0;

    if (!len) {
        return error_result_as_false(L, PARSE_EAGAIN, "vchar");
    } else if (hwire_parse_vchar(str, len, &pos) != len) {
        return error_result_as_false(L, PARSE_EILSEQ, "vchar");
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int quoted_string_lua(lua_State *L)
{
    size_t len      = 0;
    const char *str = lauxh_checklstring(L, 1, &len);
    size_t maxlen   = (size_t)lauxh_optuint16(L, 2, DEFAULT_STR_MAXLEN);
    size_t pos      = 0;
    int rv          = hwire_parse_quoted_string(str, len, &pos, maxlen);

    if (rv != PARSE_OK) {
        return error_result_as_false(L, rv, "quoted_string");
    } else if (pos != len) {
        return error_result_as_false(L, PARSE_EILSEQ, "quoted_string");
    }
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * 5.6.6. Parameters
 * https://www.ietf.org/archive/id/draft-ietf-httpbis-semantics-16.html#parameter
 *
 * Parameters are instances of name=value pairs; they are often used in
 * field values as a common syntax for appending auxiliary information to an
 * item. Each parameter is usually delimited by an immediately preceding
 * semicolon.
 *
 *  parameters      = *( OWS ";" OWS [ parameter ] )
 *  parameter       = parameter-name "=" parameter-value
 *  parameter-name  = token
 *  parameter-value = ( token / quoted-string )
 *
 * Parameter names are case-insensitive. Parameter values might or might
 * not be case-sensitive, depending on the semantics of the parameter name.
 * Examples of parameters and some equivalent forms can be seen in media
 * types (Section 8.3.1) and the Accept header field (Section 12.5.1).
 *
 * A parameter value that matches the token production can be transmitted
 * either as a token or within a quoted-string. The quoted and unquoted
 * values are equivalent.
 *
 * Note: Parameters do not allow whitespace (not even "bad" whitespace)
 * around the "=" character.
 * verify parameters
 */

static int param_cb(hwire_ctx_t *ctx, hwire_param_t *param)
{
    parse_cb_ctx_t *cb = (parse_cb_ctx_t *)ctx->uctx;
    lua_State *L       = cb->L;
    lua_pushlstring(L, ctx->key_lc.buf, ctx->key_lc.len);
    lua_pushlstring(L, param->value.ptr, param->value.len);
    lua_rawset(L, cb->tblidx);
    return 0;
}

static int parameters_lua(lua_State *L)
{
    size_t len                   = 0;
    const char *str              = lauxh_checklstring(L, 1, &len);
    uint16_t maxlen              = lauxh_optuint16(L, 3, DEFAULT_STR_MAXLEN);
    parse_cb_ctx_t cb_ctx        = {.L = L, .tblidx = 2};
    char buf[DEFAULT_STR_MAXLEN] = {0};
    // parse context
    hwire_ctx_t ctx = {
        .uctx     = &cb_ctx,
        .key_lc   = {.buf = buf, .size = sizeof(buf)},
        .param_cb = param_cb,
    };
    size_t pos = 0;
    int rv     = 0;

    // confirm table argument
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

    if (!len) {
        return error_result_as_false(L, PARSE_EAGAIN, "parameters");
    }

    if (maxlen > DEFAULT_STR_MAXLEN) {
        ctx.key_lc.buf  = (char *)lua_newuserdata(L, maxlen);
        ctx.key_lc.size = maxlen;
    }

    rv = hwire_parse_parameters(&ctx, str, len, &pos, maxlen, UINT8_MAX, 1);
    if (rv == HWIRE_ECALLBACK) {
        return error_result_as_false(L, cb_ctx.error, "parameters");
    } else if (rv != HWIRE_OK) {
        return error_result_as_false(L, rv, "parameters");
    } else if (pos < len) {
        return error_result_as_false(L, PARSE_EILSEQ, "parameters");
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int chunksize_cb(hwire_ctx_t *ctx, uint32_t size)
{
    parse_cb_ctx_t *cb = (parse_cb_ctx_t *)ctx->uctx;
    cb->chunksize      = (uint64_t)size;
    return 0;
}

static int chunksize_ext_cb(hwire_ctx_t *ctx, hwire_chunksize_ext_t *ext)
{
    parse_cb_ctx_t *cb = (parse_cb_ctx_t *)ctx->uctx;
    lua_State *L       = cb->L;
    lua_pushlstring(L, ext->key.ptr, ext->key.len);
    lua_pushlstring(L, ext->value.ptr, ext->value.len);
    lua_rawset(L, cb->tblidx);
    return 0;
}

#define DEFAULT_CHUNKSIZE_MAXLEN 4096

static int chunksize_lua(lua_State *L)
{
    size_t len      = 0;
    const char *str = lauxh_checklstring(L, 1, &len);
    size_t maxlen   = (size_t)lauxh_optuint16(L, 3, DEFAULT_CHUNKSIZE_MAXLEN);
    parse_cb_ctx_t cb_ctx = {.L = L, .tblidx = 2, .chunksize = 0};
    // parse context
    hwire_ctx_t ctx = {
        .uctx             = &cb_ctx,
        .chunksize_cb     = chunksize_cb,
        .chunksize_ext_cb = chunksize_ext_cb,
    };
    size_t pos = 0;
    int rv     = 0;

    // confirm table argument
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

    if (!len) {
        return error_result_as_nil(L, PARSE_EAGAIN, "chunksize");
    }

    rv = hwire_parse_chunksize(&ctx, str, len, &pos, maxlen, UINT8_MAX);
    if (rv == HWIRE_ECALLBACK) {
        return error_result_as_nil(L, cb_ctx.error, "chunksize");
    } else if (rv != HWIRE_OK) {
        return error_result_as_nil(L, rv, "chunksize");
    }
    lua_pushinteger(L, cb_ctx.chunksize);
    lua_pushnil(L);
    lua_pushinteger(L, pos);
    return 3;
}

// RFC 6265 HTTP State Management Mechanism
//
//  6. Implementation Considerations
//     https://tools.ietf.org/html/rfc6265#section-6
//
//  - At least 4096 bytes per cookie (as measured by the sum of the
//    length of the cookie's name, value, and attributes).
//  - At least 50 cookies per domain.
//
// Cookie-Header:   field-name: field-value
// field-name   :   'Set-Cookie: '  ; 12 byte
// field-value  :   field-value     ; 4096 byte
#define DEFAULT_HDR_MAXLEN 4108
#define DEFAULT_HDR_MAXNUM UINT8_MAX
#define DEFAULT_MSG_MAXLEN 2048

static int header_value_lua(lua_State *L)
{
    size_t len      = 0;
    const char *str = lauxh_checklstring(L, 1, &len);
    size_t maxlen   = (size_t)lauxh_optuint16(L, 2, DEFAULT_HDR_MAXLEN);
    size_t pos      = 0;

    if (!len) {
        return error_result_as_false(L, PARSE_EAGAIN, "header_value");
    } else if (len > maxlen) {
        return error_result_as_false(L, PARSE_EHDRLEN, "header_value");
    } else if (!hwire_is_vchar((unsigned char)str[len - 1])) {
        // field-content must end with VCHAR or obs-text
        return error_result_as_false(L, PARSE_EHDRVAL, "header_value");
    } else if (hwire_parse_fcchar(str, len, &pos) != len) {
        return error_result_as_false(L, PARSE_EHDRVAL, "header_value");
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int header_name_lua(lua_State *L)
{
    size_t len       = 0;
    const char *str  = lauxh_checklstring(L, 1, &len);
    size_t maxhdrlen = (size_t)lauxh_optuint16(L, 2, DEFAULT_HDR_MAXLEN);
    size_t pos       = 0;

    if (len > maxhdrlen) {
        return error_result_as_false(L, PARSE_EHDRLEN, "header_name");
    } else if (hwire_parse_tchar(str, len, &pos) != len) {
        return error_result_as_false(L, PARSE_EHDRNAME, "header_name");
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int header_cb(hwire_ctx_t *ctx, hwire_header_t *header)
{
    parse_cb_ctx_t *cb = (parse_cb_ctx_t *)ctx->uctx;
    lua_State *L       = cb->L;
    int tblidx         = cb->tblidx;

    if (header->value.len == 0) {
        return 0;
    } else if (header->key.len + 1 + header->value.len > cb->maxhdrlen) {
        cb->error = PARSE_EHDRLEN;
        return -1;
    }
    cb->nhdr++;

    lua_pushlstring(L, ctx->key_lc.buf, ctx->key_lc.len);
    lua_pushvalue(L, -1);
    lua_rawget(L, tblidx);

    switch (lua_type(L, -1)) {
    default: {
        lua_pop(L, 1);
        lua_createtable(L, 3, 0);
        lauxh_pushint2tbl(L, "idx", cb->nhdr);
        lua_pushliteral(L, "key");
        lua_pushlstring(L, header->key.ptr, header->key.len);
        lua_rawset(L, -3);
        lua_pushliteral(L, "val");
        lua_createtable(L, 1, 0);
        lauxh_pushlstr2arr(L, 1, header->value.ptr, header->value.len);
        lua_rawset(L, -3);
        lua_pushvalue(L, -2);
        lua_pushvalue(L, -2);
        lua_rawset(L, tblidx);
        lua_rawseti(L, tblidx, cb->nhdr);
    } break;

    case LUA_TTABLE:
        lua_pushliteral(L, "val");
        lua_rawget(L, -2);
        lauxh_pushlstr2arr(L, lauxh_rawlen(L, -1) + 1, header->value.ptr,
                           header->value.len);
        lua_pop(L, 2);
        break;
    }
    lua_pop(L, 1);
    return 0;
}

static int header_lua(lua_State *L)
{
    size_t len            = 0;
    const char *str       = lauxh_checklstring(L, 1, &len);
    size_t cur            = (size_t)lauxh_optuint64(L, 3, 0);
    uint16_t maxhdrlen    = lauxh_optuint16(L, 4, DEFAULT_HDR_MAXLEN);
    uint8_t maxhdrnum     = lauxh_optuint8(L, 5, DEFAULT_HDR_MAXNUM);
    const char *head      = str;
    parse_cb_ctx_t cb_ctx = {.L = L, .tblidx = 2, .maxhdrlen = maxhdrlen};
    char buf[DEFAULT_HDR_MAXLEN] = {0};
    // parse context
    hwire_ctx_t ctx = {
        .uctx      = &cb_ctx,
        .key_lc    = {.buf = buf, .size = sizeof(buf)},
        .header_cb = header_cb,
    };
    size_t pos = 0;
    int rv     = 0;

    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

    if (cur > len) {
        str += len;
        len = 0;
    } else {
        str += cur;
        len -= cur;
    }

    if (maxhdrlen > DEFAULT_HDR_MAXLEN) {
        ctx.key_lc.buf  = (char *)lua_newuserdata(L, maxhdrlen);
        ctx.key_lc.size = maxhdrlen;
    }

    rv = hwire_parse_headers(&ctx, str, len, &pos, maxhdrlen, maxhdrnum);
    if (rv == HWIRE_ECALLBACK) {
        return error_result_as_nil(L, cb_ctx.error, "header");
    } else if (rv != HWIRE_OK) {
        return error_result_as_nil(L, rv, "header");
    }
    lua_settop(L, 1);
    lua_pushinteger(L, (str + pos) - head);
    return 1;
}

static int request_cb(hwire_ctx_t *ctx, hwire_request_t *req)
{
    parse_cb_ctx_t *cb = (parse_cb_ctx_t *)ctx->uctx;
    lua_State *L       = cb->L;

    if (req->uri.len > cb->maxmsglen) {
        cb->error = PARSE_ELEN;
        return -1;
    }
    cb->request_line_parsed = 1;

    lauxh_pushlstr2tbl(L, "method", req->method.ptr, req->method.len);
    lauxh_pushlstr2tbl(L, "uri", req->uri.ptr, req->uri.len);
    lauxh_pushnum2tbl(L, "version", hwire_version_to_double(req->version));

    lua_createtable(L, 0, 0);
    cb->tblidx = lua_gettop(L);
    return 0;
}

static int request_lua(lua_State *L)
{
    size_t len            = 0;
    const char *str       = lauxh_checklstring(L, 1, &len);
    uint16_t maxmsglen    = lauxh_optuint16(L, 3, DEFAULT_MSG_MAXLEN);
    uint16_t maxhdrlen    = lauxh_optuint16(L, 4, DEFAULT_HDR_MAXLEN);
    uint8_t maxhdrnum     = lauxh_optuint8(L, 5, DEFAULT_HDR_MAXNUM);
    size_t maxlen         = (maxmsglen > maxhdrlen) ? maxmsglen : maxhdrlen;
    parse_cb_ctx_t cb_ctx = {
        .L = L, .maxmsglen = maxmsglen, .maxhdrlen = maxhdrlen};
    char buf[DEFAULT_HDR_MAXLEN] = {0};
    // parse context
    hwire_ctx_t ctx = {
        .uctx       = &cb_ctx,
        .key_lc     = {.buf = buf, .size = sizeof(buf)},
        .request_cb = request_cb,
        .header_cb  = header_cb,
    };
    size_t pos = 0;
    int rv     = 0;

    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

    if (maxhdrlen > DEFAULT_HDR_MAXLEN) {
        ctx.key_lc.buf  = (char *)lua_newuserdata(L, maxhdrlen);
        ctx.key_lc.size = maxhdrlen;
    }

    rv = hwire_parse_request(&ctx, str, len, &pos, maxlen, maxhdrnum);
    if (rv == HWIRE_OK) {
        lua_setfield(L, 2, "header");
        lua_settop(L, 1);
        lua_pushinteger(L, pos);
        return 1;
    } else if (rv == HWIRE_ECALLBACK) {
        return error_result_as_nil(L, cb_ctx.error, "request");
    } else if (rv == HWIRE_EAGAIN && !cb_ctx.request_line_parsed &&
               len >= maxmsglen) {
        return error_result_as_nil(L, PARSE_ELEN, "request");
    }
    return error_result_as_nil(L, rv, "request");
}

static int response_cb(hwire_ctx_t *ctx, hwire_response_t *rsp)
{
    parse_cb_ctx_t *cb = (parse_cb_ctx_t *)ctx->uctx;
    lua_State *L       = cb->L;

    if (rsp->reason.len > cb->maxmsglen) {
        cb->error = PARSE_ELEN;
        return -1;
    }
    cb->request_line_parsed = 1;

    lauxh_pushnum2tbl(L, "version", hwire_version_to_double(rsp->version));
    lauxh_pushint2tbl(L, "status", rsp->status);
    lauxh_pushlstr2tbl(L, "reason", rsp->reason.ptr, rsp->reason.len);

    lua_createtable(L, 0, 0);
    cb->tblidx = lua_gettop(L);
    return 0;
}

static int response_lua(lua_State *L)
{
    size_t len            = 0;
    const char *str       = lauxh_checklstring(L, 1, &len);
    uint16_t maxmsglen    = lauxh_optuint16(L, 3, DEFAULT_MSG_MAXLEN);
    uint16_t maxhdrlen    = lauxh_optuint16(L, 4, DEFAULT_HDR_MAXLEN);
    uint8_t maxhdrnum     = lauxh_optuint8(L, 5, DEFAULT_HDR_MAXNUM);
    size_t maxlen         = (maxmsglen > maxhdrlen) ? maxmsglen : maxhdrlen;
    parse_cb_ctx_t cb_ctx = {
        .L         = L,
        .maxmsglen = maxmsglen,
        .maxhdrlen = maxhdrlen,
    };
    char buf[DEFAULT_HDR_MAXLEN] = {0};
    // parse context
    hwire_ctx_t ctx = {
        .uctx        = &cb_ctx,
        .key_lc      = {.buf = buf, .size = sizeof(buf)},
        .response_cb = response_cb,
        .header_cb   = header_cb,
    };
    size_t pos = 0;
    int rv     = 0;

    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

    if (maxhdrlen > DEFAULT_HDR_MAXLEN) {
        ctx.key_lc.buf  = (char *)lua_newuserdata(L, maxhdrlen);
        ctx.key_lc.size = maxhdrlen;
    }

    rv = hwire_parse_response(&ctx, str, len, &pos, maxlen, maxhdrnum);
    if (rv == HWIRE_OK) {
        lua_setfield(L, 2, "header");
        lua_settop(L, 1);
        lua_pushinteger(L, pos);
        return 1;
    } else if (rv == HWIRE_ECALLBACK) {
        return error_result_as_nil(L, cb_ctx.error, "response");
    } else if (rv == HWIRE_EAGAIN && !cb_ctx.request_line_parsed &&
               len >= maxmsglen) {
        return error_result_as_nil(L, PARSE_ELEN, "response");
    }
    return error_result_as_nil(L, rv, "response");
}

LUALIB_API int luaopen_net_http_parse(lua_State *L)
{
    struct luaL_Reg funcs[] = {
        {"response",      response_lua     },
        {"request",       request_lua      },
        {"header",        header_lua       },
        {"header_name",   header_name_lua  },
        {"header_value",  header_value_lua },
        {"chunksize",     chunksize_lua    },
        {"parameters",    parameters_lua   },
        {"quoted_string", quoted_string_lua},
        {"tchar",         tchar_lua        },
        {"vchar",         vchar_lua        },
        {NULL,            NULL             }
    };
    struct luaL_Reg *ptr = funcs;

    init_error_types(L);

    lua_createtable(L, 0, sizeof(funcs) / sizeof(struct luaL_Reg) + 13);
    do {
        lauxh_pushfn2tbl(L, ptr->name, ptr->func);
        ptr++;
    } while (ptr->name);

    // constants
    lauxh_pushref(L, PARSE_ERR_EAGAIN);
    lua_setfield(L, -2, "EAGAIN");
    lauxh_pushref(L, PARSE_ERR_EMSG);
    lua_setfield(L, -2, "EMSG");
    lauxh_pushref(L, PARSE_ERR_ELEN);
    lua_setfield(L, -2, "ELEN");
    lauxh_pushref(L, PARSE_ERR_EMETHOD);
    lua_setfield(L, -2, "EMETHOD");
    lauxh_pushref(L, PARSE_ERR_EVERSION);
    lua_setfield(L, -2, "EVERSION");
    lauxh_pushref(L, PARSE_ERR_EEOL);
    lua_setfield(L, -2, "EEOL");
    lauxh_pushref(L, PARSE_ERR_EHDRNAME);
    lua_setfield(L, -2, "EHDRNAME");
    lauxh_pushref(L, PARSE_ERR_EHDRVAL);
    lua_setfield(L, -2, "EHDRVAL");
    lauxh_pushref(L, PARSE_ERR_EHDRLEN);
    lua_setfield(L, -2, "EHDRLEN");
    lauxh_pushref(L, PARSE_ERR_EHDRNUM);
    lua_setfield(L, -2, "EHDRNUM");
    lauxh_pushref(L, PARSE_ERR_ESTATUS);
    lua_setfield(L, -2, "ESTATUS");
    lauxh_pushref(L, PARSE_ERR_EILSEQ);
    lua_setfield(L, -2, "EILSEQ");
    lauxh_pushref(L, PARSE_ERR_ERANGE);
    lua_setfield(L, -2, "ERANGE");
    lauxh_pushref(L, PARSE_ERR_EEMPTY);
    lua_setfield(L, -2, "EEMPTY");
    lauxh_pushref(L, PARSE_ERR_EURI);
    lua_setfield(L, -2, "EURI");

    return 1;
}
