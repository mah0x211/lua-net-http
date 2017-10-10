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
local Header = require('net.http.header');
local toline = require('net.http.status').toline;


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
                                 self.header:getlines() );
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
-- @return err
local function new( conn )
    return setmetatable({
        conn = conn,
        header = Header.new()
    },{
        __index = Response
    });
end


return {
    new = new
};

