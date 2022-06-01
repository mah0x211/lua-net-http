--
-- Copyright (C) 2022 Masatoshi Fukunaga
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
--- assign to local
local sub = string.sub
local new_reader = require('net.http.reader').new
local new_writer = require('net.http.writer').new
local new_request = require('net.http.message.request').new
local new_response = require('net.http.message.response').new
local new_content = require('net.http.content').new
local new_chunked_content = require('net.http.content.chunked').new
local parse = require('net.http.parse')
local parse_request = parse.request
local parse_response = parse.response
--- constants
-- need more bytes
local EAGAIN = parse.EAGAIN
--- parse error code to http status code
local DEFAULT_READSIZE = 4096

--- @class net.http.connection
--- @field sock net.stream.Socket
--- @field reader net.http.reader
--- @field writer net.http.writer
--- @field content net.http.content
local Connection = {}

--- init
--- @param sock net.stream.Socket
--- @return net.http.connection conn
--- @return string? err
function Connection:init(sock)
    self.sock = sock
    self.readsize = DEFAULT_READSIZE
    self.reader = new_reader(sock)
    self.writer = new_writer(sock)
    return self
end

--- close
--- @return boolean ok
--- @return string? err
function Connection:close()
    return self.sock:close()
end

--- write
--- @param data string
--- @return boolean ok
--- @return string? err
function Connection:write(data)
    return self.writer:write(data)
end

--- flush
--- @return integer? len
--- @return string? err
function Connection:flush()
    return self.writer:flush()
end

--- read_message
--- @param msg net.http.message
--- @param parser function
--- @return table msg
--- @return string? err
function Connection:read_message(msg, parser)
    local reader = self.reader
    local readsize = self.readsize
    local header = msg.header
    local str = ''

    msg.header = {}
    while true do
        local s, err = reader:read(readsize)
        if err or #s == 0 then
            return nil, err
        end
        str = str .. s

        -- TODO: add methods to sets the MAX_MSGLEN, MAX_HDRLEN and MAX_HDRNUM
        -- parse message
        -- parser(str, tbl, MAX_MSGLEN, MAX_HDRLEN, MAX_HDRNUM)
        local cur
        cur, err = parser(str, msg)
        -- parsed
        if cur then
            -- prepend extra data
            reader:prepend(sub(str, cur + 1))

            -- create header
            header.dict = msg.header
            msg.header = header

            -- 3.3.3.  Message Body Length
            -- https://datatracker.ietf.org/doc/html/rfc7230#section-3.3.3
            --
            -- If a message is received with both a Transfer-Encoding and a
            -- Content-Length header field, the Transfer-Encoding overrides the
            -- Content-Length.
            --
            -- Such a message might indicate an attempt to perform request
            -- smuggling (Section 9.5) or response splitting (Section 9.4) and
            -- ought to be handled as an error.
            --
            -- A sender MUST remove the received Content-Length field prior to
            -- forwarding such a message downstream.
            --
            local len = header:content_length()
            if header:is_transfer_encoding_chunked() then
                msg.content = new_chunked_content(reader)
            elseif len and len > 0 then
                msg.content = new_content(reader, len)
            end

            return msg

        elseif err.type ~= EAGAIN then
            -- parse error
            return nil, err
        end
        -- more bytes need
    end
end

--- read_request
--- @return net.http.message.request
--- @return string? err
function Connection:read_request()
    return self:read_message(new_request(), parse_request)
end

--- read_response
--- @return net.http.message.response
--- @return string? err
function Connection:read_response()
    return self:read_message(new_response(), parse_response)
end

return {
    new = require('metamodule').new(Connection),
}

