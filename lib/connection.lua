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
local Parser = require('net.http.parser');
local Status = require('net.http.status');
local ParseRequest = Parser.request;
--- constants
local REQUEST_TIMEOUT = Status.REQUEST_TIMEOUT;
local INTERNAL_SERVER_ERROR = Status.INTERNAL_SERVER_ERROR;
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


--- recv
-- @return req
--  method
--  scheme (optional)
--  host (optional)
--  port (optional)
--  path
--  ver
--  header
-- @return rc
-- @return err
function Connection:recv()
    local sock = self.sock;
    local buf = self.buf;
    local req = {
        header = {}
    };

    while true do
        local cur = EAGAIN;

        -- parse buffered message
        if #buf > 0 then
            cur = ParseRequest( req, buf );
        end

        -- parsed
        if cur > 0 then
            -- remove bytes used
            self.buf = buf:sub( cur + 1 );
            return req;
        -- more bytes need
        elseif cur == EAGAIN then
            local str, err, timeout = sock:recv();

            -- 500 internal server error
            if err then
                return nil, INTERNAL_SERVER_ERROR, err;
            -- 408 request timedout
            elseif timeout then
                return nil, REQUEST_TIMEOUT;
            -- closed by peer
            elseif not str then
                return;
            end

            buf = buf .. str;
        -- invalid request
        else
            return nil, PERR2STATUS[cur];
        end
    end
end


--- sendHeader
-- @param msg
-- @return len
-- @return err
-- @return timeout
function Connection:sendHeader( msg )
    if not self.cork then
        self.cork = self.sock:tcpcork( true );
    end

    return self.sock:send( msg );
end


--- send
-- @param msg
-- @return len
-- @return err
-- @return timeout
function Connection:send( msg )
    if self.cork then
        self.cork = self.sock:tcpcork( false );
    end

    return self.sock:send( msg );
end


--- createConnection
-- @param sock
-- @return conn
local function new( sock )
    return setmetatable({
        sock = sock,
        buf = '',
        cork = false,
    },{
        __index = Connection
    });
end


return {
    new = new
};

