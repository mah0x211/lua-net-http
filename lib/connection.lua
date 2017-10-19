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

  http/connection.lua
  lua-net-http
  Created by Masatoshi Teruya on 17/09/25.

--]]

--- assign to local
local tointeger = require('tointeger');
local chunksize = require('rfcvalid.implc').chunksize;
local InetClient = require('net.stream.inet').client;
local Parser = require('net.http.parser');
local ParseResponse = Parser.response;
local ParseHeader = Parser.header;
local ParseTransferEncoding = Parser.tencoding;
local Status = require('net.http.status');
local setmetatable = setmetatable;
local concat = table.concat;
local strsub = string.sub;
--- constants
-- need more bytes
local EAGAIN = Parser.EAGAIN;
local BAD_REQUEST = Status.BAD_REQUEST;
--- parse error code to http status code
local PERR2STATUS = {
    -- method not implemented
    EMETHOD = Status.NOT_IMPLEMENTED,
    -- invalid uri string
    EURIFMT = BAD_REQUEST,
    -- uri-length too large
    EURILEN = Status.REQUEST_URI_TOO_LONG,
    -- version not support
    EVERSION = Status.HTTP_VERSION_NOT_SUPPORTED,
    -- header-length too large
    EHDRLEN = Status.REQUEST_HEADER_FIELDS_TOO_LARGE,
    -- too many headers
    EHDRNUM = Status.REQUEST_HEADER_FIELDS_TOO_LARGE,
    -- invalid header format
    EHDRFMT = BAD_REQUEST,
    -- invalid header field-name
    EHDRNAME = BAD_REQUEST,
    -- invalid header field-value
    EHDRVAL = BAD_REQUEST
};


--- class Connection
local Connection = {};


--- close
-- @return err
function Connection:close()
    local err = self.sock:close();

    self.sock = nil;
    return err;
end


--- send
-- @param msg
-- @return len
-- @return err
-- @return timeout
function Connection:send( msg )
    return self.sock:send( msg );
end


--- recv
-- @return entity
--  request-entity
--      method
--      scheme (optional)
--      host (optional)
--      port (optional)
--      path
--      ver
--      header
--  response-entity
--      ver
--      status
--      reasons
--      header
-- @return err
-- @return timeout
-- @return perr
function Connection:recv()
    local sock = self.sock;
    local parser = self.parser;
    local buf = self.buf;
    local header = {};
    local entity = {
        header = header
    };
    -- drain body data
    local _, err, timeout = self:drain();

    if err or timeout then
        return nil, err, timeout;
    end

    while true do
        local cur = EAGAIN;

        -- parse buffered message
        if #buf > 0 then
            cur = parser( entity, buf );
        end

        -- parsed
        if cur > 0 then
            local clen = header['content-length'];
            local tenc = header['transfer-encoding'];

            if clen then
                -- multiple content-length headers does not allowed
                if type( clen ) == 'table' then
                    return nil, nil, nil, BAD_REQUEST;
                end

                clen = tointeger( clen );
                -- invalid length format
                if not clen then
                    return nil, nil, nil, BAD_REQUEST;
                end
            end

            -- parse transfer-encoding
            if tenc then
                tenc = ParseTransferEncoding( tenc );
                header['transfer-encoding'] = tenc;
                -- set remaining length
                if tenc.chunked then
                    self.remains = -1;
                    clen = nil;
                end
            end

            -- set remaining length
            if clen then
                self.remains = clen;
            end

            -- remove bytes used
            self.buf = strsub( buf, cur + 1 );
            return entity;
        -- more bytes need
        elseif cur == EAGAIN then
            local str;

            str, err, timeout = sock:recv();
            if not str or err or timeout then
                return nil, err, timeout;
            end

            buf = buf .. str;
        -- parse error
        else
            return nil, nil, nil, PERR2STATUS[cur];
        end
    end
end


--- readn
-- @param sock
-- @param n
-- @param buf
-- @param len
-- @return data
-- @return remains
-- @return err
-- @return timeout
local function readn( sock, n, buf, len )
    local arr = {
        buf
    };
    local idx = 1;

    while true do
        local data, err, timeout = sock:recv();

        -- fail
        if not data or err or timeout then
            return nil, '', err, timeout;
        end

        -- decrease
        n = n - len;
        len = #data;

        -- done
        if len >= n then
            arr[idx + 1] = strsub( data, 1, n );
            return concat( arr ), strsub( data, n + 3 );
        end

        idx = idx + 1;
        arr[idx] = data;
    end
end


--- drain
-- @return body
-- @return trailer
-- @return err
-- @return timeout
-- @return perr
function Connection:drain()
    if self.remains then
        local remains = self.remains;
        local buf = self.buf;
        local len = #buf;

        self.remains = nil;

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
        if remains == -1 then
            local sock = self.sock;
            local arr = {};
            local idx = 0;

            while true do
                local consumed, clen = chunksize( buf );

                -- got chunk size
                if consumed > 0 then
                    -- got last-chunk
                    if clen == 0 then
                        local trailer = {};

                        -- parse trailer-part
                        while true do
                            consumed = ParseHeader( trailer, buf, consumed + 1 );
                            -- parsed
                            if consumed > 0 then
                                -- remove bytes used
                                self.buf = strsub( buf, consumed + 1 );
                                return concat( arr ), trailer;
                            -- more bytes need
                            elseif consumed == EAGAIN then
                                local data, err, timeout = sock:recv();

                                if not data or err or timeout then
                                    return nil, nil, err, timeout;
                                end

                                buf = buf .. data;
                            -- parse error
                            else
                                return nil, nil, nil, PERR2STATUS[consumed];
                            end
                        end
                    end

                    -- remove chunk-header
                    buf = strsub( buf, consumed + 1 );
                    len = #buf;

                    -- slice
                    if len > clen then
                        idx = idx + 1;
                        arr[idx] = strsub( buf, 1, clen );
                        buf = strsub( buf, clen + 3 );
                    -- need more bytes
                    else
                        local data, err, timeout;

                        data, buf, err, timeout = readn( sock, clen, buf, len );
                        -- fail
                        if not data or err or timeout then
                            self.buf = buf;
                            return nil, nil, err, timeout;
                        end

                        idx = idx + 1;
                        arr[idx] = data;
                    end
                -- need more bytes
                elseif consumed == -1 then
                    local data, err, timeout = sock:recv();

                    -- fail
                    if not data or err or timeout then
                        self.buf = buf;
                        return nil, nil, err, timeout;
                    end

                    buf = buf .. data;
                -- invalid line
                else
                    return nil, nil, 'invalid chunk-size';
                end
            end
        -- recv already
        elseif len >= remains then
            self.buf = strsub( buf, remains + 1 );
            return strsub( buf, 1, remains );
        -- recv remains of data
        else
            local data, err, timeout;

            data, self.buf, err, timeout = readn( self.sock, remains, buf, len );

            return data, nil, err, timeout;
        end
    end
end


--- createConnection
-- @param sock
-- @return conn
local function new( sock, parser )
    return setmetatable({
        sock = sock,
        parser = parser,
        buf = ''
    },{
        __index = Connection
    });
end


--- open
-- @param host
-- @param port
-- @return conn
-- @return err
local function open( host, port )
    local sock, err = InetClient.new({
        host = host,
        port = port,
    });

    if err then
        return nil, err;
    end

    return new( sock, ParseResponse );
end



return {
    new = new,
    open = open
};

