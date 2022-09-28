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
local concat = table.concat
local lower = string.lower
local gsub = string.gsub
local pcall = pcall
local format = string.format
local tostring = tostring
local base64encode = require('base64mix').encode
local instanceof = require('metamodule').instanceof
local parse_url = require('url').parse
local isa = require('isa')
local is_string = isa.string
local realpath = require('realpath')
local toerror = require('error').toerror
local new_errno = require('errno').new
local new_header = require('net.http.header').new
local decode_form = require('net.http.form').decode
local is_valid_boundary = require('net.http.form').is_valid_boundary
--- constants
local WELL_KNOWN_PORT = {
    ['80'] = true,
    ['443'] = true,
}

local LIST_VALID_METHOD = {
    'GET',
    'HEAD',
    'POST',
    'PUT',
    'DELETE',
    'OPTIONS',
    'TRACE',
    'CONNECT',
}
local VALID_METHOD = {}
for _, v in ipairs(LIST_VALID_METHOD) do
    VALID_METHOD[v] = v
    VALID_METHOD[lower(v)] = v
end
LIST_VALID_METHOD = concat(LIST_VALID_METHOD, ' | ')

--- @class net.http.message.request : net.http.message
--- @field method string
--- @field uri string
--- @field userinfo string
--- @field user string
--- @field password string
--- @field scheme string
--- @field host string
--- @field hostname string
--- @field port string
--- @field path string
--- @field rawpath string
--- @field query string
--- @field query_params table
--- @field fragment string
local Request = {}

--- init
--- @return net.http.message.request msg
function Request:init()
    self.header = new_header()
    self.method = 'GET'
    self.uri = '/'
    self.version = '1.1'
    return self
end

--- set_method
--- @param method string
--- @return boolean ok
function Request:set_method(method)
    local v = VALID_METHOD[method]
    if not is_string(method) then
        error('method must be string', 2)
    elseif not v then
        return false, new_errno('EINVAL', format(
                                    'method must be the following string: %s',
                                    LIST_VALID_METHOD))
    end

    self.method = v
    return true
end

--- set_uri
--- @param uri string
--- @param parse_query? boolean
--- @return boolean ok
--- @return string err
function Request:set_uri(uri, parse_query)
    if not is_string(uri) then
        error('uri must be string', 2)
    end

    local parsed_uri, pos, err = parse_url(uri, parse_query)
    if err then
        return false, new_errno('EINVAL', format(
                                    'invalid uri character %q found at %d', err,
                                    pos + 1))
    end

    self.uri = uri
    for k, v in pairs(parsed_uri) do
        self[k] = v
    end
    self.rawpath = self.path or '/'

    -- path normalization
    local path
    path, err = realpath(self.rawpath, nil, false)
    if err then
        return false, err
    end

    path = gsub(path, '^[^/]', function(c)
        if c == '.' then
            return '/'
        end
        return '/' .. c
    end)
    self.path = path

    return true
end

--- read_form
--- @param maxsize integer|nil
--- @param filetmpl string|nil
--- @return form|nil form
--- @return any err
function Request:read_form(maxsize, filetmpl)
    local form = self.form
    if form then
        return form
    end

    local mime, err, params = self.header:content_type()
    if mime then
        if mime == 'application/x-www-form-urlencoded' then
            self.form, err = decode_form(self.content)
        elseif mime == 'multipart/form-data' then
            if not params or not params.boundary then
                return nil, new_errno('EINVAL',
                                      'invalid Content-Type header: boundary not defined')
            end
            self.form, err = decode_form(self.content, nil, params.boundary,
                                         maxsize, filetmpl)
        end
    end

    if err then
        return nil, toerror(err)
    end
    return self.form
end

--- write_firstline
--- @param w net.http.writer
--- @return integer n
--- @return string? err
function Request:write_firstline(w)
    if not self.host then
        local ok, err = self:set_uri(self.uri)
        if not ok then
            return 0, err
        end
    end

    -- set Host header
    if self.host then
        if not self.port or not WELL_KNOWN_PORT[self.port] then
            self.header:set('Host', self.host)
        else
            self.header:set('Host', self.hostname)
        end
    end

    -- set Authorization header
    if self.userinfo then
        self.header:set('Authorization', 'Basic ' .. base64encode(self.userinfo))
    end

    return w:write(concat({
        self.method,
        ' ',
        self.path,
        self.query or '',
        ' HTTP/',
        format('%.1f', self.version),
        '\r\n',
    }))
end

--- write_form
--- @param self net.http.message.request
--- @param w net.http.writer
--- @param form net.http.form
--- @param boundary string|nil
--- @param tmpfiles table
--- @return integer n
--- @return any err
local function write_form(self, w, form, boundary, tmpfiles)
    local n = 0
    local chunks = {}
    -- encode form
    local len, err = form:encode({
        write = function(_, s)
            chunks[#chunks + 1] = s
            return #s
        end,
        writefile = function(_, file, len, offset, part)
            local ok, err = file:seek('set', offset)
            if not ok then
                return nil, err
            end
            chunks[#chunks + 1] = {
                file = file,
                len = len,
                offset = offset,
                name = part.name,
            }
            if part.is_tmpfile then
                tmpfiles[#tmpfiles + 1] = file
            end
            return len - offset
        end,
    }, boundary)
    if err then
        return nil, format('failed to encode form: %s', tostring(err))
    end

    if not self.header_sent then
        local header = self.header

        -- write header
        header:set('Content-Length', tostring(len))
        if boundary then
            header:set('Content-Type',
                       'multipart/form-data; boundary=' .. boundary)
        else
            header:set('Content-Type', 'application/x-www-form-urlencoded')
        end

        len, err = self:write_header(w)
        if err then
            return nil, format('failed to write header: %s', tostring(err))
        end
        n = n + len
    end

    -- write buffered chunks
    for _, v in ipairs(chunks) do
        if is_string(v) then
            len, err = w:write(v)
            if err then
                return nil, format('failed to write content: %s', tostring(err))
            end
            n = n + len
        else
            -- TODO: add support sendfile api
            local file = v.file
            local s
            s, err = file:read(4096)
            while len do
                len, err = w:write(s)
                if err then
                    return nil, format('failed to write content of %q: %s',
                                       v.name, tostring(err))
                end
                n = n + len
                len, err = file:read(4096)
            end
            if err then
                return nil, format('failed to read content of %q: %s', v.name,
                                   tostring(err))
            end
        end
    end

    return n
end

--- write_form
--- @param w net.http.writer
--- @param form net.http.form
--- @param boundary string|nil
--- @return integer n
--- @return any err
function Request:write_form(w, form, boundary)
    if not instanceof(form, 'net.http.form') then
        error('form must be net.http.form', 2)
    elseif boundary ~= nil and not is_valid_boundary(boundary) then
        error('boundary must be valid-boundary string', 2)
    end

    local tmpfiles = {}
    local ok, res, err = pcall(write_form, self, w, form, boundary, tmpfiles)
    for _, file in pairs(tmpfiles) do
        file:close()
    end
    assert(ok, res)
    return res, err
end

return {
    new = require('metamodule').new(Request, 'net.http.message'),
}
