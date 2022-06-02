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
local tostring = tostring
local format = string.format
local new_errno = require('errno').new
local new_header = require('net.http.header').new
local isa = require('isa')
local is_string = isa.string
local is_finite = isa.finite
--- constants
local LIST_VALID_VERSION = '0.9 | 1.0 | 1.1'
local VALID_VERSION = {}
for _, v in ipairs({
    0.9,
    1.0,
    1.1,
}) do
    VALID_VERSION[v] = true
end

--- @class net.http.message
--- @field header net.http.header
--- @field version number
--- @field content? net.http.content
--- @field header_sent? integer
--- @field content_sent? integer
local Message = {}

--- init
--- @return net.http.message msg
function Message:init()
    self.header = new_header()
    return self
end

--- set_version
--- @param version number
--- @return boolean ok
--- @return string err
function Message:set_version(version)
    if not is_finite(version) then
        error('version must be finite-number', 2)
    elseif not VALID_VERSION[version] then
        return false,
               new_errno('EINVAL',
                         format('version must be the following number: %s',
                                LIST_VALID_VERSION))
    end

    self.version = version
    return true
end

--- set_content
--- @param content net.http.content
function Message:set_content(content)
    self.content = content
    self.content_sent = nil
end

--- write_firstline
--- @param w net.http.writer
--- @return integer n
--- @return string? err
function Message:write_firstline(w)
    return 0
end

--- write_header
--- @param self net.http.message
--- @param w net.http.writer
--- @param with_content boolean
--- @return integer n
--- @return string? err
local function write_header(self, w, with_content)
    if self.header_sent then
        error('header has already been sent', 2)
    end
    self.header_sent = 0

    local header = self.header
    if with_content and not header:get('Content-Type') then
        -- add default Content-Type header
        header:set('Content-Type', 'application/octet-stream')
    end

    -- write first-line
    local len, err = self:write_firstline(w)
    if not len or err then
        return nil, err
    end
    local n = len

    -- write header
    len, err = self.header:write(w)
    if not len or err then
        return nil, err
    end
    self.header_sent = n + len

    return self.header_sent
end

--- write_header
--- @param w net.http.writer
--- @return integer n
--- @return string? err
function Message:write_header(w)
    return write_header(self, w)
end

--- write_content
--- @param w net.http.writer
--- @return integer n
--- @return string? err
function Message:write_content(w)
    if not self.content then
        error('content does not exist', 2)
    elseif self.content_sent then
        error('content has already been sent', 2)
    end
    self.content_sent = 0

    local n = 0

    if not self.header_sent then
        local header = self.header

        if self.content.is_chunked then
            if not header:is_transfer_encoding_chunked() then
                header:set('Content-Length')
                header:set('Transfer-Encoding', 'chunked')
            end
        elseif not header:content_length() then
            local size = self.content:size()
            header:set('Content-Length', tostring(size))
            header:set('Transfer-Encoding')
        end

        -- write header
        local len, err = write_header(self, w, true)
        if not len or err then
            return nil, err
        end
        n = n + len
    end

    -- write content
    local len, err = self.content:write(w)
    if not len or err then
        return nil, err
    end
    self.content_sent = n + len

    return self.content_sent
end

--- write data
--- @param w net.http.writer
--- @param data string
--- @return integer n
--- @return string? err
function Message:write(w, data)
    local size = 0
    if data ~= nil then
        if not is_string(data) then
            error('data must be string', 2)
        end
        size = #data
    end

    local n = 0

    if not self.header_sent then
        local with_content = size > 0
        if with_content then
            self.header:set('Content-Length', tostring(size))
        end

        -- write header
        local len, err = write_header(self, w, with_content)
        if not len or err then
            return nil, err
        end
        n = n + len
    end

    if size == 0 then
        return n
    end

    local len, err = w:write(data)
    if not len or err then
        return nil, err
    end
    return n + len
end

return {
    new = require('metamodule').new(Message),
}

