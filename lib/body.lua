--[[

  Copyright (C) 2017-2018 Masatoshi Teruya

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

  lib/body.lua
  lua-net-http
  Created by Masatoshi Teruya on 17/10/13.

--]]

--- assign to local
local isUInt = require('isa').uint;
local chunksize = require('rfcvalid.implc').chunksize;
local ParseHeader = require('net.http.parser').header;
local strerror = require('net.http.parser').strerror;
local type = type;
local error = error;
local setmetatable = setmetatable;
local strsub = string.sub;
local concat = table.concat;
--- constants
local EAGAIN = require('net.http.parser').EAGAIN;


--- length
-- @return len
local function length( self )
    return self.len;
end


--- readString
-- @param self
-- @param len
-- @return data
local function readString( self, len )
    local data = self.data;

    if len == nil or len >= #data then
        return data;
    end

    return strsub( data, 1, len );
end


--- readRemainingString
-- @param self
-- @param len
-- @return data
-- @return err
-- @return timeout
local function readRemainingString( self )
    if self.amount then
        local data = self.data;
        local amount = self.amount;

        self.data = nil;
        self.amount = nil;

        return strsub( data, 1, amount );
    end

    return nil;
end


--- readStream
-- @param self
-- @param len
-- @return data
-- @return err
-- @return timeout
local function readStream( self, len )
    return self.reader( self.data, len );
end


--- readRemainingStream
-- @param self
-- @param reader
-- @return data
-- @return err
-- @return timeout
local function readRemainingStream( self )
    if self.data then
        local data, err, timeout = self.reader( self.data, self.amount );

        if not data or err or timeout then
            self.data = nil;
            self.amount = nil;
        else
            local len = #data;
            local amount = self.amount - len;

            if amount > 0 then
                self.amount = amount;
            else
                self.data = nil;
                self.amount = nil;
                -- remove the excess
                if amount < 0 then
                    data = strsub( data, 1, len + amount )
                end
            end
        end

        return data, err, timeout;
    end

    return nil;
end


--- new
-- @param data
-- @param amount
-- @return body
local function new( data, amount )
    local t = type( data );
    local readfn, reader, len;

    if amount ~= nil then
        if not isUInt( amount ) then
            error( 'amount must be unsigned integer' );
        end
    end

    if t == 'string' then
        if amount then
            readfn = readRemainingString;
            -- change len to actual length
            len = #data;
            if len < amount then
                amount = len;
            else
                len = amount;
            end
        else
            readfn = readString;
            len = #data;
        end
    elseif t == 'table' or t == 'userdata' then
        if amount then
            readfn = readRemainingStream;
        else
            readfn = readStream;
        end

        if type( data.read ) == 'function' then
            reader = data.read;
        elseif type( data.recv ) == 'function' then
            reader = data.recv;
        else
            readfn = nil;
        end
    end

    if not readfn then
        error( 'data must be string or implement read or recv method' );
    end

    return setmetatable({
        data = data,
        reader = reader,
        len = len,
        amount = amount,
    },{
        __index = {
            read = readfn,
            length = length,
        }
    });
end


--- readChunked
-- @return body
-- @return trailer
-- @return err
-- @return timeout
local function readChunked( self )
    if self.body == nil then
        return nil;
    elseif type( self.body ) == 'string' then
        return self.body, self.trailer;
    else
        local body = self.body;
        local chunks = self.chunks or '';
        local arr = {};
        local idx = 0;

        self.body = nil;
        self.chunks = nil;

        --
        -- 4.1.  Chunked Transfer Coding
        -- https://tools.ietf.org/html/rfc7230#section-4.1
        --
        -- chunked-body   = *chunk
        --                  last-chunk
        --                  trailer-part
        --                  CRLF
        --
        -- chunk          = chunk-size [ chunk-ext ] CRLF
        --                  chunk-data CRLF
        -- chunk-size     = 1*HEXDIG
        -- last-chunk     = 1*("0") [ chunk-ext ] CRLF
        --
        -- chunk-data     = 1*OCTET ; a sequence of chunk-size octets
        --
        -- chunk-ext      = *( ";" chunk-ext-name [ "=" chunk-ext-val ] )
        -- chunk-ext-name = token
        -- chunk-ext-val  = token / quoted-string
        --
        -- trailer-part   = *( header-field CRLF )
        --
        while true do
            local consumed, clen = chunksize( chunks );

            -- got chunk size
            if consumed > 0 then
                -- got last-chunk
                if clen == 0 then
                    local trailer = {};

                    -- parse trailer-part
                    while true do
                        consumed = ParseHeader( chunks, trailer, consumed + 1 );
                        -- parsed
                        if consumed > 0 then
                            self.body = concat( arr );
                            self.trailer = trailer;
                            return self.body, trailer;
                        -- more bytes need
                        elseif consumed == EAGAIN then
                            local data, err, timeout = body:read();

                            if not data or err or timeout then
                                return nil, nil, err, timeout;
                            end

                            chunks = chunks .. data;
                        -- parse error
                        else
                            return nil, nil, strerror( consumed );
                        end
                    end
                end

                -- remove chunk-header
                chunks = strsub( chunks, consumed + 1 );
                -- need more bytes
                while #chunks < clen do
                    local data, err, timeout = body:read();

                    if not data or err or timeout then
                        return nil, nil, err, timeout;
                    end

                    chunks = chunks .. data;
                end

                -- save chunks into array
                idx = idx + 1;
                arr[idx] = strsub( chunks, 1, clen );
                chunks = strsub( chunks, clen + 3 );

            -- need more bytes
            elseif consumed == -1 then
                local data, err, timeout = body:read();

                if not data or err or timeout then
                    return nil, nil, err, timeout;
                end

                chunks = chunks .. data;
            -- invalid line
            else
                return nil, nil, 'invalid chunk-size';
            end
        end
    end
end


--- newChunkedReader
-- @param data
-- @param chunks
-- @return body
local function newChunkedReader( data, chunks )
    local body = new( data );

    if chunks ~= nil and type( chunks ) ~= 'string' then
        error( 'chunks must be string' );
    end

    return setmetatable({
        body = body,
        chunks = chunks,
    },{
        __index = {
            read = readChunked,
            length = length,
        }
    });
end


--- readContent
-- @return body
-- @return trailer
-- @return err
-- @return timeout
local function readContent( self )
    if self.body == nil then
        return nil;
    elseif type( self.body ) == 'string' then
        return self.body;
    else
        local body = self.body;
        local arr = { self.chunks or '' };
        local idx = 1;

        self.body = nil;
        self.chunks = nil;

        while true do
            local data, err, timeout = body:read();

            if err or timeout then
                return nil, nil, err, timeout;
            elseif not data then
                self.body = concat( arr );
                return self.body;
            end

            idx = idx + 1;
            arr[idx] = data;
        end
    end
end


--- newContentReader
-- @param data
-- @param chunks
-- @param amount
-- @return body
local function newContentReader( data, chunks, amount )
    local body;

    if not isUInt( amount ) then
        error( 'amount must be unsigned integer' );
    elseif chunks == nil then
        body = new( data, amount );
    elseif type( chunks ) ~= 'string' then
        error( 'chunks must be string' );
    elseif ( amount - #chunks ) > 0 then
        body = new( data, amount - #chunks );
    -- already received
    else
        body = chunks;
        chunks = nil;
    end

    return setmetatable({
        body = body,
        chunks = chunks,
        len = amount
    },{
        __index = {
            read = readContent,
            length = length,
        }
    });
end


--- readNil
-- @return nil
local function readNil()
    return nil;
end


--- newNilReader
-- @return body
local function newNilReader()
    return setmetatable({},{
        __index = {
            read = readNil,
            length = length,
        }
    });
end


return {
    new = new,
    newContentReader = newContentReader,
    newChunkedReader = newChunkedReader,
    newNilReader = newNilReader,
};

