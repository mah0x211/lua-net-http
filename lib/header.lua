--
-- Copyright (C) 2017 Masatoshi Teruya
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
-- lib/header.lua
-- lua-net-http
-- Created by Masatoshi Teruya on 17/10/08.
--
--- assign to local
local concat = table.concat
local type = type
local error = error
local tostring = tostring
local setmetatable = setmetatable
local strlower = string.lower
--- constants
local CRLF = '\r\n'
local DELIM = ': '

--- class Header
local Header = {}

--- del
-- @param key
-- @return ok
function Header:del(k)
    if type(k) == 'string' then
        local dict = self.dict
        local key = strlower(k)

        if dict[key] then
            dict[key] = nil
            return true
        end

        return false
    end

    error('key must be string')
end

--- set
-- @param key
-- @param val
-- @param append
-- @return ok
-- @return err
function Header:set(k, v, append)
    if type(k) ~= 'string' then
        error('key must be string')
    elseif v == nil then
        error('val must not be nil')
    elseif type(v) ~= 'table' then
        v = {
            v,
        }
    end

    local key = strlower(k)
    local dict = self.dict
    local vals = dict[key]

    if not vals or not append then
        vals = {}
        dict[key] = vals
    end

    for i = 1, #v do
        local hval = v[i]
        if type(hval) ~= 'string' then
            hval = tostring(hval)
        end
        vals[#vals + 1] = k .. DELIM .. hval .. CRLF
    end

    return true
end

--- get
-- @param key
-- @return val
function Header:get(k)
    if type(k) == 'string' then
        local vals = self.dict[strlower(k)]
        if vals then
            return concat(vals)
        end

        return nil
    else
        error('key must be string')
    end
end

--- get
-- @param key
-- @return val
function Header:getall()
    local arr = {}

    for _, vals in pairs(self.dict) do
        for _, v in ipairs(vals) do
            arr[#arr + 1] = v
        end
    end
    table.sort(arr)

    return arr
end

--- new
-- @param narr
-- @param nrec
-- @return header
-- @return err
local function new()
    return setmetatable({
        dict = {},
    }, {
        __index = Header,
    })
end

return {
    new = new,
}

