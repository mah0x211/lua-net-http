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

#include "lauxhlib.h"
#include <errno.h>
#include <lua.h>
#include <stdlib.h>
#include <string.h>

/* delimiters */
#define CR    '\r'
#define LF    '\n'
#define SP    ' '
#define HT    '\t'
#define COLON ':'

/**
 * return code
 */
/* success */
#define PARSE_OK       0
/* need more bytes */
#define PARSE_EAGAIN   -1
/* invalid message */
#define PARSE_EMSG     -2
/* message-length too large */
#define PARSE_EMSGLEN  -3
/* method not implemented */
#define PARSE_EMETHOD  -4
/* version not supported */
#define PARSE_EVERSION -5
/* invalid end-of-line terminator */
#define PARSE_EEOL     -6
/* invalid header field-name */
#define PARSE_EHDRNAME -7
/* invalid header field-val */
#define PARSE_EHDRVAL  -8
/* header-length too large */
#define PARSE_EHDRLEN  -9
/* too many headers */
#define PARSE_EHDRNUM  -10
/* invalid status code */
#define PARSE_ESTATUS  -11

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
    //   !   "   #    $    %    &    '    (  )   *    +   ,   -    .   /
    '!', 0, '#', '$', '%', '&', '\'', 0, 0, '*', '+', 0, '-', '.', 0,
    //   0    1    2    3    4    5    6    7    8    9
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    //  :  ;  <  =  >  ?  @
    1, 0, 0, 0, 0, 0, 0,
    //   A    B    C    D    E    F    G    H    I    J    K    L    M    N    O
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
    //   P   Q     R    S    T    U    V    W    X    Y    Z
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
    //  [  \  ]   ^    _    `
    0, 0, 0, '^', '_', '`',
    //   a    b    c    d    e    f    g    h    i    j    k    l    m    n    o
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
    //   p    q    r    s    t    u    v    w    x    y    z
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
    //  {   |   }   ~
    0, '|', 0, '~'};

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
    //                             HT LF       CR
    0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0,
    //  SP !  "  #  $  %  &  '  (  )  *  +  ,  -  .  /
    2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
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

static int parse_hval(unsigned char *str, size_t len, size_t *cur,
                      size_t *maxhdrlen)
{
    size_t tail     = 0;
    size_t pos      = 0;
    unsigned char c = 0;

    for (; pos < len; pos++) {
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

            // check length
            if (tail > *maxhdrlen) {
                return PARSE_EHDRLEN;
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
#define DEFAULT_MAX_HDRLEN 4108
#define DEFAULT_MAX_HDRNUM UINT8_MAX
#define DEFAULT_MAX_MSGLEN 2048

static int header_value_lua(lua_State *L)
{
    size_t len      = 0;
    const char *str = lauxh_checklstring(L, 1, &len);
    size_t maxlen   = (size_t)lauxh_optuint16(L, 2, DEFAULT_MAX_HDRLEN);
    size_t cur      = 0;
    int rv          = parse_hval((unsigned char *)str, len, &cur, &maxlen);

    switch (rv) {
    case PARSE_EAGAIN:
        if (VCHAR[str[len - 1]] == 1) {
            lua_pushlstring(L, str, len);
            return 1;
        }

    case PARSE_OK:
    case PARSE_EEOL:
        // str must not contain the end-of-line terminator (CRLF)
        rv = PARSE_EHDRVAL;
    default:
        lua_pushnil(L);
        lua_pushinteger(L, rv);
        return 2;
    }
}

static int parse_hkey(unsigned char *str, size_t len, size_t *cur,
                      size_t *maxhdrlen)
{
    size_t pos      = 0;
    unsigned char c = 0;

    for (; pos < len; pos++) {
        c = TCHAR[str[pos]];
        switch (c) {
        // illegal byte sequence
        case 0:
            return PARSE_EHDRNAME;

        // found COLON
        case 1:
            // check length
            if (pos == 0) {
                return PARSE_EHDRNAME;
            } else if (pos > *maxhdrlen) {
                return PARSE_EHDRLEN;
            }

            *maxhdrlen = pos;
            *cur       = pos + 1;
            return PARSE_OK;

        default:
            str[pos] = c;
            continue;
        }
    }

    // header-length too large
    if (len > *maxhdrlen) {
        return PARSE_EHDRLEN;
    }

    return PARSE_EAGAIN;
}

static int header_name_lua(lua_State *L)
{
    size_t len      = 0;
    const char *str = lauxh_checklstring(L, 1, &len);
    size_t maxlen   = (size_t)lauxh_optuint16(L, 2, DEFAULT_MAX_HDRLEN);
    size_t cur      = 0;
    int rv          = parse_hkey((unsigned char *)str, len, &cur, &maxlen);

    switch (rv) {
    case PARSE_EAGAIN:
        lua_pushlstring(L, str, len);
        return 1;

    case PARSE_OK:
        // str must not contains the field separator (COLON)
        rv = PARSE_EHDRNAME;
    default:
        lua_pushnil(L);
        lua_pushinteger(L, rv);
        return 2;
    }
}

typedef struct {
    const char *key;
    const char *val;
    size_t klen;
    size_t vlen;
} header_t;

static int parse_header(lua_State *L, unsigned char *str, size_t len,
                        size_t offset, uint16_t maxhdrlen, uint8_t maxhdrnum)
{
    int tblidx       = lua_gettop(L);
    header_t *hdridx = lua_newuserdata(L, sizeof(header_t) * maxhdrnum);
    uintptr_t top    = (uintptr_t)str;
    uintptr_t head   = 0;
    uint8_t nhdr     = 0;
    size_t cur       = 0;
    int rv           = 0;

    // set offset
    if (offset > len) {
        str += len;
        len -= len;
    } else {
        str += offset;
        len -= offset;
    }

RETRY:
    switch (*str) {
    // need more bytes
    case 0:
        lua_settop(L, 0);
        lua_pushinteger(L, PARSE_EAGAIN);
        return 1;

    // check header-tail
    case CR:
        // null-terminated
        if (!str[1]) {
            lua_settop(L, 0);
            lua_pushinteger(L, PARSE_EAGAIN);
            return 1;
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
        lua_settop(L, 0);
        lua_pushinteger(L, PARSE_EHDRNUM);
        return 1;
    }

    head              = (uintptr_t)str;
    hdridx[nhdr].key  = (const char *)str;
    hdridx[nhdr].klen = maxhdrlen;
    rv                = parse_hkey(str, len, &cur, &hdridx[nhdr].klen);
    if (rv != PARSE_OK) {
        lua_settop(L, 0);
        lua_pushinteger(L, rv);
        return 1;
    }
    // skip OWS
    while (str[cur] == SP || str[cur] == HT) {
        cur++;
    }
    str += cur;
    len -= cur;

    hdridx[nhdr].val  = (const char *)str;
    hdridx[nhdr].vlen = maxhdrlen - ((uintptr_t)str - head);
    rv                = parse_hval(str, len, &cur, &hdridx[nhdr].vlen);
    if (rv != PARSE_OK) {
        lua_settop(L, 0);
        lua_pushinteger(L, rv);
        return 1;
    }
    str += cur;
    len -= cur;
    // set header
    if (hdridx[nhdr].vlen) {
        nhdr++;
    }

    goto RETRY;

PUSH_HEADERS:
    while (nhdr) {
        // check existing value of key
        lua_pushlstring(L, hdridx->key, hdridx->klen);
        lua_rawget(L, tblidx);
        switch (lua_type(L, -1)) {
        case LUA_TNIL:
            lua_pop(L, 1);
            lua_pushlstring(L, hdridx->key, hdridx->klen);
            lua_pushlstring(L, hdridx->val, hdridx->vlen);
            lua_rawset(L, tblidx);
            break;

        case LUA_TSTRING:
            lua_pushlstring(L, hdridx->key, hdridx->klen);
            lua_createtable(L, 3, 0);
            // set existing value to table
            lua_pushvalue(L, -3);
            lua_rawseti(L, -2, 1);
            // set value to table
            lua_pushlstring(L, hdridx->val, hdridx->vlen);
            lua_rawseti(L, -2, 2);
            // replace existing value to table
            lua_rawset(L, tblidx);
            lua_pop(L, 1);
            break;

        case LUA_TTABLE:
            // set value to table
            lua_pushlstring(L, hdridx->val, hdridx->vlen);
            lua_rawseti(L, -2, lauxh_rawlen(L, -2) + 1);
            lua_pop(L, 1);
            break;
        }

        nhdr--;
        hdridx++;
    }

    lua_settop(L, 0);
    lua_pushinteger(L, (uintptr_t)str - top);
    return 1;
}

static int header_lua(lua_State *L)
{
    size_t len         = 0;
    unsigned char *str = (unsigned char *)lauxh_checklstring(L, 1, &len);
    size_t offset      = (size_t)lauxh_optuint64(L, 3, 0);
    uint16_t maxhdrlen = lauxh_optuint16(L, 4, DEFAULT_MAX_HDRLEN);
    uint8_t maxhdrnum  = lauxh_optuint8(L, 5, DEFAULT_MAX_HDRNUM);

    // check container table
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

    return parse_header(L, str, len, offset, maxhdrlen, maxhdrnum);
}

/**
 *  structure for 64 bit comparison
 */
typedef union {
    char str[8];
    uint64_t bit;
} match64bit_u;

static int parse_version(unsigned char *str, size_t len, size_t *cur, int *ver)
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
            *ver = 11;
            return PARSE_OK;
        }
        // HTTP/1.0
        else if (src.bit == V_10.bit) {
            *ver = 10;
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
// method length
#define METHOD_LEN 7

    // methods
    static match64bit_u M_GET     = {.str = "GET"};
    static match64bit_u M_HEAD    = {.str = "HEAD"};
    static match64bit_u M_POST    = {.str = "POST"};
    static match64bit_u M_PUT     = {.str = "PUT"};
    static match64bit_u M_DELETE  = {.str = "DELETE"};
    static match64bit_u M_OPTIONS = {.str = "OPTIONS"};
    static match64bit_u M_TRACE   = {.str = "TRACE"};
    static match64bit_u M_CONNECT = {.str = "CONNECT"};

    if (len <= METHOD_LEN) {
        return PARSE_EAGAIN;
    } else {
        void *sp = memchr((const void *)str, SP, len);

        if (sp) {
            size_t slen      = (uintptr_t)sp - (uintptr_t)str;
            match64bit_u src = {.bit = 0};

            *mlen = slen;
            *cur  = slen + 1;

            switch (slen) {
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
        }

        // method not implemented
        return PARSE_EMETHOD;
    }

#undef METHOD_LEN
}

/**
 * RFC 3986
 *
 * alpha         = lowalpha | upalpha
 * lowalpha      = "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" |
 *                 "j" | "k" | "l" | "m" | "n" | "o" | "p" | "q" | "r" |
 *                 "s" | "t" | "u" | "v" | "w" | "x" | "y" | "z"
 * upalpha       = "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" |
 *                 "J" | "K" | "L" | "M" | "N" | "O" | "P" | "Q" | "R" |
 *                 "S" | "T" | "U" | "V" | "W" | "X" | "Y" | "Z"
 * --------------------------------------------------------------------------
 * digit         = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9"
 * --------------------------------------------------------------------------
 * pct-encoded   = "%" hex hex
 * hex           = digit | "A" | "B" | "C" | "D" | "E" | "F" |
 *                         "a" | "b" | "c" | "d" | "e" | "f"
 * --------------------------------------------------------------------------
 * gen-delims    = ":" | "/" | "?" | "#" | "[" | "]" | "@"
 * --------------------------------------------------------------------------
 * sub-delims    = "!" | "$" | "&" | "'" | "(" | ")" | "*" | "+" | "," | ";"
 *                 "="
 * --------------------------------------------------------------------------
 * reserved      = gen-delims | sub-delims
 * --------------------------------------------------------------------------
 * unreserved    = alpha | digit | "-" | "." | "_" | "~"
 * --------------------------------------------------------------------------
 * pchar         = unreserved | pct-encoded | sub-delim | ":" | "@"
 * --------------------------------------------------------------------------
 * URI           = scheme "://"
 *                 [ userinfo[ ":" userinfo ] "@" ]
 *                 host
 *                 [ ":" port ]
 *                 path
 *                 [ "?" query ]
 *                 [ "#" fragment ]
 * --------------------------------------------------------------------------
 * scheme        = alpha *( alpha / digit / "+" / "-" / "." )
 * --------------------------------------------------------------------------
 * userinfo      = *( unreserved / pct-encoded / sub-delims )
 * --------------------------------------------------------------------------
 * host          = IP-literal / IPv4address / reg-name
 * --------------------------------------------------------------------------
 * port          = *digit
 * --------------------------------------------------------------------------
 * path          = empty / *( "/" pchar )
 * empty         = zero characters
 * --------------------------------------------------------------------------
 * query         = *( pchar / "/" / "?" )
 * --------------------------------------------------------------------------
 * fragment      = query
 * --------------------------------------------------------------------------
 */
static const unsigned char URIC_TBL[256] = {
    //  ctrl-code: 0-32
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0,
    //  SP       "  #
    SP, '!', 0, 0, '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/',
    //  digit
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',

    //            <       >
    ':', ';', 0, '=', 0, '?', '@',

    //  alpha-upper
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O',
    'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',

    //       \       ^       `
    '[', 0, ']', 0, '_', 0,

    //  alpha-lower
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',

    //  {  |  }
    0, 0, 0, '~'};

static int request_lua(lua_State *L)
{
    size_t len          = 0;
    unsigned char *str  = (unsigned char *)lauxh_checklstring(L, 1, &len);
    uint16_t maxmsglen  = lauxh_optuint16(L, 3, DEFAULT_MAX_MSGLEN);
    uint16_t maxhdrlen  = lauxh_optuint16(L, 4, DEFAULT_MAX_HDRLEN);
    uint8_t maxhdrnum   = lauxh_optuint8(L, 5, DEFAULT_MAX_HDRNUM);
    unsigned char *head = str;
    size_t hlen         = len;
    const char *method  = NULL;
    size_t mlen         = 0;
    const char *uri     = NULL;
    size_t ulen         = 0;
    int ver             = 0;
    size_t cur          = 0;
    int rv              = 0;

    // check container table
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

SKIP_NEXT_CRLF:
    switch (*str) {
    // need more bytes
    case 0:
        lua_pushinteger(L, PARSE_EAGAIN);
        return 1;

    case CR:
    case LF:
        str++;
        len--;
        goto SKIP_NEXT_CRLF;
    }

    method = (const char *)str;
    rv     = parse_method(str, len, &cur, &mlen);
    if (rv != PARSE_OK) {
        lua_pushinteger(L, rv);
        return 1;
    }
    str += cur;
    len -= cur;

    // parse-uri
    uri  = (const char *)str;
    ulen = 0;
CHECK_URI:
    if (ulen >= len) {
        lua_pushinteger(L, PARSE_EAGAIN);
        return 1;
    } else if (ulen > maxmsglen) {
        lua_pushinteger(L, PARSE_EMSGLEN);
        return 1;
    }
    switch (URIC_TBL[str[ulen]]) {
    case 0:
        lua_pushinteger(L, PARSE_EMSG);
        return 1;

    case SP:
        break;

    default:
        ulen++;
        goto CHECK_URI;
    }
    str += ulen + 1;
    len -= ulen + 1;

    rv = parse_version(str, len, &cur, &ver);
    if (rv != PARSE_OK) {
        lua_pushinteger(L, rv);
        return 1;
    }
    switch (str[cur]) {
    case 0:
        lua_pushinteger(L, PARSE_EAGAIN);
        return 1;

    case CR:
        // null-terminated
        if (!str[cur + 1]) {
            lua_pushinteger(L, PARSE_EAGAIN);
            return 1;
        }
        // invalid end-of-line terminator
        else if (str[cur + 1] != LF) {
            lua_pushinteger(L, PARSE_EEOL);
            return 1;
        }
        cur++;

    case LF:
        cur++;
        break;

    default:
        lua_pushinteger(L, PARSE_EVERSION);
        return 1;
    }

    // set result to table
    lauxh_pushlstr2tbl(L, "method", method, mlen);
    lauxh_pushlstr2tbl(L, "uri", uri, ulen);
    lauxh_pushint2tbl(L, "version", ver);
    // number of bytes consumed
    str += cur;

    // parse header if exists
    lua_pushliteral(L, "header");
    lua_rawget(L, -2);
    if (lua_type(L, -1) == LUA_TTABLE) {
        return parse_header(L, head, hlen, (uintptr_t)str - (uintptr_t)head,
                            maxhdrlen, maxhdrnum);
    }

    lua_settop(L, 0);
    lua_pushinteger(L, (uintptr_t)str - (uintptr_t)head);

    return 1;
}

static int parse_reason(unsigned char *str, size_t len, size_t *cur,
                        size_t *maxlen)
{
    size_t pos      = 0;
    unsigned char c = 0;

    for (; pos < len; pos++) {
        c = str[pos];
        switch (VCHAR[c]) {
        case 1:
        case 2:
            continue;

        // LF or CR
        case 3:
            // phrase-length too large
            if (pos > *maxlen) {
                return PARSE_EMSGLEN;
            }
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
        return PARSE_EMSGLEN;
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
    uint16_t maxmsglen  = lauxh_optuint16(L, 3, DEFAULT_MAX_MSGLEN);
    uint16_t maxhdrlen  = lauxh_optuint16(L, 4, DEFAULT_MAX_HDRLEN);
    uint8_t maxhdrnum   = lauxh_optuint8(L, 5, DEFAULT_MAX_HDRNUM);
    unsigned char *head = str;
    size_t hlen         = len;
    size_t cur          = 0;
    int ver             = 0;
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
        lua_pushinteger(L, PARSE_EAGAIN);
        return 1;

    case CR:
    case LF:
        str++;
        len--;
        goto SKIP_NEXT_CRLF;
    }

    rv = parse_version(str, len, &cur, &ver);
    if (rv != PARSE_OK) {
        lua_pushinteger(L, rv);
        return 1;
    } else if (!str[cur]) {
        lua_pushinteger(L, PARSE_EAGAIN);
        return 1;
    } else if (str[cur] != SP) {
        lua_pushinteger(L, PARSE_EVERSION);
        return 1;
    }
    str += cur + 1;
    len -= cur + 1;

    rv = parse_status(str, len, &cur, &status);
    if (rv != PARSE_OK) {
        lua_pushinteger(L, rv);
        return 1;
    }
    str += cur;
    len -= cur;

    reason = (const char *)str;
    rlen   = maxmsglen;
    rv     = parse_reason(str, len, &cur, &rlen);
    if (rv != PARSE_OK) {
        lua_pushinteger(L, rv);
        return 1;
    }

    // set result to table
    lauxh_pushint2tbl(L, "version", ver);
    lauxh_pushint2tbl(L, "status", status);
    lauxh_pushlstr2tbl(L, "reason", reason, rlen);
    // number of bytes consumed
    str += cur;

    // parse header if exists
    lua_pushliteral(L, "header");
    lua_rawget(L, -2);
    if (lua_type(L, -1) == LUA_TTABLE) {
        return parse_header(L, head, hlen, (uintptr_t)str - (uintptr_t)head,
                            maxhdrlen, maxhdrnum);
    }

    lua_settop(L, 0);
    lua_pushinteger(L, (uintptr_t)str - (uintptr_t)head);

    return 1;
}

static int strerror_lua(lua_State *L)
{
    switch (lauxh_checkinteger(L, 1)) {
    case PARSE_EAGAIN:
        lua_pushliteral(L, "need more bytes");
        return 1;

    case PARSE_EMSG:
        lua_pushliteral(L, "invalid message");
        return 1;

    case PARSE_EMSGLEN:
        lua_pushliteral(L, "message-length too large");
        return 1;

    case PARSE_EMETHOD:
        lua_pushliteral(L, "method not implemented");
        return 1;

    case PARSE_EVERSION:
        lua_pushliteral(L, "version not supported");
        return 1;

    case PARSE_EEOL:
        lua_pushliteral(L, "invalid end-of-line terminator");
        return 1;

    case PARSE_EHDRNAME:
        lua_pushliteral(L, "invalid header field-name");
        return 1;

    case PARSE_EHDRVAL:
        lua_pushliteral(L, "invalid header field-value");
        return 1;

    case PARSE_EHDRLEN:
        lua_pushliteral(L, "header-length too large");
        return 1;

    case PARSE_EHDRNUM:
        lua_pushliteral(L, "too many headers");
        return 1;

    case PARSE_ESTATUS:
        lua_pushliteral(L, "invalid status code");
        return 1;

    default:
        lua_pushliteral(L, "unknown error");
        return 1;
    }
}

LUALIB_API int luaopen_net_http_parse(lua_State *L)
{
    struct luaL_Reg funcs[] = {
        {"strerror",     strerror_lua    },
        {"response",     response_lua    },
        {"request",      request_lua     },
        {"header",       header_lua      },
        {"header_name",  header_name_lua },
        {"header_value", header_value_lua},
        {NULL,           NULL            }
    };
    struct luaL_Reg *ptr = funcs;

    lua_createtable(L, 0, sizeof(funcs) / sizeof(struct luaL_Reg) + 12);
    do {
        lauxh_pushfn2tbl(L, ptr->name, ptr->func);
        ptr++;
    } while (ptr->name);

    // constants
    // return code
    lauxh_pushint2tbl(L, "EAGAIN", PARSE_EAGAIN);
    lauxh_pushint2tbl(L, "EMSG", PARSE_EMSG);
    lauxh_pushint2tbl(L, "EMSGLEN", PARSE_EMSGLEN);
    lauxh_pushint2tbl(L, "EMETHOD", PARSE_EMETHOD);
    lauxh_pushint2tbl(L, "EVERSION", PARSE_EVERSION);
    lauxh_pushint2tbl(L, "EEOL", PARSE_EEOL);
    lauxh_pushint2tbl(L, "EHDRNAME", PARSE_EHDRNAME);
    lauxh_pushint2tbl(L, "EHDRVAL", PARSE_EHDRVAL);
    lauxh_pushint2tbl(L, "EHDRLEN", PARSE_EHDRLEN);
    lauxh_pushint2tbl(L, "EHDRNUM", PARSE_EHDRNUM);
    lauxh_pushint2tbl(L, "ESTATUS", PARSE_ESTATUS);

    return 1;
}
