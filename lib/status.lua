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
local find = string.find
local format = string.format
local isa = require('isa')
local is_int = isa.int
local is_finite = isa.finite
local is_string = isa.string
--- constants
local HTTP_VER = {
    [0.9] = 'HTTP/0.9',
    [1.0] = 'HTTP/1.0',
    [1.1] = 'HTTP/1.1',
}
local NAME2CODE = {}
local CODE2NAME = {}
local CODE2REASON = {}
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
    CODE2NAME[v.code] = v.name
    CODE2REASON[v.code] = v.reason
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

--- code2name
--- @param code integer
--- @return string name
local function code2name(code)
    if not is_int(code) then
        error('code must be integer', 2)
    end
    return CODE2NAME[code]
end

--- toline
--- @param code integer
--- @param ver? number
--- @param reason? string
--- @return string msg
local function toline(code, ver, reason)
    if not is_int(code) then
        error('code must be integer', 2)
    elseif ver ~= nil then
        local httpver = HTTP_VER[ver]
        if httpver then
            ver = httpver
        elseif not is_finite(ver) then
            error('version must be finite-number', 2)
        else
            ver = format('HTTP/%.1f', ver)
        end
    end

    if reason == nil then
        reason = CODE2REASON[code]
        if not reason then
            reason = 'Unknown Status'
        end
    elseif not is_string(reason) or find(reason, '[^a-zA-Z0-9\'_ \t-]') then
        error('reason must be the following string: [a-zA-Z0-9\'_ \t-]', 2)
    end

    if ver then
        return format('%s %d %s\r\n', ver, code, reason)
    end

    return format('%d %s\r\n', code, reason)
end

return {
    name2code = name2code,
    code2name = code2name,
    toline = toline,
}

