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
local type = type;
local error = error;
local setmetatable = setmetatable;
local strsub = string.sub;


--- readstr
-- @param self
-- @param len
-- @return data
local function readstr( self, len )
    local data = self.data;

    if len == nil or len >= #data then
        return data;
    end

    return strsub( data, 1, len );
end


--- readstream
-- @param self
-- @param len
-- @return data
-- @return err
local function readstream( self, len )
    return self.data:read( len );
end


--- recvstream
-- @param self
-- @param len
-- @return data
-- @return err
local function recvstream( self, len )
    return self.data:recv( len );
end


--- length
-- @return len
local function length( self )
    if type( self.data ) == 'string' then
        return #self.data;
    end

    return nil;
end


--- new
-- @param data
-- @return body
local function new( data )
    local t = type( data );
    local readfn;

    if t == 'string' then
        readfn = readstr;
    elseif t == 'table' or t == 'userdata' then
        if type( data.read ) == 'function' then
            readfn = readstream;
        elseif type( data.recv ) == 'function' then
            readfn = recvstream;
        end
    end

    if not readfn then
        error( 'data must be string or implement read or recv method' );
    end

    return setmetatable({
        data = data
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

