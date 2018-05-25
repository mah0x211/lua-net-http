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

  lib/body.lua
  lua-net-http
  Created by Masatoshi Teruya on 17/10/13.

--]]

--- assign to local
local isUInt = require('isa').uint;
local type = type;
local error = error;
local setmetatable = setmetatable;
local strsub = string.sub;


--- length
-- @return len
local function length( self )
    return self.len;
end


--- readString
-- @param self
-- @param len
-- @return data
local function readString( self, len )
    local data = self.data;

    if len == nil or len >= #data then
        return data;
    end

    return strsub( data, 1, len );
end


--- readRemainingString
-- @param self
-- @param len
-- @return data
-- @return err
-- @return timeout
local function readRemainingString( self )
    if self.amount then
        local data = self.data;
        local amount = self.amount;

        self.data = nil;
        self.amount = nil;

        return strsub( data, 1, amount );
    end

    return nil;
end


--- readStream
-- @param self
-- @param len
-- @return data
-- @return err
-- @return timeout
local function readStream( self, len )
    return self.reader( self.data, len );
end


--- readRemainingStream
-- @param self
-- @param reader
-- @return data
-- @return err
-- @return timeout
local function readRemainingStream( self )
    local data, err, timeout = self.reader( self.data, self.amount );

    if not data or err or timeout then
        self.data = nil;
        self.amount = nil;
    else
        local len = #data;
        local amount = self.amount - len;

        if amount > 0 then
            self.amount = amount;
        else
            self.data = nil;
            self.amount = nil;
            -- remove the excess
            if amount < 0 then
                data = strsub( data, 1, len + amount )
            end
        end
    end

    return data, err, timeout;
end


--- new
-- @param data
-- @param amount
-- @return body
local function new( data, amount )
    local t = type( data );
    local readfn, reader, len;

    if amount ~= nil then
        if not isUInt( amount ) then
            error( 'amount must be unsigned integer' );
        end
    end

    if t == 'string' then
        if amount then
            readfn = readRemainingString;
            -- change len to actual length
            len = #data;
            if len < amount then
                amount = len;
            else
                len = amount;
            end
        else
            readfn = readString;
            len = #data;
        end
    elseif t == 'table' or t == 'userdata' then
        if amount then
            readfn = readRemainingStream;
        else
            readfn = readStream;
        end

        if type( data.read ) == 'function' then
            reader = data.read;
        elseif type( data.recv ) == 'function' then
            reader = data.recv;
        end
    end

    if not reader then
        error( 'data must be string or implement read or recv method' );
    end

    return setmetatable({
        data = data,
        reader = reader,
        len = len,
        amount = amount,
    },{
        __index = {
            read = readfn,
            length = length,
        }
    });
end


return {
    new = new
};

