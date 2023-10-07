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
local fatalf = require('error').fatalf
local errorf = require('error').format
local is_uint = require('isa').uint
--- constants
local DEFAULT_CHUNKSIZE = 1024 * 8

--- @class net.http.content
--- @field reader net.http.reader
--- @field len integer
--- @field consumed integer
--- @field is_chunked boolean
--- @field is_consumed boolean
local Content = {}

--- init
--- @param r net.http.reader
--- @param len integer
--- @return net.http.content content
function Content:init(r, len)
    if not is_uint(len) then
        fatalf(2, 'len must be uint')
    end

    self.reader = r
    self.len = len
    self.consumed = 0
    self.is_chunked = false
    self.is_consumed = len == 0
    return self
end

--- size
--- @return integer? size
function Content:size()
    return self.len
end

--- read
--- @param self net.http.content
--- @param chunksize integer
--- @return string? s
--- @return any err
--- @return boolean? timeout
local function read(self, chunksize)
    if not self.is_consumed then
        local s, err, timeout = self.reader:read(
                                    chunksize < self.len and chunksize or
                                        self.len)
        if err then
            return nil, errorf('failed to read()', err)
        elseif not s then
            return nil, nil, timeout
        end
        self.len = self.len - #s
        self.is_consumed = self.len <= 0
        return s
    end
end

--- read
--- @param chunksize integer?
--- @return string? s
--- @return any err
--- @return boolean? timeout
function Content:read(chunksize)
    if chunksize == nil then
        chunksize = DEFAULT_CHUNKSIZE
    elseif not is_uint(chunksize) or chunksize == 0 then
        fatalf(2, 'chunksize must be uint greater than 0')
    end

    return read(self, chunksize)
end

--- readall
--- @return string? s
--- @return any err
function Content:readall()
    if not self.is_consumed then
        local s, err = self.reader:readfull(self.len)
        if err then
            return nil, errorf('failed to readall()', err)
        elseif s then
            self.len = self.len - #s
            self.is_consumed = self.len <= 0
            return s
        end
    end
end

--- copy
--- @param w net.http.writer
--- @param chunksize integer?
--- @return integer? len
--- @return any err
--- @return boolean? timeout
function Content:copy(w, chunksize)
    if chunksize == nil then
        chunksize = DEFAULT_CHUNKSIZE
    elseif not is_uint(chunksize) or chunksize == 0 then
        fatalf(2, 'chunksize must be uint greater than 0')
    end

    local ncopy = 0
    local s, err, timeout = read(self, chunksize)
    while s do
        local n
        n, err, timeout = w:write(s)
        if err then
            return nil, errorf('failed to copy()', err)
        elseif not n then
            return nil, nil, timeout
        end
        ncopy = ncopy + n
        s, err, timeout = read(self, chunksize)
    end

    if err then
        return nil, errorf('failed to copy()', err)
    elseif timeout then
        return nil, nil, timeout
    end
    return ncopy
end

--- dispose
--- @param chunksize integer?
--- @return integer? len
--- @return any err
--- @return boolean? timeout
function Content:dispose(chunksize)
    return self:copy({
        write = function(_, s)
            return #s
        end,
    }, chunksize)
end

--- write
--- @param w net.http.writer
--- @param chunksize? integer
--- @return integer? len
--- @return any err
--- @return boolean? timeout
function Content:write(w, chunksize)
    return self:copy(w, chunksize)
end

return {
    new = require('metamodule').new(Content),
}
