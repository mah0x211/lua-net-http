--
-- Copyright (C) 2017 Masatoshi Teruya
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
-- lib/status.lua
-- lua-net-http
-- Created by Masatoshi Teruya on 17/08/01.
--
--- assign to local
local tostring = tostring
local format = string.format
local isa = require('isa')
local is_int = isa.int
local is_string = isa.string
--- constants
local HTTP_VER = {
    [1] = 'HTTP/1.0',
    [1.1] = 'HTTP/1.1',
}
local NAME2CODE = {}
for _, v in ipairs({
    --- status names
    -- 1×× Informational
    {
        name = 'CONTINUE',
        code = 100,
        reason = 'Continue',
    },
    {
        name = 'SWITCHING_PROTOCOLS',
        code = 101,
        reason = 'Switching Protocols',
    },
    {
        name = 'PROCESSING',
        code = 102,
        reason = 'Processing',
    },
    -- 2×× Success
    {
        name = 'OK',
        code = 200,
        reason = 'OK',
    },
    {
        name = 'CREATED',
        code = 201,
        reason = 'Created',
    },
    {
        name = 'ACCEPTED',
        code = 202,
        reason = 'Accepted',
    },
    {
        name = 'NON_AUTHORITATIVE_INFORMATION',
        code = 203,
        reason = 'Non-authoritative Information',
    },
    {
        name = 'NO_CONTENT',
        code = 204,
        reason = 'No Content',
    },
    {
        name = 'RESET_CONTENT',
        code = 205,
        reason = 'Reset Content',
    },
    {
        name = 'PARTIAL_CONTENT',
        reason = 'Partial Content',
        code = 206,
    },
    {
        name = 'MULTI_STATUS',
        code = 207,
        reason = 'Multi-Status',
    },
    {
        name = 'ALREADY_REPORTED',
        code = 208,
        reason = 'Already Reported',
    },
    {
        name = 'IM_USED',
        code = 226,
        reason = 'IM Used',
    },
    -- 3×× Redirection
    {
        name = 'MULTIPLE_CHOICES',
        code = 300,
        reason = 'Multiple Choices',
    },
    {
        name = 'MOVED_PERMANENTLY',
        code = 301,
        reason = 'Moved Permanently',
    },
    {
        name = 'FOUND',
        code = 302,
        reason = 'Found',
    },
    {
        name = 'SEE_OTHER',
        code = 303,
        reason = 'See Other',
    },
    {
        name = 'NOT_MODIFIED',
        code = 304,
        reason = 'Not Modified',
    },
    {
        name = 'USE_PROXY',
        code = 305,
        reason = 'Use Proxy',
    },
    {
        name = 'TEMPORARY_REDIRECT',
        code = 307,
        reason = 'Temporary Redirect',
    },
    {
        name = 'PERMANENT_REDIRECT',
        code = 308,
        reason = 'Permanent Redirect',
    },
    -- 4×× Client Error
    {
        name = 'BAD_REQUEST',
        code = 400,
        reason = 'Bad Request',
    },
    {
        name = 'UNAUTHORIZED',
        code = 401,
        reason = 'Unauthorized',
    },
    {
        name = 'PAYMENT_REQUIRED',
        code = 402,
        reason = 'Payment Required',
    },
    {
        name = 'FORBIDDEN',
        code = 403,
        reason = 'Forbidden',
    },
    {
        name = 'NOT_FOUND',
        code = 404,
        reason = 'Not Found',
    },
    {
        name = 'METHOD_NOT_ALLOWED',
        code = 405,
        reason = 'Method Not Allowed',
    },
    {
        name = 'NOT_ACCEPTABLE',
        code = 406,
        reason = 'Not Acceptable',
    },
    {
        name = 'PROXY_AUTHENTICATION_REQUIRED',
        code = 407,
        reason = 'Proxy Authentication Required',
    },
    {
        name = 'REQUEST_TIMEOUT',
        code = 408,
        reason = 'Request Timeout',
    },
    {
        name = 'CONFLICT',
        code = 409,
        reason = 'Conflict',
    },
    {
        name = 'GONE',
        code = 410,
        reason = 'Gone',
    },
    {
        name = 'LENGTH_REQUIRED',
        code = 411,
        reason = 'Length Required',
    },
    {
        name = 'PRECONDITION_FAILED',
        code = 412,
        reason = 'Precondition Failed',
    },
    {
        name = 'PAYLOAD_TOO_LARGE',
        code = 413,
        reason = 'Payload Too Large',
    },
    {
        name = 'REQUEST_URI_TOO_LONG',
        code = 414,
        reason = 'Request-URI Too Long',
    },
    {
        name = 'UNSUPPORTED_MEDIA_TYPE',
        code = 415,
        reason = 'Unsupported Media Type',
    },
    {
        name = 'REQUESTED_RANGE_NOT_SATISFIABLE',
        code = 416,
        reason = 'Requested Range Not Satisfiable',
    },
    {
        name = 'EXPECTATION_FAILED',
        code = 417,
        reason = 'Expectation Failed',
    },
    {
        name = 'IM_A_TEAPOT',
        code = 418,
        reason = 'I\'m a teapot',
    },
    {
        name = 'MISDIRECTED_REQUEST',
        code = 421,
        reason = 'Misdirected Request',
    },
    {
        name = 'UNPROCESSABLE_ENTITY',
        code = 422,
        reason = 'Unprocessable Entity',
    },
    {
        name = 'LOCKED',
        code = 423,
        reason = 'Locked',
    },
    {
        name = 'FAILED_DEPENDENCY',
        code = 424,
        reason = 'Failed Dependency',
    },
    {
        name = 'UPGRADE_REQUIRED',
        code = 426,
        reason = 'Upgrade Required',
    },
    {
        name = 'PRECONDITION_REQUIRED',
        code = 428,
        reason = 'Precondition Required',
    },
    {
        name = 'TOO_MANY_REQUESTS',
        code = 429,
        reason = 'Too Many Requests',
    },
    {
        name = 'REQUEST_HEADER_FIELDS_TOO_LARGE',
        code = 431,
        reason = 'Request Header Fields Too Large',
    },
    {
        name = 'UNAVAILABLE_FOR_LEGAL_REASONS',
        code = 451,
        reason = 'Unavailable For Legal Reasons',
    },
    -- 5×× Server Error
    {
        name = 'INTERNAL_SERVER_ERROR',
        code = 500,
        reason = 'Internal Server Error',
    },
    {
        name = 'NOT_IMPLEMENTED',
        code = 501,
        reason = 'Not Implemented',
    },
    {
        name = 'BAD_GATEWAY',
        code = 502,
        reason = 'Bad Gateway',
    },
    {
        name = 'SERVICE_UNAVAILABLE',
        code = 503,
        reason = 'Service Unavailable',
    },
    {
        name = 'GATEWAY_TIMEOUT',
        code = 504,
        reason = 'Gateway Timeout',
    },
    {
        name = 'HTTP_VERSION_NOT_SUPPORTED',
        code = 505,
        reason = 'HTTP Version Not Supported',
    },
    {
        name = 'VARIANT_ALSO_NEGOTIATES',
        code = 506,
        reason = 'Variant Also Negotiates',
    },
    {
        name = 'INSUFFICIENT_STORAGE',
        code = 507,
        reason = 'Insufficient Storage',
    },
    {
        name = 'LOOP_DETECTED',
        code = 508,
        reason = 'Loop Detected',
    },
    {
        name = 'NOT_EXTENDED',
        code = 510,
        reason = 'Not Extended',
    },
    {
        name = 'NETWORK_AUTHENTICATION_REQUIRED',
        code = 511,
        reason = 'Network Authentication Required',
    },
}) do
    NAME2CODE[v.name] = v.code
end

--- name2code
--- @param name string
--- @return integer code
local function name2code(name)
    if not is_string(name) then
        error('name must be string', 2)
    end
    return NAME2CODE[name]
end

local STATUS_MSG = {
    -- 1×× Informational
    [100] = '100 Continue',
    [101] = '101 Switching Protocols',
    [102] = '102 Processing',
    -- 2×× Success
    [200] = '200 OK',
    [201] = '201 Created',
    [202] = '202 Accepted',
    [203] = '203 Non-authoritative Information',
    [204] = '204 No Content',
    [205] = '205 Reset Content',
    [206] = '206 Partial Content',
    [207] = '207 Multi-Status',
    [208] = '208 Already Reported',
    [226] = '226 IM Used',
    -- 3×× Redirection
    [300] = '300 Multiple Choices',
    [301] = '301 Moved Permanently',
    [302] = '302 Found',
    [303] = '303 See Other',
    [304] = '304 Not Modified',
    [305] = '305 Use Proxy',
    [307] = '307 Temporary Redirect',
    [308] = '308 Permanent Redirect',
    -- 4×× Client Error
    [400] = '400 Bad Request',
    [401] = '401 Unauthorized',
    [402] = '402 Payment Required',
    [403] = '403 Forbidden',
    [404] = '404 Not Found',
    [405] = '405 Method Not Allowed',
    [406] = '406 Not Acceptable',
    [407] = '407 Proxy Authentication Required',
    [408] = '408 Request Timeout',
    [409] = '409 Conflict',
    [410] = '410 Gone',
    [411] = '411 Length Required',
    [412] = '412 Precondition Failed',
    [413] = '413 Payload Too Large',
    [414] = '414 Request-URI Too Long',
    [415] = '415 Unsupported Media Type',
    [416] = '416 Requested Range Not Satisfiable',
    [417] = '417 Expectation Failed',
    [418] = '418 I\'m a teapot',
    [421] = '421 Misdirected Request',
    [422] = '422 Unprocessable Entity',
    [423] = '423 Locked',
    [424] = '424 Failed Dependency',
    [426] = '426 Upgrade Required',
    [428] = '428 Precondition Required',
    [429] = '429 Too Many Requests',
    [431] = '431 Request Header Fields Too Large',
    [451] = '451 Unavailable For Legal Reasons',
    -- 5×× Server Error
    [500] = '500 Internal Server Error',
    [501] = '501 Not Implemented',
    [502] = '502 Bad Gateway',
    [503] = '503 Service Unavailable',
    [504] = '504 Gateway Timeout',
    [505] = '505 HTTP Version Not Supported',
    [506] = '506 Variant Also Negotiates',
    [507] = '507 Insufficient Storage',
    [508] = '508 Loop Detected',
    [510] = '510 Not Extended',
    [511] = '511 Network Authentication Required',
}

--- toline
--- @param code integer
--- @param ver number
--- @return string msg
local function toline(code, ver)
    if not is_int(code) then
        error('code must be integer', 2)
    elseif ver ~= nil then
        local httpver = HTTP_VER[ver]
        if not httpver then
            error(format('unsupported version %q', tostring(ver)), 2)
        end
        ver = httpver
    end

    local msg = STATUS_MSG[code]
    if not msg then
        msg = format('%d Unknown Status Code', code)
    end

    if ver then
        return format('%s %s\r\n', ver, msg)
    end
    return msg
end

return {
    name2code = name2code,
    toline = toline,
    --- status names
    -- 1×× Informational
    CONTINUE = 100,
    SWITCHING_PROTOCOLS = 101,
    PROCESSING = 102,
    -- 2×× Success
    OK = 200,
    CREATED = 201,
    ACCEPTED = 202,
    NON_AUTHORITATIVE_INFORMATION = 203,
    NO_CONTENT = 204,
    RESET_CONTENT = 205,
    PARTIAL_CONTENT = 206,
    MULTI_STATUS = 207,
    ALREADY_REPORTED = 208,
    IM_USED = 226,
    -- 3×× Redirection
    MULTIPLE_CHOICES = 300,
    MOVED_PERMANENTLY = 301,
    FOUND = 302,
    SEE_OTHER = 303,
    NOT_MODIFIED = 304,
    USE_PROXY = 305,
    TEMPORARY_REDIRECT = 307,
    PERMANENT_REDIRECT = 308,
    -- 4×× Client Error
    BAD_REQUEST = 400,
    UNAUTHORIZED = 401,
    PAYMENT_REQUIRED = 402,
    FORBIDDEN = 403,
    NOT_FOUND = 404,
    METHOD_NOT_ALLOWED = 405,
    NOT_ACCEPTABLE = 406,
    PROXY_AUTHENTICATION_REQUIRED = 407,
    REQUEST_TIMEOUT = 408,
    CONFLICT = 409,
    GONE = 410,
    LENGTH_REQUIRED = 411,
    PRECONDITION_FAILED = 412,
    PAYLOAD_TOO_LARGE = 413,
    REQUEST_URI_TOO_LONG = 414,
    UNSUPPORTED_MEDIA_TYPE = 415,
    REQUESTED_RANGE_NOT_SATISFIABLE = 416,
    EXPECTATION_FAILED = 417,
    IM_A_TEAPOT = 418,
    MISDIRECTED_REQUEST = 421,
    UNPROCESSABLE_ENTITY = 422,
    LOCKED = 423,
    FAILED_DEPENDENCY = 424,
    UPGRADE_REQUIRED = 426,
    PRECONDITION_REQUIRED = 428,
    TOO_MANY_REQUESTS = 429,
    REQUEST_HEADER_FIELDS_TOO_LARGE = 431,
    UNAVAILABLE_FOR_LEGAL_REASONS = 451,
    -- 5×× Server Error
    INTERNAL_SERVER_ERROR = 500,
    NOT_IMPLEMENTED = 501,
    BAD_GATEWAY = 502,
    SERVICE_UNAVAILABLE = 503,
    GATEWAY_TIMEOUT = 504,
    HTTP_VERSION_NOT_SUPPORTED = 505,
    VARIANT_ALSO_NEGOTIATES = 506,
    INSUFFICIENT_STORAGE = 507,
    LOOP_DETECTED = 508,
    NOT_EXTENDED = 510,
    NETWORK_AUTHENTICATION_REQUIRED = 511,
}

