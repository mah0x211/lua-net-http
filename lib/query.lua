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
--- assign to local
local type = type
local tostring = tostring
local find = string.find
local concat = table.concat
local fatalf = require('error').fatalf
local isa = require('isa')
local is_int = isa.int
local is_string = isa.string
local is_table = isa.table
local flatten = require('table.flatten')
local encode_uri = require('url').encode_uri
-- local decode_uri = require('url').decode_uri
-- local encode_idna = require('idna').encode
--- constants

--- set_as_array
--- @param res table
--- @param key? string
--- @param val? string
local function set_as_array(res, key, val)
    if key then
        res[#res + 1] = key .. '=' .. val
    end
end

--- encode_param
--- @param key string
--- @param val any
--- @return string? key
--- @return string? val
local function encode_param(key, val)
    -- ignore parameters that begin with a numeric index
    if find(key, '^[a-zA-Z_]') then
        local t = type(val)
        if t == 'string' then
            return encode_uri(key), encode_uri(val)
        elseif t == 'number' or t == 'boolean' then
            return encode_uri(key), encode_uri(tostring(val))
        end
    end
    -- ignore arguments except string|number|boolean
end

--- key2str
--- @param prefix string
--- @param key any
--- @return string?
local function key2str(prefix, key)
    if is_string(key) then
        if prefix then
            return prefix .. '.' .. key
        end
        return key
    elseif is_int(key) then
        return prefix
    end
end

--- encode
--- @param query table
--- @return string query
local function encode(query)
    if not is_table(query) then
        fatalf(2, 'query must be table')
    end

    -- set new query-string
    local list = flatten(query, 0, encode_param, set_as_array, key2str)
    if #list > 1 then
        return '?' .. concat(list, '&')
    end

    return ''
end

return {
    encode = encode,
}
