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

  lib/request.lua
  lua-net-http
  Created by Masatoshi Teruya on 17/10/12.

--]]

--- assign to local
local parseURI = require('url').parse;
local encodeURI = require('url').encodeURI;
-- local decodeURI = require('url').decodeURI;
-- local encodeIdna = require('idna').encode;
local Header = require('net.http.header');
local Entity = require('net.http.entity');
local setmetatable = setmetatable;
local type = type;
local assert = assert;
local concat = table.concat;
-- local strfind = string.find;
local strupper = string.upper;
local strformat = string.format;
--- constants
local CRLF = '\r\n';
local DEFAULT_AGENT = 'User-Agent: lua-net-http' .. CRLF;
local SCHEME_LUT = {
    http = 80,
    https = 443
};
local METHOD_LUT = {
    CONNECT = 'CONNECT',
    DELETE = 'DELETE',
    GET = 'GET',
    HEAD = 'HEAD',
    OPTIONS = 'OPTIONS',
    POST = 'POST',
    PUT = 'PUT',
    TRACE = 'TRACE',
};


--- class Request
local Request = {
    setBody = Entity.setBody,
    unsetBody = Entity.unsetBody
};


--- line
-- @return str
function Request:line()
    local arr = {
        self.method,
        ' '
    };
    local narr = 4;

    -- create request line
    if self.url.scheme then
        arr[3] = self.url.scheme;
        arr[4] = '://';
        arr[5] = self.url.hostname;
        if self.url.port then
            arr[6] = ':';
            arr[7] = self.url.port;
            arr[8] = self.url.path;
            narr = 9;
        else
            arr[6] = self.url.path;
            narr = 7;
        end
    else
        arr[3] = self.url.path;
    end

    -- append query-string
    if self.url.query then
        arr[narr] = self.url.query;
        narr = narr + 1;
    end

    -- set version
    arr[narr] = ' HTTP/1.1\r\n';

    return concat( arr );
end


--- setMethod
-- @param data
-- @param len
function Request:setMethod( method )
    self.method = assert( METHOD_LUT[strupper(method)], 'invalid method' );
end


--- setQuery
-- @param qry
function Request:setQuery( qry )
    if qry == nil then
        self.url.query = nil;
    elseif type( qry ) == 'table' then
        local arr = {};
        local idx = 1;

        for k, v in pairs( qry ) do
            if type( k ) == 'string' and type( v ) == 'string' then
                arr[idx] = '&';
                arr[idx + 1] = encodeURI( k );
                arr[idx + 2] = '=';
                arr[idx + 3] = encodeURI( v );
                idx = idx + 4;
            end
        end

        -- set new query-string
        if idx > 1 then
            self.url.query = '?' .. concat( arr, nil, 2 );
        -- remove query-string
        else
            self.url.query = nil;
        end
    end

    error( 'qry must be table or nil' );
end


--- new
-- @param method
-- @param uri
-- @return res
-- @return err
local function new( method, uri )
    local header = Header.new();
    local vals = header.vals;
    local dict = header.dict;
    local req = {
        header = header
    };
    local wellknown, offset, err;

    -- check method
    assert( type( method ) == 'string', 'method must be string' );
    req.method = METHOD_LUT[strupper(method)];
    if not req.method then
        return nil, 'invalid method - unsupported method';
    end

    -- parse url
    assert( type( uri ) == 'string', 'uri must be string' );
    uri = assert( encodeURI( uri ) );
    req.url, offset, err = parseURI( uri );
    if err then
        return nil, strformat(
            'invalid uri - found illegal byte sequence %q at %d', err, offset
        );
    -- scheme required
    elseif not req.url.scheme then
        return nil, 'invalid uri - scheme required';
    -- unknown scheme
    elseif not SCHEME_LUT[req.url.scheme] then
        return nil, 'invalid uri - unsupported scheme';
    -- set to default port
    elseif not req.url.port or req.url.port == SCHEME_LUT[req.url.scheme] then
        req.url.port = SCHEME_LUT[req.url.scheme];
        wellknown = true;
    end

    -- TODO: hostname should encode by punycode
    -- if strfind( req.url.hostname, '%', 1, true ) then
    --     local host;

    --     host, err = decodeURI( req.url.hostname );
    --     if err then
    --         return nil, 'invalid uri - ' .. err;
    --     end

    --     req.url.hostname, err = encodeIdna( host );
    --     if err then
    --         return nil, err;
    --     end

    --     req.url.host = req.url.hostname .. ':' .. req.url.port;
    -- end

    -- set host header
    -- without port-number
    if wellknown then
        vals[3] = 'Host: ' .. req.url.hostname .. CRLF;
    -- with port-number
    else
        vals[3] = 'Host: ' .. req.url.host .. CRLF;
    end
    dict[3] = 'host';
    dict.host = 3;

    -- set default path
    if not req.url.path then
        req.url.path = '/';
    end

    -- set default headers
    -- reserved for first-line
    vals[1] = false;
    vals[2] = DEFAULT_AGENT;
    -- reserved for first-line
    dict[1] = false;
    dict[2] = 'user-agent';
    dict['user-agent'] = 2;

    return setmetatable( req, {
        __index = Request
    });
end


--- trace
-- @param uri
-- @return req
-- @return err
local function trace( uri )
    return new( 'TRACE', uri );
end


--- put
-- @param uri
-- @return req
-- @return err
local function put( uri )
    return new( 'PUT', uri );
end


--- post
-- @param uri
-- @return req
-- @return err
local function post( uri )
    return new( 'POST', uri );
end


--- options
-- @param uri
-- @return req
-- @return err
local function options( uri )
    return new( 'OPTIONS', uri );
end


--- head
-- @param uri
-- @return req
-- @return err
local function head( uri )
    return new( 'HEAD', uri );
end


--- get
-- @param uri
-- @return req
-- @return err
local function get( uri )
    return new( 'GET', uri );
end


--- delete
-- @param uri
-- @return req
-- @return err
local function delete( uri )
    return new( 'DELETE', uri );
end


--- connect
-- @param uri
-- @return req
-- @return err
local function connect( uri )
    return new( 'CONNECT', uri );
end


return {
    new = new,
    connect = connect,
    delete = delete,
    get = get,
    head = head,
    options = options,
    post = post,
    put = put,
    trace = trace,
};

