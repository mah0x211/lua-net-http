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

  http/server.lua
  lua-net-http
  Created by Masatoshi Teruya on 17/08/01.

--]]

--- assign to local
local InetServer = require('net.stream.inet').server;
local UnixServer = require('net.stream.unix').server;
local Connection = require('net.http.connection');


--- class Server
local Server = {};


--- close
-- @return err
function Server:close()
    local err = self.sock:close()

    self.sock = nil;
    return err;
end


--- accept
-- @return conn
-- @return err
function Server:accept()
    local sock, err = self.sock:accept();

    if err then
        return nil, err;
    end

    return Connection.new( sock );
end


--- new
-- @param opts:table: following fields are defined;
--  tlscfg
--  for unix domain socket
--      path
--  for inet server
--      host
--      port
--      reuseaddr
--      reuseport
--      nodelay
-- @return server
-- @return err
local function new( opts )
    local sock, err;

    if opts.path then
        sock, err = UnixServer.new( opts );
    else
        sock, err = InetServer.new({
            tlscfg = opts.tlscfg,
            host = opts.host,
            port = opts.port or opts.tlscfg and 443 or 80,
            reuseaddr = opts.reuseaddr,
            reuseport = opts.reuseport,
            nodelay = opts.nodelay == nil and true or opts.nodelay
        });
    end

    if err then
        return nil, err;
    end

    err = sock:listen();
    if err then
        sock:close();
        return nil, err;
    end

    return setmetatable({
        sock = sock
    }, {
        __index = Server
    });
end


return {
    new = new
};

