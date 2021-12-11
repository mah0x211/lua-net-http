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
local InetServer = require('net.stream.inet').server
local UnixServer = require('net.stream.unix').server
local ParseRequest = require('net.http.parse').request
local new_header = require('net.http').header.new
local NewReaderFromHeader = require('net.http.body').newReaderFromHeader
local recvfrom = require('net.http.entity').recvfrom

--- class Peer
local Peer = require('halo').class.Peer

Peer.inherits {
    'net.stream.Socket',
}

--- recvRequest
-- @return req
-- @return err
-- @return timeout
function Peer:recvRequest()
    local header = new_header()
    local req = {
        header = header.dict,
    }
    local ok, excess, err, timeout = recvfrom(self, ParseRequest, req)

    if ok then
        req.header = header
        req.body = NewReaderFromHeader(req.header, self, excess)
        return req
    end

    self:close()

    return nil, err, timeout
end

Peer = Peer.exports

--- createConnection
-- please refer to https://github.com/mah0x211/lua-net#sock--sockcreateconnection-sock-tls-
local function createConnection(_, sock, tls)
    return Peer.new(sock, tls)
end

--- new
-- @param opts
-- @return server
-- @return err
local function new(opts)
    local server, err

    if opts.path then
        server, err = UnixServer.new(opts)
    else
        server, err = InetServer.new(opts)
    end

    if err then
        return nil, err
    end

    err = server:listen()
    if err then
        server:close()
        return nil, err
    end

    -- overwrite
    server.createConnection = createConnection

    return server
end

return {
    new = new,
}

