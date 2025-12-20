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
local sub = string.sub
local pcall = pcall
local format = string.format
local tostring = tostring
local pairs = pairs
local ipairs = ipairs
local is_string = require('lauxhlib.is').str
local errorf = require('error').format
local fatalf = require('error').fatalf
local pread = require('io.pread')
local base64encode = require('base64mix').encode
local instanceof = require('metamodule').instanceof
local parse_url = require('url').parse
local path_normalize = require('realpath.normalize')
local new_errno = require('errno').new
local new_header = require('net.http.header').new
local new_form = require('net.http.form').new
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
--- @field method string method string (e.g., GET, POST, PUT, DELETE)
--- @field uri string raw uri
--- @field scheme string? scheme (e.g., http, https)
--- @field userinfo string? userinfo (e.g., user:password)
--- @field user string? username part of userinfo
--- @field password string? password part of userinfo
--- @field host string? host (e.g., www.example.com, www.example.com:8080)
--- @field hostname string? hostname part of host
--- @field port string? port part of host
--- @field rawpath string raw path (default: '/')
--- @field path string normalized path (default: '/')
--- @field query string? query string (e.g., ?foo=bar&foo=baz)
--- @field query_params table? parsed query string (e.g., { foo = { 'bar', 'baz' } })
--- @field fragment string? fragment (e.g., #foo)
--- @field parsed_uri string uri with a normalized path
local Request = {}

--- init
--- @return net.http.message.request msg
function Request:init()
    self.header = new_header()
    self.method = 'GET'
    self.version = '1.1'
    self.uri = '/'
    self.rawpath = '/'
    self.path = '/'
    return self
end

--- set_method
--- @param method string
--- @return boolean ok
function Request:set_method(method)
    local v = VALID_METHOD[method]
    if not is_string(method) then
        fatalf(2, 'method must be string')
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
--- @return any err
function Request:set_uri(uri, parse_query)
    if not is_string(uri) then
        fatalf(2, 'uri must be string')
    end

    local parsed_uri, pos, err = parse_url(uri, parse_query)
    if err then
        return false, new_errno('EINVAL', format(
                                    'invalid uri character %q found at %d', err,
                                    pos + 1), 'set_uri')
    end

    self.uri = uri
    -- set parsed values
    self.scheme = parsed_uri.scheme
    self.userinfo = parsed_uri.userinfo
    self.user = parsed_uri.user
    self.password = parsed_uri.password
    self.host = parsed_uri.host
    self.hostname = parsed_uri.hostname
    self.port = parsed_uri.port
    self.path = parsed_uri.path
    self.query = parsed_uri.query
    self.query_params = parsed_uri.query_params
    self.fragment = parsed_uri.fragment
    self.rawpath = parsed_uri.path or '/'
    -- path normalization
    local path
    path, err = path_normalize(self.rawpath, nil, false)
    if err then
        return false, errorf('failed to set_uri()', err)
    elseif sub(path, 1, 1) ~= '/' then
        -- add leading slash if not exists
        path = '/' .. path
    end
    self.path = path
    -- re-construct uri with normalized path
    self.parsed_uri = concat({
        self.scheme and self.scheme .. '://' or '',
        self.userinfo and self.userinfo .. '@' or '',
        self.host or '',
        self.path,
        self.query or '',
        self.fragment and '#' .. self.fragment or '',
    })

    return true
end

--- read_form
--- @param maxsize? integer
--- @param filetmpl? string
--- @return net.http.form? form
--- @return any err
function Request:read_form(maxsize, filetmpl)
    local form = self.form
    if form then
        return form
    elseif not self.content then
        self.form = new_form()
        return self.form
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
            self.form, err = decode_form(self.content, params.boundary, maxsize,
                                         filetmpl)
        end
    end

    if err then
        return nil, errorf('failed to read_form()', err)
    end
    return self.form
end

--- write_firstline
--- @param w net.http.writer
--- @return integer? n
--- @return any err
--- @return boolean? timeout
function Request:write_firstline(w)
    if self:is_firstline_sent() then
        fatalf(2, 'the first line has already been sent')
    end
    self.firstline_sent = 0

    if not self.host then
        local ok, err = self:set_uri(self.uri)
        if not ok then
            return nil, errorf('failed to write_firstline()', err)
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

    local n, err, timeout = w:write(concat({
        self.method,
        ' ',
        self.path,
        self.query or '',
        ' HTTP/',
        format('%.1f', self.version),
        '\r\n',
    }))
    if err then
        return nil, errorf('failed to write_firstline()', err)
    elseif not n then
        return nil, nil, timeout
    end
    self.firstline_sent = n
    return n
end

--- write_form
--- @param self net.http.message.request
--- @param w net.http.writer
--- @param form net.http.form
--- @param boundary string?
--- @param tmpfiles table
--- @return integer? n
--- @return any err
--- @return boolean? timeout
local function write_form(self, w, form, boundary, tmpfiles)
    local chunks = {}
    -- encode form
    local len, encerr = form:encode(boundary, {
        write = function(_, s)
            chunks[#chunks + 1] = s
            return #s
        end,
        writefile = function(_, file, len, offset, part)
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
    })
    if encerr then
        return nil, errorf('failed to write_form()', encerr)
    end

    local nsent = 0
    if not self:is_header_sent() then
        local header = self.header

        -- write header
        header:set('Content-Length', tostring(len))
        if boundary then
            header:set('Content-Type',
                       'multipart/form-data; boundary=' .. boundary)
        else
            header:set('Content-Type', 'application/x-www-form-urlencoded')
        end

        local n, err, timeout = self:write_header(w)
        if err then
            return nil, errorf('failed to write_form()', err)
        elseif not n then
            return nil, nil, timeout
        end
        nsent = nsent + n
    end

    -- write buffered chunks
    for _, v in ipairs(chunks) do
        if is_string(v) then
            local n, err, timeout = w:write(v)
            if err then
                return nil, errorf('failed to write_form()', err)
            elseif not n then
                return nil, nil, timeout
            end
            nsent = nsent + n
        else
            -- TODO: add support sendfile api
            local file = v.file
            local offset = v.offset
            local s, err = pread(file, 4096, offset)
            while s do
                local n, timeout
                n, err, timeout = w:write(s)
                if err then
                    return nil, errorf('failed to write_form()', err)
                elseif not n then
                    return nil, nil, timeout
                end
                nsent = nsent + n
                offset = offset + #s
                s, err = pread(file, 4096, offset)
            end

            if err then
                return nil, errorf('failed to write_form()', err)
            end
        end
    end

    return nsent
end

--- write_form
--- @param w net.http.writer
--- @param form net.http.form
--- @param boundary string?
--- @return integer n
--- @return any err
function Request:write_form(w, form, boundary)
    if not instanceof(form, 'net.http.form') then
        fatalf(2, 'form must be net.http.form')
    elseif boundary ~= nil and not is_valid_boundary(boundary) then
        fatalf(2, 'boundary must be valid-boundary string')
    end

    local tmpfiles = {}
    local ok, res, err = pcall(write_form, self, w, form, boundary, tmpfiles)
    for _, file in pairs(tmpfiles) do
        file:close()
    end
    assert(ok, res)
    return res, err
end

local http_parse_request = require('net.http.parse').request

--- parse_message parse a request message from a string
--- @param str string
--- @param msg net.http.message.request
--- @return integer? cur position of the next character to read
--- @return any err
local function parse_request(str, msg)
    local header = msg.header
    local cur, err = http_parse_request(str, msg)
    header.dict = msg.header
    msg.header = header
    return cur, err
end

local new_request = require('metamodule').new(Request, 'net.http.message')
local message_parse = require('net.http.message').parse
-- invalid message error
local EMSG = require('net.http.parse').EMSG

--- parse a request message from a reader
--- @param reader net.http.reader
--- @param readsize integer
--- @return net.http.message.request? req
--- @return any err
--- @return boolean? timeout
local function parse(reader, readsize)
    local req = new_request()
    local ok, err, timeout = message_parse(reader, readsize, parse_request, req)
    if ok then
        -- parse-uri
        ok, err = req:set_uri(req.uri, true)
        if not ok then
            -- invalid uri format
            return nil, EMSG:new('failed to request.parse()', err)
        end
        return req
    elseif err then
        return nil, errorf('failed to request.parse()', err)
    end
    return nil, nil, timeout
end

return {
    parse = parse,
    new = new_request,
}
