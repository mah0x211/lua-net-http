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
local new_writer = require('bufio.writer').new

--- @class net.http.writer
--- @field private writer bufio.writer
local Writer = {}

--- init
--- @param sock net.Socket
--- @return net.http.writer writer
function Writer:init(sock)
    self.writer = new_writer(sock)
    return self
end

--- setbufsize sets the buffer size.
--- @param size integer
function Writer:setbufsize(size)
    self.writer:setbufsize(size)
end

--- flush a buffered data to the connection.
--- if the error or timeout occurs, then returns nil, err, timeout,
--- otherwise, returns the number of bytes flushed.
--- @return integer? n
--- @return any err
--- @return boolean? timeout
function Writer:flush()
    local n, err, timeout = self.writer:flush()
    if err or timeout then
        return nil, err, timeout
    end
    return n
end

--- write a data string to the connection.
--- if the error or timeout occurs, then returns nil, err, timeout,
--- otherwise, returns the number of bytes written.
--- @param data string
--- @return integer? n
--- @return any err
--- @return boolean? timeout
function Writer:write(data)
    local n, err, timeout = self.writer:write(data)
    if err or timeout then
        return nil, err, timeout
    end
    return n
end

--- writeout writes a data string to the connection.
--- if the error or timeout occurs, then returns nil, err, timeout,
--- otherwise, returns the number of bytes written.
--- @param data string
--- @return integer? n
--- @return any err
--- @return boolean? timeout
function Writer:writeout(data)
    local n, err, timeout = self.writer:writeout(data)
    if err or timeout then
        return nil, err, timeout
    end
    return n
end

return {
    new = require('metamodule').new(Writer, 'bufio.writer'),
}

