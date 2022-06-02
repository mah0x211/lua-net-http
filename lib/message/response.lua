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
local format = string.format
local new_errno = require('errno').new
local date_now = require('net.http.date').now
local new_header = require('net.http.header').new
local status = require('net.http.status')
local code2name = status.code2name
local toline = status.toline

--- @class net.http.message.response : net.http.message
--- @field status integer
--- @field reason? string
local Response = {}

--- init
--- @return net.http.message.response msg
function Response:init()
    self.header = new_header()
    self.status = 200
    self.version = 1.1
    return self
end

--- set_status
--- @param code integer
--- @return boolean ok
--- @return string err
function Response:set_status(code)
    if not code2name(code) then
        return false,
               new_errno('EINVAL', format('unsupported status code %d', code))
    end

    self.status = code
    return true
end

--- write_firstline
--- @param w net.http.writer
--- @return integer n
--- @return string? err
function Response:write_firstline(w)
    local line = toline(self.status, self.version, self.reason)

    -- set date header
    self.header:set('Date', date_now())

    return w:write(line)
end

return {
    new = require('metamodule').new(Response, 'net.http.message'),
}
