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

#include <limits.h>
#include <stdint.h>
#include <string.h>
// lua
#include <lua_error.h>
// hwire
#include "hwire.h"

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
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 0, 0, 0, 0, 0, 0, 0,
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

static inline unsigned char is_tchar(unsigned char c)
{
    return TCHAR[c];
}

// strtchar: count consecutive tchar characters with lowercase conversion
// Returns the number of consecutive characters from the beginning of str
// that are valid tchar. Stops at first non-tchar or end of string.

#define STRTCHAR_NOOP ((void)0)

#define STRTCHAR_EX_CHECK(str, pos, c, udf)                                    \
    {                                                                          \
        c = is_tchar((str)[pos]);                                              \
        if (!c)                                                                \
            break;                                                             \
        udf;                                                                   \
        pos++;                                                                 \
    }

#define strtchar_ex(str, len, pos, c, udf)                                     \
    ({                                                                         \
        while (pos + 8 <= (len)) {                                             \
            STRTCHAR_EX_CHECK((str), pos, c, udf);                             \
            STRTCHAR_EX_CHECK((str), pos, c, udf);                             \
            STRTCHAR_EX_CHECK((str), pos, c, udf);                             \
            STRTCHAR_EX_CHECK((str), pos, c, udf);                             \
            STRTCHAR_EX_CHECK((str), pos, c, udf);                             \
            STRTCHAR_EX_CHECK((str), pos, c, udf);                             \
            STRTCHAR_EX_CHECK((str), pos, c, udf);                             \
            STRTCHAR_EX_CHECK((str), pos, c, udf);                             \
        }                                                                      \
        while (pos < (len)) {                                                  \
            STRTCHAR_EX_CHECK((str), pos, c, udf);                             \
        }                                                                      \
        pos;                                                                   \
    })

#define strtchar(str, len)                                                     \
    ({                                                                         \
        size_t pos      = 0;                                                   \
        unsigned char c = 0;                                                   \
        strtchar_ex((str), (len), pos, c, STRTCHAR_NOOP);                      \
    })

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
// 1 = field-content (VCHAR or obs-text)
// 0 = invalid (including DEL)
static const unsigned char VCHAR[256] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    // VCHAR 0x21 - 0x7E
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    // except DEL 0x7F
    0,
    // all obs-text 0x80 - 0xFF
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1};

// is_vchar: check if character is field-content (VCHAR or obs-text)
// Returns 1 if VCHAR[c] == 1, otherwise returns 0
static inline int is_vchar(unsigned char c)
{
    return VCHAR[c] == 1;
}

// strvchar_lut: LUT-based implementation (fallback)
static inline size_t strvchar_lut(const unsigned char *str, size_t len)
{
    size_t pos = 0;

#define CHECK_VCHAR()                                                          \
    do {                                                                       \
        if (!is_vchar(str[pos])) {                                             \
            return pos;                                                        \
        }                                                                      \
        pos++;                                                                 \
    } while (0)

    // Process 8 bytes at a time (manual unrolling)
    while (pos + 8 <= len) {
        CHECK_VCHAR();
        CHECK_VCHAR();
        CHECK_VCHAR();
        CHECK_VCHAR();
        CHECK_VCHAR();
        CHECK_VCHAR();
        CHECK_VCHAR();
        CHECK_VCHAR();
    }

#undef CHECK_VCHAR

    // Handle remaining bytes (< 8)
    while (pos < len && is_vchar(str[pos])) {
        pos++;
    }
    return pos;
}

#if defined(__aarch64__) || (defined(__arm__) && defined(__ARM_NEON))
# include <arm_neon.h>

// strvchar_neon: NEON-optimized implementation (16 bytes)
//
// Algorithm: Blacklist approach - detect invalid characters
// - Invalid: 0x00-0x20 (control chars + SP) or 0x7F (DEL)
// - Valid:   0x21-0x7E (VCHAR) or 0x80-0xFF (obs-text)
//
// Each byte in 'invalid' vector is either 0x00 (valid) or 0xFF (invalid).
// We extract the first 8 bytes as a 64-bit mask and find the first invalid
// byte.
//
// Safety analysis for __builtin_ctzll(mask) >> 3:
// - mask is 64 bits (8 bytes), so __builtin_ctzll(mask) max value is 63
// - 63 >> 3 = 7, which is within the 8-byte range (0-7)
// - Combined with pos, the result is always within the 16-byte chunk
static inline size_t strvchar_neon(const unsigned char *str, size_t len)
{
    size_t pos = 0;

    // Pre-compute constants (compile-time)
    const uint8x16_t threshold = vdupq_n_u8(0x21);
    const uint8x16_t del_byte  = vdupq_n_u8(0x7F);

    while (pos + 16 <= len) {
        // Load 16 bytes
        uint8x16_t data = vld1q_u8(str + pos);

        // Detect invalid characters using blacklist approach:
        // - lt_21:  bytes where data < 0x21 (invalid: 0x00-0x20)
        // - eq_7f:  bytes where data == 0x7F (invalid: DEL)
        // - invalid: OR of both conditions (0x00=valid, 0xFF=invalid)
        uint8x16_t lt_21   = vcltq_u8(data, threshold);
        uint8x16_t eq_7f   = vceqq_u8(data, del_byte);
        uint8x16_t invalid = vorrq_u8(lt_21, eq_7f);

        // Interpret the 16-byte vector as two 64-bit integers
        uint64x2_t qdata = vreinterpretq_u64_u8(invalid);

        // Check first 8 bytes (lower 64 bits)
        uint64_t mask1 = vgetq_lane_u64(qdata, 0);
        if (mask1) {
            // Find first set bit and convert to byte position
            // Each byte in mask1 is 0x00 or 0xFF, so ctzll gives the bit
            // position of the first invalid byte. Dividing by 8 (>> 3) converts
            // to byte position. Max value is 63 >> 3 = 7, which is safe.
            return pos + (__builtin_ctzll(mask1) >> 3);
        }

        // Check second 8 bytes (upper 64 bits)
        uint64_t mask2 = vgetq_lane_u64(qdata, 1);
        if (mask2) {
            // Same logic as mask1, but add 8 to account for offset
            return pos + 8 + (__builtin_ctzll(mask2) >> 3);
        }

        // All 16 bytes are valid, continue to next chunk
        pos += 16;
    }

    // Fall back to LUT for remaining bytes (< 16 bytes)
    return pos + strvchar_lut(str + pos, len - pos);
}

#endif

#if defined(__SSE2__)
# include <emmintrin.h>

// SIMD constants for threshold comparison (as int8_t for signed SIMD ops)
// Used by SSE2/AVX2 implementations to detect invalid characters using
// sign-flip technique: (data ^ 0x80) < (0x21 ^ 0x80) is equivalent to data <
// 0x21 Defined in SSE2 block since AVX2 implies SSE2 (superset)
# define SIMD_SIGN_FLIP         ((int8_t)0x80) // XOR mask to toggle sign bit
# define SIMD_THRESHOLD_SHIFTED ((int8_t)(0x21 ^ 0x80)) // = -95 (0xA1)

// strvchar_sse2: SSE2 optimized implementation (16 bytes)
//
// Algorithm: Blacklist approach using comparison and movemask
// - Invalid: 0x00-0x20 (control chars + SP) or 0x7F (DEL)
// - Valid:   0x21-0x7E (VCHAR) or 0x80-0xFF (obs-text)
//
// Technique: Toggle sign bit (XOR with 0x80) to enable unsigned comparison
// with signed comparison instructions (_mm_cmpgt_epi8).
// - Original:        0x00-0xFF unsigned
// - After XOR 0x80:  0x80-0x7F (now in signed range)
// - Compare with (0x21 ^ 0x80) to detect < 0x21
//
// _mm_movemask_epi8 creates a 16-bit mask where each bit represents
// whether the corresponding byte is invalid (1) or valid (0).
static inline size_t strvchar_sse2(const unsigned char *str, size_t len)
{
    size_t pos = 0;

    // Pre-compute constants (compile-time)
    const __m128i sign_flip = _mm_set1_epi8(SIMD_SIGN_FLIP);
    const __m128i threshold = _mm_set1_epi8(SIMD_THRESHOLD_SHIFTED);
    const __m128i del_byte  = _mm_set1_epi8(0x7F);

    while (pos + 16 <= len) {
        // Load 16 bytes (unaligned load)
        __m128i data = _mm_loadu_si128((const __m128i *)(str + pos));

        // Toggle sign bit to enable unsigned comparison with signed
        // instructions This transforms the unsigned comparison (data < 0x21)
        // into a signed one
        __m128i data_shifted = _mm_xor_si128(data, sign_flip);

        // Detect invalid characters:
        // - lt_21: bytes where (data ^ 0x80) < (0x21 ^ 0x80), i.e., data < 0x21
        // - eq_7f: bytes where data == 0x7F (DEL)
        __m128i lt_21 = _mm_cmpgt_epi8(threshold, data_shifted);
        __m128i eq_7f = _mm_cmpeq_epi8(data, del_byte);

        // Combine: invalid if lt_21 OR eq_7f
        __m128i invalid = _mm_or_si128(lt_21, eq_7f);

        // Create 16-bit mask: bit i is 1 if byte i is invalid
        int mask = _mm_movemask_epi8(invalid);
        if (mask) {
            // __builtin_ctz(mask) returns the position of the first set bit
            // which corresponds to the first invalid byte position (0-15)
            return pos + __builtin_ctz(mask);
        }

        // All 16 bytes are valid, continue to next chunk
        pos += 16;
    }

    // Fall back to LUT for remaining bytes (< 16 bytes)
    return pos + strvchar_lut(str + pos, len - pos);
}

#endif

#if defined(__AVX2__)
# include <immintrin.h>

// strvchar_avx2: AVX2 optimized implementation (32 bytes)
//
// Algorithm: Blacklist approach using 256-bit SIMD
// - Invalid: 0x00-0x20 (control chars + SP) or 0x7F (DEL)
// - Valid:   0x21-0x7E (VCHAR) or 0x80-0xFF (obs-text)
static inline size_t strvchar_avx2(const unsigned char *str, size_t len)
{
    size_t pos = 0;

    // Pre-compute constants (compile-time)
    const __m256i sign_flip = _mm256_set1_epi8(SIMD_SIGN_FLIP);
    const __m256i threshold = _mm256_set1_epi8(SIMD_THRESHOLD_SHIFTED);
    const __m256i del_byte  = _mm256_set1_epi8(0x7F);

    // Process 32 bytes at a time
    while (pos + 32 <= len) {
        __m256i data         = _mm256_loadu_si256((const __m256i *)(str + pos));
        __m256i data_shifted = _mm256_xor_si256(data, sign_flip);
        __m256i lt_21        = _mm256_cmpgt_epi8(threshold, data_shifted);
        __m256i eq_7f        = _mm256_cmpeq_epi8(data, del_byte);
        __m256i invalid      = _mm256_or_si256(lt_21, eq_7f);
        int mask             = _mm256_movemask_epi8(invalid);
        if (mask) {
            return pos + __builtin_ctz(mask);
        }
        pos += 32;
    }

    // Fall back to SSE2 for remaining bytes (< 32 bytes)
    return pos + strvchar_sse2(str + pos, len - pos);
}

#endif

// strvchar: count consecutive field-content characters (VCHAR or obs-text)
// Returns the number of consecutive characters from the beginning of str
// that are field-content (VCHAR or obs-text)
static inline size_t strvchar(const unsigned char *str, size_t len)
{
#if defined(__AVX2__)
    return strvchar_avx2(str, len);
#elif defined(__SSE2__)
    return strvchar_sse2(str, len);
#elif defined(__aarch64__) || (defined(__arm__) && defined(__ARM_NEON))
    return strvchar_neon(str, len);
#else
    // Fall back to LUT for remaining bytes
    return strvchar_lut(str, len);
#endif
}

static int vchar_lua(lua_State *L)
{
    size_t len         = 0;
    unsigned char *str = (unsigned char *)lauxh_checklstring(L, 1, &len);

    if (!len) {
        return error_result_as_false(L, PARSE_EAGAIN, "vchar");
    }

    // Use SIMD-accelerated strvchar to check all characters
    size_t n = strvchar(str, len);
    if (n != len) {
        return error_result_as_false(L, PARSE_EILSEQ, "vchar");
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
    uint64_t dec = 0;

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
        }
        // accumulate digit
        dec = (dec << 4) | (c - 1);

        if (dec > (uint64_t)SSIZE_MAX) {
            // result too large
            // limit to max value of 32bit (0x7FFFFFFF)
            return PARSE_ERANGE;
        }
    }

    *cur = len;
    return (ssize_t)dec;
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
    0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, // HTAB
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
    1, // 0x20 - 0x21 SP and exclamation mark
    0, // 0x22 double-quote
    // 0x23 - 0x5B
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1,
    0, // 0x5C backslash
    // 0x5D - 0x7E
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1,
    0, // DEL 0x7F
    // all obs-text 0x80 - 0xFF
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1};

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
        unsigned char c = str[pos];
        if (pos > *maxlen) {
            return PARSE_ELEN;
        } else if (!QDTEXT[c]) {
            switch (c) {
            case DQUOTE:
                *maxlen = pos - head;
                *cur    = pos + 1;
                return PARSE_OK;

            case BACKSLASH:
                // quoted-pair = "\" ( HTAB / SP / VCHAR / obs-text )
                if (pos + 1 >= len) {
                    // reach to the end of string, need more bytes
                    return PARSE_EAGAIN;
                }
                c = str[pos + 1];
                if (is_vchar(c) || c == HT || c == SP) {
                    // valid quoted-pair
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
    size_t tail           = (len > maxlen) ? maxlen : len;
    size_t cur            = 0;
    size_t head           = 0;
    unsigned char c       = 0;

    // check container table
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

    if (!len) {
        return error_result_as_false(L, PARSE_EAGAIN, "parameters");
    }

    // parse parameter
CHECK_PARAM:
    // skip OWS
    if (skip_ws(str, tail, &cur, maxlen) != PARSE_OK) {
        return error_result_as_false(L, PARSE_ELEN, "parameters");
    }
    // parse parameter-name
    head = cur;
    strtchar_ex(str, tail, cur, c, { str[cur] = c; });
    if (cur == maxlen && len > maxlen) {
        return error_result_as_false(L, PARSE_ELEN, "parameters");
    } else if (str[cur] != '=') {
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
        switch (parse_quoted_string(str, tail, &cur, &qlen)) {
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
    cur += strtchar(str + cur, tail - cur);
    if (cur == maxlen && len > maxlen) {
        return error_result_as_false(L, PARSE_ELEN, "parameters");
    }
    lua_pushlstring(L, (const char *)str + head, cur - head);
    lua_rawset(L, 2);

CHECK_EOL:
    if (skip_ws(str, tail, &cur, maxlen) != PARSE_OK) {
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
    do {                                                                       \
        if (skip_ws(str, len, &cur, maxlen) != PARSE_OK) {                     \
            return error_result_as_nil(L, PARSE_ELEN, "chunksize");            \
        } else if (str[cur] == 0) {                                            \
            /* more bytes need */                                              \
            return error_result_as_nil(L, PARSE_EAGAIN, "chunksize");          \
        }                                                                      \
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
    cur += strtchar(str + cur, len - cur);
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
    cur += strtchar(str + cur, len - cur);
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
    size_t pos       = 0;
    size_t ows_start = SIZE_MAX;
    size_t maxlen    = (len > *maxhdrlen) ? *maxhdrlen : len;

CHECK_NEXT:
    pos += strvchar(str + pos, maxlen - pos);
    if (pos < maxlen) {
        // stop at first non VCHAR/obs-text
        unsigned char c = str[pos];
        switch (c) {
        case HT:
        case SP:
            // skip OWS
            ows_start = pos;
            pos++;
            while (pos < maxlen && (str[pos] == HT || str[pos] == SP)) {
                pos++;
            }
            if (is_vchar(str[pos])) {
                // continue with field-content
                ows_start = SIZE_MAX;
            }
            goto CHECK_NEXT;

        case CR:
            if (!str[pos + 1]) {
                // null-terminator
                break;
            }
            if (str[pos + 1] != LF) {
                // invalid end-of-line terminator
                return PARSE_EEOL;
            }
        case LF:
            // set tail position
            *cur       = pos + 1 + (c == CR);
            *maxhdrlen = (ows_start == SIZE_MAX) ? pos : ows_start;
            return PARSE_OK;

        // invalid
        default:
            return PARSE_EHDRVAL;
        }
    }

CHECK_AGAIN:
    // header-length too large
    if (len > maxlen) {
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
        // end with field-content (VCHAR or obs-text)
        if (is_vchar(str[len - 1])) {
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

static int parse_hkey(lua_State *L, unsigned char *str, size_t len, size_t *cur,
                      size_t *maxhdrlen)
{
    int top         = lua_gettop(L);
    size_t maxlen   = (len > *maxhdrlen) ? *maxhdrlen : len;
    size_t pos      = 0;
    unsigned char c = 0;
    luaL_Buffer b   = {0};

    luaL_buffinit(L, &b);

    // Use strtchar to find the length of consecutive tchar
    size_t tchar_len =
        strtchar_ex(str, maxlen, pos, c, { luaL_addchar(&b, c); });

    if (tchar_len == 0) {
        // Empty or first character is invalid
        lua_settop(L, top);
        return PARSE_EHDRNAME;
    }

    if (tchar_len < maxlen) {
        // strtchar stopped before maxlen - check why
        unsigned char c = str[tchar_len];
        if (c == ':') {
            // Found colon - success
            // Header name already converted to lowercase by strtchar
            *maxhdrlen = tchar_len;
            *cur       = tchar_len + 1;
            luaL_pushresult(&b);
            return PARSE_OK;
        }
        // Non-tchar, non-colon character - error
        lua_settop(L, top);
        return PARSE_EHDRNAME;
    }

    // All characters up to maxlen were tchar
    if (len > maxlen) {
        // More data available but exceeded maxlen
        lua_settop(L, top);
        return PARSE_EHDRLEN;
    }

    lua_settop(L, top);
    return PARSE_EAGAIN;
}

static int header_name_lua(lua_State *L)
{
    size_t len       = 0;
    const char *str  = lauxh_checklstring(L, 1, &len);
    size_t maxhdrlen = (size_t)lauxh_optuint16(L, 2, DEFAULT_HDR_MAXLEN);
    size_t namelen   = 0;

    if (len > maxhdrlen) {
        // header-name too long
        return error_result_as_false(L, PARSE_EHDRLEN, "header_name");
    } else if (strtchar((unsigned char *)str, maxhdrlen) != len) {
        // invalid character found
        return error_result_as_false(L, PARSE_EHDRNAME, "header_name");
    }
    // All characters are valid tchar
    lua_pushboolean(L, 1);
    return 1;
}

static int parse_header(lua_State *L, unsigned char *str, size_t len,
                        size_t *cur, uint16_t maxhdrlen, uint8_t maxhdrnum)
{
    int tblidx         = lua_gettop(L);
    unsigned char *top = str;
    uintptr_t head     = 0;
    uint8_t nhdr       = 0;
    size_t pos         = 0;
    int rv             = 0;
    size_t klen        = 0;
    size_t vlen        = 0;
    char *val          = NULL;

RETRY:
    switch (*str) {
    // need more bytes
    case 0:
        lua_settop(L, tblidx);
        return PARSE_EAGAIN;

    // check header-tail
    case CR:
        // null-terminated
        if (!str[1]) {
            lua_settop(L, tblidx);
            return PARSE_EAGAIN;
        } else if (str[1] == LF) {
            // skip CR
            str++;
        case LF:
            // skip LF
            str++;
            *cur = (uintptr_t)str - (uintptr_t)top;
            return PARSE_OK;
        }
    }

    // check maximum header number constraint
    if (nhdr >= maxhdrnum) {
        lua_settop(L, tblidx);
        return PARSE_EHDRNUM;
    }
    nhdr++;

    head = (uintptr_t)str;
    klen = maxhdrlen;
    // parse key and push to stack
    rv   = parse_hkey(L, str, len, &pos, &klen);
    if (rv != PARSE_OK) {
        lua_settop(L, tblidx);
        return rv;
    }

    // skip OWS
    while (str[pos] == SP || str[pos] == HT) {
        pos++;
    }

    // re-check maximum header length constraint
    if (pos > maxhdrlen) {
        lua_settop(L, tblidx);
        return PARSE_EHDRLEN;
    }
    str += pos;
    len -= pos;

    val  = (char *)str;
    vlen = maxhdrlen - ((intptr_t)str - head);
    rv   = parse_hval(str, len, &pos, &vlen);
    if (rv != PARSE_OK) {
        lua_settop(L, tblidx);
        return rv;
    }
    str += pos;
    len -= pos;

    // check empty header value
    if (!vlen) {
        // avoid header with empty value
        // pop key
        lua_pop(L, 1);
        nhdr--;
        goto RETRY;
    }

    // check existing kv table of key
    // stack: tbl, key
    lua_pushvalue(L, -1);
    // stack: tbl, key, key
    lua_rawget(L, tblidx);
    // stack: tbl, key, val?
    switch (lua_type(L, -1)) {
    default: {
        int idx = lauxh_rawlen(L, tblidx) + 1;
        lua_pop(L, 1);
        // stack: tbl, key

        // create kv table
        lua_createtable(L, 3, 0);
        lauxh_pushint2tbl(L, "idx", idx);
        // set raw-key
        lua_pushliteral(L, "key");
        lua_pushlstring(L, (char *)head, klen);
        lua_rawset(L, -3);

        // create kv->val table
        lua_pushliteral(L, "val");
        lua_createtable(L, 1, 0);
        lauxh_pushlstr2arr(L, 1, val, vlen);
        lua_rawset(L, -3);

        // push kv table to tbl[key]
        // stack: tbl, key, kv
        lua_pushvalue(L, -2);
        // stack: tbl, key, kv, key
        lua_pushvalue(L, -2);
        // stack: tbl, key, kv, key, kv
        lua_rawset(L, tblidx);
        // stack: tbl, key, kv

        // push kv table to tbl[idx]
        lua_rawseti(L, tblidx, idx);
        // stack: tbl, key
    } break;

    case LUA_TTABLE:
        // stack: tbl, key, kv
        // get kv->val table
        lua_pushliteral(L, "val");
        lua_rawget(L, -2);
        // stack: tbl, key, kv, val_tbl
        // append to tail
        lauxh_pushlstr2arr(L, lauxh_rawlen(L, -1) + 1, val, vlen);
        lua_pop(L, 2);
        // stack: tbl, key
        break;
    }
    // pop key
    lua_pop(L, 1);
    goto RETRY;
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

static int parse_version(unsigned char *str, size_t len, size_t *cur,
                         double *ver)
{
// version length: HTTP/x.x
#define VER_LEN 8

    if (len < VER_LEN) {
        // versions string incomplete
        return PARSE_EAGAIN;
    }

    // parse version
    *cur = VER_LEN;
    if (memcmp(str, "HTTP/1.1", VER_LEN) == 0) {
        *ver = 1.1;
        return PARSE_OK;
    } else if (memcmp(str, "HTTP/1.0", VER_LEN) == 0) {
        *ver = 1.0;
        return PARSE_OK;
    }
    // invalid version format
    return PARSE_EVERSION;

#undef VER_LEN
}

static int parse_method(unsigned char *str, size_t len, size_t *cur,
                        size_t *mlen)
{
// TODO: a method allows 1*tchar, but we only implement common methods here.
// Probably, we should support 1*tchar and let user to verify the method
// string.
// maximum method length with SP
#define METHOD_LEN 8

    size_t pos    = *cur;
    size_t maxlen = pos + METHOD_LEN;

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
        if (memcmp(str, "GET", 3) == 0 || memcmp(str, "PUT", 3) == 0) {
            return PARSE_OK;
        }
        return PARSE_EMETHOD;

    case 4:
        if (memcmp(str, "POST", 4) == 0 || memcmp(str, "HEAD", 4) == 0) {
            return PARSE_OK;
        }
        return PARSE_EMETHOD;

    case 5:
        if (memcmp(str, "TRACE", 5) == 0) {
            return PARSE_OK;
        }
        return PARSE_EMETHOD;

    case 6:
        if (memcmp(str, "DELETE", 6) == 0) {
            return PARSE_OK;
        }
        return PARSE_EMETHOD;

    case 7:
        if (memcmp(str, "OPTIONS", 7) == 0 || memcmp(str, "CONNECT", 7) == 0) {
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

    // parse headers
    lua_createtable(L, 0, (maxhdrnum > 2) ? maxhdrnum / 2 : maxhdrnum);
    rv = parse_header(L, str, len, &cur, maxhdrlen, maxhdrnum);
    if (rv < 0) {
        return error_result_as_nil(L, rv, "request");
    }
    lua_setfield(L, -2, "header");
    str += cur;

    lua_settop(L, 1);
    lua_pushinteger(L, (uintptr_t)str - (uintptr_t)head);
    return 1;
}

static int parse_reason(unsigned char *str, size_t len, size_t *cur,
                        size_t *maxmsglen)
{
    size_t maxlen = (len > *maxmsglen) ? *maxmsglen : len;
    size_t pos    = 0;

CHECK_NEXT:
    pos += strvchar(str + pos, maxlen - pos);
    if (pos < maxlen) {
        // stop at first non VCHAR/HT/SP/obs-text
        unsigned char c = str[pos];
        switch (c) {
        case HT:
        case SP:
            // skip OWS
            pos++;
            while (pos < maxlen && (str[pos] == HT || str[pos] == SP)) {
                pos++;
            }
            goto CHECK_NEXT;

        case CR:
            if (!str[pos + 1]) {
                // null-terminator
                break;
            }
            if (str[pos + 1] != LF) {
                // invalid end-of-line terminator
                return PARSE_EEOL;
            }
        case LF:
            *cur       = pos + 1 + (c == CR);
            *maxmsglen = pos;
            return PARSE_OK;

        default:
            // invalid reason-phrase
            return PARSE_EMSG;
        }
    }

    // phrase-length too large
    if (len > maxlen) {
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
    // TODO: HTTP status code allows 3*DIGIT, but we only validate common
    // status codes here. Probably, we should support 3*DIGIT and let user
    // to verify the code. invalid status code
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
        return error_result_as_nil(L, PARSE_EAGAIN, "response");

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

    // parse headers
    lua_createtable(L, 0, (maxhdrnum > 2) ? maxhdrnum / 2 : maxhdrnum);
    rv = parse_header(L, str, len, &cur, maxhdrlen, maxhdrnum);
    if (rv < 0) {
        return error_result_as_nil(L, rv, "response");
    }
    lua_setfield(L, -2, "header");
    str += cur;

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
