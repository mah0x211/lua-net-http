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
local decode_form = require('form').decode
local is_valid_boundary = require('form').is_valid_boundary

--- @class net.http.form : form
local Form = {}

Form = require('metamodule').new(Form, 'form')

--- decode
--- @param chunk string|table|userdata
--- @param boundary? string
--- @param maxsize? integer
--- @param filetmpl? string
--- @param chunksize? integer
--- @return net.http.form? form
--- @return any err
local function decode(chunk, boundary, maxsize, filetmpl, chunksize)
    local form, err = decode_form(chunk, boundary, maxsize, filetmpl, chunksize)
    if err then
        return nil, err
    end

    local newform = Form()
    newform.data = form.data
    newform.boundary = boundary
    return newform
end

return {
    new = Form,
    decode = decode,
    is_valid_boundary = is_valid_boundary,
}

