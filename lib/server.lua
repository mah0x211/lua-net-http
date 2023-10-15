--
-- Copyright (C) 2017-2022 Masatoshi Fukunaga
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
local find = string.find
local sub = string.sub
local fatalf = require('error').fatalf
local new_metamodule = require('metamodule').new
local isa = require('isa')
local is_string = isa.string
local is_table = isa.table
local new_inet_server = require('net.stream.inet').server.new
local new_unix_server = require('net.stream.unix').server.new
local new_connection = require('net.http.connection').new

-- base for net.http.server.* classes
local Server = {}

--- accepted
--- @param self net.stream.Socket
--- @param sock net.stream.Socket
--- @param ai llsocket.addrinfo
--- @return net.http.connection conn
--- @return any err
--- @return llsocket.addrinfo ai
function Server:accepted(sock, ai)
    return new_connection(sock), nil, ai
end

--- @class net.http.server.Inet : net.stream.inet.Server
local InetServer = new_metamodule.Inet(Server, 'net.stream.inet.Server')

--- @class net.http.server.InetTLS
local InetTSLServer = new_metamodule.InetTLS(Server,
                                             'net.tls.stream.inet.Server')

--- @class net.http.server.Unix : net.stream.unix.Server, net.http.server
local UnixServer = new_metamodule.Unix(Server, 'net.stream.unix.Server')

--- @class net.http.server.UnixTLS : net.tls.stream.unix.Server, net.http.server
local UnixTLSServer = new_metamodule.UnixTLS(Server,
                                             'net.tls.stream.unix.Server')

--- new
--- @param addr string
--- @param opts table?
--- @return net.stream.Server? server
--- @return any err
local function new(addr, opts)
    if not is_string(addr) then
        fatalf(2, 'addr must be string')
    elseif opts == nil then
        opts = {}
    elseif not is_table(opts) then
        fatalf(2, 'opts must be table')
    end

    -- unix server
    if find(addr, '^[./]') then
        local s, err = new_unix_server(addr, opts.tlscfg)
        if err then
            return nil, err
        elseif s.tls then
            return UnixTLSServer(s.sock, s.tls)
        end
        return UnixServer(s.sock)
    end

    -- inet server
    local delim = find(addr, ':')
    local host = addr
    local port
    if delim then
        host = sub(addr, 1, delim - 1)
        port = sub(addr, delim + 1)
    end

    local s, err = new_inet_server(host, port, opts)
    if err then
        return nil, err
    elseif s.tls then
        return InetTSLServer(s.sock, s.tls)
    end
    return InetServer(s.sock)
end

return {
    new = new,
}

