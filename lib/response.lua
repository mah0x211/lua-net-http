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
local strformat = string.format;
--- constants
local DEFAULT_SERVER = 'Server: lua-net-http\r\n';
local DEFAULT_READSIZ = 4096;
local CRLF = '\r\n';


--- class Response
local Response = {};


--- send
-- @param status
-- @return len
-- @return err
-- @return timeout
function Response:send( status )
    local vals = self.header.vals;
    local nval = #vals;
    local body = self.body;

    vals[1] = toline( status, self.ver );

    if body then
        vals[nval + 1] = CRLF;
        if not self.chunked then
            vals[nval + 2] = body:read();
        else
            --
            -- 4.1.  Chunked Transfer Coding
            -- https://tools.ietf.org/html/rfc7230#section-4.1
            --
            --  chunked-body   = *chunk
            --                   last-chunk
            --                   trailer-part
            --                   CRLF
            --
            --  chunk          = chunk-size [ chunk-ext ] CRLF
            --                   chunk-data CRLF
            --  chunk-size     = 1*HEXDIG
            --  last-chunk     = 1*("0") [ chunk-ext ] CRLF
            --
            --  chunk-data     = 1*OCTET ; a sequence of chunk-size octets
            --
            --  chunk-ext      = *( ";" chunk-ext-name [ "=" chunk-ext-val ] )
            --  chunk-ext-name = token
            --  chunk-ext-val  = token / quoted-string
            --
            --  trailer-part   = *( header-field CRLF )
            --
            local total = 0;
            local idx = nval + 2;
            local arr = {};

            repeat
                local data = body:read( DEFAULT_READSIZ );
                local bytes = data and #data or 0;
                local len, err, timeout;

                vals[idx] = strformat( '%x\r\n', bytes );
                if bytes > 0 then
                    vals[idx + 1] = data;
                    vals[idx + 2] = CRLF;
                else
                    vals[idx + 1] = CRLF;
                end

                len, err, timeout = self.conn:send( concat( vals ) );
                if not len or err or timeout then
                    return total, err, timeout;
                else
                    total = total + len;
                    idx = 1;
                    vals = arr;
                    vals[3] = nil;
                end
            until data == nil;

            return total;
        end

    end

    return self.conn:send( concat( vals ) );
end


--- setBody
-- @param data
-- @param len
function Response:setBody( data, len )
    local body = Body.new( data );

    if len ~= nil then
        if self.chunked then
            self.chunked = nil;
            self.header:del( 'Transfer-Encoding' );
        end
        self.header:set( 'Content-Length', len );
    -- chunked transfer coding
    else
        if self.body and not self.chunked then
            self.header:del( 'Content-Length' );
        end
        self.chunked = true;
        self.header:set( 'Transfer-Encoding', 'chunked' );
    end

    self.body = body;
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

    -- reserved for first-line
    dict[1] = false;
    dict[2] = 'server';
    dict.server = 2;

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

