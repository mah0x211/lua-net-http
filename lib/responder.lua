--
-- Copyright (C) 2024 Masatoshi Fukunaga
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
local find = string.find
local type = type
local pcall = pcall
local fopen = require('io.fopen')
local fatalf = require('error').fatalf
local errorf = require('error').format
local checkopt = require('lauxhlib.checkopt')
local is_file = require('lauxhlib.is').file
local encode_json = require('yyjson').encode
local new_mime = require('mime').new
local new_response = require('net.http.message.response').new
local code2message = require('net.http.status').code2message

--- @class mime
--- @field getmime fun(self, ext: string, as_pathname:boolean?): string?

--- @class net.http.responder
--- @field header net.http.header
--- @field private writer net.http.writer
--- @field private mime mime
--- @field private filter fun(code:integer, data: any, as_json:boolean?):(data:any, err:any)
--- @field private message net.http.message.response
local Responder = {}

--- init
--- @param writer net.http.writer
--- @param mime? mime
--- @param filter? fun(code:integer, data: any, as_json:boolean?):(data:any, err:any)
--- @return net.http.responder res
function Responder:init(writer, mime, filter)
    if writer == nil then
        fatalf('writer is required')
    elseif not pcall(function()
        -- check whether the writer has net.http.writer methods.
        assert(type(writer.write) == 'function')
        assert(type(writer.flush) == 'function')
    end) then
        fatalf('writer must have write() and flush() methods')
    elseif mime == nil then
        mime = new_mime()
    elseif not pcall(function()
        -- check whether the mime has a getmime() method.
        assert(type(mime.getmime) == 'function')
    end) then
        fatalf('mime must have a getmime() method')
    end
    -- check whether the filter is a callable or nil.
    checkopt.callable(filter, nil, 'filter')

    self.writer = writer
    self.mime = mime
    self.filter = filter
    self.message = new_response()
    self.header = self.message.header
    return self
end

--- write a data string to the writer.
--- if the error or timeout occurs, then returns false, err, timeout,
--- otherwise, returns a true
--- @param data string?
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Responder:write(data)
    local _, err, timeout = self.message:write(self.writer, data)
    if err then
        return false, errorf('failed to write()', err)
    elseif timeout then
        return false, nil, true
    end
    return true
end

--- write_file write a file content to the writer.
--- if the error or timeout occurs, then returns false, err, timeout,
--- otherwise, returns a true
--- @param file file*
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Responder:write_file(file)
    local _, err, timeout = self.message:write_file(self.writer, file)
    if err then
        return false, errorf('failed to write_file()', err)
    elseif timeout then
        return false, nil, true
    end
    return true
end

--- flush a calls writer:flush() method
--- if the error or timeout occurs, then returns flase, err, timeout,
--- otherwise, returns a true.
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Responder:flush()
    local _, err, timeout = self.writer:flush()
    if err then
        return false, errorf('failed to flush()', err)
    elseif timeout then
        return false, nil, true
    end
    return true
end

--- reply_file a write a file content to the writer.
--- if the Content-Type header is not set, then determine the content type from
--- the file extension and set it to the 'Content-Type' header. if the content type
--- is not found, then set it to 'application/octet-stream' as the default.
--- @param code integer
--- @param file string|file*
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Responder:reply_file(code, file)
    if self.message.header_sent then
        return false, errorf('cannot send a response message twice')
    end
    local filetype = type(file)
    assert(filetype == 'string' or is_file(file),
           'file must be a string or file*')

    -- set status code
    local ok, err = self.message:set_status(code)
    if not ok then
        return false, err
    elseif code == 204 then
        -- ignore file for 204 No Content response
        self.header:set('Content-Length', '0')
        return self:write('')
    end

    -- set 'Content-Type' header
    if not self.header:get('Content-Type') then
        local mime = 'application/octet-stream' -- default content type is binary
        if filetype == 'string' then
            -- determine the content type from the file extension and set it to
            -- the 'Content-Type' header. if the content type is not found, then set
            -- it to 'application/octet-stream' as the default.
            mime = self.mime:getmime(file, true)
            if mime == nil then
                mime = 'application/octet-stream'
            elseif type(mime) ~= 'string' then
                return false, errorf(
                           'mime:getmime() returns non-string value: %q',
                           type(mime))
            end
        end
        self.header:set('Content-Type', mime)
    end

    if filetype ~= 'string' then
        return self:write_file(file)
    end

    local f
    f, err = fopen(file)
    if not f then
        return false, errorf('failed to open a file', err)
    end
    local timeout
    ok, err, timeout = self:write_file(f)
    f:close()
    return ok, err, timeout
end

--- reply a response message.
--- @param code integer
--- @param data any
--- @param as_json boolean? if true, encode data as JSON
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Responder:reply(code, data, as_json)
    if self.message.header_sent then
        -- cannot send a status code twice
        return false, errorf('cannot send a response message twice')
    end

    -- set status code
    local ok, err = self.message:set_status(code)
    if not ok then
        return false, err
    elseif code == 204 then
        -- ignore data for 204 No Content response
        self.header:set('Content-Length', '0')
        return self:write('')
    end

    as_json = as_json == true
    if self.filter then
        data, err = self.filter(code, data, as_json)
        if err then
            return false, errorf('failed to filter()', err)
        end
    end

    if data == nil then
        -- set default data for non-204 response code
        data = code2message(code)
        self.header:set('Content-Type', 'text/plain')
    end

    if as_json then
        data = encode_json(data)
        if not data then
            return false, errorf('failed to encode data as JSON')
        end
        self.header:set('Content-Type', 'application/json')
    elseif not self.header:get('Content-Type') then
        self.header:set('Content-Type', 'application/octet-stream')
        if type(data) ~= 'string' then
            data = tostring(data)
        end
    end
    self.header:set('Content-Length', tostring(#data))

    return self:write(data)
end

--- continue
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:continue(data)
    return self:reply(100, data)
end

--- switching_protocols
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:switching_protocols(data)
    return self:reply(101, data)
end

--- processing
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:processing(data)
    return self:reply(102, data)
end

--- ok
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:ok(data)
    return self:reply(200, data)
end

--- created
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:created(data)
    return self:reply(201, data)
end

--- accepted
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:accepted(data)
    return self:reply(202, data)
end

--- non_authoritative_information
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:non_authoritative_information(data)
    return self:reply(203, data)
end

--- no_content
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:no_content(data)
    return self:reply(204, data)
end

--- reset_content
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:reset_content(data)
    return self:reply(205, data)
end

--- partial_content
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:partial_content(data)
    return self:reply(206, data)
end

--- multi_status
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:multi_status(data)
    return self:reply(207, data)
end

--- already_reported
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:already_reported(data)
    return self:reply(208, data)
end

--- im_used
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:im_used(data)
    return self:reply(226, data)
end

--- response300_304 response a 300 Multiple Choices or 304 Not Modified response.
--- @param self net.http.responder
--- @param code integer
--- @param uri string
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
local function response300_304(self, code, data, uri)
    if uri ~= nil then
        if type(uri) ~= 'string' or #uri == 0 or find(uri, '%s') then
            return false, errorf('uri must be non-empty string with no spaces')
        end
        -- set 'Content-Location' header for 304 Not Modified response, otherwise
        -- set 'Location' header.
        self.header:set(code == 304 and 'Content-Location' or 'Location', uri)
    end
    return self:reply(code, data)
end

--- multiple_choices
--- @param data any
--- @param uri string?
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:multiple_choices(data, uri)
    return response300_304(self, 300, data, uri)
end

--- not_modified
--- @param data any
--- @param uri string?
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:not_modified(data, uri)
    return response300_304(self, 304, data, uri)
end

--- response3xx
--- @param self net.http.responder
--- @param code integer
--- @param uri string
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
local function response3xx(self, code, uri, data)
    if type(uri) ~= 'string' or #uri == 0 or find(uri, '%s') then
        return false, errorf('uri must be non-empty string with no spaces')
    end
    self.header:set('Location', uri)
    return self:reply(code, data)
end

--- moved_permanently
--- @param uri string
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:moved_permanently(uri, data)
    return response3xx(self, 301, uri, data)
end

--- found
--- @param uri string
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:found(uri, data)
    return response3xx(self, 302, uri, data)
end

--- see_other
--- @param uri string
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:see_other(uri, data)
    return response3xx(self, 303, uri, data)
end

--- use_proxy
--- @param uri string
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:use_proxy(uri, data)
    return response3xx(self, 305, uri, data)
end

--- temporary_redirect
--- @param uri string
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:temporary_redirect(uri, data)
    return response3xx(self, 307, uri, data)
end

--- permanent_redirect
--- @param uri string
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:permanent_redirect(uri, data)
    return response3xx(self, 308, uri, data)
end

--- bad_request
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:bad_request(data)
    return self:reply(400, data)
end

--- unauthorized
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:unauthorized(data)
    return self:reply(401, data)
end

--- payment_required
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:payment_required(data)
    return self:reply(402, data)
end

--- forbidden
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:forbidden(data)
    return self:reply(403, data)
end

--- not_found
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:not_found(data)
    return self:reply(404, data)
end

--- method_not_allowed
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:method_not_allowed(data)
    return self:reply(405, data)
end

--- not_acceptable
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:not_acceptable(data)
    return self:reply(406, data)
end

--- proxy_authentication_required
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:proxy_authentication_required(data)
    return self:reply(407, data)
end

--- request_timeout
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:request_timeout(data)
    return self:reply(408, data)
end

--- conflict
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:conflict(data)
    return self:reply(409, data)
end

--- gone
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:gone(data)
    return self:reply(410, data)
end

--- length_required
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:length_required(data)
    return self:reply(411, data)
end

--- precondition_failed
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:precondition_failed(data)
    return self:reply(412, data)
end

--- payload_too_large
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:payload_too_large(data)
    return self:reply(413, data)
end

--- request_uri_too_long
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:request_uri_too_long(data)
    return self:reply(414, data)
end

--- unsupported_media_type
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:unsupported_media_type(data)
    return self:reply(415, data)
end

--- requested_range_not_satisfiable
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:requested_range_not_satisfiable(data)
    return self:reply(416, data)
end

--- expectation_failed
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:expectation_failed(data)
    return self:reply(417, data)
end

--- unprocessable_entity
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:unprocessable_entity(data)
    return self:reply(422, data)
end

--- locked
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:locked(data)
    return self:reply(423, data)
end

--- failed_dependency
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:failed_dependency(data)
    return self:reply(424, data)
end

--- upgrade_required
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:upgrade_required(data)
    return self:reply(426, data)
end

--- precondition_required
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:precondition_required(data)
    return self:reply(428, data)
end

--- too_many_requests
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:too_many_requests(data)
    return self:reply(429, data)
end

--- request_header_fields_too_large
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:request_header_fields_too_large(data)
    return self:reply(431, data)
end

--- unavailable_for_legal_reasons
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:unavailable_for_legal_reasons(data)
    return self:reply(451, data)
end

--- internal_server_error
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:internal_server_error(data)
    return self:reply(500, data)
end

--- not_implemented
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:not_implemented(data)
    return self:reply(501, data)
end

--- bad_gateway
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:bad_gateway(data)
    return self:reply(502, data)
end

--- service_unavailable
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:service_unavailable(data)
    return self:reply(503, data)
end

--- gateway_timeout
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:gateway_timeout(data)
    return self:reply(504, data)
end

--- http_version_not_supported
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:http_version_not_supported(data)
    return self:reply(505, data)
end

--- variant_also_negotiates
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:variant_also_negotiates(data)
    return self:reply(506, data)
end

--- insufficient_storage
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:insufficient_storage(data)
    return self:reply(507, data)
end

--- loop_detected
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:loop_detected(data)
    return self:reply(508, data)
end

--- not_extended
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:not_extended(data)
    return self:reply(510, data)
end

--- network_authentication_required
--- @param data any
--- @return boolean ok
--- @return any err
--- @return boolean timeout
function Responder:network_authentication_required(data)
    return self:reply(511, data)
end

return {
    new = require('metamodule').new(Responder),
}

