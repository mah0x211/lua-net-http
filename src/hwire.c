/**
 *  Copyright (C) 2018-present Masatoshi Teruya
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
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 *  IN THE SOFTWARE.
 *
 *  src/hwire.c
 *  lua-net-http
 *  Zero-Allocation HTTP Parser
 */

#include "hwire.h"
#include <assert.h>
#include <limits.h>
#include <string.h>
#include <sys/types.h>

// ALIGNED(n): compiler-portable alignment specifier.
// Standard alignas/`_Alignas` is preferred when available (C++11 / C11).
// The #else branch also disables all SIMD paths by undefining the architecture
// macros before the intrinsic headers are included, since an unknown compiler
// is unlikely to support the required intrinsics.
#if defined(__cplusplus) && __cplusplus >= 201103L
# define ALIGNED(n) alignas(n)
#elif __STDC_VERSION__ >= 201112L
# define ALIGNED(n) _Alignas(n)
#elif defined(_MSC_VER)
# define ALIGNED(n) __declspec(align(n))
#elif defined(__GNUC__) || defined(__clang__)
# define ALIGNED(n) __attribute__((aligned(n)))
#else
# define ALIGNED(n)
// Defensive: undefine all SIMD arch macros so that the header block below
// falls through to #else and defines NO_SIMD automatically.
# undef __AVX2__
# undef __SSE4_2__
# undef __SSSE3__
# undef __SSE2__
# undef __aarch64__
# undef __ARM_NEON
#endif

// SIMD intrinsic headers.  Each x86 header transitively includes its
// prerequisites: AVX2 ⊃ SSE4.2 ⊃ SSSE3 ⊃ SSE2.
// NO_SIMD is defined when no known SIMD architecture is active, including
// after the defensive undef-s above for unknown compilers.
#if defined(__AVX2__)
# include <immintrin.h>
#elif defined(__SSE4_2__)
# include <nmmintrin.h>
#elif defined(__SSSE3__)
# include <tmmintrin.h>
#elif defined(__SSE2__)
# include <emmintrin.h>
#elif defined(__aarch64__) || (defined(__arm__) && defined(__ARM_NEON))
# include <arm_neon.h>
#else
# define NO_SIMD
#endif

// ctz32/ctz64: count trailing zeros.
// Defined only when the SIMD arch that uses each function is active.
// <intrin.h> is guarded by NO_SIMD to avoid including it when SIMD is disabled.
#if defined(_MSC_VER) && !defined(NO_SIMD)
# include <intrin.h>
#endif

#if defined(__AVX2__) || defined(__SSE4_2__) || defined(__SSSE3__) ||          \
    defined(__SSE2__)
static inline int ctz32(unsigned int x)
{
# if defined(_MSC_VER)
    unsigned long i;
    _BitScanForward(&i, x);
    return (int)i;
# else
    return __builtin_ctz(x);
# endif
}
#endif

#if defined(__aarch64__) || (defined(__arm__) && defined(__ARM_NEON))
static inline int ctz64(unsigned long long x)
{
# if defined(_MSC_VER)
    unsigned long i;
    _BitScanForward64(&i, x);
    return (int)i;
# else
    return __builtin_ctzll(x);
# endif
}
#endif

// Sign-flip trick: (byte ^ 0x80) maps unsigned bytes to signed, enabling
// _mm_cmplt_epi8 to implement unsigned byte < threshold comparisons.
#if defined(__SSE2__)
# define SIMD_SIGN_FLIP ((int8_t)0x80)
#endif

#if defined(__GNUC__) || defined(__clang__)
# define likely(x)   __builtin_expect(!!(x), 1)
# define unlikely(x) __builtin_expect(!!(x), 0)
#else
# define likely(x)   (x)
# define unlikely(x) (x)
#endif

/**
 * @name Character Validation Tables
 * @{
 */

/**
 * @brief TCHAR lookup table for token validation
 *
 * RFC 7230:
 * token = 1*tchar
 * tchar = "!" / "#" / "$" / "%" / "&" / "'" / "*"
 *       / "+" / "-" / "." / "^" / "_" / "`" / "|" / "~"
 *       / DIGIT / ALPHA
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

/**
 * @brief VCHAR lookup table for field-content validation
 *
 * RFC 7230:
 * field-content = *VCHAR / obs-text
 * VCHAR          = %x21-7E
 * obs-text       = %x80-FF
 */
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

/**
 * @brief Field-content allowed characters (RFC 7230)
 */
static const unsigned char FCVCHAR[256] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, // HT is allowed for field-vchar, but not for VCHAR
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // VCHAR 0x20 - 0x7E
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    // except DEL 0x7F
    0,
    // all obs-text 0x80 - 0xFF
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1};

/**
 * @brief URI allowed characters (RFC 3986)
 *
 * unreserved / sub-delims / ":" / "@" / "/" / "?" / "%"
 * unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
 * sub-delims = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
 */
static const unsigned char URI_CHAR[256] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 0-15
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 16-31
    0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, // 32-47 ( ! # $ % & ' ( ) * + , - . / )
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, // 48-63 ( 0-9 : ; < = > ? )
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 64-79 ( @ A-O )
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, // 80-95 ( P-Z [ \ ] ^ _ )
    0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 96-111 ( ` a-o )
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1,
    0, // 112-127 ( p-z { | } ~ DEL )
    // Extended ASCII (128-255) are NOT allowed in URI (must be unreserved)
    // Actually RFC 3986 says characters "not in the allowed set" must be
    // pct-encoded. So raw UTF-8 bytes > 127 are invalid in URI.
    0};

static inline size_t strurichar(const unsigned char *str, size_t len)
{
    size_t i = 0;

    // Process 8 bytes at a time using bitwise OR (branchless)
    while (i + 8 <= len) {
        int check = !URI_CHAR[str[i + 0]] | !URI_CHAR[str[i + 1]] |
                    !URI_CHAR[str[i + 2]] | !URI_CHAR[str[i + 3]] |
                    !URI_CHAR[str[i + 4]] | !URI_CHAR[str[i + 5]] |
                    !URI_CHAR[str[i + 6]] | !URI_CHAR[str[i + 7]];

        if (check) {
            // Find exact position of invalid character
            for (size_t j = 0; j < 8; j++) {
                if (!URI_CHAR[str[i + j]]) {
                    return i + j;
                }
            }
        }
        i += 8;
    }

    // Handle remaining bytes
    while (i < len) {
        if (!URI_CHAR[str[i]]) {
            return i;
        }
        i++;
    }
    return i;
}

/**
 * @brief QDTEXT lookup table for quoted-string validation
 *
 * RFC 7230:
 * quoted-string = DQUOTE *( qdtext / quoted-pair ) DQUOTE
 * qdtext        = HTAB / SP / %x21 / %x23-5B / %x5D-7E / obs-text
 * quoted-pair   = "\" ( HTAB / SP / VCHAR / obs-text )
 * obs-text      = %x80-FF
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

/** @} */ /* end of Character Validation Tables */

/**
 * @name Internal Macros
 * @{
 */

#define HT        '\t'
#define SP        ' '
#define CR        '\r'
#define LF        '\n'
#define EQ        '='
#define COLON     ':'
#define SEMICOLON ';'
#define DQUOTE    '"'
#define BACKSLASH '\\'

/** @} */ /* end of Internal Macros */

/**
 * @name Internal Character Validation Functions
 * @{
 */

/**
 * @brief Convert hexadecimal string to size_t
 *
 * Converts a hexadecimal string to a size_t value. Updates `cur` to point to
 * the first non-hexadecimal character.
 *
 * @param str String containing hexadecimal digits
 * @param len Maximum length of string
 * @param cur Output: set to first non-hex character position (0-based)
 * @param maxsize Maximum allowed value; returns HWIRE_ERANGE if exceeded
 * @return Converted value on success (0 if no hex digits found, *cur unchanged)
 * @return HWIRE_ERANGE if value exceeds maxsize (HWIRE_MAX_CHUNKSIZE =
 * UINT32_MAX)
 *
 * @note This function is used by hwire_parse_chunksize to parse the chunk-size
 * field.
 * @note HEXDIGIT table is used for fast digit lookup (1-16 for valid hex
 * digits).
 */
static int64_t hex2size(const unsigned char *str, size_t len, size_t *cur,
                        uint32_t maxsize)
{
    assert(str != NULL);
    assert(cur != NULL);
    int64_t dec = 0;

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

        if (dec > (int64_t)maxsize) {
            // result too large
            // limit to max value of 32bit (0x7FFFFFFF)
            return HWIRE_ERANGE;
        }
    }

    *cur = len;
    return dec;
}

/**
 * @brief Check if character is a valid tchar (token character)
 *
 * @param c Character to check
 * @return 1 if TCHAR[c] != 0 (valid tchar), otherwise 0
 *
 * @note The internal TCHAR table returns lowercase for valid tchar,
 *       but this function only returns a boolean.
 */
static inline int is_tchar(unsigned char c)
{
    return TCHAR[c] != 0;
}

/**
 * @brief Check if character is valid field-content (VCHAR or obs-text)
 *
 * @param c Character to check
 * @return 1 if VCHAR[c] == 1, otherwise 0
 */
static inline int is_vchar(unsigned char c)
{
    return VCHAR[c] == 1;
}

static inline int is_fcchar(unsigned char c)
{
    return FCVCHAR[c] == 1;
}

// TCHAR_NIBBLE_LO / TCHAR_NIBBLE_HI: nibble-split lookup tables for tchar
// validation.
//
// For any byte c: (TCHAR_NIBBLE_LO[c & 0xF] & TCHAR_NIBBLE_HI[c >> 4]) != 0
// iff c is a valid tchar character (RFC 7230).
//
// Bit assignment in TCHAR_NIBBLE_HI: hi=2→bit0, hi=3→bit1, hi=4→bit2,
//   hi=5→bit3, hi=6→bit4, hi=7→bit5. hi=0,1,8-F map to 0 (all invalid).
#if defined(__AVX2__) || defined(__SSSE3__)
static const int8_t ALIGNED(16) TCHAR_NIBBLE_LO[16] = {
    // lo:   0x0   0x1   0x2   0x3   0x4   0x5   0x6   0x7
    0x3A, 0x3F, 0x3E, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F,
    // lo:   0x8   0x9   0xA   0xB   0xC   0xD   0xE   0xF
    0x3E, 0x3E, 0x3D, 0x15, 0x34, 0x15, 0x3D, 0x1C};
static const int8_t ALIGNED(16) TCHAR_NIBBLE_HI[16] = {
    // hi:   0x0   0x1   0x2   0x3   0x4   0x5   0x6   0x7
    0x00, 0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20,
    // hi:   0x8   0x9   0xA   0xB   0xC   0xD   0xE   0xF
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
#endif

/**
 * @brief Count consecutive tchar characters with lowercase conversion
 *
 * Counts the number of consecutive tchar (token) characters from the
 * beginning of str, writing the lowercase-converted characters into lc->buf.
 *
 * Uses AVX2 (32B/iter) or SSSE3 (16B/iter) for validation and lowercasing
 * when available.  For typical HTTP header names (4-15 chars) the SIMD path
 * completes in a single iteration.  A scalar 4-char-unrolled fallback handles
 * any remaining bytes.
 *
 * @param str   String to parse (must not be NULL)
 * @param len   Maximum length of string
 * @param lc    Lowercase output buffer (must not be NULL)
 * @return Number of consecutive tchar characters written to lc->buf
 * @return SIZE_MAX if lc->buf is full and more tchars remain in str
 */
static inline size_t strtchar_cmp_lc(const unsigned char *str, size_t len,
                                     hwire_buf_t *lc)
{
    size_t pos         = 0;
    unsigned char *buf = (unsigned char *)lc->buf;
    size_t limit       = (len < lc->size) ? len : lc->size;

#if defined(__AVX2__)
    if (likely(pos + 32 <= limit)) {
        const __m256i lo_lut = _mm256_broadcastsi128_si256(
            _mm_loadu_si128((const __m128i *)(const void *)TCHAR_NIBBLE_LO));
        const __m256i hi_lut = _mm256_broadcastsi128_si256(
            _mm_loadu_si128((const __m128i *)(const void *)TCHAR_NIBBLE_HI));
        const __m256i nibble  = _mm256_set1_epi8(0x0F);
        const __m256i at_char = _mm256_set1_epi8(0x40); // '@' (0x41-1)
        const __m256i bkt     = _mm256_set1_epi8(0x5B); // '[' (0x5A+1)
        const __m256i bit5    = _mm256_set1_epi8(0x20);
        do {
            __m256i data =
                _mm256_loadu_si256((const __m256i *)(const void *)(str + pos));
            __m256i lo_v =
                _mm256_shuffle_epi8(lo_lut, _mm256_and_si256(data, nibble));
            __m256i hi_v = _mm256_shuffle_epi8(
                hi_lut, _mm256_and_si256(_mm256_srli_epi16(data, 4), nibble));
            int mask = _mm256_movemask_epi8(_mm256_cmpeq_epi8(
                _mm256_and_si256(lo_v, hi_v), _mm256_setzero_si256()));
            // lowercase: A-Z (0x41-0x5A) -> set bit5
            __m256i is_upper =
                _mm256_and_si256(_mm256_cmpgt_epi8(data, at_char), // c > '@'
                                 _mm256_cmpgt_epi8(bkt, data));    // '[' > c
            __m256i lc_out =
                _mm256_or_si256(data, _mm256_and_si256(is_upper, bit5));
            // store 32 bytes (safe: pos+32 <= limit <= lc->size)
            _mm256_storeu_si256((__m256i *)(void *)(buf + pos), lc_out);
            if (mask) {
                pos += (size_t)ctz32((unsigned)mask);
                lc->len = pos;
                return pos;
            }
            pos += 32;
        } while (pos + 32 <= limit);
    }
#elif defined(__SSSE3__)
    if (pos + 16 <= limit) {
        const __m128i lo_lut =
            _mm_loadu_si128((const __m128i *)(const void *)TCHAR_NIBBLE_LO);
        const __m128i hi_lut =
            _mm_loadu_si128((const __m128i *)(const void *)TCHAR_NIBBLE_HI);
        const __m128i nibble  = _mm_set1_epi8(0x0F);
        const __m128i at_char = _mm_set1_epi8(0x40); // '@' (0x41-1)
        const __m128i bkt     = _mm_set1_epi8(0x5B); // '[' (0x5A+1)
        const __m128i bit5    = _mm_set1_epi8(0x20);
        do {
            __m128i data =
                _mm_loadu_si128((const __m128i *)(const void *)(str + pos));
            __m128i lo_v =
                _mm_shuffle_epi8(lo_lut, _mm_and_si128(data, nibble));
            __m128i hi_v = _mm_shuffle_epi8(
                hi_lut, _mm_and_si128(_mm_srli_epi16(data, 4), nibble));
            int mask = _mm_movemask_epi8(
                _mm_cmpeq_epi8(_mm_and_si128(lo_v, hi_v), _mm_setzero_si128()));
            // lowercase: A-Z (0x41-0x5A) -> set bit5
            __m128i is_upper =
                _mm_and_si128(_mm_cmpgt_epi8(data, at_char), // c > '@'
                              _mm_cmpgt_epi8(bkt, data));    // '[' > c
            __m128i lc_out = _mm_or_si128(data, _mm_and_si128(is_upper, bit5));
            // store 16 bytes (safe: pos+16 <= limit <= lc->size)
            _mm_storeu_si128((__m128i *)(void *)(buf + pos), lc_out);
            if (mask) {
                pos += (size_t)ctz32((unsigned)mask);
                lc->len = pos;
                return pos;
            }
            pos += 16;
        } while (pos + 16 <= limit);
    }
#endif

    // scalar fallback for remaining bytes (< 16/32) or non-SIMD builds
    while (pos + 4 <= limit) {
        unsigned char c0 = str[pos];
        unsigned char c1 = str[pos + 1];
        unsigned char c2 = str[pos + 2];
        unsigned char c3 = str[pos + 3];
        if (likely(is_tchar(c0) & is_tchar(c1) & is_tchar(c2) & is_tchar(c3))) {
            buf[pos]     = TCHAR[c0];
            buf[pos + 1] = TCHAR[c1];
            buf[pos + 2] = TCHAR[c2];
            buf[pos + 3] = TCHAR[c3];
            pos += 4;
            continue;
        }
        break;
    }
    while (pos < limit && is_tchar(str[pos])) {
        buf[pos] = TCHAR[str[pos]];
        pos++;
    }
    lc->len = pos;

    // buffer is full - check if there are more tchars
    if (pos < len && is_tchar(str[pos])) {
        return SIZE_MAX;
    }
    return pos;
}

/**
 * @brief Count consecutive tchar characters (no lowercase conversion)
 *
 * Uses AVX2 (32B/iter) or SSSE3 (16B/iter) nibble-trick when available,
 * with scalar fallback for tail bytes.  For typical HTTP header names
 * (6-15 chars) the AVX2/SSSE3 path completes in a single iteration.
 *
 * @param str String to parse (must not be NULL)
 * @param len Maximum length of string
 * @return Index of first non-tchar byte (0 if first char is not tchar)
 */
static inline size_t strtchar_cmp(const unsigned char *str, size_t len)
{
    size_t pos = 0;

#if defined(__AVX2__)
    if (likely(pos + 32 <= len)) {
        const __m256i lo_lut = _mm256_broadcastsi128_si256(
            _mm_loadu_si128((const __m128i *)(const void *)TCHAR_NIBBLE_LO));
        const __m256i hi_lut = _mm256_broadcastsi128_si256(
            _mm_loadu_si128((const __m128i *)(const void *)TCHAR_NIBBLE_HI));
        const __m256i nibble = _mm256_set1_epi8(0x0F);
        do {
            __m256i data =
                _mm256_loadu_si256((const __m256i *)(const void *)(str + pos));
            __m256i lo_v =
                _mm256_shuffle_epi8(lo_lut, _mm256_and_si256(data, nibble));
            __m256i hi_v = _mm256_shuffle_epi8(
                hi_lut, _mm256_and_si256(_mm256_srli_epi16(data, 4), nibble));
            int mask = _mm256_movemask_epi8(_mm256_cmpeq_epi8(
                _mm256_and_si256(lo_v, hi_v), _mm256_setzero_si256()));
            if (mask)
                return pos + (size_t)ctz32((unsigned)mask);
            pos += 32;
        } while (pos + 32 <= len);
    }
#elif defined(__SSSE3__)
    if (pos + 16 <= len) {
        const __m128i lo_lut =
            _mm_loadu_si128((const __m128i *)(const void *)TCHAR_NIBBLE_LO);
        const __m128i hi_lut =
            _mm_loadu_si128((const __m128i *)(const void *)TCHAR_NIBBLE_HI);
        const __m128i nibble = _mm_set1_epi8(0x0F);
        do {
            __m128i data =
                _mm_loadu_si128((const __m128i *)(const void *)(str + pos));
            __m128i lo_v =
                _mm_shuffle_epi8(lo_lut, _mm_and_si128(data, nibble));
            __m128i hi_v = _mm_shuffle_epi8(
                hi_lut, _mm_and_si128(_mm_srli_epi16(data, 4), nibble));
            int mask = _mm_movemask_epi8(
                _mm_cmpeq_epi8(_mm_and_si128(lo_v, hi_v), _mm_setzero_si128()));
            if (mask)
                return pos + (size_t)ctz32((unsigned)mask);
            pos += 16;
        } while (pos + 16 <= len);
    }
#endif

    while (pos < len && TCHAR[str[pos]]) {
        pos++;
    }
    return pos;
}

/**
 * @brief Count consecutive tchar characters with optional lowercase conversion
 *
 * Counts the number of consecutive tchar (token) characters from the
 * beginning of str. Uses 8x loop unrolling for performance.
 *
 * If lc is non-NULL, stores the lowercase-converted tchar characters into
 * lc->buf starting at lc->len.
 *
 * @param str String to parse (must not be NULL)
 * @param len Maximum length of string
 * @param lc  Optional lowercase buffer (NULL to skip lowercase conversion)
 * @return Number of consecutive tchar characters (0 if first char is not tchar)
 * @return SIZE_MAX if buffer is full and there are more tchars to process
 */
static inline size_t strtchar(const unsigned char *str, size_t len,
                              hwire_buf_t *lc)
{
    if (lc) {
        return strtchar_cmp_lc(str, len, lc);
    }

    return strtchar_cmp(str, len);
}

/**
 * @brief Skip whitespace characters (SP and HT)
 *
 * Skips spaces (SP) and horizontal tabs (HT) in the input string, up to the
 * specified maximum length.
 *
 * @param str Input string
 * @param len Total length of input string
 * @param pos Input: current position; Output: updated position after skipping
 * @param maxpos Maximum allowed position to skip
 * @return HWIRE_OK on success
 * @return HWIRE_ELEN if position exceeds maxpos
 *
 * @note This function is used to skip BWS (Bad Whitespace) in chunk-size
 * parsing.
 * @note Only SP and HT are considered whitespace (per RFC 7230).
 */
static inline int skip_ws(const unsigned char *str, size_t len, size_t *pos,
                          size_t maxpos)
{
    assert(str != NULL);
    assert(pos != NULL);
    size_t cur  = *pos;
    size_t tail = maxpos;

    if (tail > len) {
        tail = len;
    }

    // skip SP and HT
    for (; cur < tail; cur++) {
        switch (str[cur]) {
        case SP:
        case HT:
            continue;

        default:
            // stopped at non-whitespace
            *pos = cur;
            return HWIRE_OK;
        }
    }
    // update position
    *pos = cur;

    if (len > maxpos) {
        // exceeded maxpos
        return HWIRE_ELEN;
    }
    // all whitespace
    return HWIRE_OK;
}

// strvchar_cmp: Compare characters in str against VCHAR set, with optional
// field-vchar support. Returns the number of valid characters from the start of
// str.
// is_field_vchar: 1 to allow field-vchar, 0 otherwise
// endc: set to the first invalid byte (non-NULL assumed)
static inline size_t strvchar_cmp(const unsigned char *str, size_t len,
                                  int is_field_vchar, unsigned char *endc)
{
    size_t pos                  = 0;
    // Select lookup table based on is_field_vchar: FCVCHAR for field-vchar,
    // else VCHAR
    const unsigned char *lookup = is_field_vchar ? FCVCHAR : VCHAR;

    // Process 8 bytes at a time using bitwise OR (branchless)
    while (pos + 8 <= len) {
        int check = !lookup[str[pos + 0]] | !lookup[str[pos + 1]] |
                    !lookup[str[pos + 2]] | !lookup[str[pos + 3]] |
                    !lookup[str[pos + 4]] | !lookup[str[pos + 5]] |
                    !lookup[str[pos + 6]] | !lookup[str[pos + 7]];

        if (check) {
            // Find exact position of invalid character
            for (size_t i = 0; i < 8; i++) {
                if (!lookup[str[pos + i]]) {
                    *endc = str[pos + i];
                    return pos + i;
                }
            }
        }
        pos += 8;
    }

    // Handle remaining bytes (< 8)
    while (pos < len && lookup[str[pos]]) {
        pos++;
    }
    if (pos < len) {
        *endc = str[pos];
    }
    return pos;
}

#if defined(__aarch64__) || (defined(__arm__) && defined(__ARM_NEON))

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
// strvchar_neon: NEON-optimized implementation (16 bytes)
// endc: set to the first invalid byte (non-NULL assumed)
static inline size_t strvchar_neon(const unsigned char *str, size_t len,
                                   int is_field_vchar, unsigned char *endc)
{
    size_t pos                 = 0;
    // Pre-compute constants (compile-time inlined)
    // 0x20 for field-vchar, else 0x21 (exclamation mark) for VCHAR
    const uint8x16_t first_cmp = vdupq_n_u8(is_field_vchar ? 0x20 : 0x21);
    const uint8x16_t del_char  = vdupq_n_u8(0x7F);
    const uint8x16_t ht_char   = vdupq_n_u8(0x09);

    while (pos + 16 <= len) {
        // Load 16 bytes
        uint8x16_t data = vld1q_u8(str + pos);

        // Check1: is_before_first: bytes where data < firstc
        uint8x16_t is_before_first = vcltq_u8(data, first_cmp);

        // Check2: SP/HT exception logic - if is_field_vchar, then SP/HT
        // (0x09) is valid even if < firstc
        if (is_field_vchar) {
            // If is_field_vchar is true, we will mark SP/HT bytes as valid
            // (0x00) in the is_before_first mask. We do this by creating
            // a mask of SP/HT bytes and then using vbicq_u8 to clear those bits
            // in is_before_first.
            uint8x16_t is_spht = vceqq_u8(data, ht_char);
            is_before_first    = vbicq_u8(is_before_first, is_spht);
        }

        // Check3: is_del: bytes where data == 0x7F (DEL)
        uint8x16_t is_del = vceqq_u8(data, del_char);

        // Combine: invalid if is_before_first OR is_del
        uint8x16_t is_invalid = vorrq_u8(is_before_first, is_del);

        // Interpret as 64-bit integers
        uint64x2_t qdata = vreinterpretq_u64_u8(is_invalid);

        uint64_t mask1 = vgetq_lane_u64(qdata, 0);
        if (mask1) {
            size_t first = (size_t)(ctz64(mask1) >> 3);
            *endc        = str[pos + first]; // L1 hit: data was just loaded
            return pos + first;
        }

        uint64_t mask2 = vgetq_lane_u64(qdata, 1);
        if (mask2) {
            size_t first = 8 + (size_t)(ctz64(mask2) >> 3);
            *endc        = str[pos + first]; // L1 hit: data was just loaded
            return pos + first;
        }

        pos += 16;
    }

    // Fall back to LUT for remaining bytes (< 16 bytes)
    return pos + strvchar_cmp(str + pos, len - pos, is_field_vchar, endc);
}

#endif

#if defined(__SSE2__)

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
// strvchar_sse2: SSE2 optimized implementation (16 bytes)
//
// Parameters:
// - is_field_vchar: non-zero if field-vchar is allowed, 0x00 otherwise
// - endc: set to the first invalid byte (non-NULL assumed)
static inline size_t strvchar_sse2(const unsigned char *str, size_t len,
                                   int8_t is_field_vchar, unsigned char *endc)
{
    size_t pos              = 0;
    // Pre-compute constants (compile-time)
    const __m128i sign_flip = _mm_set1_epi8(SIMD_SIGN_FLIP);
    // 0x20 (space) for field-vchar, else 0x21 (exclamation mark) for VCHAR
    const __m128i first_cmp =
        _mm_set1_epi8((is_field_vchar ? 0x20 : 0x21) ^ SIMD_SIGN_FLIP);
    const __m128i del_char = _mm_set1_epi8(0x7F);
    const __m128i ht_char  = _mm_set1_epi8(0x09);
    const __m128i allow_ht = _mm_set1_epi8(-(is_field_vchar != 0));

    while (pos + 16 <= len) {
        // Load 16 bytes (unaligned load)
        __m128i data =
            _mm_loadu_si128((const __m128i *)(const void *)(str + pos));

        // Toggle sign bit to enable unsigned comparison with signed
        // instructions This transforms the unsigned comparison (data < 0x21)
        // into a signed one
        __m128i data_shifted = _mm_xor_si128(data, sign_flip);

        // Check1: Detect bytes where (data ^ 0x80) < (firstc ^ 0x80) which is
        // equivalent
        __m128i is_before_first = _mm_cmpgt_epi8(first_cmp, data_shifted);

        // Check2: SP/HT exception logic
        // if is_field_vchar is true, then HT (0x09) is valid even if < firstc.
        __m128i is_ht         = _mm_cmpeq_epi8(data, ht_char);
        __m128i is_allowed_ht = _mm_and_si128(is_ht, allow_ht);
        is_before_first = _mm_andnot_si128(is_allowed_ht, is_before_first);

        // Check3: DEL (0x7F) is always invalid
        __m128i is_del = _mm_cmpeq_epi8(data, del_char);

        // Combine: invalid if is_before_first OR is_del
        __m128i is_invalid = _mm_or_si128(is_before_first, is_del);

        // Create 16-bit mask: bit i is 1 if byte i is invalid
        int mask = _mm_movemask_epi8(is_invalid);
        if (mask) {
            int first = ctz32((unsigned int)mask);
            // L1 hit: data was just loaded from str+pos
            *endc     = str[pos + (size_t)first];
            return pos + (size_t)first;
        }

        // All 16 bytes are valid, continue to next chunk
        pos += 16;
    }

    return pos + strvchar_cmp(str + pos, len - pos, is_field_vchar, endc);
}

#endif

#if defined(__SSE4_2__)

// strvchar_sse42: SSE4.2 optimized implementation using PCMPESTRI
//
// Algorithm: Blacklist approach using PCMPESTRI range matching
// - Invalid ranges for VCHAR: 0x00-0x20, 0x7F-0x7F
// - Invalid ranges for field-vchar: 0x00-0x08, 0x0A-0x1F, 0x7F-0x7F (excludes
// HT)
// - Valid: 0x21-0x7E (VCHAR) or 0x80-0xFF (obs-text)
//
// PCMPESTRI checks up to 8 ranges (16 bytes) against 16 bytes of data.
// When a match is found (invalid char), switch to slow loop.
static inline size_t strvchar_sse42(const unsigned char *str, size_t len,
                                    int is_field_vchar, unsigned char *endc)
{
    size_t pos = 0;
    // Invalid character ranges (padded to 16 bytes to match _mm_loadu_si128):
    // - VCHAR:       0x00-0x20 (control + SP), 0x7F-0x7F (DEL) - 2 ranges
    // - field-vchar: 0x00-0x08, 0x0A-0x1F, 0x7F-0x7F - 3 ranges (excludes HT)
    static const char ALIGNED(16) VCHAR_INVALID_RANGES[16] =
        "\x00\x20\x7f\x7f"; // 2 ranges = 4 bytes; remaining 12 bytes are \0
    static const char ALIGNED(16) FCVCHAR_INVALID_RANGES[16] =
        "\x00\x08\x0a\x1f\x7f\x7f"; // 3 ranges = 6 bytes; remaining 10 bytes
                                    // are \0

    const __m128i ranges = _mm_loadu_si128((
        const __m128i *)(const void *)(is_field_vchar ? FCVCHAR_INVALID_RANGES :
                                                        VCHAR_INVALID_RANGES));
    const int ranges_len = is_field_vchar ? 6 : 4;

    while (pos + 16 <= len) {
        __m128i data =
            _mm_loadu_si128((const __m128i *)(const void *)(str + pos));

        // PCMPESTRI: find first byte in data that falls within any of the
        // invalid ranges. Returns index of first match (0-15), or 16 if no
        // match.
        int idx = _mm_cmpestri(ranges, ranges_len, data, 16,
                               _SIDD_LEAST_SIGNIFICANT | _SIDD_CMP_RANGES |
                                   _SIDD_UBYTE_OPS);

        if (idx != 16) {
            // Use PSHUFB to bring data[idx] to lane 0 — no memory address
            // dependency on 'idx' (unlike str[pos+idx] which needs
            // idx→addr→load)
            *endc = (unsigned char)_mm_cvtsi128_si32(
                _mm_shuffle_epi8(data, _mm_set1_epi8((int8_t)idx)));
            return pos + (size_t)idx;
        }

        pos += 16;
    }

    return pos + strvchar_cmp(str + pos, len - pos, is_field_vchar, endc);
}

#endif

#if defined(__AVX2__)

// strvchar_avx2: AVX2 optimized implementation (32 bytes)
//
// Algorithm: Blacklist approach using 256-bit SIMD
// - Invalid: characters < threshold (except HT if allowed) or character == 0x7F
// (DEL)
//
// Parameters:
// - is_field_vchar: non-zero if field-vchar is allowed, 0x00 otherwise
// - endc: set to the first invalid byte (non-NULL assumed)
//
// AVX2 implies SSSE3, so _mm_shuffle_epi8 (PSHUFB) is available.
// We extract the stopped byte from the already-loaded 256-bit 'data' register
// using VEXTRACTI128 + PSHUFB, avoiding str[pos+first] address dependency.
static inline size_t strvchar_avx2(const unsigned char *str, size_t len,
                                   int8_t is_field_vchar, unsigned char *endc)
{
    size_t pos              = 0;
    // Pre-compute constants (compile-time if arguments are constant)
    const __m256i sign_flip = _mm256_set1_epi8(SIMD_SIGN_FLIP);
    const __m256i first_cmp =
        _mm256_set1_epi8((is_field_vchar ? 0x20 : 0x21) ^ SIMD_SIGN_FLIP);
    const __m256i del_char = _mm256_set1_epi8(0x7F);
    const __m256i ht_char  = _mm256_set1_epi8(0x09);
    const __m256i allow_ht = _mm256_set1_epi8(-(is_field_vchar != 0));

    // Process 32 bytes at a time
    while (pos + 32 <= len) {
        __m256i data =
            _mm256_loadu_si256((const __m256i *)(const void *)(str + pos));
        __m256i data_shifted = _mm256_xor_si256(data, sign_flip);

        // Check 1: Characters less than firstc (after sign flip) are
        // invalid (data ^ 0x80) < (firstc ^ 0x80)
        __m256i is_before_first = _mm256_cmpgt_epi8(first_cmp, data_shifted);

        // Check2: HT exception logic - if allow_ht, then HT (0x09) is valid
        // even if < firstc
        __m256i is_ht         = _mm256_cmpeq_epi8(data, ht_char);
        __m256i is_allowed_ht = _mm256_and_si256(is_ht, allow_ht);
        is_before_first = _mm256_andnot_si256(is_allowed_ht, is_before_first);

        // Check3: DEL (0x7F) is always invalid
        __m256i is_del = _mm256_cmpeq_epi8(data, del_char);

        // Combine invalid conditions
        __m256i is_invalid = _mm256_or_si256(is_before_first, is_del);

        int mask = _mm256_movemask_epi8(is_invalid);
        if (mask) {
            int first    = ctz32((unsigned int)mask);
            // Use VEXTRACTI128 + PSHUFB to extract data[first] from the loaded
            // register — avoids str[pos+first] memory address dependency on
            // 'first'
            __m128i half = first < 16 ? _mm256_castsi256_si128(data) :
                                        _mm256_extracti128_si256(data, 1);
            *endc        = (unsigned char)_mm_cvtsi128_si32(
                _mm_shuffle_epi8(half, _mm_set1_epi8((int8_t)(first & 15))));
            return pos + (size_t)first;
        }
        pos += 32;
    }

    // Fall back to SSE2 for remaining bytes (< 32 bytes)
    return pos + strvchar_sse2(str + pos, len - pos, is_field_vchar, endc);
}

#endif

// strvchar: count consecutive field-content characters (VCHAR or obs-text)
// Returns the number of consecutive characters from the beginning of str
// that are field-content (VCHAR or obs-text)

// strfcchar: count consecutive field-content characters (VCHAR, obs-text,
// SP, HT) Returns the number of consecutive characters from the beginning
// of str that are field-content (VCHAR, obs-text, SP, HT)

static inline size_t strvchar(const unsigned char *str, size_t len)
{
    unsigned char endc = 0; // discarded; compiler optimizes away
#if defined(__AVX2__)
    if (likely(len >= 32)) {
        return strvchar_avx2(str, len, 0, &endc);
    }
#endif

#if defined(__SSE4_2__)
    if (likely(len >= 16)) {
        return strvchar_sse42(str, len, 0, &endc);
    }
#elif defined(__SSE2__)
    if (likely(len >= 16)) {
        return strvchar_sse2(str, len, 0, &endc);
    }
#elif defined(__aarch64__) || (defined(__arm__) && defined(__ARM_NEON))
    if (likely(len >= 16)) {
        return strvchar_neon(str, len, 0, &endc);
    }
#endif
    return strvchar_cmp(str, len, 0, &endc);
}

static inline size_t strfcchar(const unsigned char *str, size_t len,
                               unsigned char *endc)
{
#if defined(__AVX2__)
    if (likely(len >= 32)) {
        return strvchar_avx2(str, len, 1, endc);
    }
#endif

#if defined(__SSE4_2__)
    if (likely(len >= 16)) {
        return strvchar_sse42(str, len, 1, endc);
    }
#elif defined(__SSE2__)
    if (likely(len >= 16)) {
        return strvchar_sse2(str, len, 1, endc);
    }
#elif defined(__aarch64__) || (defined(__arm__) && defined(__ARM_NEON))
    if (likely(len >= 16)) {
        return strvchar_neon(str, len, 1, endc);
    }
#endif

    return strvchar_cmp(str, len, 1, endc);
}

/** @} */ /* end of Internal Character Validation Functions */

/**
 * @name Character Validation Functions
 * @{
 */

int hwire_is_tchar(unsigned char c)
{
    return is_tchar(c);
}

int hwire_is_vchar(unsigned char c)
{
    return is_vchar(c);
}

int hwire_is_fcchar(unsigned char c)
{
    return is_fcchar(c);
}

/**
 * @brief Count consecutive tchar characters
 *
 * Counts the number of consecutive tchar (token) characters from the
 * beginning of str, starting at offset *pos. Updates *pos to the position
 * after the matched characters.
 *
 * @param str String to parse (must not be NULL)
 * @param len Maximum length of string
 * @param pos Input: start offset, Output: end offset (must not be NULL)
 * @return Number of consecutive tchar characters matched (0 if first char is
 * not tchar)
 * @see RFC 7230 Section 3.2.6 Field Value Components
 * @see RFC 9110 Section 5.6.2 Tokens
 */
size_t hwire_parse_tchar(const char *str, size_t len, size_t *pos)
{
    assert(str != NULL);
    assert(pos != NULL);
    size_t cur                = *pos;
    const unsigned char *ustr = (const unsigned char *)str + cur;
    size_t n                  = strtchar(ustr, len - cur, NULL);
    *pos += n;
    return n;
}

/**
 * @brief Count consecutive vchar characters
 *
 * Counts the number of consecutive vchar (field-content) characters from the
 * beginning of str, starting at offset *pos. Updates *pos to the position
 * after the matched characters.
 *
 * @param str String to parse (must not be NULL)
 * @param len Maximum length of string
 * @param pos Input: start offset, Output: end offset (must not be NULL)
 * @return Number of consecutive vchar characters matched (0 if first char is
 * not vchar)
 * @see RFC 7230 Section 3.2.6 Field Value Components
 * @see RFC 9110 Section 5.5 Field Values
 */
size_t hwire_parse_vchar(const char *str, size_t len, size_t *pos)
{
    assert(str != NULL);
    assert(pos != NULL);
    size_t cur                = *pos;
    const unsigned char *ustr = (const unsigned char *)str + cur;
    size_t n                  = strvchar(ustr, len - cur);
    *pos += n;
    return n;
}

/**
 * @brief Count consecutive fcchar characters
 *
 * Counts the number of consecutive field-content characters (VCHAR, obs-text,
 * SP, HTAB) from str, starting at offset *pos. Updates *pos to the position
 * after the matched characters.
 *
 * @param str String to parse (must not be NULL)
 * @param len Maximum length of string
 * @param pos Input: start offset, Output: end offset (must not be NULL)
 * @return Number of consecutive fcchar characters matched (0 if first char is
 * not fcchar)
 * @see RFC 9110 Section 5.5 Field Values
 */
size_t hwire_parse_fcchar(const char *str, size_t len, size_t *pos)
{
    assert(str != NULL);
    assert(pos != NULL);
    size_t cur                = *pos;
    const unsigned char *ustr = (const unsigned char *)str + cur;
    unsigned char endc        = 0; /* discarded; caller uses str[*pos] */
    size_t n                  = strfcchar(ustr, len - cur, &endc);
    *pos += n;
    return n;
}

/**
 * @see RFC 7230 Section 3.2.6 Field Value Components
 * @see RFC 9110 Section 5.6.4 Quoted Strings
 */
int hwire_parse_quoted_string(const char *str, size_t len, size_t *pos,
                              size_t maxlen)
{
    assert(str != NULL);
    assert(pos != NULL);
    const unsigned char *ustr = (const unsigned char *)str;
    size_t cur                = *pos;
    size_t tail               = cur + maxlen;

    if (cur >= len) {
        // cur exceeds length
        return HWIRE_EAGAIN;
    } else if (ustr[cur] != DQUOTE) {
        // not starting with DQUOTE
        return HWIRE_EILSEQ;
    } else if (tail > len) {
        // adjust tail if exceeds length
        tail = len;
    }
    // Skip opening quote
    cur++;

    // parse quoted-string
    // RFC 9110 5.6.4: quoted-string = DQUOTE *( qdtext / quoted-pair ) DQUOTE
    // qdtext = HTAB / SP / %x21 / %x23-5B / %x5D-7E / obs-text
    // obs-text = %x80-FF
    for (; cur < tail; cur++) {
        unsigned char c = ustr[cur];
        if (!QDTEXT[c]) {
            switch (c) {
            case DQUOTE:
                // Found closing quote
                *pos = cur + 1; // Skip closing quote
                return HWIRE_OK;

            case BACKSLASH:
                // quoted-pair = "\" ( HTAB / SP / VCHAR / obs-text )
                if (cur + 1 >= len) {
                    // reach to the end of string, need more bytes
                    *pos = cur;
                    return HWIRE_EAGAIN;
                }
                c = ustr[cur + 1];
                if (is_vchar(c) || c == HT || c == SP) {
                    // valid quoted-pair
                    cur++;
                    continue;
                }
                // fallthrough

            default:
                // found illegal byte sequence
                *pos = cur;
                return HWIRE_EILSEQ;
            }
        }
    }

    if (len > tail) {
        // length exceeds maxlen
        *pos = cur;
        return HWIRE_ELEN;
    }
    // need more bytes
    *pos = cur;
    return HWIRE_EAGAIN;
}

/** @} */ /* end of Character Validation Functions */

/**
 * @name String Parsing Functions
 * @{
 */

/**
 * @brief Parse one parameter
 *
 * Parses a single parameter from a semicolon-separated list.
 *
 *  parameters = *( OWS ";" OWS [ parameter ] )
 *  parameter = parameter-name "=" parameter-value
 *  parameter-name = token
 *  parameter-value = ( token / quoted-string )
 *
 * @param str String to parse (must not be NULL)
 * @param len Maximum length of string
 * @param pos Input: start offset, Output: end offset (must not be NULL)
 * @param maxpos Maximum position
 * @param cb Callback context (must not be NULL)
 * @return HWIRE_OK on success
 * @return HWIRE_EAGAIN if more data needed
 * @return HWIRE_EILSEQ for invalid byte sequence
 * @return HWIRE_ELEN if length exceeds maxlen
 * @return HWIRE_EKEYLEN if key length exceeds ctx->key_lc.size
 * @return HWIRE_ECALLBACK if callback returned non-zero
 * @see RFC 7231 Section 3.1.1.1 Parameter
 * @see RFC 9110 Section 5.6.6 Parameters
 */
static int parse_parameter(const char *str, size_t len, size_t *pos,
                           size_t maxpos, hwire_ctx_t *ctx)
{
    hwire_param_t param       = {0};
    const unsigned char *ustr = (const unsigned char *)str;
    size_t cur                = *pos;
    size_t head               = cur;
    size_t tail               = maxpos;

    if (tail > len) {
        // adjust tail if exceeds length
        tail = len;
    }

#define CHECK_POSITON()                                                        \
    *pos = cur;                                                                \
    if (cur == len) {                                                          \
        /* reached end of string, need more bytes */                           \
        return HWIRE_EAGAIN;                                                   \
    } else if (cur >= maxpos) {                                                \
        /* exceeded maxlen */                                                  \
        return HWIRE_ELEN;                                                     \
    }

    // parse parameter-name (token)
    if (ctx->key_lc.size > 0) {
        size_t n = strtchar(ustr + cur, tail - cur, &ctx->key_lc);
        if (n == SIZE_MAX) {
            *pos = cur;
            return HWIRE_EKEYLEN;
        }
        cur += n;
    } else {
        cur += strtchar(ustr + cur, tail - cur, NULL);
    }
    CHECK_POSITON();
    param.key.ptr = str + head;
    param.key.len = cur - head;
    // parameter-name must not be empty
    if (param.key.len == 0) {
        *pos = cur;
        return HWIRE_EILSEQ;
    }

    // check for '='
    if (ustr[cur] != '=') {
        *pos = cur;
        return HWIRE_EILSEQ;
    }
    // skip '='
    cur++;
    CHECK_POSITON();

    // parse parameter-value
    head = cur;
    if (ustr[cur] == DQUOTE) {
        // parse as a quoted-string
        int rc = hwire_parse_quoted_string(str, len, &cur, maxpos - cur);
        if (rc == HWIRE_OK) {
            // cur was updated via &cur pointer
            param.value.ptr = str + head + 1; // skip opening quote
            param.value.len = cur - head - 2; // exclude quotes

            // call callback
            if (ctx->param_cb(ctx, &param)) {
                return HWIRE_ECALLBACK;
            }
        }
        // update position (cur was already updated by
        // hwire_parse_quoted_string)
        *pos = cur;
        return rc;
    }

    // parse as a token
    param.value.ptr = str + head;
    param.value.len = hwire_parse_tchar(str, tail, &cur);
    if (param.value.len == 0) {
        CHECK_POSITON();
        // parameter-value must not be empty
        return HWIRE_EILSEQ;
    }

#undef CHECK_POSITON

    *pos = cur;

    // call callback
    if (ctx->param_cb(ctx, &param)) {
        return HWIRE_ECALLBACK;
    }
    return HWIRE_OK;
}

/**
 * @brief Parse parameters from a semicolon-separated list
 *
 * Parses parameters from a semicolon-separated list.
 *
 *  parameters = *( OWS ";" OWS [ parameter ] )
 *
 * Caller must inspect the byte at *pos (e.g., for CRLF or end of data)
 * after this function returns HWIRE_OK.
 *
 * @param str String to parse (must not be NULL)
 * @param len Maximum length of string
 * @param pos Input: start offset, Output: end offset (must not be NULL)
 * @param maxlen Maximum length of the input string
 * @param maxnparams Maximum number of parameters
 * @param skip_leading_semicolon Non-zero to skip semicolon check for first
 * @param cb Callback context (must not be NULL)
 * @return HWIRE_OK on success
 * @return HWIRE_EAGAIN if more data needed
 * @return HWIRE_EILSEQ for invalid byte sequence
 * @return HWIRE_ELEN if length exceeds maxlen
 * @return HWIRE_EKEYLEN if key length exceeds ctx->key_lc.size
 * @return HWIRE_ECALLBACK if callback returned non-zero
 * @return HWIRE_ENOBUFS if number of parameters exceeds maxnparams
 */
int hwire_parse_parameters(hwire_ctx_t *ctx, const char *str, size_t len,
                           size_t *pos, size_t maxlen, uint8_t maxnparams,
                           int skip_leading_semicolon)
{
    assert(str != NULL);
    assert(pos != NULL);
    assert(ctx != NULL);
    assert(ctx->param_cb != NULL);
    const unsigned char *ustr = (const unsigned char *)str;
    size_t cur                = *pos;
    size_t maxpos             = cur + maxlen;
    uint8_t nparams           = 0;
    int rv                    = HWIRE_OK;

    if (skip_leading_semicolon) {
        // skip leading semicolon if present
        goto CHECK_PARAM;
    }

CHECK_NEXT_PARAM:
    if (skip_ws(ustr, len, &cur, maxpos) != HWIRE_OK) {
        // exceeded maxlen
        *pos = cur;
        return HWIRE_ELEN;
    }

    *pos = cur;
    if (cur >= len) {
        // buffer exhausted: no ';' found, no more parameters
        return HWIRE_OK;
    }
    if (ustr[cur] != SEMICOLON) {
        // no more parameters
        // NOTE: caller must inspect the byte at *pos for CRLF or other
        // terminator after this function returns HWIRE_OK.
        return HWIRE_OK;
    }

SKIP_SEMICOLON:
    // skip ';'
    cur++;

    // check position
    *pos = cur;
    if (cur == len) {
        // reached end of string, need more bytes
        return HWIRE_EAGAIN;
    } else if (cur >= maxpos) {
        // exceeded maxlen
        return HWIRE_ELEN;
    }

CHECK_PARAM:
    if (nparams >= maxnparams) {
        // exceeded maximum number of parameters
        return HWIRE_ENOBUFS;
    }

    // skip trailing OWS
    if (skip_ws(ustr, len, &cur, maxpos) != HWIRE_OK) {
        return HWIRE_ELEN;
    }

    // reset key_lc.len before parsing each parameter
    ctx->key_lc.len = 0;

    // Checking for end of string is required because we might have
    // consumed a semicolon (empty parameter) and reached EOS.
    // In this case, we have a valid empty parameter at the end, so return OK.
    if (cur == len) {
        *pos = cur;
        return HWIRE_OK;
    }

    // parse one parameter
    // RFC 9110 5.6.6: parameters = *( OWS ";" OWS [ parameter ] )
    if (ustr[cur] == SEMICOLON) {
        // empty parameter, skip
        goto SKIP_SEMICOLON;
    }

    rv = parse_parameter(str, len, &cur, maxpos, ctx);
    if (rv == HWIRE_OK) {
        // parsed one parameter, continue to next
        nparams++;
        goto CHECK_NEXT_PARAM;
    }

    // propagate error from parse_parameter
    return rv;
}

/** @} */ /* end of String Parsing Functions */

/**
 * @name Chunked Transfer Coding Functions
 * @{
 */

/**
 * @brief Parse chunk-size and optional chunk-extensions from a chunk-size line
 *
 * Parses a chunk-size line according to RFC 7230 Section 4.1:
 *   chunk-size = 1*HEXDIG
 *   chunk-ext = *( BWS ";" BWS ext-name [ BWS "=" BWS ext-val ] )
 *   ext-name = token
 *   ext-val = token / quoted-string
 *
 * @param str Input string containing the chunk-size line (must start at
 * chunk-size)
 * @param len Length of input string
 * @param pos Output: bytes consumed from str[0] (must not be NULL; must be 0 on
 * entry)
 * @param maxlen Maximum allowed length for parsing
 * @param maxexts Maximum number of chunk-extensions to parse
 * @param cb Callback context (must not be NULL)
 * @return HWIRE_OK on success
 * @return HWIRE_EAGAIN if more data is needed
 * @return HWIRE_ELEN if parsed length exceeds maxlen
 * @return HWIRE_ERANGE if chunk-size exceeds maxsize
 * @return HWIRE_EEXTNAME if extension name is empty
 * @return HWIRE_EEXTVAL if extension value is invalid
 * @return HWIRE_ECALLBACK if callback returned non-zero
 * @return HWIRE_ENOBUFS if number of extensions exceeds maxexts
 * @return HWIRE_EILSEQ if byte sequence is illegal
 * @return HWIRE_EEOL if end-of-line terminator is invalid
 *
 * @note This function requires CRLF (\\r\\n) as the line terminator.
 * @note Extensions with no value have empty string as value (ptr="" len=0).
 */
int hwire_parse_chunksize(hwire_ctx_t *ctx, const char *str, size_t len,
                          size_t *pos, size_t maxlen, uint8_t maxexts)
{
    assert(str != NULL);
    assert(pos != NULL);
    assert(ctx != NULL);
    assert(ctx->chunksize_cb != NULL);
    const unsigned char *ustr = (const unsigned char *)str;
    size_t cur  = 0; // hex2size always scans from str[0]; *pos is output-only
    size_t head = 0;
    const unsigned char *key = NULL;
    size_t klen              = 0;
    const unsigned char *val = NULL;
    size_t vlen              = 0;
    int64_t size             = 0;
    uint8_t nexts            = 0;

    if (!len) {
        // need more bytes
        return HWIRE_EAGAIN;
    }

    // parse chunk-size
    // chunk-size = 1*HEXDIG
    // RFC 7230 4.1 / RFC 9112 7.1: Chunk Size
    size = hex2size(ustr, len, &cur, HWIRE_MAX_CHUNKSIZE);
    if (size < 0) {
        // chunk size exceeds maximum allowed size or invalid
        return (int)size;
    } else if (cur == 0) {
        // no hexadecimal digits found
        return HWIRE_EILSEQ;
    }

    // call chunksize callback
    if (ctx->chunksize_cb(ctx, (uint32_t)size)) {
        return HWIRE_ECALLBACK;
    }

    // 4.1.1. Chunk Extensions
    //
    // chunk-ext    = *( BWS ";" BWS ext-name [ BWS "=" BWS ext-val ] )
    // ext-name     = token
    // ext-val      = token / quoted-string
    // RFC 7230 4.1.1 / RFC 9112 7.1.1: Chunk Extensions
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
CHECK_EOL:

#define skip_bws()                                                             \
    do {                                                                       \
        if (skip_ws(ustr, len, &cur, maxlen) != HWIRE_OK) {                    \
            return HWIRE_ELEN;                                                 \
        } else if (cur >= len) {                                               \
            /* more bytes needed */                                            \
            return HWIRE_EAGAIN;                                               \
        }                                                                      \
    } while (0)

    // skip BWS
    skip_bws();

    switch (ustr[cur]) {
    default:
        // illegal byte sequence
        return HWIRE_EILSEQ;

    // found tail
    case CR:
        cur++;
        if (cur >= len) {
            // more bytes needed
            return HWIRE_EAGAIN;
        } else if (ustr[cur] != LF) {
            // invalid end-of-line terminator
            return HWIRE_EEOL;
        }
    case LF:
        // call extension callback for last extension
        if (klen) {
            hwire_chunksize_ext_t ext = {
                .key   = {.len = klen, .ptr = (const char *)key              },
                .value = {.len = vlen, .ptr = (vlen) ? (const char *)val : ""}
            };
            if (ctx->chunksize_ext_cb(ctx, &ext)) {
                return HWIRE_ECALLBACK;
            }
        }
        // return and number of bytes consumed
        *pos = cur + 1;
        return HWIRE_OK;

    case SEMICOLON:
        // has chunk-extensions
        cur++;
        skip_bws();
    }

    // parse chunk-extensions
    if (nexts >= maxexts) {
        // exceeded maximum number of extensions
        return HWIRE_ENOBUFS;
    }

    // call extension callback for previous extension
    if (klen) {
        hwire_chunksize_ext_t ext = {
            .key   = {.len = klen, .ptr = (const char *)key              },
            .value = {.len = vlen, .ptr = (vlen) ? (const char *)val : ""}
        };
        if (ctx->chunksize_ext_cb(ctx, &ext)) {
            return HWIRE_ECALLBACK;
        }
        nexts++;
        klen = 0;
        vlen = 0;
    }

    // parse ext-name
    head = cur;
    hwire_parse_tchar(str, len, &cur);
    if (cur == head) {
        // disallow empty ext-name (invalid extension name)
        return HWIRE_EEXTNAME;
    }
    key  = ustr + head;
    klen = cur - head;

    skip_bws();
    if (ustr[cur] != EQ) {
        // no ext-value
        goto CHECK_EOL;
    }
    // skip '='
    cur++;
    skip_bws();

    // parse ext-value
    if (ustr[cur] == DQUOTE) {
        int rv = 0;
        // parse as a quoted-string
        head   = cur + 1;
        vlen   = maxlen;
        rv     = hwire_parse_quoted_string((const char *)str, len, &cur, vlen);
        if (rv == HWIRE_OK) {
            vlen = cur - head - 1; // exclude closing quote
            val  = ustr + head;    // skip opening quote
            goto CHECK_EOL;
        }
        // treat an illegal byte sequence as extension value error
        return (rv == HWIRE_EILSEQ) ? HWIRE_EEXTVAL : rv;
    }
    // parse as a token
    head = cur;
    hwire_parse_tchar(str, len, &cur);
    val  = ustr + head;
    vlen = cur - head;

    goto CHECK_EOL;

#undef skip_bws
}

/** @} */ /* end of Chunked Transfer Coding Functions */

/**
 * @name HTTP Headers Parsing Functions
 * @{
 */

/**
 * @brief Parse header value
 *
 * Ported from parse.c:parse_hval
 */
static int parse_hval(const unsigned char *str, size_t len, size_t *cur,
                      size_t *maxlen)
{
    size_t max = (len > *maxlen) ? *maxlen : len;

    // Use strfcchar to scan VCHAR + SP + HT + obs-text in one go
    // This stops at CR, LF, or any invalid character (e.g. CTLs)
    // endc receives the stopped byte from within the SIMD function (pshufb on
    // AVX2/SSE4.2) or via L1-cached str[pos] on SSE2/NEON/scalar — avoids
    // a separate str[pos] load after strfcchar returns.
    unsigned char endc = 0;
    size_t pos         = strfcchar(str, max, &endc);
    if (pos < max) {
        // Stopped at non-field-content; use endc (already set) instead of
        // str[pos]
        if (likely(endc == CR && pos + 1 < len && str[pos + 1] == LF)) {
            // valid end of header value, continue to trim OWS and check CRLF
            // set tail position after CRLF and trim trailing OWS
            *cur = pos + 2; // skip CRLF

REMOVE_OWS:

#define IS_OWS() (pos > 0 && (str[pos - 1] == SP || str[pos - 1] == HT))
            // Backtrack to trim trailing OWS
            // Enter slow loop only if the last character is OWS
            if (unlikely(IS_OWS())) {
                do {
                    pos--;
                } while (IS_OWS());
            }
#undef IS_OWS

            *maxlen = pos;
            return HWIRE_OK;
        } else if (likely(endc == LF)) {
            // only LF found - valid end of header value, continue to trim OWS
            *cur = pos + 1; // skip LF
            goto REMOVE_OWS;
        } else if (unlikely(endc != CR)) {
            // invalid character in header value
            return HWIRE_EHDRVALUE;
        } else if (unlikely(pos + 1 != len)) {
            // invalid end-of-line terminator
            return HWIRE_EEOL;
        }
    }

    // CHECK_LEN:
    // header-length too large
    if (len > max) {
        return HWIRE_EHDRLEN;
    }
    return HWIRE_EAGAIN;
}

/**
 * @brief Parse header key and store lowercase in key_lc
 *
 * Ported from parse.c:parse_hkey
 */
static int parse_hkey(const unsigned char *str, size_t len, size_t *cur,
                      size_t *maxlen, hwire_ctx_t *ctx)
{
    size_t max       = (len > *maxlen) ? *maxlen : len;
    size_t tchar_len = 0;

    if (ctx->key_lc.size > 0) {
        tchar_len = strtchar(str, max, &ctx->key_lc);
        if (tchar_len == SIZE_MAX) {
            return HWIRE_EKEYLEN;
        }
    } else {
        tchar_len = strtchar(str, max, NULL);
    }

    if (unlikely(tchar_len == 0)) {
        // Empty or first character is invalid
        return HWIRE_EHDRNAME;
    }

    if (likely(tchar_len < max)) {
        // strtchar stopped before maxlen - check why
        if (likely(str[tchar_len] == ':')) {
            // Found colon - success
            *maxlen = tchar_len;
            *cur    = tchar_len + 1;
            return HWIRE_OK;
        }
        // Non-tchar, non-colon character - error
        return HWIRE_EHDRNAME;
    }

    // All characters up to maxlen were tchar
    if (unlikely(len > max)) {
        // More data available but exceeded maxlen
        return HWIRE_EHDRLEN;
    }

    return HWIRE_EAGAIN;
}

/**
 * @brief Parse HTTP headers
 *
 * Ported from parse.c:parse_header
 */
int hwire_parse_headers(hwire_ctx_t *ctx, const char *str, size_t len,
                        size_t *pos, size_t maxlen, uint8_t maxnhdrs)
{
    assert(str != NULL);
    assert(pos != NULL);
    assert(ctx != NULL);
    assert(ctx->header_cb != NULL);
    const unsigned char *ustr = (const unsigned char *)str;
    const unsigned char *top  = ustr;
    const unsigned char *head = 0;
    uint8_t nhdr              = 0;
    size_t cur                = 0;
    int rv                    = 0;
    size_t klen               = 0;
    size_t vlen               = 0;
    hwire_header_t header;

RETRY:
    // End-of-headers (CR/LF) or incomplete data — happens once per request,
    // not once per header. Use unlikely to keep the hot header-parsing path
    // as a straight-line fall-through.
    if (unlikely(len == 0)) {
        return HWIRE_EAGAIN;
    }
    if (unlikely(*ustr <= CR)) {
        // Most common: CRLF end-of-headers (browsers always send CRLF)
        if (likely(*ustr == CR)) {
            if (unlikely(len < 2)) {
                return HWIRE_EAGAIN;
            } else if (likely(ustr[1] == LF)) {
                ustr += 2;
                *pos = (size_t)(ustr - top);
                return HWIRE_OK;
            }
            // CR without LF: fall through → parse_hkey rejects as non-tchar
        } else if (*ustr == LF) {
            ustr++;
            *pos = (size_t)(ustr - top);
            return HWIRE_OK;
        }
        // Any other control char ≤ CR: fall through → parse_hkey rejects
    }

    // check maximum header number constraint
    if (unlikely(nhdr >= maxnhdrs)) {
        return HWIRE_ENOBUFS;
    }
    nhdr++;

    head            = ustr;
    klen            = maxlen;
    ctx->key_lc.len = 0;
    // parse key and store lowercase in key_lc
    // header-field = field-name ":" OWS field-value OWS
    // field-name = token
    // RFC 7230 3.2 / RFC 9112 5.1: Field Names
    rv              = parse_hkey(ustr, len, &cur, &klen, ctx);
    if (unlikely(rv != HWIRE_OK)) {
        return rv;
    }

    // skip OWS
    while (cur < len && (ustr[cur] == SP || ustr[cur] == HT)) {
        cur++;
    }

    // re-check maximum header length constraint
    if (unlikely(cur > maxlen)) {
        return HWIRE_EHDRLEN;
    }
    ustr += cur;
    len -= cur;

    header.value.ptr = (const char *)ustr;
    vlen             = maxlen - (size_t)(ustr - head);
    // field-value = *field-content
    // RFC 7230 3.2 / RFC 9112 5.5: Field Values
    // Note: Empty field-value is allowed.
    rv               = parse_hval(ustr, len, &cur, &vlen);
    if (unlikely(rv != HWIRE_OK)) {
        return rv;
    }
    ustr += cur;
    len -= cur;

    // set header key and value
    header.key.ptr   = (const char *)head;
    header.key.len   = klen;
    header.value.len = vlen;

    // call callback
    if (unlikely(ctx->header_cb(ctx, &header) != 0)) {
        return HWIRE_ECALLBACK;
    }

    goto RETRY;
}

/** @} */ /* end of HTTP Headers Parsing Functions */

/**
 * @name HTTP Request Parsing Functions
 * @{
 */

/**
 * @brief Parse HTTP version string
 *
 * @param str String to parse (must not be NULL)
 * @param len Length of string
 * @param pos Output: position after version string (must not be NULL)
 * @param version Output: HTTP version enum
 * @return HWIRE_OK on success
 * @return HWIRE_EAGAIN if more data needed
 * @return HWIRE_EVERSION for invalid version
 */
static int parse_version(const unsigned char *str, size_t len, size_t *pos,
                         hwire_http_version_t *version)
{
#define VER_LEN 8
    if (len < VER_LEN) {
        return HWIRE_EAGAIN;
    }
    if (memcmp(str, "HTTP/1.1", VER_LEN) == 0) {
        *version = HWIRE_HTTP_V11;
        *pos     = VER_LEN;
        return HWIRE_OK;
    } else if (memcmp(str, "HTTP/1.0", VER_LEN) == 0) {
        *version = HWIRE_HTTP_V10;
        *pos     = VER_LEN;
        return HWIRE_OK;
    }
    return HWIRE_EVERSION;
#undef VER_LEN
}

/**
 * @brief Parse request-target (URI)
 *
 * Scans the request-target until a space (SP) is found.
 * Defines the request-target as origin-form / absolute-form /
 * authority-form / asterisk-form (RFC 7230 3.1.1 / RFC 9112 3.2).
 *
 * @param str Input string
 * @param len Total length of input string
 * @param pos Output: position after parsed URI (excluding SP)
 * @param maxlen Maximum allowed length for URI
 * @param uri Output: URI string slice
 * @return HWIRE_OK on success
 * @return HWIRE_EAGAIN if more data is needed
 * @return HWIRE_ELEN if URI exceeds maxlen
 * @return HWIRE_EURI if invalid character is found
 */
static int parse_uri(const unsigned char *str, size_t len, size_t *pos,
                     size_t maxlen, hwire_str_t *uri)
{
    size_t limit   = len > maxlen ? maxlen : len;
    size_t uri_len = strurichar(str, limit);

    if (uri_len < len && str[uri_len] == SP) {
        if (uri_len == 0) {
            return HWIRE_EURI;
        }
        uri->ptr = (const char *)str;
        uri->len = uri_len;
        *pos     = uri_len + 1;
        return HWIRE_OK;
    }

    if (uri_len != limit) {
        // found an illegal character before reaching maxlen
        return HWIRE_EURI;
    } else if (uri_len == len) {
        // reached end of string without finding SP, need more bytes
        return HWIRE_EAGAIN;
    }
    return HWIRE_ELEN;
}

/**
 * @brief Parse HTTP method
 *
 * Parses method as 1*tchar followed by SP.
 *
 * @param str String to parse (must not be NULL)
 * @param len Length of string
 * @param pos Input: start offset, Output: end offset (must not be NULL)
 * @param method Output: method string slice
 * @return HWIRE_OK on success
 * @return HWIRE_EAGAIN if more data needed
 * @return HWIRE_EMETHOD for invalid method (not tchar or no SP)
 */
static int parse_method(const unsigned char *str, size_t len, size_t *pos,
                        hwire_str_t *method)
{
    size_t cur  = 0;
    size_t mlen = 0;

    // method = 1*tchar
    mlen = hwire_parse_tchar((const char *)str, len, &cur);
    if (mlen == 0) {
        // first character is not tchar
        return HWIRE_EMETHOD;
    }

    // SP is required
    if (cur >= len) {
        return HWIRE_EAGAIN;
    }
    if (str[cur] != SP) {
        return HWIRE_EMETHOD;
    }

    method->ptr = (const char *)str;
    method->len = mlen;
    *pos        = cur + 1; // skip SP
    return HWIRE_OK;
}

/**
 * @brief Parse request line
 */
int hwire_parse_request(hwire_ctx_t *ctx, const char *str, size_t len,
                        size_t *pos, size_t maxlen, uint8_t maxnhdrs)
{
    assert(str != NULL);
    assert(pos != NULL);
    assert(ctx != NULL);
    assert(ctx->request_cb != NULL);
    assert(ctx->header_cb != NULL);
    const unsigned char *ustr = (const unsigned char *)str;
    const unsigned char *top  = ustr;
    hwire_request_t req;
    size_t cur = 0;
    int rv     = 0;

SKIP_NEXT_CRLF:
    if (unlikely(len == 0)) {
        return HWIRE_EAGAIN;
    }
    switch (*ustr) {
    case CR:
    case LF:
        ustr++;
        len--;
        goto SKIP_NEXT_CRLF;
    }

    // parse method
    // method = 1*tchar
    // RFC 7230 3.1.1 / RFC 9112 3.1: Method
    rv = parse_method(ustr, len, &cur, &req.method);
    if (rv != HWIRE_OK) {
        return rv;
    }
    ustr += cur;
    len -= cur;

    // parse-uri (find SP delimiter)
    // request-target = origin-form / absolute-form / authority-form /
    // asterik-form RFC 7230 3.1.1 / RFC 9112 3.2: Request Target
    rv = parse_uri(ustr, len, &cur, maxlen, &req.uri);
    if (rv != HWIRE_OK) {
        return rv;
    }
    ustr += cur;
    len -= cur;

    // parse version
    // HTTP-version = HTTP-name "/" DIGIT "." DIGIT
    // RFC 7230 2.6 / RFC 9110 2.5: Protocol Versioning
    rv = parse_version(ustr, len, &cur, &req.version);
    if (rv != HWIRE_OK) {
        return rv;
    }

    // check end-of-line after version
    if (unlikely(cur >= len)) {
        return HWIRE_EAGAIN;
    }
    switch (ustr[cur]) {
    case CR:
        if (cur + 1 >= len) {
            return HWIRE_EAGAIN;
        } else if (ustr[cur + 1] != LF) {
            // invalid end-of-line terminator
            return HWIRE_EEOL;
        }
        cur++;

    case LF:
        cur++;
        break;

    default:
        return HWIRE_EVERSION;
    }

    ustr += cur;
    len -= cur;

    // call request callback
    if (ctx->request_cb(ctx, &req) != 0) {
        return HWIRE_ECALLBACK;
    }

    // parse headers
    cur = 0;
    rv  = hwire_parse_headers(ctx, (const char *)ustr, len, &cur, maxlen,
                              maxnhdrs);
    if (rv != HWIRE_OK) {
        return rv;
    }
    ustr += cur;

    *pos = (size_t)(ustr - top);
    return HWIRE_OK;
}

/** @} */ /* end of HTTP Request Parsing Functions */

/**
 * @name HTTP Response Parsing Functions
 * @{
 */

/**
 * @brief Parse HTTP reason-phrase
 *
 * @param str String to parse (must not be NULL)
 * @param len Length of string
 * @param cur Output: bytes consumed (must not be NULL)
 * @param maxlen Input: max length, Output: reason phrase length
 * @return HWIRE_OK on success
 * @return HWIRE_EAGAIN if more data needed
 * @return HWIRE_EEOL for invalid end-of-line
 * @return HWIRE_EILSEQ for invalid byte sequence
 */
static int parse_reason(const unsigned char *str, size_t len, size_t *cur,
                        size_t *maxlen)
{
    size_t limit       = (len > *maxlen) ? *maxlen : len;
    unsigned char endc = 0;
    size_t n           = strfcchar(str, limit, &endc);

    if (n < limit) {
        if (likely(endc == CR && n + 1 < len && str[n + 1] == LF)) {
            *maxlen = n;
            *cur    = n + 2;
            return HWIRE_OK;
        } else if (likely(endc == LF)) {
            *cur    = n + 1;
            *maxlen = n;
            return HWIRE_OK;
        } else if (unlikely(endc != CR)) {
            // invalid character (including NUL) in reason-phrase
            return HWIRE_EILSEQ;
        } else if (unlikely(n + 1 != len)) {
            // CR found but next byte is not LF
            return HWIRE_EEOL;
        }
        // CR at exact end of buffer: need more data
        return HWIRE_EAGAIN;
    }

    // phrase-length too large
    if (len > *maxlen) {
        return HWIRE_ELEN;
    }

    return HWIRE_EAGAIN;
}

/**
 * @brief Parse HTTP status code
 *
 * @param str String to parse (must not be NULL)
 * @param len Length of string
 * @param cur Output: bytes consumed (must not be NULL)
 * @param status Output: status code (must not be NULL)
 * @return HWIRE_OK on success
 * @return HWIRE_EAGAIN if more data needed
 * @return HWIRE_ESTATUS for invalid status code
 */
static int parse_status(const unsigned char *str, size_t len, size_t *cur,
                        uint16_t *status)
{
#define STATUS_LEN 3

    if (len <= STATUS_LEN) {
        return HWIRE_EAGAIN;
    } else if (str[STATUS_LEN] != SP) {
        return HWIRE_ESTATUS;
    }
    // HTTP status code: 3*DIGIT (100-599)
    else if (str[0] < '1' || str[0] > '5' || str[1] < '0' || str[1] > '9' ||
             str[2] < '0' || str[2] > '9') {
        return HWIRE_ESTATUS;
    }

    *cur    = STATUS_LEN + 1;
    *status = (str[0] - 0x30) * 100 + (str[1] - 0x30) * 10 + (str[2] - 0x30);
    return HWIRE_OK;

#undef STATUS_LEN
}

/**
 * @brief Parse HTTP response
 *
 * Parses status line and headers, calling response_cb after status line
 * and header_cb for each header.
 */
int hwire_parse_response(hwire_ctx_t *ctx, const char *str, size_t len,
                         size_t *pos, size_t maxlen, uint8_t maxnhdrs)
{
    assert(str != NULL);
    assert(pos != NULL);
    assert(ctx != NULL);
    assert(ctx->response_cb != NULL);
    assert(ctx->header_cb != NULL);
    const unsigned char *ustr = (const unsigned char *)str;
    const unsigned char *top  = ustr;
    hwire_response_t rsp;
    size_t cur = 0;
    int rv     = 0;

SKIP_NEXT_CRLF:
    if (unlikely(len == 0)) {
        return HWIRE_EAGAIN;
    }
    switch (*ustr) {
    case CR:
    case LF:
        ustr++;
        len--;
        goto SKIP_NEXT_CRLF;
    }

    // parse version
    // status-line = HTTP-version SP status-code SP reason-phrase CRLF
    // RFC 7230 3.1.2 / RFC 9112 4: Status Line
    // RFC 7230 3.1.2 / RFC 9112 4: Status Line
    rv = parse_version(ustr, len, &cur, &rsp.version);
    if (rv != HWIRE_OK) {
        return rv;
    } else if (cur >= len) {
        return HWIRE_EAGAIN;
    } else if (ustr[cur] != SP) {
        return HWIRE_EVERSION;
    }
    ustr += cur + 1;
    len -= cur + 1;

    // parse status
    // status-code = 3DIGIT
    // RFC 7230 3.1.2 / RFC 9112 4: Status Code
    rv = parse_status(ustr, len, &cur, &rsp.status);
    if (rv != HWIRE_OK) {
        return rv;
    }
    ustr += cur;
    len -= cur;

    // parse reason
    // reason-phrase = *( HTAB / SP / VCHAR / obs-text )
    // RFC 7230 3.1.2 / RFC 9112 4: Reason Phrase
    rsp.reason.ptr = (const char *)ustr;
    rsp.reason.len = maxlen;
    rv             = parse_reason(ustr, len, &cur, &rsp.reason.len);
    if (rv != HWIRE_OK) {
        return rv;
    }
    ustr += cur;
    len -= cur;

    // call response callback
    if (ctx->response_cb(ctx, &rsp) != 0) {
        return HWIRE_ECALLBACK;
    }

    // parse headers
    cur = 0;
    rv  = hwire_parse_headers(ctx, (const char *)ustr, len, &cur, maxlen,
                              maxnhdrs);
    if (rv != HWIRE_OK) {
        return rv;
    }
    ustr += cur;

    *pos = (size_t)(ustr - top);
    return HWIRE_OK;
}

/** @} */ /* end of HTTP Response Parsing Functions */

// EOF
