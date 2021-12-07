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
-- lib/request.lua
-- lua-net-http
-- Created by Masatoshi Teruya on 17/10/12.
--
--- assign to local
local InetClient = require('net.stream.inet').client
local TLSConfig = require("libtls.config")
local flatten = require('table.flatten')
local parseURI = require('url').parse
local encodeURI = require('url').encodeURI
-- local decodeURI = require('url').decodeURI
-- local encodeIdna = require('idna').encode
local ParseResponse = require('net.http.parse').response
local Header = require('net.http').header
local Body = require('net.http.body')
local Entity = require('net.http.entity')
local sendto = Entity.sendto
local recvfrom = Entity.recvfrom
local setmetatable = setmetatable
local type = type
local assert = assert
local tostring = tostring
local concat = table.concat
local strupper = string.upper
local strformat = string.format
--- constants
local DEFAULT_UA = 'lua-net-http'
local SCHEME_LUT = {
    http = '80',
    https = '443',
}
local METHOD_LUT = {
    CONNECT = 'CONNECT',
    DELETE = 'DELETE',
    GET = 'GET',
    HEAD = 'HEAD',
    OPTIONS = 'OPTIONS',
    POST = 'POST',
    PUT = 'PUT',
    TRACE = 'TRACE',
}

--- class Request
local Request = {
    setBody = Entity.setBody,
    unsetBody = Entity.unsetBody,
}

--- setStartLine
-- @return str
local function setStartLine(self)
    if not self.startLine then
        local arr = {
            self.method,
            ' ',
            self.url.scheme,
            '://',
            self.url.hostname,
        }
        local narr = 6

        -- set port-number
        if not self.withoutPort then
            arr[6] = ':'
            arr[7] = self.url.port
            narr = 8
        end

        -- set pathname
        arr[narr] = self.url.path
        narr = narr + 1

        -- append query-string
        if self.url.query then
            arr[narr] = self.url.query
            narr = narr + 1
        end

        -- set version
        arr[narr] = ' HTTP/1.1\r\n'
        self.startLine = concat(arr)
    end
end

--- sendto
-- @param sock
-- @return res
-- @return err
-- @return timeout
function Request:sendto(sock)
    setStartLine(self)
    local len, err, timeout = sendto(sock, self)

    if not len or err or timeout then
        return nil, err, timeout
    else
        local res = {
            header = {},
        }
        local ok, excess

        -- recv response
        ok, excess, err, timeout = recvfrom(sock, ParseResponse, res)
        if ok then
            res.body = Body.newReaderFromHeader(res.header, sock, excess)
            return res
        end

        return nil, err, timeout
    end
end

--- send
-- @param conndeadl
-- @return res
-- @return err
-- @return timeout
function Request:send(conndeadl)
    local sock, tlscfg, servername, err, timeout

    -- create tls config
    if self.url.scheme == 'https' then
        servername = self.url.hostname
        tlscfg, err = TLSConfig.new()
        if err then
            return nil, err
            -- set insecure mode
        elseif self.insecure == true then
            tlscfg:insecure_noverifycert()
            tlscfg:insecure_noverifyname()
        end
    end

    sock, err, timeout = InetClient.new({
        host = self.url.hostname,
        port = self.url.port,
        tlscfg = tlscfg,
        servername = servername,
    }, nil, conndeadl)

    if sock then
        local res

        res, err, timeout = self:sendto(sock)
        if res then
            return res
        end

        sock:close()

        return nil, err, timeout
    end

    return nil, err, timeout
end

--- line
-- @return str
function Request:line()
    setStartLine(self)
    return self.startLine
end

--- setMethod
-- @param method
-- @return err
function Request:setMethod(method)
    assert(type(method) == 'string', 'method must be string')
    method = METHOD_LUT[strupper(method)]
    if not method then
        return 'unsupported method'
    end

    self.method = method
    self.startLine = nil
end

--- encodeQueryParam
-- @param key
-- @param val
-- @return key
-- @return val
local function encodeQueryParam(key, val)
    local t = type(val)

    if t == 'string' then
        return encodeURI(key), encodeURI(val)
    elseif t == 'number' or t == 'boolean' then
        return encodeURI(key), encodeURI(tostring(val))
    end
end

--- setQueryAsArray
-- @param tbl
-- @param key
-- @param val
local function setQueryAsArray(tbl, key, val)
    if key then
        local idx = #tbl

        tbl[idx + 1] = '&'
        tbl[idx + 2] = key
        tbl[idx + 3] = '='
        tbl[idx + 4] = val
    end
end

--- setQuery
-- @param qry
function Request:setQuery(qry)
    if qry == nil then
        self.url.query = nil
    elseif type(qry) == 'table' then
        local arr = flatten(qry, 0, encodeQueryParam, setQueryAsArray)

        -- set new query-string
        if #arr > 1 then
            self.url.query = '?' .. concat(arr, nil, 2)
            -- remove query-string
        else
            self.url.query = nil
        end
    else
        error('qry must be table or nil')
    end

    self.startLine = nil
end

--- new
-- @param method
-- @param uri
-- @param insecure
-- @return res
-- @return err
local function new(method, uri, insecure)
    local header = Header.new()
    local req = Entity.init({
        header = header,
        insecure = insecure,
    })
    local wellknown, offset, err

    -- check method
    err = Request.setMethod(req, method)
    if err then
        return nil, err
    end

    -- parse url
    assert(type(uri) == 'string', 'uri must be string')
    uri = assert(encodeURI(uri))
    req.url, offset, err = parseURI(uri)
    if err then
        return nil, strformat(
                   'invalid uri - found illegal byte sequence %q at %d', err,
                   offset)
    elseif not req.url.scheme then
        -- scheme required
        return nil, 'invalid uri - scheme required'
    elseif not req.url.hostname then
        -- hostname required
        return nil, strformat('invalid uri - hostname required')
    elseif not SCHEME_LUT[req.url.scheme] then
        -- unknown scheme
        return nil, 'invalid uri - unsupported scheme'
    elseif not req.url.port then
        -- set to default port
        req.url.port = SCHEME_LUT[req.url.scheme]
        req.withoutPort = true
        wellknown = true
    elseif req.url.port == SCHEME_LUT[req.url.scheme] then
        wellknown = true
    end

    -- TODO: hostname should encode by punycode
    -- if strfind( req.url.hostname, '%', 1, true ) then
    --     local host

    --     host, err = decodeURI( req.url.hostname )
    --     if err then
    --         return nil, 'invalid uri - ' .. err
    --     end

    --     req.url.hostname, err = encodeIdna( host )
    --     if err then
    --         return nil, err
    --     end

    --     req.url.host = req.url.hostname .. ':' .. req.url.port
    -- end

    -- set host header
    -- without port-number
    if wellknown then
        header:set('Host', req.url.hostname)
        -- with port-number
    else
        header:set('Host', req.url.host)
    end

    -- set default path
    if not req.url.path then
        req.url.path = '/'
    end

    -- set default headers
    header:set('User-Agent', DEFAULT_UA)

    return setmetatable(req, {
        __index = Request,
    })
end

--- trace
-- @param uri
-- @param insecure
-- @return req
-- @return err
local function trace(...)
    return new('TRACE', ...)
end

--- put
-- @param uri
-- @param insecure
-- @return req
-- @return err
local function put(...)
    return new('PUT', ...)
end

--- post
-- @param uri
-- @param insecure
-- @return req
-- @return err
local function post(...)
    return new('POST', ...)
end

--- options
-- @param uri
-- @param insecure
-- @return req
-- @return err
local function options(...)
    return new('OPTIONS', ...)
end

--- head
-- @param uri
-- @param insecure
-- @return req
-- @return err
local function head(...)
    return new('HEAD', ...)
end

--- get
-- @param uri
-- @param insecure
-- @return req
-- @return err
local function get(...)
    return new('GET', ...)
end

--- delete
-- @param uri
-- @param insecure
-- @return req
-- @return err
local function delete(...)
    return new('DELETE', ...)
end

--- connect
-- @param uri
-- @param insecure
-- @return req
-- @return err
local function connect(...)
    return new('CONNECT', ...)
end

return {
    new = new,
    connect = connect,
    delete = delete,
    get = get,
    head = head,
    options = options,
    post = post,
    put = put,
    trace = trace,
}

