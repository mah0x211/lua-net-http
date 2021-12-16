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
local error = error
local format = string.format
local is_uint = require('isa').uint
local is_finite = require('isa').finite
--- constants
local CRLF = '\r\n'
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
local STATUS_LINE10 = {}
local STATUS_LINE11 = {}
for k, v in pairs(STATUS_MSG) do
    STATUS_LINE10[k] = 'HTTP/1.0 ' .. v .. CRLF
    STATUS_LINE11[k] = 'HTTP/1.1 ' .. v .. CRLF
end

--- toline
--- @param code integer
--- @param ver number
--- @return string msg
--- @return string err
local function toline(code, ver)
    local msg

    if not is_uint(code) then
        error('code must be number', 2)
    elseif ver == nil then
        msg = STATUS_MSG[code]
    elseif not is_finite(ver) then
        error('ver must be finite-number', 2)
    elseif ver == 1.0 then
        -- http/1.0
        msg = STATUS_LINE10[code]
    elseif ver == 1.1 then
        -- http/1.1
        msg = STATUS_LINE11[code]
    else
        -- invalid version number
        return nil, format('unsupported version %q', ver)
    end

    if not msg then
        return nil, format('unsupported status code %q', code)
    end

    return msg
end

return {
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

