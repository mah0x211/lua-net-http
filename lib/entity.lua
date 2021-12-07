--
-- Copyright (C) 2017 Masatoshi Teruya
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
-- lib/entity.lua
-- lua-net-http
-- Created by Masatoshi Teruya on 17/10/16.
--
--- assign to local
local Body = require('net.http.body')
local concat = table.concat
local strsub = string.sub
local strformat = string.format
--- constants
local DEFAULT_READSIZ = 4096
local CRLF = '\r\n'
local EAGAIN = require('net.http.parse').EAGAIN
local strerror = require('net.http.parse').strerror

--- recvfrom
-- @param sock
-- @param parser
-- @param ctx
-- @param ...
-- @return ok
-- @return excess
-- @return err
-- @return timeout
-- @return perr
local function recvfrom(sock, parser, ctx, ...)
    local buf = ''

    while true do
        local cur = EAGAIN

        -- parse buffered message
        if #buf > 0 then
            cur = parser(buf, ctx, ...)
        end

        if cur > 0 then
            -- parsed
            return true, strsub(buf, cur + 1)
        elseif cur == EAGAIN then
            -- more bytes need
            local str, err, timeout
            for _ = 1, 10 do
                str, err, timeout = sock:recv()
                if not timeout then
                    break
                end
            end

            if not str or err or timeout then
                return false, nil, err, timeout
            end

            buf = buf .. str
        else
            -- parse error
            return false, nil, strerror(cur), nil, cur
        end
    end
end

--- sendto
-- @param sock
-- @param msg
-- @return len
-- @return err
-- @return timeout
local function sendto(sock, msg)
    local body = msg.entity.body
    local header = {
        msg.startLine or '',
    }

    for k, v in msg.header:pairs() do
        header[#header + 1] = k .. ': ' .. v .. CRLF
    end
    header[#header + 1] = CRLF

    -- send header
    local len, err, timeout = sock:send(concat(header))
    if not len or err or timeout or not body then
        return len, err, timeout
    elseif msg.entity.clen then
        local total = len

        len, err, timeout = sock:send(msg.entity.body:read())
        if len then
            return total + len, err, timeout
        end

        return total, err, timeout
    else
        --
        -- 4.1.  Chunked Transfer Coding
        -- https://tools.ietf.org/html/rfc7230#section-4.1
        --
        --  chunked-body   = *chunk
        --                   last-chunk
        --                   trailer-part
        --                   CRLF
        --
        --  chunk          = chunk-size [ chunk-ext ] CRLF
        --                   chunk-data CRLF
        --  chunk-size     = 1*HEXDIG
        --  last-chunk     = 1*("0") [ chunk-ext ] CRLF
        --
        --  chunk-data     = 1*OCTET ; a sequence of chunk-size octets
        --
        --  chunk-ext      = *( ";" chunk-ext-name [ "=" chunk-ext-val ] )
        --  chunk-ext-name = token
        --  chunk-ext-val  = token / quoted-string
        --
        --  trailer-part   = *( header-field CRLF )
        --
        local total = len

        repeat
            local data = body:read(DEFAULT_READSIZ)

            if data then
                len, err, timeout = sock:send(
                                        strformat('%x\r\n', #data) .. data ..
                                            CRLF)
            else
                len, err, timeout = sock:send('0\r\n\r\n')
            end

            if not len or err or timeout then
                return total, err, timeout
            end
            total = total + len

        until data == nil

        return total
    end
end

--- setBody
-- @param msg
-- @param data
-- @param ctype
local function setBody(msg, data, ctype)
    local body = Body.new(data)
    local clen = body:length()

    msg.entity.body = body
    -- set content-type header
    if ctype then
        msg.entity.ctype = true
        msg.header:set('Content-Type', ctype)
    end

    -- set content-length header
    if clen then
        msg.entity.clen = true
        msg.header:set('Content-Length', clen)
    else
        msg.header:add('Transfer-Encoding', 'chunked')
    end
end

--- unsetBody
-- @param msg
local function unsetBody(msg)
    if msg.entity.body then
        msg.entity.body = nil
        -- unset content-type header
        if msg.entity.ctype then
            msg.entity.ctype = nil
            msg.header:set('Content-Type')
        end

        -- unset content-length header
        if msg.entity.clen then
            msg.entity.clen = nil
            msg.header:set('Content-Length')
        else
            msg.header:set('Transfer-Encoding')
        end
    end
end

--- init
-- @param msg
-- @return msg
local function init(msg)
    msg.entity = {}
    return msg
end

return {
    init = init,
    sendto = sendto,
    recvfrom = recvfrom,
    setBody = setBody,
    unsetBody = unsetBody,
}

