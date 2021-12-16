--
-- Copyright (C) 2021 Masatoshi Fukunaga
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
local error = error
local tointeger = require('tointeger')
local string = require('stringex')
local lower = string.lower
local trim_space = string.trim_space
local split = string.split
local isa = require('isa')
local is_string = isa.string
local is_table = isa.table
local parse = require('net.http.parse')
local parse_strerror = parse.strerror
local parse_header_name = parse.header_name
local parse_header_value = parse.header_value
local parse_tchar = parse.tchar
local parse_parameters = parse.parameters
--- constants

--- @class net.http.Header
--- @field dict table<string, string[]>
local Header = {}

--- init
--- @return net.http.Header
function Header:init()
    self.dict = {}
    return self
end

--- has_content_type
--- @return boolean ok
--- @return string err
--- @return string mime
--- @return table<string, string> params
function Header:has_content_type()
    local kv = self.dict['content-type']
    if not kv then
        return false
    end
    -- use last value
    local mime = split(trim_space(kv.vals[#kv.vals]), '%s*;%s*', false, 1)

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
    local media = split(mime[1], '/', true, 1)
    if #media ~= 2 or parse_tchar(media[1]) ~= parse.OK or parse_tchar(media[2]) ~=
        parse.OK then
        return false, 'invalid media-type format'
    elseif #mime == 1 then
        return true, nil, mime[1]
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
    if parse_parameters(mime[2], parameters) ~= parse.OK then
        return false, 'invalid media-type parameters format'
    end

    return true, nil, mime[1], parameters
end

--- has_transfer_encoding_chunked
--- @return boolean ok
function Header:has_transfer_encoding_chunked()
    local kv = self.dict['transfer-encoding']
    if not kv then
        return false
    end

    for _, v in ipairs(kv.vals) do
        if v == 'chunked' then
            return true
        end
    end

    return false
end

--- has_content_length
--- @return boolean ok
--- @return integer len
function Header:has_content_length()
    local kv = self.dict['content-length']
    if not kv then
        return false
    end

    -- use last value
    local len = tointeger(kv.vals[#kv.vals])
    if len then
        return true, len
    end

    return false
end

-- luacheck: ignore 212
--- create_header_values
--- @param val string
--- @return string[] arr
--- @return string? err
function Header:_create_header_values(val)
    if not is_table(val) then
        val = {
            val,
        }
    end

    local arr = {}
    local errno
    for i, v in ipairs(val) do
        if not is_string(v) then
            v = tostring(v)
        end
        arr[i], errno = parse_header_value(trim_space(v))
        if errno then
            return nil, parse_strerror(errno)
        end
    end

    return arr
end

--- set
--- @param key string
--- @param val string
--- @return boolean ok
--- @return string? err
function Header:set(key, val)
    local dict = self.dict
    local k, errno = parse_header_name(key)

    if errno then
        return false, parse_strerror(errno)
    elseif val == nil then
        local kv = dict[k]
        -- remove key
        if kv then
            dict[k], dict[kv.ord] = nil, false
            return true
        end
        return false
    end

    local arr, err = self:_create_header_values(val)
    if not arr then
        return false, err
    end

    local ord = #dict + 1
    local kv = {
        ord = ord,
        key = k,
        vals = arr,
    }
    self.dict[ord] = kv
    self.dict[k] = kv

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
    local k, errno = parse_header_name(key)
    if errno then
        return false, parse_strerror(errno)
    elseif val == nil then
        return false, 'val must not be nil'
    end

    local arr, err = self:_create_header_values(val)
    if not arr then
        return false, err
    end

    local dict = self.dict
    local kv = dict[k]
    if not kv then
        local ord = #dict + 1
        kv = {
            ord = ord,
            key = k,
            vals = arr,
        }
        dict[ord] = kv
        dict[k] = kv
        return true
    end

    -- append to tail
    local vals = kv.vals
    local n = #vals
    for i, v in ipairs(arr) do
        vals[n + i] = v
    end

    return true
end

--- get
--- @param key string
--- @return string[]? vals
function Header:get(key)
    if not is_string(key) then
        error('key must be string', 2)
    end
    local kv = self.dict[lower(key)]
    return kv and kv.vals or nil
end

--- pairs
--- @return function next
function Header:pairs()
    local dict = self.dict
    local ord = 1
    local kv = dict[ord]
    local vi = 1

    return function()
        while kv ~= nil do
            -- luacheck: ignore 512
            while kv do
                local val = kv.vals[vi]
                if val then
                    vi = vi + 1
                    return kv.key, val
                end
                vi = 1
                break
            end
            ord = ord + 1
            kv = dict[ord]
        end
    end
end

Header = require('metamodule').new.Header(Header)

return {
    header = {
        new = Header,
    },
}

