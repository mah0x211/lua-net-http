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
local lower = string.lower
local format = string.format
local remove = table.remove
local pairs = pairs
local type = type
local errorf = require('error').format
local fatalf = require('error').fatalf
local tointeger = require('tointeger')
local capitalize = require('string.capitalize')
local trim = require('string.trim')
local split = require('string.split')
local is_boolean = require('lauxhlib.is').bool
local is_string = require('lauxhlib.is').str
local is_table = require('lauxhlib.is').table
local new_errno = require('errno').new
local parse = require('net.http.parse')
local parse_header_name = parse.header_name
local parse_header_value = parse.header_value
local parse_tchar = parse.tchar
local parse_parameters = parse.parameters

--- is_valid_key
--- @param key string
--- @return string? key
--- @return any err
local function is_valid_key(key)
    if not is_string(key) then
        return nil, new_errno('EINVAL',
                              format('string expected, got %s', type(key)))
    end
    key = trim(key)

    local ok, err = parse_header_name(key)
    if not ok then
        return nil, err
    end
    return key
end

--- is_valid_val
--- @param val string
--- @return string? val
--- @return any err
local function is_valid_val(val)
    if not is_string(val) then
        return nil, new_errno('EINVAL',
                              format('string expected, got %q', type(val)))
    end

    val = trim(val)
    if #val == 0 then
        return val
    end
    val = trim(val)

    local ok, err = parse_header_value(val)
    if not ok then
        return nil, err
    end
    return val
end

--- copy_values
--- @param vals string[]
--- @return string[]? copied
--- @return any err
local function copy_values(vals)
    local arr = {}

    for i = 1, #vals do
        local v, err = is_valid_val(vals[i])
        if not v then
            return nil, new_errno('EINVAL', format('val#%d invalid value', i),
                                  nil, err)
        end
        arr[i] = v
    end

    -- empty-table will be nil
    if #arr == 0 then
        return nil
    end

    return arr
end

--- @class net.http.header
--- @field dict table<integer|string, table>
local Header = {}

--- init
--- @param header? table
--- @return net.http.header
function Header:init(header)
    self.dict = {}

    -- set initial headers
    if header ~= nil then
        if not is_table(header) then
            fatalf(2, 'header must be table')
        end
        for k, v in pairs(header) do
            self:set(k, v)
        end
    end

    return self
end

--- size
function Header:size()
    return #self.dict
end

--- set
--- @param key string
--- @param val? string
--- @return boolean ok
function Header:set(key, val)
    local k, err = is_valid_key(key)

    if not k then
        fatalf(2, 'invalid key: %s', err)
    elseif val ~= nil then
        if is_table(val) then
            val, err = copy_values(val)
            if err then
                fatalf(2, 'invalid val: %s', err)
            end
        elseif is_string(val) then
            val, err = is_valid_val(val)
            if not val then
                fatalf(2, 'invalid val: %s', err)
            end
            val = {
                val,
            }
        else
            fatalf(2, 'val must be string or string[]')
        end
    end

    local dict = self.dict
    local lk = lower(k)
    -- remove key
    if val == nil then
        local item = dict[lk]
        if item then
            dict[lk] = nil
            for idx = item.idx + 1, #dict do
                dict[idx].idx = dict[idx].idx - 1
            end
            remove(dict, item.idx)
            return true
        end
        return false
    end

    local item = dict[lk]
    if item then
        -- update value
        item.val = val
    else
        -- set new item
        local idx = #dict + 1
        item = {
            idx = idx,
            key = capitalize(key),
            val = val,
        }
        dict[lk], dict[idx] = item, item
    end

    -- TODO: host header should be encoded by punycode
    -- if strfind( req.url.hostname, '%', 1, true ) then
    --     local host

    --     host, err = decodeURI( req.url.hostname )
    --     if err then
    --         return nil, 'invalid uri - ' .. err
    --     end

    --     req.url.hostname, err = encodeIdna( host )
    --     if err then
    --         return nil, err
    --     end

    --     req.url.host = req.url.hostname .. ':' .. req.url.port
    -- end

    return true
end

--- add
--- @param key string
--- @param val any
--- @return boolean ok
function Header:add(key, val)
    local k, err = is_valid_key(key)

    if err then
        fatalf(2, 'invalid key: %s', err)
    elseif is_string(val) then
        val, err = is_valid_val(val)
        if not val then
            fatalf(2, 'invalid val: %s', err)
        end
        val = {
            val,
        }
    elseif is_table(val) then
        val, err = copy_values(val)
        if err then
            fatalf(2, 'invalid val: %s', err)
        end
    else
        fatalf(2, 'val must be string or string[]')
    end

    local dict = self.dict
    local lk = lower(k)
    local item = dict[lk]
    if item then
        -- append values
        local arr = item.val
        for i = 1, #val do
            arr[#arr + 1] = val[i]
        end
    else
        -- set new item
        local idx = #dict + 1
        item = {
            idx = idx,
            key = capitalize(k),
            val = val,
        }
        dict[lk], dict[idx] = item, item
    end

    return true
end

--- get
--- @param key string
--- @param all boolean
--- @return string|string[]? val
--- @return string? key
function Header:get(key, all)
    if not is_string(key) then
        fatalf(2, 'key must be string')
    elseif all ~= nil and not is_boolean(all) then
        fatalf(2, 'all must be boolean')
    end

    local item = self.dict[lower(key)]
    if item then
        return all and item.val or item.val[#item.val], item.key
    end

    return nil
end

--- pairs
--- @return function next
function Header:pairs()
    local dict = self.dict
    local idx = 0
    local item, key, val, vidx

    return function(_, ...)
        repeat
            if val then
                local v
                vidx, v = next(val, vidx)
                if vidx then
                    return idx, key, v
                end
                val = nil
                vidx = nil
            end

            idx = idx + 1
            item = dict[idx]
            if item then
                key = item.key
                val = item.val
            end
        until item == nil
    end
end

--- write headers to writer
--- @param w net.http.writer
--- @return integer? len
--- @return any err
--- @return boolean? timeout
function Header:write(w)
    local total = 0

    for _, k, v in self:pairs() do
        local s = format('%s: %s\r\n', k, v)
        local n, err, timeout = w:write(s)
        if err then
            return nil, errorf('failed to write()', err)
        elseif not n then
            return nil, nil, timeout
        end
        total = total + n
    end

    local n, err, timeout = w:write('\r\n')
    if err then
        return nil, errorf('failed to write()', err)
    elseif not n then
        return nil, nil, timeout
    end

    return total + 2
end

--- get_content_type
--- @return string? mime
--- @return any err
--- @return table<string, string>? params
function Header:content_type()
    local val = self:get('content-type')
    if not val then
        return nil
    end

    -- use last value
    local mime = split(trim(val), '%s*;%s*', 1)

    -- 8.3.1. Media Type
    -- https://www.ietf.org/archive/id/draft-ietf-httpbis-semantics-16.html#name-media-type
    --
    -- HTTP uses media types [RFC2046] in the Content-Type (Section 8.3) and
    -- Accept (Section 12.5.1) header fields in order to provide open and extensible
    -- data typing and type negotiation. Media types define both a data format and
    -- various processing models: how to process that data in accordance with the
    -- message context.
    --
    --  media-type = type "/" subtype parameters
    --  type       = token
    --  subtype    = token
    --
    -- verify media-type
    local media = split(mime[1], '/', 1)
    if #media ~= 2 or not parse_tchar(media[1]) or not parse_tchar(media[2]) then
        return nil, new_errno('EILSEQ', 'invalid media-type format')
    elseif #mime == 1 then
        return mime[1]
    end

    -- 5.6.6. Parameters
    -- https://www.ietf.org/archive/id/draft-ietf-httpbis-semantics-16.html#parameter
    --
    -- Parameters are instances of name=value pairs; they are often used in
    -- field values as a common syntax for appending auxiliary information to an
    -- item. Each parameter is usually delimited by an immediately preceding
    -- semicolon.
    --
    --  parameters      = *( OWS ";" OWS [ parameter ] )
    --  parameter       = parameter-name "=" parameter-value
    --  parameter-name  = token
    --  parameter-value = ( token / quoted-string )
    --
    -- Parameter names are case-insensitive. Parameter values might or might
    -- not be case-sensitive, depending on the semantics of the parameter name.
    -- Examples of parameters and some equivalent forms can be seen in media
    -- types (Section 8.3.1) and the Accept header field (Section 12.5.1).
    --
    -- A parameter value that matches the token production can be transmitted
    -- either as a token or within a quoted-string. The quoted and unquoted
    -- values are equivalent.
    --
    -- Note: Parameters do not allow whitespace (not even "bad" whitespace)
    -- around the "=" character.
    --
    -- verify parameters
    local parameters = {}
    if not parse_parameters(mime[2], parameters) then
        return nil, new_errno('EILSEQ', 'invalid media-type parameters format')
    end

    return mime[1], nil, parameters
end

--- content_length
--- @return integer? len
function Header:content_length()
    local val = self:get('content-length')
    if val then
        return tointeger(val)
    end
end

--- is_transfer_encoding_chunked
--- @return boolean ok
function Header:is_transfer_encoding_chunked()
    local val = self:get('transfer-encoding', true)
    if val then
        for i = 1, #val do
            if val[i] == 'chunked' then
                return true
            end
        end
    end

    return false
end

return {
    new = require('metamodule').new(Header),
}

