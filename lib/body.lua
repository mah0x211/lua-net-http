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
local strfind = string.find;
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
    local src = self.src;

    if len == nil or len >= #src then
        return src;
    end

    return strsub( src, 1, len );
end


--- readRemainingString
-- @param self
-- @param len
-- @return data
-- @return err
-- @return timeout
local function readRemainingString( self )
    if self.amount then
        local src = self.src;
        local amount = self.amount;

        self.src = nil;
        self.amount = nil;

        return strsub( src, 1, amount );
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
    return self.reader( self.src, len );
end


--- readRemainingStream
-- @param self
-- @param reader
-- @return data
-- @return err
-- @return timeout
local function readRemainingStream( self )
    if self.src then
        local data, err, timeout = self.reader( self.src, self.amount );

        if not data or err or timeout then
            self.src = nil;
            self.amount = nil;
        else
            local len = #data;
            local amount = self.amount - len;

            if amount > 0 then
                self.amount = amount;
            else
                self.src = nil;
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
-- @param src
-- @param amount
-- @return body
local function new( src, amount )
    local t = type( src );
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
            len = #src;
            if len < amount then
                amount = len;
            else
                len = amount;
            end
        else
            readfn = readString;
            len = #src;
        end
    elseif t == 'table' or t == 'userdata' then
        if amount then
            readfn = readRemainingStream;
        else
            readfn = readStream;
        end

        if type( src.read ) == 'function' then
            reader = src.read;
        elseif type( src.recv ) == 'function' then
            reader = src.recv;
        else
            readfn = nil;
        end
    end

    if not readfn then
        error( 'src must be string or implement read or recv method' );
    end

    return setmetatable({
        src = src,
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
-- @param src
-- @param chunks
-- @return body
local function newChunkedReader( src, chunks )
    if chunks ~= nil and type( chunks ) ~= 'string' then
        error( 'chunks must be string' );
    end

    return setmetatable({
        body = new( src ),
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
-- @param src
-- @param chunks
-- @param amount
-- @return body
local function newContentReader( src, chunks, amount )
    local body;

    if not isUInt( amount ) then
        error( 'amount must be unsigned integer' );
    elseif chunks == nil then
        body = new( src, amount );
    elseif type( chunks ) ~= 'string' then
        error( 'chunks must be string' );
    elseif ( amount - #chunks ) > 0 then
        body = new( src, amount - #chunks );
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


--- isChunkedTransferEncoding
-- @param hval
local function isChunkedTransferEncoding( hval )
    if hval ~= nil then
        if type( hval ) == 'table' then
            hval = concat( hval, ',' );
        end

        if strfind( hval, '%s*,*%s*chunked%s*,*' ) then
            return true;
        end
    end

    return false;
end


--- newReaderFromHeader
-- @param header
-- @param sock
-- @param chunks
-- @return newfn
local function newReaderFromHeader( header, sock, chunks )
    if type( header ) == 'table' then
        local clen = header['content-length'];

        -- chunked-transfer-encoding reader
        if isChunkedTransferEncoding( header['transfer-encoding'] ) then
            return newChunkedReader( sock, chunks );
        elseif clen then
            -- use last-value
            if type( clen ) == 'table' then
                clen = clen[#clen];
            end

            clen = tonumber( clen );
            -- fixed-length content reader
            if isUInt( clen ) then
                return newContentReader( sock, chunks, clen );
            end
        end

        return newNilReader();
    end

    error( 'header must not be nil' );
end


return {
    new = new,
    newContentReader = newContentReader,
    newChunkedReader = newChunkedReader,
    newNilReader = newNilReader,
    newReaderFromHeader = newReaderFromHeader,
};

