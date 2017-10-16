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

  lib/response.lua
  lua-net-http
  Created by Masatoshi Teruya on 17/08/08.

--]]

--- assign to local
local Header = require('net.http.header');
local Body = require('net.http.body');
local toline = require('net.http.status').toline;
local concat = table.concat;
local setmetatable = setmetatable;
--- constants
local DEFAULT_SERVER = 'Server: lua-net-http\r\n';
local DEFAULT_CONTENT_TYPE = 'Content-Type: text/plain\r\n';
local CRLF = '\r\n';


--- class Response
local Response = {};


--- send
-- @param status
-- @param msg
-- @return len
-- @return err
-- @return timeout
function Response:send( status, msg )
    local vals = self.header.vals;
    local nval;

    self.header:set( 'Content-Length', #msg );
    nval = #vals;
    vals[1] = toline( status, self.ver );
    vals[nval + 1] = CRLF;
    vals[nval + 2] = msg;

    return self.conn:send( concat( vals ) );
end


--- setBody
-- @param data
-- @param len
function Response:setBody( data, len )
    self.body = Body.new( data );

    if len == nil then
        self.chunked = true;
        self.header:set('Transfer-Encoding', 'chunked' );
    else
        self.header:set('Content-Length', len );
        if self.chunked then
            self.chunked = nil;
            self.header:del('Transfer-Encoding' );
        end
    end
end


--- unsetBody
function Response:unsetBody()
    self.body = nil;
    self.header:del( self.chunked and 'Transfer-Encoding' or 'Content-Length' );
    self.chunked = nil;
end


--- new
-- @param conn
-- @return res
-- @return err
local function new( conn, ver )
    local header = Header.new( 15, 15 );
    local vals = header.vals;
    local dict = header.dict;

    -- reserved for first-line
    vals[1] = false;
    vals[2] = DEFAULT_SERVER;
    vals[3] = DEFAULT_CONTENT_TYPE;

    -- reserved for first-line
    dict[1] = false;
    dict[2] = 'server';
    dict[3] = 'content-type';
    dict.server = 2;
    dict['content-type'] = 3;

    return setmetatable({
        conn = conn,
        ver = ver or 1.1,
        header = Header.new()
    },{
        __index = Response
    });
end


return {
    new = new
};

