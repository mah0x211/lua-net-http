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
-- local isFieldName = require('rfcvalid.7230').isFieldName;
-- local isFieldValue = require('rfcvalid.7230').isFieldValue;
-- local isCookieValue = require('rfcvalid.6265').isCookieValue;
local concat = table.concat;
--- constants
local CRLF = '\r\n';


--- class Header
local Header = {};


--- del
-- @param key
-- @return ok
function Header:del( k )
    assert( type( k ) == 'string', 'key must be string' );
    local key = k:lower();
    local idx = self.vidx[key];

    if idx then
        local nval = self.nval;
        local vals = self.vals;
        local vidx = self.vidx;

        vidx[key] = nil;
        -- fill holes by last value
        if nval ~= idx then
            vals[idx] = vals[nval];
            vals[nval] = nil;

            vidx[idx] = vidx[nval];
            vidx[vidx[nval]] = idx;
            vidx[nval] = nil;
        -- remove value
        else
            vals[idx] = nil;
            vidx[idx] = nil;
        end

        -- update number of values
        nval = nval - 1;
        self.nval = nval;

        return true;
    end

    return false;
end


--- setval
-- @param vals
-- @param key
-- @param val
-- @param idx
-- @return ok
local function tostr( key, val )
    local t = type( val );

    if t == 'string' then
        return key .. ': ' .. val .. CRLF;
    -- set multiple value
    elseif t == 'table' then
        local arr = {};

        -- ignore empty array
        if #val > 0 then
            for i = 1, #val do
                if type( val[i] ) == 'string' then
                    arr[i] = key .. ': ' .. val[i];
                else
                    arr[i] = key .. ': ' .. tostring( val[i] );
                end
            end

            return concat( arr, CRLF ) .. CRLF;
        end
    else
        return key .. ': ' .. tostring( val ) .. CRLF;
    end
end


--- set
-- @param key
-- @param val
-- @return ok
function Header:set( k, val )
    assert( type( k ) == 'string', 'key must be string' );
    assert( val ~= nil, 'val must not be nil' );
    val = tostr( k, val );
    if val then
        local key = k:lower();
        local idx = self.vidx[key];

        -- update current value
        if idx then
            self.vals[idx] = val;
        else
            -- add new value
            local nval = self.nval + 1;

            self.vals[nval] = val;
            self.nval = nval;
            -- update index
            self.vidx[nval] = key;
            self.vidx[key] = nval;
        end

        return true;
    end

    return false;
end


--- getlines
-- @return lines
function Header:getlines()
    return concat( self.vals );
end


--- new
-- @return header
local function new()
    return setmetatable({
        vidx = {
            'server',
            'content-type',
            server = 1,
            ['content-type'] = 2,
        },
        vals = {
            'Server: lua-net-http',
            'Content-Type: text/plain'
        },
        nval = 2;
    }, {
        __index = Header,
    });
end


return {
    new = new
};

