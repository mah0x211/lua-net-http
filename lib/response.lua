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

  lib/response.lua
  lua-net-http
  Created by Masatoshi Teruya on 17/08/08.

--]]

--- assign to local
local isFieldName = require('rfcvalid.7230').isFieldName;
local isFieldValue = require('rfcvalid.7230').isFieldValue;
local isCookieValue = require('rfcvalid.6265').isCookieValue;
local toline = require('net.http.status').toline;
--- constants
local CRLF = '\r\n';
--- static variables
local HEADERS = setmetatable({}, {
    __mode = 'k'
});


--- class Header
local Header = {};


--- tostring
function Header:__tostring()
    local tbl = HEADERS[self];

    if tbl then
        local str = '';

        for k, v in pairs( tbl ) do
            str = str .. k .. ': ' .. v .. CRLF;
        end

        return str .. CRLF;
    end
end


--- index
function Header:__index( k )
    local tbl = HEADERS[self];

    if tbl then
        return tbl[k];
    end
end


--- newindex
function Header:__newindex( k, v )
    local tbl = HEADERS[self];

    if tbl then
        -- verify name
        k = isFieldName( k );
        if k then
            -- verify value
            if v ~= nil then
                if type( v ) ~= 'string' then
                    v = tostring( v );
                end

                -- verify value
                if k:lower() ~= 'set-cookie' then
                    v = isFieldValue( v );
                else
                    v = isCookieValue( v );
                end

                if not v then
                    error( 'field-value must be rfc valid value', 2 );
                end
            end

            tbl[k] = v;
        else
            error( 'field-name must be rfc valid name', 2 );
        end
    end
end


--- createHeader
-- @return header
local function createHeader()
    local self = setmetatable( {}, Header );

    -- create header table
    HEADERS[self] = {
        Server = 'lua-net-http',
        ['Content-Type'] = 'text/plain'
    };

    return self;
end


--- class Response
local Response = {};


--- sendHeader
-- @param status
-- @param ver
-- @return len
-- @return err
-- @return timeout
function Response:sendHeader( status, ver )
    return self.conn:sendHeader( toline( status, ver or 1 ) ..
                                 tostring( self.header ) );
end


--- send
-- @param msg
-- @return len
-- @return err
-- @return timeout
function Response:send( msg )
    return self.conn:send( msg );
end


--- new
-- @param conn
-- @return res
local function new( conn )
    return setmetatable({
        conn = conn,
        header = createHeader()
    },{
        __index = Response
    });
end


return {
    new = new
};

