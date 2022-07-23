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
local format = string.format
local lower = string.lower
local base64encode = require('base64mix').encode
local parse_url = require('url').parse
local isa = require('isa')
local is_string = isa.string
local new_errno = require('errno').new
local new_header = require('net.http.header').new
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
--- @field parsed_uri? table<string, any>
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
    self.parsed_uri = parsed_uri
    return true
end

--- get_parsed_uri
--- @param parse_query boolean
--- @return table parsed_uri
--- @return string err
function Request:get_parsed_uri(parse_query)
    if not self.parsed_uri then
        local ok, err = self:set_uri(self.uri, parse_query)
        if not ok then
            return nil, err
        end
    end
    return self.parsed_uri
end

--- write_firstline
--- @param w net.http.writer
--- @return integer n
--- @return string? err
function Request:write_firstline(w)
    if not self.parsed_uri then
        local ok, err = self:set_uri(self.uri)
        if not ok then
            return 0, err
        end
    end

    local parsed_uri = self.parsed_uri

    -- set Host header
    if parsed_uri.host then
        if not parsed_uri.port or not WELL_KNOWN_PORT[parsed_uri.port] then
            self.header:set('Host', parsed_uri.host)
        else
            self.header:set('Host', parsed_uri.hostname)
        end
    end

    -- set Authorization header
    if parsed_uri.userinfo then
        self.header:set('Authorization',
                        'Basic ' .. base64encode(parsed_uri.userinfo))
    end

    return w:write(concat({
        self.method,
        ' ',
        parsed_uri.path,
        parsed_uri.query or '',
        ' HTTP/',
        format('%.1f', self.version),
        '\r\n',
    }))
end

return {
    new = require('metamodule').new(Request, 'net.http.message'),
}
