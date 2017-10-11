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
local isVchar = require('rfcvalid.implc').isvchar;
local tonumber = tonumber;
local strfind = string.find;
local strsub = string.sub;
local strbyte = string.byte;
local strlower = string.lower;
--- error constants
-- need more bytes
local EAGAIN = -1;
-- method not implemented
local EMETHOD = -2;
-- invalid uri string
local EURIFMT = -3;
-- uri-length too large
local EURILEN = -4;
-- version not support
local EVERSION = -5;
-- header-length too large
local EHDRLEN = -6;
-- too many headers
local EHDRNUM = -7;
-- invalid header format
local EHDRFMT = -8;
-- invalid header field-name
local EHDRNAME = -9;
-- invalid header field-value
local EHDRVAL = -10;
-- invalid status code
local ESTATUS = -11;
-- invalid reason-phrase length
local EREASONLEN = -12;
-- invalid reason-phrase format
local EREASONFMT = -13;
--- constants
local SLASH = strbyte('/');
local CRLF_SKIPS = {
    [strbyte('\n')] = 2,
    [strbyte('\r')] = 3
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
-- muximum version length: 8 (HTTP/x.x)
local VERSION_LEN_MAX = 8;
-- muximum status-code length: 3 (1xx - 5xx)
local STATUS_LEN_MAX = 3;
--- defaults
-- muximum reason length: 127
local REASON_LEN_MAX = 127;
-- maximum uri length (include CRLF)
local URI_LEN_MAX = 4096;
-- maximum header length (include CRLF)
local HEADER_LEN_MAX = 4096;
-- number of headers
local HEADER_NUM_MAX = 127;
--- default limits
local DEFAULT_LIMITS = {
    REASON_LEN_MAX = REASON_LEN_MAX,
    URI_LEN_MAX = URI_LEN_MAX,
    HEADER_LEN_MAX = HEADER_LEN_MAX,
    HEADER_NUM_MAX = HEADER_NUM_MAX
};


--- getlimits
-- @param limits
-- @return limits
local function getlimits( limits )
    return {
        REASON_LEN_MAX = limits.REASON_LEN_MAX or DEFAULT_LIMITS.REASON_LEN_MAX,
        URI_LEN_MAX = limits.URI_LEN_MAX or DEFAULT_LIMITS.URI_LEN_MAX,
        HEADER_LEN_MAX = limits.HEADER_LEN_MAX or DEFAULT_LIMITS.HEADER_LEN_MAX,
        HEADER_NUM_MAX = limits.HEADER_NUM_MAX or DEFAULT_LIMITS.HEADER_NUM_MAX
    };
end


--- header
-- @param hdr
-- @param msg
-- @param cur
-- @param limits
-- @return consumed
local function header( hdr, msg, cur, limits )
    local nhdr = 0;
    local head, tail;

    -- use default cursor posision
    if cur == nil then
        cur = 1;
    end

    -- use default limits
    if limits == nil then
        limits = DEFAULT_LIMITS;
    end

    -- parse header
    head, tail = strfind( msg, '\r?\n', cur );

    if not head then
        -- more bytes need
        if ( #msg - cur ) <= limits.HEADER_LEN_MAX then
            return EAGAIN;
        end

        -- invalid header-length
        return EHDRLEN;
    -- invalid header-length
    elseif ( head - cur ) > limits.HEADER_LEN_MAX then
        return EHDRLEN;
    end

    -- parse headers
    while head ~= cur do
        -- limit number of headers exceeded
        if nhdr > limits.HEADER_NUM_MAX then
            return EHDRNUM;
        else
            local line = strsub( msg, cur, head - 1 );
            local key, val;

            -- update cursor
            cur = tail + 1;
            -- find separater
            head = strfind( line, ':', 1, true );
            if not head then
                -- invalid header-format
                return EHDRFMT;
            end

            -- verify key
            key = isFieldName( strsub( line, 1, head - 1 ) );
            if not key then
                -- invalid header-name
                return EHDRNAME;
            end
            key = strlower( key );

            -- verify val
            val = isFieldValue( strsub( line, head + 1 ) );
            if not val then
                -- invalid header-value
                return EHDRVAL;
            -- ignore empty val
            elseif #val > 0 then
                -- duplicated
                if hdr[key] then
                    hdr[key] = {
                        hdr[key],
                        val
                    };
                else
                    hdr[key] = val;
                end
            end

            -- find next line
            head, tail = strfind( msg, '\r?\n', cur );
            if not head then
                -- more bytes need
                if ( #msg - cur ) <= limits.HEADER_LEN_MAX then
                    return EAGAIN;
                end

                -- invalid header-length
                return EHDRLEN;
            -- invalid header-length
            elseif ( head - cur ) > limits.HEADER_LEN_MAX then
                return EHDRLEN;
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
-- @param limits
-- @return consumed
local function request( req, msg, limits )
    -- skip leading CRLF
    local cur = CRLF_SKIPS[strbyte( msg, 1 )] or 1;
    local head, tail;

    -- use default-limits
    if limits == nil then
        limits = DEFAULT_LIMITS;
    end

    -- find tail of method
    head = strfind( msg, ' ', cur, true );
    if not head then
        -- more bytes need
        if #msg < METHOD_LEN_MAX then
            return EAGAIN;
        end

        -- unsupported method
        return EMETHOD;
    end

    -- extract method
    req.method = strsub( msg, cur, head - 1 );
    -- unsupported method
    if not METHOD[req.method] then
        return EMETHOD;
    end
    cur = head + 1;

    -- parse absolute-path
    if strbyte( msg, cur ) == SLASH then
        -- find tail of path
        head = strfind( msg, ' ', cur + 1, true );
        if not head then
            -- more bytes need
            if ( #msg - cur ) <= limits.URI_LEN_MAX then
                return EAGAIN;
            end

            -- uri too long
            return EURILEN;
        -- uri too long
        elseif ( head - cur ) > limits.URI_LEN_MAX then
            return EURILEN;
        end

        -- extract path
        req.path = strsub( msg, cur, head - 1 );
        cur = head + 1;

    -- parse scheme and authority
    else
        local top = cur;
        local authority;

        -- find tail of scheme
        head, tail = strfind( msg, '://', cur, true );
        -- more bytes need
        if not head then
            return EAGAIN;
        end

        -- extract scheme
        req.scheme = strsub( msg, cur, head - 1 );
        -- scheme = alpha *( alpha / digit / "+" / "-" / "." )
        -- invalid scheme
        if not strfind( req.scheme, '^(%a[%w+.-]*)$' ) then
            return EURIFMT;
        end
        cur = tail + 1;

        -- parse authority
        -- find tail of authority (SLASH or SP)
        head, tail, authority = strfind( msg, '^([^/ ]+)', cur );
        if not head then
            -- more bytes need
            if ( #msg - cur ) <= AUTHORITY_LEN_MAX then
                return EAGAIN;
            end

            -- invalid authority-length
            return EURIFMT;
        -- invalid authority-length
        elseif #authority > AUTHORITY_LEN_MAX then
            return EURIFMT;
        end
        cur = tail + 1;

        -- find port separater
        head = strfind( authority, ':', 1, true );
        if head then
            -- extract port
            req.port = tonumber( strsub( authority, head + 1 ) );
            -- verify port
            if not req.port or not isUInt16( req.port ) then
                -- invalid port or port-range
                return EURIFMT;
            end
            req.host = strsub( authority, 1, head - 1 );
        else
            req.host = authority;
        end

        -- verify host
        if not isHostname( req.host ) then
            -- invalid hostname
            return EURIFMT;
        end

        -- found SLASH
        if strbyte( msg, cur ) == SLASH then
            -- find tail of path
            head = strfind( msg, ' ', cur, true );
            if not head then
                -- more bytes need
                if ( cur - top ) <= limits.URI_LEN_MAX then
                    return EAGAIN;
                end

                -- uri too long
                return EURILEN;
            -- uri too long
            elseif ( head - top ) > limits.URI_LEN_MAX then
                return EURILEN;
            end

            -- extract path
            req.path = strsub( msg, cur, head - 1 );
            cur = head + 1;
        -- found SP
        else
            req.path = '/';
            cur = cur + 1;
        end
    end

    -- TODO: verify path

    -- parse version
    head, tail, req.ver = strfind( msg, '^HTTP/(1.[01])\r?\n', cur );
    if not head then
        -- more bytes need
        if ( #msg - cur ) < VERSION_LEN_MAX then
            return EAGAIN;
        end

        -- invalid version or version-length
        return EVERSION;
    end
    req.ver = VERSION[req.ver];
    cur = tail + 1;

    -- parse header
    return header( req.header, msg, cur, limits );
end


--- response
-- @param res
-- @param msg
-- @param limits
-- @return consumed
local function response( res, msg, limits )
    local head, tail, cur;

    -- use default-limits
    if limits == nil then
        limits = DEFAULT_LIMITS;
    end

    -- parse version
    head, tail, res.ver = strfind( msg, '^HTTP/(1.[01]) ', 1 );
    if not head then
        -- more bytes need
        if #msg < VERSION_LEN_MAX then
            return EAGAIN;
        end

        -- invalid version or version-length
        return EVERSION;
    end
    res.ver = VERSION[res.ver];
    cur = tail + 1;

    -- parse status
    head, tail, res.status = strfind( msg, '^([1-5][0-9][0-9]) ', cur );
    if not head then
        -- more bytes need
        if ( #msg - cur ) < STATUS_LEN_MAX then
            return EAGAIN;
        end

        -- invalid status-code
        return ESTATUS;
    end
    res.status = tonumber( res.status );
    cur = tail + 1;

    -- parse reason-phrase
    head, tail = strfind( msg, '\r?\n', cur );
    if not head then
        -- more bytes need
        if ( #msg - cur ) < limits.REASON_LEN_MAX then
            return EAGAIN;
        end

        -- invalid reason-length
        return EREASONLEN;
    end
    res.reason = strsub( msg, cur, head - 1 );
    cur = tail + 1;

    -- reason-phrase  = *( HTAB / SP / VCHAR / obs-text )
    -- VCHAR          = %x21-7E
    res.reasons = isVchar( res.reason );
    if not res.reason then
        -- invalid reason-phrase
        return EREASONFMT;
    end

    return header( res.header, msg, cur, limits )
end


return {
    header = header,
    request = request,
    response = response,
    getlimits = getlimits,
    --- error constants
    -- need more bytes
    EAGAIN = EAGAIN,
    -- method not implemented
    EMETHOD = EMETHOD,
    -- invalid uri string
    EURIFMT = EURIFMT,
    -- uri-length too large
    EURILEN = EURILEN,
    -- version not support
    EVERSION = EVERSION,
    -- header-length too large
    EHDRLEN = EHDRLEN,
    -- too many headers
    EHDRNUM = EHDRNUM,
    -- invalid header format
    EHDRFMT = EHDRFMT,
    -- invalid header field-name
    EHDRNAME = EHDRNAME,
    -- invalid header field-value
    EHDRVAL = EHDRVAL,
    -- invalid status code
    ESTATUS = ESTATUS,
    -- invalid reason-phrase length
    EREASONLEN = EREASONLEN,
    -- invalid reason-phrase format
    EREASONFMT = EREASONFMT
};

