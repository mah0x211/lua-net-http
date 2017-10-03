--[[

  Copyright (C) 2017 Masatoshi Teruya

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.

  lib/parser.lua
  lua-net-http
  Created by Masatoshi Teruya on 17/08/03.

--]]

--- asign to local
local isFieldName = require('rfcvalid.7230').isFieldName;
local isFieldValue = require('rfcvalid.7230').isFieldValue;
local isHostname = require('rfcvalid.1035').isHostname;
local isUInt16 = require('rfcvalid.1035').isUInt16;
--- constants
local EAGAIN = -2;
local Status = require('net.http.status');
local BAD_REQUEST = -Status.BAD_REQUEST;
local REQUEST_URI_TOO_LONG = -Status.REQUEST_URI_TOO_LONG;
local REQUEST_HEADER_FIELDS_TOO_LARGE = -Status.REQUEST_HEADER_FIELDS_TOO_LARGE;
local NOT_IMPLEMENTED = -Status.NOT_IMPLEMENTED;
local SLASH = string.byte('/');
local CRLF_SKIPS = {
    [('\n'):byte(1)] = 2,
    [('\r'):byte(1)] = 3
};
local VERSION = {
    ['1.0'] = 1.0,
    ['1.1'] = 1.1
};
local METHOD = {
    GET = 'get',
    PUT = 'put',
    POST = 'post',
    HEAD = 'head',
    TRACE = 'trace',
    DELETE = 'delete',
    OPTIONS = 'options',
    CONNECT = 'connect',
};
local METHOD_LEN_MAX = #METHOD.CONNECT;
-- maximum authority length: 253 (domain-name length) + 5 (16-bit port-number)
local AUTHORITY_LEN_MAX = 258;
-- maximum uri length (include CRLF)
local URI_LEN_MAX = 4096;
-- muximum version length: 8 (HTTP/x.x)
local VERSION_LEN_MAX = 8;
-- maximum header length (include CRLF)
local HEADER_LEN_MAX = 4096;
--- defaults
-- number of headers
local HEADER_NUM_MAX = 127;
local REQ_HEADER_NUM_MAX = 31;


--- header
-- @param hdr
-- @param msg
-- @param cur
-- @param maxhdr
-- @return consumed
-- @return err
local function header( hdr, msg, cur, maxhdr )
    local nhdr = 0;
    local head, tail;

    if cur == nil then
        cur = 1;
    end

    if maxhdr == nil then
        maxhdr = DEFAULT_HEADER_NUM_MAX;
    end

    -- parse header
    head, tail = msg:find( '\r?\n', cur );

    if not head then
        -- more bytes need
        if ( #msg - cur ) <= HEADER_LEN_MAX then
            return EAGAIN;
        end

        -- invalid header-length
        return REQUEST_HEADER_FIELDS_TOO_LARGE, 'invalid header-length';
    end

    -- parse headers
    while head ~= cur do
        -- limit number of headers exceeded
        if nhdr > maxhdr then
            return BAD_REQUEST, 'too many headers';
        else
            local line = msg:sub( cur, head - 1 );
            local key, val;

            -- update cursor
            cur = tail + 1;
            -- find separater
            head = line:find( ':', 1, true );
            if not head then
                -- invalid header
                return BAD_REQUEST, 'invalid header format';
            end

            -- verify key
            key = isFieldName( line:sub( 1, head - 1 ) );
            if not key then
                -- invalid header-name
                return BAD_REQUEST, 'invalid header-name';
            end
            key = key:lower();

            -- verify val
            val = isFieldValue( line:sub( head + 1 ) );
            if not val then
                -- invalid header-value
                return BAD_REQUEST, 'invalid header-value';
            end

            -- duplicated
            if hdr[key] then
                hdr[key] = {
                    hdr[key],
                    val
                };
            else
                hdr[key] = val;
            end

            -- find next line
            head, tail = msg:find( '\r?\n', cur );
            if not head then
                -- more bytes need
                if ( #msg - cur ) <= HEADER_LEN_MAX then
                    return EAGAIN;
                end

                -- invalid header-length
                return REQUEST_HEADER_FIELDS_TOO_LARGE, 'invalid header-length';
            end

            -- count number of headers
            nhdr = nhdr + 1;
        end
    end

    return tail;
end


--- request
-- @param req
-- @param msg
-- @return consumed
-- @return err
local function request( req, msg )
    -- skip leading CRLF
    local cur = CRLF_SKIPS[msg:byte(1)] or 1;
    local head, tail;

    -- find tail of method
    head = msg:find(' ', cur, true );
    if not head then
        -- more bytes need
        if #msg < METHOD_LEN_MAX then
            return EAGAIN;
        end

        -- unsupported method
        return NOT_IMPLEMENTED, 'unsupported method';
    end

    -- extract method
    req.method = msg:sub( cur, head - 1 );
    -- invalid method
    if not METHOD[req.method] then
        return NOT_IMPLEMENTED, 'unsupported method';
    end
    cur = head + 1;

    -- parse absolute-path
    if msg:byte( cur ) == SLASH then
        -- find tail of path
        head = msg:find( ' ', cur + 1, true );
        if not head then
            -- more bytes need
            if ( #msg - cur ) <= URI_LEN_MAX then
                return EAGAIN;
            end

            -- uri too long
            return REQUEST_URI_TOO_LONG, 'uri too long';
        -- uri too long
        elseif ( head - cur ) > URI_LEN_MAX then
            return REQUEST_URI_TOO_LONG, 'uri too long';
        end

        -- extract path
        req.path = msg:sub( cur, head - 1 );
        cur = head + 1;

    -- parse scheme and authority
    else
        local top = cur;
        local authority;

        -- find tail of scheme
        head, tail = msg:find( '://', cur, true );
        -- more bytes need
        if not head then
            return EAGAIN;
        end

        -- extract scheme
        req.scheme = msg:sub( cur, head - 1 );
        -- scheme = alpha *( alpha / digit / "+" / "-" / "." )
        -- invalid scheme
        if not req.scheme:find('^(%a[%w+.-]*)$') then
            return BAD_REQUEST, 'invalid scheme format';
        end
        cur = tail + 1;

        -- parse authority
        -- find tail of authority (SLASH or SP)
        head, tail, authority = msg:find( '^([^/ ]+)', cur );
        if not head then
            -- more bytes need
            if ( #msg - cur ) <= AUTHORITY_LEN_MAX then
                return EAGAIN;
            end

            -- invalid authority-length
            return BAD_REQUEST, 'invalid authority-length';
        -- invalid authority-length
        elseif #authority > AUTHORITY_LEN_MAX then
            return BAD_REQUEST, 'invalid authority-length';
        end
        cur = tail + 1;

        -- find port separater
        head = authority:find( ':', 1, true );
        if head then
            -- extract port
            req.port = tonumber( authority:sub( head + 1 ) );
            -- verify port
            if not req.port or not isUInt16( req.port ) then
                -- invalid port or port-range
                return BAD_REQUEST, 'invalid port';
            end
            req.host = authority:sub( 1, head - 1 );
        else
            req.host = authority;
        end

        -- verify host
        if not isHostname( req.host ) then
            -- invalid hostname
            return BAD_REQUEST, 'invalid host';
        end

        -- found SLASH
        if msg:byte( cur ) == SLASH then
            -- find tail of path
            head = msg:find( ' ', cur, true );
            if not head then
                -- more bytes need
                if ( cur - top ) <= URI_LEN_MAX then
                    return EAGAIN;
                end

                -- uri too long
                return REQUEST_URI_TOO_LONG, 'uri too long';
            -- uri too long
            elseif ( head - top ) > URI_LEN_MAX then
                return REQUEST_URI_TOO_LONG, 'uri too long';
            end

            -- extract path
            req.path = msg:sub( cur, head - 1 );
            cur = head + 1;
        -- found SP
        else
            req.path = '/';
            cur = cur + 1;
        end
    end

    -- TODO: verify path

    -- parse version
    head, tail, req.ver = msg:find( '^HTTP/(1.[01])\r?\n', cur );
    if not head then
        -- more bytes need
        if ( #msg - cur ) < VERSION_LEN_MAX then
            return EAGAIN;
        end

        -- invalid version or version-length
        return BAD_REQUEST, 'invalid version';
    end
    req.ver = VERSION[req.ver];
    cur = tail + 1;

    -- parse header
    return header( req.header, msg, cur, REQ_HEADER_NUM_MAX );
end


return {
    header = header,
    request = request,
};

