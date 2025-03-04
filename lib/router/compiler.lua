--
-- Copyright (C) 2025 Masatoshi Fukunaga
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
-- modules
local pcall = pcall
local type = type
local errorf = require('error').format
local loadfile = require('loadchunk').file

--- compiler compiles the specified pathname and returns the method table.
--- @param pathname string
--- @param fenv table?
--- @return table<string, function>? methods
--- @return any err
local function compiler(pathname, fenv)
    if type(fenv) ~= 'table' then
        error('fenv must be table', 2)
    end

    -- set the handler method registrar
    local fn, err = loadfile(pathname, fenv)
    if err then
        return nil, errorf('failed to loadfile()', err)
    end

    local ok, res = pcall(fn)
    if not ok then
        return nil, errorf('failed to pre-process()', res)
    end
    return res
end

return compiler
