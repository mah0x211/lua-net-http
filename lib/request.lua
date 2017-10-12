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
local isUInt16 = require('rfcvalid.util').isUInt16;
local type = type;
local assert = assert;
local tonumber = tonumber;
local strfind = string.find;
--- constants
local SCHEME_LUT = {
    http = 80,
    https = 443
};
local METHOD_LUT = {};
for k, v in pairs({
    connect = 'CONNECT',
    delete = 'DELETE',
    get = 'GET',
    head = 'HEAD',
    options = 'OPTIONS',
    post = 'POST',
    put = 'PUT',
    trace = 'TRACE',
}) do
    METHOD_LUT[k] = v;
    METHOD_LUT[k:upper()] = v;
end


--- class Request
local Request = {};


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
    local req, err;

    -- check arguments
    method = METHOD_LUT[method];
    assert( method, 'invalid method' );
    assert( type( uri ) == 'string', 'uri must be string' );

    -- parse url
    uri = assert( encodeURI( uri ) );
    req, err = parseURI( uri );
    if err then
        return nil, err;
    elseif req.scheme then
        -- unknown scheme
        if not SCHEME_LUT[req.scheme] then
            return nil, 'unsupported scheme';
        -- host undefined
        elseif not req.host then
            return nil, 'hostname undefined';
        elseif req.port then
            local port = tonumber( req.port );

            if not isUInt16( port ) then
                return nil, 'invalid port-range'
            end

            req.port = port;
        end

        -- hostname should encode by punycode
        if strfind( req.host, '%', 1, true ) then
            local host;

            host, err = decodeURI( req.host );
            if err then
                return nil, err;
            end

            req.host, err = encodeIdna( host );
            if err then
                return nil, err;
            end
        end
    end

    req.method = method;

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

