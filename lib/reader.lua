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
local new_reader = require('bufio.reader').new

--- @class net.http.reader
--- @field protected reader bufio.reader
local Reader = {}

--- init
--- @param sock net.Socket
--- @return net.http.reader reader
function Reader:init(sock)
    self.reader = new_reader(sock)
    return self
end

--- setbufsize sets the buffer size.
--- @param size integer
function Reader:setbufsize(size)
    self.reader:setbufsize(size)
end

--- size returns the number of bytes of the unread portion of the buffer.
--- @return integer size
function Reader:size()
    return self.reader:size()
end

--- prepend prepends the data to the reader buffer.
--- @param data string
function Reader:prepend(data)
    self.reader:prepend(data)
end

--- read a data string from the connection.
--- if the error or timeout occurs, then returns nil, err, timeout
--- otherwise, returns data
--- @param size integer
--- @return string? data
--- @return any err
--- @return boolean? timeout
function Reader:read(size)
    local data, err, timeout = self.reader:read(size)
    if err then
        return nil, err
    elseif timeout then
        return nil, nil, true
    end
    return data
end

--- readfull reads data from the connection until the buffer is full.
--- if either the error or timeout occurs, then returns nil, err, timeout
--- otherwise, returns data
--- @param size integer
--- @return string? data
--- @return any err
--- @return boolean? timeout
function Reader:readfull(size)
    local data, err, timeout = self.reader:readfull(size)
    if err then
        return nil, err
    elseif timeout then
        return nil, nil, true
    end
    return data
end

return {
    new = require('metamodule').new(Reader, 'bufio.reader'),
}

