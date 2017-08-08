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

  lib/connection.lua
  lua-net-http
  Created by Masatoshi Teruya on 17/08/01.

--]]

--- assign to local
local ParseRequest = require('net.http.parser').request;
--- constants
local REQUEST_TIMEOUT = require('net.http.status').REQUEST_TIMEOUT;
local INTERNAL_SERVER_ERROR = require('net.http.status').INTERNAL_SERVER_ERROR;


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
    local hdr = {};
    local req = {
        header = hdr
    };

    while true do
        local cur = -2;
        local err;

        if #buf > 0 then
            cur, err = ParseRequest( req, buf );
        end

        -- parsed
        if cur > 0 then
            -- remove bytes used
            self.buf = buf:sub( cur );
            return req;
        -- more bytes need
        elseif cur == -2 then
            local str, perr, timeout = sock:recv();

            -- 500 internal server error
            if perr then
                return nil, INTERNAL_SERVER_ERROR, perr;
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
            return nil, -cur, err;
        end
    end
end


--- send
-- @param msg
-- @return len
-- @return err
-- @return timeout
function Connection:send( msg )
    return self.sock:send( msg );
end


--- new
-- @param sock
-- @return conn
local function new( sock )
    return setmetatable({
        sock = sock,
        buf = '',
    },{
        __index = Connection
    });
end


return {
    new = new
};

