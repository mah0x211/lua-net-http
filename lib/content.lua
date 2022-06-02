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
local is_uint = require('isa').uint
--- constants
local DEFAULT_CHUNKSIZE = 1024 * 8

--- @class net.http.content
--- @field reader net.http.reader
--- @field len integer
--- @field is_chunked boolean
--- @field is_consumed boolean
local Content = {}

--- init
--- @param r net.http.reader
--- @param len integer
--- @return net.http.content content
function Content:init(r, len)
    if not is_uint(len) then
        error('len must be uint', 2)
    end

    self.reader = r
    self.len = len
    self.is_chunked = false
    self.is_consumed = false
    return self
end

--- size
--- @return integer? size
function Content:size()
    if not self.is_consumed then
        return self.len
    end
end

--- copy
--- @param w net.http.writer
--- @param chunksize? integer
--- @return integer len
--- @return string? err
function Content:copy(w, chunksize)
    if self.is_consumed then
        error('content is already consumed', 2)
    elseif chunksize == nil then
        chunksize = DEFAULT_CHUNKSIZE
    elseif not is_uint(chunksize) or chunksize == 0 then
        error('chunksize must be uint greater than 0', 2)
    end
    self.is_consumed = true

    local r = self.reader
    local len = self.len
    local size = 0
    while size < len do
        local n = len - size
        if n > chunksize then
            n = chunksize
        end

        local s, err = r:read(n)
        if not s or #s == 0 or err then
            return size, err
        end

        n, err = w:write(s)
        if n then
            size = size + n
        end

        if not n or err then
            return size, err
        end
    end

    return size
end

--- write
--- @param w net.http.writer
--- @param chunksize? integer
--- @return integer len
--- @return string? err
function Content:write(w, chunksize)
    return self:copy(w, chunksize)
end

return {
    new = require('metamodule').new(Content),
}
