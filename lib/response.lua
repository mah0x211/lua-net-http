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
local Entity = require('net.http.entity');
local send = Entity.send;
local setmetatable = setmetatable;


--- class Response
local Response = {
    setBody = Entity.setBody,
    unsetBody = Entity.unsetBody
};


--- send
-- @param status
-- @return len
-- @return err
-- @return timeout
function Response:send( status )
    self.status = status;
    return send( self, self.conn );
end


--- line
-- @return line
function Response:line()
    return toline( self.status, self.ver );
end


--- new
-- @param conn
-- @return res
-- @return err
local function new( conn, ver )
    return setmetatable({
        conn = conn,
        ver = ver or 1.1,
        header = Header.new( 15, 15 ),
    },{
        __index = Response
    });
end


return {
    new = new
};

