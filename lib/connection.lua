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
local errorf = require('error').format
local new_reader = require('net.http.reader').new
local new_writer = require('net.http.writer').new
local parse_request = require('net.http.message.request').parse
local parse_response = require('net.http.message.response').parse
--- constants
--- parse error code to http status code
local DEFAULT_READSIZE = 4096

--- @class net.http.connection
--- @field protected sock net.stream.Socket
--- @field protected reader net.http.reader
--- @field protected writer net.http.writer
--- @field content net.http.content
local Connection = {}

--- init
--- @param sock net.stream.Socket
--- @return net.http.connection conn
--- @return any err
function Connection:init(sock)
    self.sock = sock
    self.readsize = DEFAULT_READSIZE
    self.reader = new_reader(sock)
    self.writer = new_writer(sock)
    return self
end

--- close
--- @return boolean ok
--- @return any err
function Connection:close()
    return self.sock:close()
end

--- write a data string to the connection
--- @param data string
--- @return integer? n
--- @return any err
--- @return boolean? timeout
function Connection:write(data)
    local n, err, timeout = self.writer:write(data)
    if err then
        return nil, errorf('failed to write()', err)
    end
    return n, nil, timeout
end

--- flush a buffered data to the connection.
--- @return integer? n
--- @return any err
--- @return boolean? timeout
function Connection:flush()
    local n, err, timeout = self.writer:flush()
    if err then
        return nil, errorf('failed to flush()', err)
    end
    return n, nil, timeout
end

--- read_request
--- @return net.http.message.request? req
--- @return any err
--- @return boolean? timeout
function Connection:read_request()
    return parse_request(self.reader, self.readsize)
end

--- read_response
--- @return net.http.message.response? res
--- @return any err
--- @return boolean? timeout
function Connection:read_response()
    return parse_response(self.reader, self.readsize)
end

return {
    new = require('metamodule').new(Connection),
}

