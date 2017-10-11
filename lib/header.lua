--[[

  Copyright (C) 2017 Masatoshi Teruya

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.

  lib/header.lua
  lua-net-http
  Created by Masatoshi Teruya on 17/10/08.

--]]

--- assign to local
local createtable = require('net.http.util.implc').createtable;
local concat = table.concat;
--- constants
local DEFAULT_SERVER = 'Server: lua-net-http\r\n';
local DEFAULT_CONTENT_TYPE = 'Content-Type: text/plain\r\n';
local CRLF = '\r\n';
local DELIM = ': ';


--- class Header
local Header = {};


--- del
-- @param key
-- @return ok
function Header:del( k )
    if type( k ) == 'string' then
        local key = k:lower();
        local idx = self.dict[key];

        if idx then
            local vals = self.vals;
            local dict = self.dict;
            local tail = #vals;

            dict[key] = nil;
            if idx == tail then
                vals[idx] = nil;
                dict[idx] = nil;
            -- fill holes by last value
            else
                dict[dict[tail]] = idx;
                vals[idx] = vals[tail];
                vals[tail] = nil;
            end

            return true;
        end

        return false;
    end

    error( 'key must be string' );
end


--- checkval
-- @param val
-- @param tbl2str
-- @return val
-- @return len
local function checkval( val, tbl2str )
    local t = type( val );

    if t == 'string' then
        return val;
    elseif t ~= 'table' or tbl2str == true then
        return tostring( val );
    else
        local len = #val;

        if len > 0 then
            if len == 1 then
                return checkval( val[1], true );
            end

            -- multiple value
            return val, len;
        end
    end
end


--- set
-- @param key
-- @param val
function Header:set( k, v )
    if type( k ) == 'string' then
        if v ~= nil then
            local val, len = checkval( v );

            if val then
                local vals = self.vals;
                local dict = self.dict;
                local key = k:lower();
                local idx = dict[key];

                -- add value
                if not idx then
                    idx = #vals + 1;
                    dict[idx] = key;
                    dict[key] = idx;
                end

                -- add value
                if not len then
                    vals[idx] = k .. DELIM .. val .. CRLF;
                else
                    local arr = {};

                    for i = 1, len do
                        arr[i] = k .. DELIM .. checkval( val[i], true ) .. CRLF;
                    end

                    vals[idx] = concat( arr );
                end
            end
        else
            error( 'val must not be nil' );
        end
    else
        error( 'key must be string' );
    end
end


--- new
-- @return header
local function new()
    local vals = createtable( 15 );
    local dict = createtable( 15, 15 );

    -- reserved for first-line
    vals[1] = '';
    vals[2] = DEFAULT_SERVER;
    vals[3] = DEFAULT_CONTENT_TYPE;

    -- reserved for first-line
    dict[1] = false
    dict[2] = 'server'
    dict[3] = 'content-type'
    dict.server = 2
    dict['content-type'] = 3

    return setmetatable({
        vals = vals,
        dict = dict,
    }, {
        __index = Header,
    });
end


return {
    new = new
};

