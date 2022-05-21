--
-- Copyright (C) 2017-2018 Masatoshi Teruya
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
-- http/server.lua
-- lua-net-http
-- Created by Masatoshi Teruya on 17/08/01.
--
--- assign to local
local new_inet_server = require('net.stream.inet').server.new
local new_unix_server = require('net.stream.unix').server.new
local new_incoming = require('net.http.connection.incoming').new

--- accepted
--- @param self net.stream.Socket
--- @param sock net.stream.Socket
--- @param nonblock boolean
--- @param ai llsocket.addrinfo
--- @return net.http.connection.incoming conn
--- @return string? err
--- @return llsocket.addrinfo ai
local function accepted(_, sock, nonblock, ai)
    return new_incoming(sock), nil, ai
end

--- new
--- @param opts table?
--- @return net.stream.Server server
--- @return string? err
local function new(opts)
    local server, err

    if opts.path then
        server, err = new_unix_server(opts.path, opts.tlscfg)
    else
        server, err = new_inet_server(opts.host, opts.port, opts)
    end

    if err then
        return nil, err
    end

    local ok
    ok, err = server:listen()
    if not ok then
        server:close()
        return nil, err
    end

    -- overwrite accepted method
    server.accepted = accepted

    return server
end

return {
    new = new,
}

