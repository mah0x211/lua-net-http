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

#include <string.h>
// lua
#include <lua_error.h>

/**
 * return code
 */
#define PARSE_OK       0   // success
#define PARSE_EAGAIN   -1  // need more bytes
#define PARSE_EMSG     -2  // invalid message
#define PARSE_ELEN     -3  // length too large
#define PARSE_EMETHOD  -4  // method not implemented
#define PARSE_EVERSION -5  // version not supported
#define PARSE_EEOL     -6  // invalid end-of-line terminator
#define PARSE_EHDRNAME -7  // invalid header field-name
#define PARSE_EHDRVAL  -8  // invalid header field-val
#define PARSE_EHDRLEN  -9  // header-length too large
#define PARSE_EHDRNUM  -10 // too many headers
#define PARSE_ESTATUS  -11 // invalid status code
#define PARSE_EILSEQ   -12 // illegal byte sequence
#define PARSE_ERANGE   -13 // result too large
#define PARSE_EEMPTY   -14 // disallow empty definitions
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

static void init_error_types(lua_State *L)
{
    int nameidx = lua_gettop(L) + 1;

    le_loadlib(L, 1);

#define create_error_type(name, message)                                       \
 do {                                                                          \
  lua_pushstring(L, "net.http.parse." #name);                                  \
  lua_pushinteger(L, PARSE_##name);                                            \
  lua_pushstring(L, (message));                                                \
  le_new_type(L, nameidx);                                                     \
  PARSE_ERR_##name = lauxh_ref(L);                                             \
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

    default:
        return luaL_error(L, "unknown errtype %d", err);
    }

    if (op) {
        lua_pushnil(L);
        lua_pushstring(L, op);
        le_new_message(L, typeidx + 1);
    }
    le_new_typed_error(L, typeidx);
    return 2;
}
#define error_result_as_false(L, err, op) error_result_ex(L, err, op, 1)
#define error_result_as_nil(L, err, op)   error_result_ex(L, err, op, 0)

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

/**
 * RFC 7230
 * 3.2.  Header Fields
 * https://tools.ietf.org/html/rfc7230#section-3.2
 *
 * OWS            = *( SP / HTAB )
 *                   ; optional whitespace
 * RWS            = 1*( SP / HTAB )
 *                  ; required whitespace
 * BWS            = OWS
 *                  ; "bad" whitespace
 *
 * header-field   = field-name ":" OWS field-value OWS
 *
 * field-name     = token
 *
 * 3.2.6.  Field Value Components
 * https://tools.ietf.org/html/rfc7230#section-3.2.6
 *
 * token          = 1*tchar
 * tchar          = "!" / "#" / "$" / "%" / "&" / "'" / "*"
 *                / "+" / "-" / "." / "^" / "_" / "`" / "|" / "~"
 *                / DIGIT / ALPHA
 *                ; any VCHAR, except delimiters
 *
 * VCHAR          = %x21-7E
 * delimiters     = "(),/:;<=>?@[\]{}
 *
 */
static const unsigned char TCHAR[256] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    //   "                            (  )            ,            /
    '!', 0, '#', '$', '%', '&', '\'', 0, 0, '*', '+', 0, '-', '.', 0,
    //                                                :  ;  <  =  >  ?  @
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 1, 0, 0, 0, 0, 0, 0,
    // upper case
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y',
    //   [  \  ]
    'z', 0, 0, 0, '^', '_', '`',
    // lower case
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y',
    //   {       }
    'z', 0, '|', 0, '~'};

static int tchar_lua(lua_State *L)
{
    size_t len         = 0;
    unsigned char *str = (unsigned char *)lauxh_checklstring(L, 1, &len);

    if (!len) {
        return error_result_as_false(L, PARSE_EAGAIN, "tchar");
    }

    for (size_t i = 0; i < len; i++) {
        switch (TCHAR[str[i]]) {
        case 0:
        case 1:
            // illegal byte sequence
            return error_result_as_false(L, PARSE_EILSEQ, "tchar");
        }
    }
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * RFC 7230
 * 3.1.2.  Status Line
 * https://tools.ietf.org/html/rfc7230#section-3.1.2
 *
 * reason-phrase  = *( HTAB / SP / VCHAR / obs-text )
 *
 * VCHAR          = %x21-7E
 * obs-text       = %x80-FF
 *
 * RFC 7230
 * 3.2.  Header Fields
 * https://tools.ietf.org/html/rfc7230#section-3.2
 *
 * OWS            = *( SP / HTAB )
 *                   ; optional whitespace
 * RWS            = 1*( SP / HTAB )
 *                  ; required whitespace
 * BWS            = OWS
 *                  ; "bad" whitespace
 *
 * header-field   = field-name ":" OWS field-value OWS
 *
 * field-name     = token
 * field-value    = *( field-content / obs-fold )
 * field-content  = field-vchar [ 1*( SP / HTAB ) field-vchar ]
 * field-vchar    = VCHAR / obs-text
 *
 * obs-fold       = CRLF 1*( SP / HTAB )
 *                  ; obsolete line folding
 *                  ; see https://tools.ietf.org/html/rfc7230#section-3.2.4
 *
 * VCHAR          = %x21-7E
 * obs-text       = %x80-FF
 */
// 1 = field-content
// 2 = LF or CR
// 0 = invalid
static const unsigned char VCHAR[256] = {
    //                         HT LF       CR
    0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    // SP !  "  #  $  %  &  '  (  )  *  +  ,  -  .  /
    0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    //  0  1  2  3  4  5  6  7  8  9
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    //  :  ;  <  =  >  ?  @
    1, 1, 1, 1, 1, 1, 1,
    //  A  B  C  D  E  F  G  H  I  J  K  L  M  N  O  P  Q  R  S  T  U  V  W  X Y
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    //  Z  [  \  ]  ^  _  `
    1, 1, 1, 1, 1, 1, 1,
    //  a  b  c  d  e  f  g  h  i  j  k  l  m  n  o  p  q  r  s  t  u  v  w  x y
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    //  z  {  |  }  ~
    1, 1, 1, 1, 1};

static int vchar_lua(lua_State *L)
{
    size_t len         = 0;
    unsigned char *str = (unsigned char *)lauxh_checklstring(L, 1, &len);

    if (!len) {
        return error_result_as_false(L, PARSE_EAGAIN, "vchar");
    }

    for (size_t i = 0; i < len; i++) {
        if (VCHAR[str[i]] != 1) {
            return error_result_as_false(L, PARSE_EILSEQ, "vchar");
        }
    }
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * https://tools.ietf.org/html/rfc7230#section-4.1
 * 4.1.  Chunked Transfer Coding
 *
 * chunked-body   = *chunk
 *                  last-chunk
 *                  trailer-part
 *                  CRLF
 *
 * chunk          = chunk-size [ chunk-ext ] CRLF
 *                  chunk-data CRLF
 * chunk-size     = 1*HEXDIG
 * last-chunk     = 1*("0") [ chunk-ext ] CRLF
 *
 * chunk-data     = 1*OCTET ; a sequence of chunk-size octets
 */
static const unsigned char HEXDIGIT[256] = {
    //  ctrl-code: 0-32
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0,
    //  SP !  "  #  $  %  &  '  (  )  *  +  ,  -  .  /,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    //  0  1  2  3  4  5  6  7  8  9
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    //  :  ;  <  =  >  ?  @
    0, 0, 0, 0, 0, 0, 0,
    //  A   B   C   D   E   F
    11, 12, 13, 14, 15, 16,
    //  G  H  I  J  K  L  M  N  O  P  Q  R  S  T  U  V  W  X  Y  Z  [  \  ]
    //  ^  _  `
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0,
    //  a   b   c   d   e   f
    11, 12, 13, 14, 15, 16,
    //  g  h  i  j  k  l  m  n  o  p  q  r  s  t  u  v  w  x  y  z  {  |  }
    //  ~
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

static ssize_t hex2size(unsigned char *str, size_t len, size_t *cur)
{
    ssize_t dec = 0;

    if (!len) {
        return PARSE_EAGAIN;
    }

    // hex to decimal
    for (size_t pos = 0; pos < len; pos++) {
        unsigned char c = HEXDIGIT[str[pos]];
        if (!c) {
            // found non hexdigit
            *cur = pos;
            return dec;
        } else if (pos >= 8) {
            // limit to max value of 32bit (0xFFFFFFFF)
            return PARSE_ERANGE;
        }
        dec = (dec << 4) | (c - 1);
    }

    *cur = len;
    return dec;
}

/**
 * 5.6.6. Parameters
 * https://www.ietf.org/archive/id/draft-ietf-httpbis-semantics-16.html#section-5.6.6
 *
 * parameter-value = token / quoted-string
 * quoted-string  = DQUOTE *( qdtext / quoted-pair ) DQUOTE
 * qdtext         = HTAB / SP / %x21 / %x23-5B / %x5D-7E / obs-text
 * quoted-pair    = "\" ( HTAB / SP / VCHAR / obs-text )
 * obs-text       = %x80-FF
 */
static const unsigned char QDTEXT[256] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, '\t', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    //        "
    ' ', '!', 0, '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.',
    '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=',
    '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L',
    'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    //  0x5C[backslash]
    '[', 0, ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i',
    'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x',
    'y', 'z', '{', '|', '}', '~'};

static int parse_quoted_string(unsigned char *str, size_t len, size_t *cur,
                               size_t *maxlen)
{
    size_t pos  = *cur;
    size_t head = pos + 1;

    if (str[pos] != DQUOTE) {
        return PARSE_EILSEQ;
    }

    pos++;
    for (; pos < len; pos++) {
        if (pos > *maxlen) {
            return PARSE_ELEN;
        } else if (!QDTEXT[str[pos]]) {
            switch (str[pos]) {
            case DQUOTE:
                *maxlen = pos - head;
                *cur    = pos + 1;
                return PARSE_OK;

            case BACKSLASH:
                // quoted-pair = "\" ( HTAB / SP / VCHAR / obs-text )
                switch (VCHAR[str[pos + 1]]) {
                case 1:
                case 2: // HT, SP
                    pos += 2;
                    continue;
                }
                // pass-through
            default:
                // found illegal byte sequence
                return PARSE_EILSEQ;
            }
        }
    }

    // more bytes need
    return PARSE_EAGAIN;
}

static int quoted_string_lua(lua_State *L)
{
    size_t len         = 0;
    unsigned char *str = (unsigned char *)lauxh_checklstring(L, 1, &len);
    size_t maxlen      = (size_t)lauxh_optuint16(L, 2, DEFAULT_STR_MAXLEN);
    size_t cur         = 0;
    int rv             = PARSE_EAGAIN;

    if (len) {
        rv = parse_quoted_string(str, len, &cur, &maxlen);
        if (rv == PARSE_OK && cur != len) {
            // did not parse to the end of string
            rv = PARSE_EILSEQ;
        }
    }

    if (rv != PARSE_OK) {
        return error_result_as_false(L, rv, "quoted_string");
    }
    lua_pushboolean(L, 1);
    return 1;
}

static inline int skip_ws(unsigned char *str, size_t len, size_t *cur,
                          size_t maxlen)
{
    size_t pos = *cur;

SKIP_NEXT:
    if (pos < len) {
        // length too large
        if (pos >= maxlen) {
            return PARSE_ELEN;
        }

        // skip SP and HT
        switch (str[pos]) {
        case SP:
        case HT:
            pos++;
            goto SKIP_NEXT;
        }
    }

    *cur = pos;
    return PARSE_OK;
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

static int parameters_lua(lua_State *L)
{
    size_t len            = 0;
    unsigned char *str    = (unsigned char *)lauxh_checklstring(L, 1, &len);
    const uint16_t maxlen = lauxh_optuint16(L, 3, DEFAULT_STR_MAXLEN);
    size_t cur            = 0;
    size_t head           = 0;

    // check container table
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

    if (!len) {
        return error_result_as_false(L, PARSE_EAGAIN, "parameters");
    }

    // parse parameter-name
CHECK_PARAM:
    // skip OWS
    if (skip_ws(str, len, &cur, maxlen) != PARSE_OK) {
        return error_result_as_false(L, PARSE_ELEN, "parameters");
    }
    head = cur;
    for (unsigned char c = TCHAR[str[cur]]; c > 1; c = TCHAR[str[cur]]) {
        str[cur++] = c;
        if (cur > maxlen) {
            return error_result_as_false(L, PARSE_ELEN, "parameters");
        }
    }
    if (str[cur] != '=') {
        return error_result_as_false(L, PARSE_EILSEQ, "parameters");
    }
    lua_pushlstring(L, (const char *)str + head, cur - head);
    cur++;

    // parse parameter-value
    head = cur;
    if (str[cur] == DQUOTE) {
        size_t qlen = maxlen;
        // parse as a quoted-string
        head++;
        switch (parse_quoted_string(str, len, &cur, &qlen)) {
        case PARSE_OK:
            lua_pushlstring(L, (const char *)str + head, qlen);
            lua_rawset(L, 2);
            goto CHECK_EOL;

        case PARSE_EAGAIN:
            // more bytes need
            return error_result_as_false(L, PARSE_EAGAIN, "parameters");

        // PARSE_EILSEQ
        default:
            // found illegal byte sequence
            return error_result_as_false(L, PARSE_EILSEQ, "parameters");
        }
    }
    // parse as a token
    while (TCHAR[str[cur]] > 1) {
        if (cur >= maxlen) {
            return error_result_as_false(L, PARSE_ELEN, "parameters");
        }
        cur++;
    }
    lua_pushlstring(L, (const char *)str + head, cur - head);
    lua_rawset(L, 2);

CHECK_EOL:
    if (skip_ws(str, len, &cur, maxlen) != PARSE_OK) {
        return error_result_as_false(L, PARSE_ELEN, "parameters");
    }
    switch (str[cur]) {
    case 0:
        lua_pushboolean(L, 1);
        return 1;

    case ';':
        // check next parameter
        cur++;
        goto CHECK_PARAM;

    default:
        // found illegal byte sequence
        return error_result_as_false(L, PARSE_EILSEQ, "parameters");
    }
}

#define DEFAULT_CHUNKSIZE_MAXLEN 4096

static int chunksize_lua(lua_State *L)
{
    size_t len         = 0;
    unsigned char *str = (unsigned char *)lauxh_checklstring(L, 1, &len);
    size_t maxlen   = (size_t)lauxh_optuint16(L, 3, DEFAULT_CHUNKSIZE_MAXLEN);
    ssize_t size    = 0;
    size_t cur      = 0;
    size_t head     = 0;
    const char *key = NULL;
    size_t klen     = 0;
    const char *val = NULL;
    size_t vlen     = 0;

    // check container table
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

    if (!len) {
        return error_result_as_nil(L, PARSE_EAGAIN, "chunksize");
    }

    // parse chunk-size
    size = hex2size(str, len, &cur);
    if (size < 0) {
        return error_result_as_nil(L, size, "chunksize");
    }

#define skip_bws()                                                             \
 do {                                                                          \
  if (skip_ws(str, len, &cur, maxlen) != PARSE_OK) {                           \
   return error_result_as_nil(L, PARSE_ELEN, "chunksize");                     \
  } else if (str[cur] == 0) {                                                  \
   /* more bytes need */                                                       \
   return error_result_as_nil(L, PARSE_EAGAIN, "chunksize");                   \
  }                                                                            \
 } while (0)

    // found tail
    if (str[cur] == CR) {
CHECK_EOL:
        switch (str[cur + 1]) {
        case 0:
            // more bytes need
            return error_result_as_nil(L, PARSE_EAGAIN, "chunksize");

        case LF:
            // push extension
            if (klen) {
                lua_pushlstring(L, key, klen);
                if (vlen) {
                    lua_pushlstring(L, val, vlen);
                } else {
                    lua_pushliteral(L, "");
                }
                lua_rawset(L, 2);
            }
            // return chunksize and number of bytes consumed
            lua_pushinteger(L, size);
            lua_pushnil(L);
            lua_pushinteger(L, cur + 2);
            return 3;

        default:
            // invalid end-of-line terminator
            return error_result_as_nil(L, PARSE_EEOL, "chunksize");
        }
    }

    // parse semicolon
    skip_bws();
    if (str[cur] != SEMICOLON) {
        return error_result_as_nil(L, PARSE_EILSEQ, "chunksize");
    }
    cur++;

    // 4.1.1.  Chunk Extensions
    //
    // chunk-ext    = *( BWS ";" BWS ext-name [ BWS "=" BWS ext-val ] )
    // ext-name     = token
    // ext-val      = token / quoted-string
    //
    // trailer-part = *( header-field CRLF )
    //
    // OWS (Optional Whitespace)        = *( SP / HTAB )
    // BWS (Must be removed by parser)  = OWS
    //                                  ; "bad" whitespace
    //
    // quoted-string  = DQUOTE *( qdtext / quoted-pair ) DQUOTE
    // qdtext         = HTAB / SP / %x21 / %x23-5B / %x5D-7E / obs-text
    // quoted-pair    = "\" ( HTAB / SP / VCHAR / obs-text )
    // obs-text       = %x80-FF
    //
    // parse chunk-extensions
CHECK_EXTNAME:
    // push previous extension
    if (klen) {
        lua_pushlstring(L, key, klen);
        if (vlen) {
            lua_pushlstring(L, val, vlen);
        } else {
            lua_pushliteral(L, "");
        }
        lua_rawset(L, 2);
        klen = 0;
        vlen = 0;
    }
    skip_bws();
    head = cur;
    while (TCHAR[str[cur]] > 1) {
        cur++;
    }
    if (cur == head) {
        // disallow empty ext-name
        return error_result_as_nil(L, PARSE_EEMPTY, "chunksize");
    }
    key  = (const char *)str + head;
    klen = cur - head;

    // found tail
    if (str[cur] == CR) {
        goto CHECK_EOL;
    }
    skip_bws();

    switch (str[cur]) {
    case SEMICOLON:
        cur++;
        goto CHECK_EXTNAME;

    case EQ:
        // parse ext-value
        cur++;
        break;

    default:
        // illegal byte sequence
        return error_result_as_nil(L, PARSE_EILSEQ, "chunksize");
    }

    // parse ext-val
    skip_bws();
    if (str[cur] == DQUOTE) {
        int rv = 0;

        // parse as a quoted-string
        head = cur + 1;
        vlen = maxlen;
        rv   = parse_quoted_string(str, len, &cur, &vlen);
        switch (rv) {
        case PARSE_OK:
            val = (const char *)str + head;
            // found tail
            if (str[cur] == CR) {
                goto CHECK_EOL;
            }
            goto CHECK_EOB;

        default:
            // PARSE_EAGAIN
            // PARSE_ELEN
            // PARSE_EILSEQ
            return error_result_as_nil(L, rv, "chunksize");
        }
    }

    // parse as a token
    head = cur;
    while (TCHAR[str[cur]] > 1) {
        cur++;
    }
    val  = (const char *)str + head;
    vlen = cur - head;
    switch (str[cur]) {
    case 0:
        // more bytes need
        return error_result_as_nil(L, PARSE_EAGAIN, "chunksize");

    case CR:
        // found tail
        goto CHECK_EOL;

    default:
CHECK_EOB:
        skip_bws();
        switch (str[cur]) {
        case SEMICOLON:
            cur++;
            goto CHECK_EXTNAME;

        default:
            // illegal byte sequence
            return error_result_as_nil(L, PARSE_EILSEQ, "chunksize");
        }
    }
#undef skip_bws
}

static int parse_hval(unsigned char *str, size_t len, size_t *cur,
                      size_t *maxhdrlen)
{
    size_t tail     = 0;
    size_t pos      = 0;
    unsigned char c = 0;

    for (; pos < len; pos++) {
        // check length
        if (pos > *maxhdrlen) {
            return PARSE_EHDRLEN;
        }

        c = str[pos];
        switch (VCHAR[c]) {
        case 1:
        case 2:
            continue;

        // LF or CR
        case 3:
            tail = pos;
            // found LF
            if (c == LF) {
                pos += 1;
            }
            // found CRLF
            else if (str[pos + 1] == LF) {
                pos += 2;
            }
            // null-terminator
            else if (!str[pos + 1]) {
                goto CHECK_AGAIN;
            }
            // invalid end-of-line terminator
            else {
                return PARSE_EEOL;
            }

            // remove OWS
            while (tail > 0 && (str[tail - 1] == SP || str[tail - 1] == HT)) {
                tail--;
            }

            *cur       = pos;
            *maxhdrlen = tail;
            return PARSE_OK;

        // invalid
        default:
            return PARSE_EHDRVAL;
        }
    }

CHECK_AGAIN:
    // header-length too large
    if (len > *maxhdrlen) {
        return PARSE_EHDRLEN;
    }

    return PARSE_EAGAIN;
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
    size_t len         = 0;
    unsigned char *str = (unsigned char *)lauxh_checklstring(L, 1, &len);
    size_t maxlen      = (size_t)lauxh_optuint16(L, 2, DEFAULT_HDR_MAXLEN);
    size_t cur         = 0;
    int rv             = parse_hval((unsigned char *)str, len, &cur, &maxlen);

    switch (rv) {
    case PARSE_EAGAIN:
        // end with field-content
        if (VCHAR[str[len - 1]] == 1) {
            lua_pushboolean(L, 1);
            return 1;
        }

    case PARSE_OK:
    case PARSE_EEOL:
        // str must not contain the end-of-line terminator (CRLF)
        rv = PARSE_EHDRVAL;
    default:
        return error_result_as_false(L, rv, "header_value");
    }
}

static int parse_hkey(lua_State *L, int *lkey, unsigned char *str, size_t len,
                      size_t *cur, size_t *maxhdrlen)
{
    int top       = lua_gettop(L);
    size_t pos    = 0;
    luaL_Buffer b = {0};

    if (lkey) {
        luaL_buffinit(L, &b);
    }

    for (; pos < len; pos++) {
        unsigned char c = TCHAR[str[pos]];

        if (pos > *maxhdrlen) {
            lua_settop(L, top);
            return PARSE_EHDRLEN;
        }

        switch (c) {
        // illegal byte sequence
        case 0:
            lua_settop(L, top);
            return PARSE_EHDRNAME;

        // found COLON
        case 1:
            // check length
            if (pos == 0) {
                lua_settop(L, top);
                return PARSE_EHDRNAME;
            }

            *maxhdrlen = pos;
            *cur       = pos + 1;
            if (lkey) {
                luaL_pushresult(&b);
                *lkey = lauxh_ref(L);
            }
            return PARSE_OK;

        default:
            if (lkey) {
                luaL_addchar(&b, c);
            }
        }
    }

    // header-length too large
    if (len > *maxhdrlen) {
        lua_settop(L, top);
        return PARSE_EHDRLEN;
    }

    lua_settop(L, top);
    return PARSE_EAGAIN;
}

static int header_name_lua(lua_State *L)
{
    size_t len      = 0;
    const char *str = lauxh_checklstring(L, 1, &len);
    size_t maxlen   = (size_t)lauxh_optuint16(L, 2, DEFAULT_HDR_MAXLEN);
    size_t cur      = 0;
    int rv = parse_hkey(L, NULL, (unsigned char *)str, len, &cur, &maxlen);

    switch (rv) {
    case PARSE_EAGAIN:
        lua_pushboolean(L, 1);
        return 1;

    case PARSE_OK:
        // str must not contains the field separator (COLON)
        rv = PARSE_EHDRNAME;
    default:
        return error_result_as_false(L, rv, "header_name");
    }
}

typedef struct {
    int lkey;
    char *key;
    char *val;
    size_t klen;
    size_t vlen;
} header_t;

static int parse_header(lua_State *L, unsigned char *str, size_t len,
                        size_t *cur, uint16_t maxhdrlen, uint8_t maxhdrnum)
{
    int tblidx         = lua_gettop(L);
    header_t *hdridx   = lua_newuserdata(L, sizeof(header_t) * maxhdrnum);
    unsigned char *top = str;
    uintptr_t head     = 0;
    uint8_t nhdr       = 0;
    size_t pos         = 0;
    int rv             = 0;

RETRY:
    switch (*str) {
    // need more bytes
    case 0:
        return PARSE_EAGAIN;

    // check header-tail
    case CR:
        // null-terminated
        if (!str[1]) {
            return PARSE_EAGAIN;
        } else if (str[1] == LF) {
            // skip CR
            str++;
        case LF:
            str++;
            // skip LF
            goto PUSH_HEADERS;
        }
    }

    // too many headers
    if (nhdr >= maxhdrnum) {
        return PARSE_EHDRNUM;
    }

    head              = (uintptr_t)str;
    hdridx[nhdr].lkey = LUA_NOREF;
    hdridx[nhdr].key  = (char *)str;
    hdridx[nhdr].klen = maxhdrlen;
    rv = parse_hkey(L, &hdridx[nhdr].lkey, str, len, &pos, &hdridx[nhdr].klen);
    if (rv != PARSE_OK) {
        return rv;
    }
    // skip OWS
    while (str[pos] == SP || str[pos] == HT) {
        pos++;
    }
    str += pos;
    len -= pos;

    hdridx[nhdr].val  = (char *)str;
    hdridx[nhdr].vlen = maxhdrlen - ((intptr_t)str - head);
    rv                = parse_hval(str, len, &pos, &hdridx[nhdr].vlen);
    if (rv != PARSE_OK) {
        return rv;
    }
    str += pos;
    len -= pos;
    // set header
    if (hdridx[nhdr].vlen) {
        nhdr++;
    }

    goto RETRY;

PUSH_HEADERS:
    while (nhdr) {
        // check existing kv table of key
        lauxh_pushref(L, hdridx->lkey);
        lua_rawget(L, tblidx);
        switch (lua_type(L, -1)) {
        default: {
            int idx = lauxh_rawlen(L, tblidx) + 1;
            lua_pop(L, 1);
            // create kv table
            lua_createtable(L, 3, 0);
            lauxh_pushint2tbl(L, "idx", idx);
            lauxh_pushlstr2tbl(L, "key", hdridx->key, hdridx->klen);
            // create kv->val table
            lua_pushliteral(L, "val");
            lua_createtable(L, 1, 0);
            lauxh_pushlstr2arr(L, 1, hdridx->val, hdridx->vlen);
            lua_rawset(L, -3);

            // push kv table to tbl[key]
            lauxh_pushref(L, hdridx->lkey);
            // copy kv table
            lua_pushvalue(L, -2);
            lua_rawset(L, tblidx);

            // push kv table to tbl[idx]
            lua_rawseti(L, tblidx, idx);
        } break;

        case LUA_TTABLE: {
            // get kv->val table
            lua_pushliteral(L, "val");
            lua_rawget(L, -2);
            // append to tail
            lauxh_pushlstr2arr(L, lauxh_rawlen(L, -1) + 1, hdridx->val,
                               hdridx->vlen);
            lua_pop(L, 2);
        } break;
        }
        lauxh_unref(L, hdridx->lkey);
        nhdr--;
        hdridx++;
    }

    *cur = (uintptr_t)str - (uintptr_t)top;
    return PARSE_OK;
}

static int header_lua(lua_State *L)
{
    size_t len          = 0;
    unsigned char *str  = (unsigned char *)lauxh_checklstring(L, 1, &len);
    size_t cur          = (size_t)lauxh_optuint64(L, 3, 0);
    uint16_t maxhdrlen  = lauxh_optuint16(L, 4, DEFAULT_HDR_MAXLEN);
    uint8_t maxhdrnum   = lauxh_optuint8(L, 5, DEFAULT_HDR_MAXNUM);
    unsigned char *head = str;
    int rv              = 0;

    // check container table
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

    // set offset
    if (cur > len) {
        str += len;
        len -= len;
    } else {
        str += cur;
        len -= cur;
    }

    rv = parse_header(L, str, len, &cur, maxhdrlen, maxhdrnum);
    if (rv < 0) {
        return error_result_as_nil(L, rv, "header");
    }
    str += cur;
    lua_settop(L, 1);
    lua_pushinteger(L, (uintptr_t)str - (uintptr_t)head);
    return 1;
}

/**
 *  structure for 64 bit comparison
 */
typedef union {
    char str[8];
    uint64_t bit;
} match64bit_u;

static int parse_version(unsigned char *str, size_t len, size_t *cur,
                         double *ver)
{
// version length: HTTP/x.x
#define VER_LEN 8

    // versions
    static match64bit_u V_10 = {.str = "HTTP/1.0"};
    static match64bit_u V_11 = {.str = "HTTP/1.1"};

    if (len < VER_LEN) {
        return PARSE_EAGAIN;
    } else {
        match64bit_u src = {.bit = *(uint64_t *)str};

        *cur = VER_LEN;
        // HTTP/1.1
        if (src.bit == V_11.bit) {
            *ver = 1.1;
            return PARSE_OK;
        }
        // HTTP/1.0
        else if (src.bit == V_10.bit) {
            *ver = 1.0;
            return PARSE_OK;
        }
    }

    // invalid version format
    return PARSE_EVERSION;

#undef VER_LEN
}

static int parse_method(unsigned char *str, size_t len, size_t *cur,
                        size_t *mlen)
{
// maximum method length with SP
#define METHOD_LEN 8

    // methods
    static match64bit_u M_GET     = {.str = "GET"};
    static match64bit_u M_HEAD    = {.str = "HEAD"};
    static match64bit_u M_POST    = {.str = "POST"};
    static match64bit_u M_PUT     = {.str = "PUT"};
    static match64bit_u M_DELETE  = {.str = "DELETE"};
    static match64bit_u M_OPTIONS = {.str = "OPTIONS"};
    static match64bit_u M_TRACE   = {.str = "TRACE"};
    static match64bit_u M_CONNECT = {.str = "CONNECT"};

    size_t pos       = *cur;
    size_t maxlen    = pos + METHOD_LEN;
    match64bit_u src = {.bit = 0};

    if (len < maxlen) {
        return PARSE_EAGAIN;
    }
    while (str[pos] != SP) {
        pos++;
        if (pos == maxlen) {
            // method not implemented
            return PARSE_EMETHOD;
        }
    }
    len   = pos - *cur;
    *mlen = len;
    *cur  = pos + 1;

    switch (len) {
    case 3:
        src.str[0] = str[0];
        src.str[1] = str[1];
        src.str[2] = str[2];
        if (src.bit == M_GET.bit || src.bit == M_PUT.bit) {
            return PARSE_OK;
        }
        return PARSE_EMETHOD;

    case 4:
        src.str[0] = str[0];
        src.str[1] = str[1];
        src.str[2] = str[2];
        src.str[3] = str[3];
        if (src.bit == M_POST.bit || src.bit == M_HEAD.bit) {
            return PARSE_OK;
        }
        return PARSE_EMETHOD;

    case 5:
        src.str[0] = str[0];
        src.str[1] = str[1];
        src.str[2] = str[2];
        src.str[3] = str[3];
        src.str[4] = str[4];
        if (src.bit == M_TRACE.bit) {
            return PARSE_OK;
        }
        return PARSE_EMETHOD;

    case 6:
        src.str[0] = str[0];
        src.str[1] = str[1];
        src.str[2] = str[2];
        src.str[3] = str[3];
        src.str[4] = str[4];
        src.str[5] = str[5];
        if (src.bit == M_DELETE.bit) {
            return PARSE_OK;
        }
        return PARSE_EMETHOD;

    case 7:
        src.str[0] = str[0];
        src.str[1] = str[1];
        src.str[2] = str[2];
        src.str[3] = str[3];
        src.str[4] = str[4];
        src.str[5] = str[5];
        src.str[6] = str[6];
        if (src.bit == M_OPTIONS.bit || src.bit == M_CONNECT.bit) {
            return PARSE_OK;
        }
        return PARSE_EMETHOD;
    }

    // method not implemented
    return PARSE_EMETHOD;

#undef METHOD_LEN
}

static int request_lua(lua_State *L)
{
    size_t len          = 0;
    unsigned char *str  = (unsigned char *)lauxh_checklstring(L, 1, &len);
    uint16_t maxmsglen  = lauxh_optuint16(L, 3, DEFAULT_MSG_MAXLEN);
    uint16_t maxhdrlen  = lauxh_optuint16(L, 4, DEFAULT_HDR_MAXLEN);
    uint8_t maxhdrnum   = lauxh_optuint8(L, 5, DEFAULT_HDR_MAXNUM);
    unsigned char *head = str;
    const char *method  = NULL;
    size_t mlen         = 0;
    const char *uri     = NULL;
    size_t ulen         = 0;
    double ver          = 0;
    size_t cur          = 0;
    int rv              = 0;

    // check container table
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

SKIP_NEXT_CRLF:
    switch (*str) {
    // need more bytes
    case 0:
        return error_result_as_nil(L, PARSE_EAGAIN, "request");

    case CR:
    case LF:
        str++;
        len--;
        goto SKIP_NEXT_CRLF;
    }

    method = (const char *)str;
    rv     = parse_method(str, len, &cur, &mlen);
    if (rv != PARSE_OK) {
        return error_result_as_nil(L, rv, "request");
    }
    str += cur;
    len -= cur;

    // parse-uri (find SP delimiter)
    uri = (const char *)str;
    if (len > maxmsglen) {
        if (!(str = memchr(str, SP, maxmsglen))) {
            return error_result_as_nil(L, PARSE_ELEN, "request");
        }
    } else if (!(str = memchr(str, SP, len))) {
        return error_result_as_nil(L, PARSE_EAGAIN, "request");
    }
    ulen = str - (unsigned char *)uri;
    str++;
    len -= ulen + 1;

    rv = parse_version(str, len, &cur, &ver);
    if (rv != PARSE_OK) {
        return error_result_as_nil(L, rv, "request");
    }
    switch (str[cur]) {
    case 0:
        return error_result_as_nil(L, PARSE_EAGAIN, "request");

    case CR:
        // null-terminated
        if (!str[cur + 1]) {
            return error_result_as_nil(L, PARSE_EAGAIN, "request");
        }
        // invalid end-of-line terminator
        else if (str[cur + 1] != LF) {
            return error_result_as_nil(L, PARSE_EEOL, "request");
        }
        cur++;

    case LF:
        cur++;
        break;

    default:
        return error_result_as_nil(L, PARSE_EVERSION, "request");
    }

    // set result to table
    lauxh_pushlstr2tbl(L, "method", method, mlen);
    lauxh_pushlstr2tbl(L, "uri", uri, ulen);
    lauxh_pushnum2tbl(L, "version", ver);
    // number of bytes consumed
    str += cur;
    len -= cur;

    // parse header if exists
    lua_pushliteral(L, "header");
    lua_rawget(L, -2);
    if (lua_type(L, -1) == LUA_TTABLE) {
        rv = parse_header(L, str, len, &cur, maxhdrlen, maxhdrnum);
        if (rv < 0) {
            return error_result_as_nil(L, rv, "request");
        }
        str += cur;
    }

    lua_settop(L, 1);
    lua_pushinteger(L, (uintptr_t)str - (uintptr_t)head);
    return 1;
}

static int parse_reason(unsigned char *str, size_t len, size_t *cur,
                        size_t *maxlen)
{
    size_t pos      = 0;
    unsigned char c = 0;

    for (; pos < len; pos++) {
        // phrase-length too large
        if (pos > *maxlen) {
            return PARSE_ELEN;
        }

        c = str[pos];
        switch (VCHAR[c]) {
        case 1:
        case 2:
            continue;

        // LF or CR
        case 3:
            *maxlen = pos;

            // found LF
            if (c == LF) {
                pos++;
            }
            // found LF after CR
            else if (str[pos + 1] == LF) {
                pos += 2;
            }
            // null-terminated
            else if (!str[pos + 1]) {
                return PARSE_EAGAIN;
            }
            // invalid end-of-line terminator
            else {
                return PARSE_EEOL;
            }

            *cur = pos;
            return PARSE_OK;

        // invalid
        default:
            return PARSE_EMSG;
        }
    }

    // phrase-length too large
    if (len > *maxlen) {
        return PARSE_ELEN;
    }

    return PARSE_EAGAIN;
}

static int parse_status(unsigned char *str, size_t len, size_t *cur,
                        int *status)
{
// status length
#define STATUS_LEN 3

    if (len <= STATUS_LEN) {
        return PARSE_EAGAIN;
    } else if (str[STATUS_LEN] != SP) {
        return PARSE_ESTATUS;
    }
    // invalid status code
    else if (str[0] < '1' || str[0] > '5' || str[1] < '0' || str[1] > '9' ||
             str[2] < '0' || str[2] > '9') {
        return PARSE_ESTATUS;
    }

    *cur    = STATUS_LEN + 1;
    // set status
    *status = (str[0] - 0x30) * 100 + (str[1] - 0x30) * 10 + (str[2] - 0x30);
    return PARSE_OK;

#undef STATUS_LEN
}

static int response_lua(lua_State *L)
{
    size_t len          = 0;
    unsigned char *str  = (unsigned char *)lauxh_checklstring(L, 1, &len);
    uint16_t maxmsglen  = lauxh_optuint16(L, 3, DEFAULT_MSG_MAXLEN);
    uint16_t maxhdrlen  = lauxh_optuint16(L, 4, DEFAULT_HDR_MAXLEN);
    uint8_t maxhdrnum   = lauxh_optuint8(L, 5, DEFAULT_HDR_MAXNUM);
    unsigned char *head = str;
    size_t cur          = 0;
    double ver          = 0;
    int status          = 0;
    const char *reason  = NULL;
    size_t rlen         = 0;
    int rv              = 0;

    // check container table
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

SKIP_NEXT_CRLF:
    switch (*str) {
    // need more bytes
    case 0:
        return error_result_as_nil(L, PARSE_ERR_EAGAIN, "response");

    case CR:
    case LF:
        str++;
        len--;
        goto SKIP_NEXT_CRLF;
    }

    rv = parse_version(str, len, &cur, &ver);
    if (rv != PARSE_OK) {
        return error_result_as_nil(L, rv, "response");
    } else if (!str[cur]) {
        return error_result_as_nil(L, PARSE_EAGAIN, "response");
    } else if (str[cur] != SP) {
        return error_result_as_nil(L, PARSE_EVERSION, "response");
    }
    str += cur + 1;
    len -= cur + 1;

    rv = parse_status(str, len, &cur, &status);
    if (rv != PARSE_OK) {
        return error_result_as_nil(L, rv, "response");
    }
    str += cur;
    len -= cur;

    reason = (const char *)str;
    rlen   = maxmsglen;
    rv     = parse_reason(str, len, &cur, &rlen);
    if (rv != PARSE_OK) {
        return error_result_as_nil(L, rv, "response");
    }

    // set result to table
    lauxh_pushnum2tbl(L, "version", ver);
    lauxh_pushint2tbl(L, "status", status);
    lauxh_pushlstr2tbl(L, "reason", reason, rlen);
    // number of bytes consumed
    str += cur;
    len -= cur;

    // parse header if exists
    lua_pushliteral(L, "header");
    lua_rawget(L, -2);
    if (lua_type(L, -1) == LUA_TTABLE) {
        rv = parse_header(L, str, len, &cur, maxhdrlen, maxhdrnum);
        if (rv < 0) {
            return error_result_as_nil(L, rv, "response");
        }
        str += cur;
    }

    lua_settop(L, 1);
    lua_pushinteger(L, (uintptr_t)str - (uintptr_t)head);
    return 1;
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

    lua_createtable(L, 0, sizeof(funcs) / sizeof(struct luaL_Reg) + 12);
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

    return 1;
}
