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
local chunksize = require('rfcvalid.implc').chunksize;
local InetClient = require('net.stream.inet').client;
local Parser = require('net.http.parser');
local ParseResponse = Parser.response;
local Status = require('net.http.status');
local setmetatable = setmetatable;
local concat = table.concat;
local strsub = string.sub;
--- constants
-- need more bytes
local EAGAIN = Parser.EAGAIN;
--- parse error code to http status code
local PERR2STATUS = {
    -- method not implemented
    EMETHOD = Status.NOT_IMPLEMENTED,
    -- invalid uri string
    EURIFMT = Status.BAD_REQUEST,
    -- uri-length too large
    EURILEN = Status.REQUEST_URI_TOO_LONG,
    -- version not support
    EVERSION = Status.HTTP_VERSION_NOT_SUPPORTED,
    -- header-length too large
    EHDRLEN = Status.REQUEST_HEADER_FIELDS_TOO_LARGE,
    -- too many headers
    EHDRNUM = Status.REQUEST_HEADER_FIELDS_TOO_LARGE,
    -- invalid header format
    EHDRFMT = Status.BAD_REQUEST,
    -- invalid header field-name
    EHDRNAME = Status.BAD_REQUEST,
    -- invalid header field-value
    EHDRVAL = Status.BAD_REQUEST
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
    local entity = {
        header = {}
    };

    while true do
        local cur = EAGAIN;

        -- parse buffered message
        if #buf > 0 then
            cur = parser( entity, buf );
        end

        -- parsed
        if cur > 0 then
            -- remove bytes used
            self.buf = strsub( buf, cur + 1 );
            return entity;
        -- more bytes need
        elseif cur == EAGAIN then
            local str, err, timeout = sock:recv();

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
-- @return err
-- @return timeout
function Connection:drain()
    if self.remains then
        local remains = self.remains;
        local buf = self.buf;
        local len = #buf;

        self.remains = nil;

        -- chunked encoded data
        if remains == -1 then
            local sock = self.sock;
            local arr = {};
            local idx = 0;

            while true do
                local consumed, clen = chunksize( buf );

                -- got chunk size
                if consumed > 0 then
                    -- done
                    if clen == 0 then
                        -- remove chunk-header and chunk data
                        self.buf = strsub( buf, consumed + 3 );
                        return concat( arr );
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
                            return nil, err, timeout;
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
                        return nil, err, timeout;
                    end

                    buf = buf .. data;
                -- invalid line
                else
                    return nil, 'invalid chunk-size';
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

            return data, err, timeout;
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

