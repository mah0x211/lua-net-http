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
local iovec = require('iovec')
local createtable = require('net.http.util.implc').createtable
local concat = table.concat
local type = type
local error = error
local tostring = tostring
local setmetatable = setmetatable
local strlower = string.lower
--- constants
local DEFAULT_NARR = 15
local DEFAULT_NREC = 15
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
        local ids = dict[key]

        if ids then
            local iov = self.iov

            for i = 1, #ids do
                local id = ids[i]
                local _, mid = iov:del(id)

                -- fill holes by last value
                if mid then
                    local mkey = dict[mid]
                    local mids = dict[mkey]

                    dict[id] = mkey
                    dict[mid] = nil
                    for j = 1, #mids do
                        if mids[j] == mid then
                            mids[j] = id
                        end
                    end
                    -- remove id
                else
                    dict[id] = nil
                end
            end

            dict[key] = nil

            return true
        end

        return false
    end

    error('key must be string')
end

--- checkval
-- @param val
-- @return val
-- @return len
local function checkval(val)
    if val ~= nil then
        if type(val) == 'table' then
            return val, #val
        end

        return {
            val,
        }, 1
    end
end

--- set
-- @param key
-- @param val
-- @param append
-- @return ok
-- @return err
function Header:set(k, v, append)
    if type(k) == 'string' then
        local val, len = checkval(v)

        if val then
            local iov = self.iov
            local dict = self.dict
            local key = strlower(k)
            local ids = dict[key]
            local head

            if not ids then
                head = 1
                ids = {}
            elseif append then
                head = #ids + 1
            else
                self:del(key)
                head = 1
                ids = {}
            end

            for i = 1, len do
                local hval = val[i]
                local id, err

                if type(hval) == 'string' then
                    id, err = iov:add(k .. DELIM .. hval .. CRLF)
                else
                    id, err = iov:add(k .. DELIM .. tostring(hval) .. CRLF)
                end

                if err then
                    for j = #ids, head, -1 do
                        dict[ids[j]] = nil
                        iov:del(ids[j])
                    end

                    return false, err
                elseif id then
                    dict[id] = key
                    ids[#ids + 1] = id
                end
            end

            if #ids > 0 then
                dict[key] = ids
            end

            return true
        end
        error('val must not be nil')
    else
        error('key must be string')
    end
end

--- get
-- @param key
-- @return val
function Header:get(k)
    if type(k) == 'string' then
        local ids = self.dict[strlower(k)]

        if ids then
            local arr = {}

            for i = 1, #ids do
                arr[i] = self.iov:get(ids[i])
            end

            return concat(arr)
        end

        return nil
    else
        error('key must be string')
    end
end

--- setStartLine
-- @param key
-- @return ok
function Header:setStartLine(line)
    if type(line) == 'string' then
        return self.iov:set(line, 0)
    else
        error('line must be string')
    end
end

--- new
-- @param narr
-- @param nrec
-- @return header
-- @return err
local function new(narr, nrec)
    local iov, err, _

    if nrec == nil then
        nrec = DEFAULT_NREC
    end

    iov, err = iovec.new(nrec)
    if err then
        return nil, err
    end

    -- add start-line
    _, err = iov:add('')
    if err then
        return nil, err
    end

    return setmetatable({
        iov = iov,
        dict = createtable(narr or DEFAULT_NARR, nrec or DEFAULT_NREC),
    }, {
        __index = Header,
    })
end

return {
    new = new,
}

