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
local decodeURI = require('url').decodeURI;
local encodeIdna = require('idna').encode;
local Header = require('net.http.header');
local Entity = require('net.http.entity');
local type = type;
local assert = assert;
local concat = table.concat;
local strfind = string.find;
local strupper = string.upper;
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
        arr[narr] = '?';
        arr[narr + 1] = self.url.query;
        narr = narr + 2;
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
    local arr = {};
    local idx = 1;

    assert( type( qry ) == 'table', 'qry must be table' );
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
        self.query = concat( arr, nil, 2 );
    -- remove query-string
    else
        self.query = nil;
    end
end


--- unsetQuery
function Request:unsetQuery()
    self.query = nil;
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
        method = assert( METHOD_LUT[method], 'invalid method' ),
        header = header
    };
    local wellknown, err, _;

    -- parse url
    assert( type( uri ) == 'string', 'uri must be string' );
    uri = assert( encodeURI( uri ) );
    req.url, _, err = parseURI( uri );
    if err then
        return nil, err;
    -- scheme required
    elseif not req.url.scheme then
        return nil, 'invalid uri - scheme required';
    -- unknown scheme
    elseif not SCHEME_LUT[req.url.scheme] then
        return nil, 'invalid uri - unsupported scheme';
    -- hostname undefined
    elseif not req.url.hostname then
        return nil, 'invalid uri - hostname required';
    -- set to default port
    elseif not req.url.port or req.url.port == SCHEME_LUT[req.url.scheme] then
        req.url.port = SCHEME_LUT[req.url.scheme];
        wellknown = true;
    end

    -- hostname should encode by punycode
    if strfind( req.url.hostname, '%', 1, true ) then
        local host;

        host, err = decodeURI( req.url.hostname );
        if err then
            return nil, 'invalid uri - ' .. err;
        end

        req.url.hostname, err = encodeIdna( host );
        if err then
            return nil, err;
        end

        req.url.host = req.url.hostname .. ':' .. req.url.port;
    end

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
local function trace( ... )
    return new( 'TRACE', ... );
end


--- put
-- @param uri
-- @return req
-- @return err
local function put( ... )
    return new( 'PUT', ... );
end


--- post
-- @param uri
-- @return req
-- @return err
local function post( ... )
    return new( 'POST', ... );
end


--- options
-- @param uri
-- @return req
-- @return err
local function options( ... )
    return new( 'OPTIONS', ... );
end


--- head
-- @param uri
-- @return req
-- @return err
local function head( ... )
    return new( 'HEAD', ... );
end


--- get
-- @param uri
-- @return req
-- @return err
local function get( ... )
    return new( 'GET', ... );
end


--- delete
-- @param uri
-- @return req
-- @return err
local function delete( ... )
    return new( 'DELETE', ... );
end


--- connect
-- @param uri
-- @return req
-- @return err
local function connect( ... )
    return new( 'CONNECT', ... );
end


return {
    connect = connect,
    delete = delete,
    get = get,
    head = head,
    options = options,
    post = post,
    put = put,
    trace = trace,
};

