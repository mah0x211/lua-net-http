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
local errorf = require('error').format
local fatalf = require('error').fatalf
local new_errno = require('errno').new
local instanceof = require('metamodule').instanceof
local new_header = require('net.http.header').new
local isa = require('isa')
local is_string = isa.string
local is_file = isa.file
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
--- @return any err
function Message:set_version(version)
    if not is_finite(version) then
        fatalf(2, 'version must be finite-number')
    elseif not VALID_VERSION[version] then
        return false,
               new_errno('EINVAL',
                         format('version must be the following number: %s',
                                LIST_VALID_VERSION))
    end

    self.version = version
    return true
end

--- write_firstline
--- @param w net.http.writer
--- @return integer? n
--- @return any err
--- @return boolean? timeout
function Message:write_firstline(w)
    return 0
end

--- write_header
--- @param self net.http.message
--- @param w net.http.writer
--- @param with_content? boolean
--- @return integer? n
--- @return any err
--- @return boolean? timeout
local function write_header(self, w, with_content)
    if self.header_sent then
        fatalf(2, 'header has already been sent')
    end
    self.header_sent = 0

    local header = self.header
    if with_content and not header:get('Content-Type') then
        -- add default Content-Type header
        header:set('Content-Type', 'application/octet-stream')
    end

    -- write first-line
    local n, err, timeout = self:write_firstline(w)
    if err then
        return nil, errorf('failed to write_header()', err)
    elseif not n then
        return nil, nil, timeout
    end

    -- write header
    local len = n
    n, err, timeout = self.header:write(w)
    if err then
        return nil, errorf('failed to write_header()', err)
    elseif not n then
        return nil, nil, timeout
    end
    self.header_sent = len + n

    return self.header_sent
end

--- write_header
--- @param w net.http.writer
--- @return integer? n
--- @return any err
function Message:write_header(w)
    return write_header(self, w)
end

--- write_content
--- @param w net.http.writer
--- @param content net.http.content
--- @return integer? n
--- @return any err
--- @return boolean? timeout
function Message:write_content(w, content)
    if not instanceof(content, 'net.http.content') then
        fatalf(2, 'content must be net.http.content')
    end

    local len = 0
    if not self.header_sent then
        local header = self.header

        if content.is_chunked then
            if not header:is_transfer_encoding_chunked() then
                header:set('Content-Length')
                header:set('Transfer-Encoding', 'chunked')
            end
        elseif not header:content_length() then
            local size = content:size()
            header:set('Content-Length', tostring(size))
            header:set('Transfer-Encoding')
        end

        -- write header
        local n, err, timeout = write_header(self, w, true)
        if err then
            return nil, errorf('failed to write_content()', err)
        elseif not n then
            return nil, nil, timeout
        end
        len = len + n
    end

    -- write content
    local n, err, timeout = content:write(w)
    if err then
        return nil, errorf('failed to write_content()', err)
    elseif not n then
        return nil, nil, timeout
    end
    return len + n
end

--- write_file
--- @param w net.http.writer
--- @param file file*
--- @return integer? n
--- @return any err
--- @return boolean? timeout
function Message:write_file(w, file)
    if not is_file(file) then
        fatalf(2, 'file must be file*')
    end

    local len = 0
    local offset = file:seek('cur')
    local size = file:seek('end') - offset
    file:seek('set', offset)

    if not self.header_sent then
        self.header:set('Content-Length', tostring(size))
        -- write header
        local n, err, timeout = write_header(self, w, true)
        if err then
            return nil, errorf('failed to write_file()', err)
        elseif not n then
            return nil, nil, timeout
        end
        len = len + n
    end

    -- write content
    local bufsize = 4096
    local s, err = file:read(bufsize)
    while s do
        local n, timeout
        n, err, timeout = w:write(s)
        if err then
            assert(file:seek('set', offset))
            return nil, errorf('failed to write_file()', err)
        elseif not n then
            assert(file:seek('set', offset))
            return nil, nil, timeout
        end
        len = len + n

        if n < bufsize then
            break
        end
        s, err = file:read(4096)
    end
    assert(file:seek('set', offset))

    if err then
        return nil, errorf('failed to write_file()', err)
    end

    return len
end

--- write data
--- @param w net.http.writer
--- @param data? string
--- @return integer? n
--- @return any err
--- @return boolean? timeout
function Message:write(w, data)
    local size = 0
    if data ~= nil then
        if not is_string(data) then
            fatalf(2, 'data must be string')
        end
        size = #data
    end

    local len = 0

    if not self.header_sent then
        self.header:set('Content-Length', tostring(size))
        -- write header
        local n, err, timeout = write_header(self, w, size > 0)
        if err then
            return nil, errorf('failed to write()', err)
        elseif not n then
            return nil, err, timeout
        end
        len = len + n
    end

    -- write no content
    if size == 0 then
        return len
    end

    local n, err, timeout = w:write(data)
    if err then
        return nil, errorf('failed to write()', err)
    elseif not n then
        return nil, nil, timeout
    end
    return len + n
end

return {
    new = require('metamodule').new(Message),
}

