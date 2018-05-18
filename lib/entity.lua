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

  lib/entity.lua
  lua-net-http
  Created by Masatoshi Teruya on 17/10/16.

--]]

--- assign to local
local Body = require('net.http.body');
local concat = table.concat;
local strformat = string.format;
--- constants
local DEFAULT_READSIZ = 4096;
local CRLF = '\r\n';


--- send
-- @param self
-- @param conn
-- @return len
-- @return err
-- @return timeout
local function send( self, conn )
    local vals = self.header.vals;
    local body = self.body;
    local nval = #vals;

    vals[1] = self:line();
    vals[nval + 1] = CRLF;

    if body then
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

                len, err, timeout = conn:send( concat( vals ) );
                if not len or err or timeout then
                    return nil, err, timeout;
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

    return conn:send( concat( vals ) );
end


--- setBody
-- @param msg
-- @param data
-- @param ctype
local function setBody( msg, data, ctype )
    -- set content-type header
    if ctype then
        msg.ctype = true;
        msg.header:set( 'Content-Type', ctype );
    end

    msg.body = Body.new( data );
end


--- unsetBody
-- @param msg
local function unsetBody( msg )
    if msg.body then
        msg.body = nil;
        -- unset content-type header
        if msg.ctype then
            msg.ctype = nil;
            msg.header:del( 'Content-Type' );
        end
    end
end


return {
    send = send,
    setBody = setBody,
    unsetBody = unsetBody
};

