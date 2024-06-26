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
--- assign to local
local is_string = require('lauxhlib.is').str
local is_table = require('lauxhlib.is').table
local is_file = require('lauxhlib.is').file
local fatalf = require('error').fatalf
local errorf = require('error').format
local new_errno = require('errno').new
local new_inet_client = require('net.stream.inet').client.new
local new_unix_client = require('net.stream.unix').client.new
local new_connection = require('net.http.connection').new
local encode_query = require('net.http.query').encode
local new_header = require('net.http.header').new
local new_request = require('net.http.message.request').new
local instanceof = require('metamodule').instanceof
--- constants
local DEFAULT_UA = 'lua-net-http'
local WELL_KNOWN_PORT = {
    http = '80',
    https = '443',
}

--- fetch
--- @param uri string
--- @param opts? table<string, any>
--- @return net.http.message.response? res
--- @return any err
--- @return boolean? timeout
local function fetch(uri, opts)
    if not is_string(uri) then
        fatalf(2, 'uri must be string')
    elseif opts == nil then
        opts = {}
    elseif not is_table(opts) then
        fatalf(2, 'opts must be table')
    end
    --[[@cast opts table]]

    local req = new_request()

    -- set header
    if opts.header then
        if instanceof(opts.header, 'net.http.header') then
            req.header = opts.header
        elseif is_table(opts.header) then
            req.header = new_header(opts.header)
        else
            fatalf(2, 'opts.header must be table or net.http.header')
        end
    end

    -- set default User-Agent
    if not req.header:get('User-Agent') then
        req.header:set('User-Agent', DEFAULT_UA)
    end

    -- set uri
    local ok, err = req:set_uri(uri)
    if not ok then
        return nil, errorf('failed to fetch()', err)
    end

    -- verify scheme
    if not req.scheme then
        return nil, errorf('failed to fetch()',
                           new_errno('EINVAL', 'url scheme not defined'))
    end
    local port = WELL_KNOWN_PORT[req.scheme]
    if not port then
        return nil, errorf('failed to fetch()',
                           new_errno('EINVAL', 'unsupported url scheme'))
    elseif req.port then
        -- use custom port
        port = req.port
    end

    -- set method
    if opts.method then
        ok, err = req:set_method(opts.method)
        if not ok then
            return nil, errorf('failed to fetch()', err)
        end
    end

    -- set version
    if opts.version then
        ok, err = req:set_version(opts.version)
        if not ok then
            return nil, errorf('failed to fetch()', err)
        end
    end

    -- set query
    if opts.query then
        req.query = encode_query(opts.query)
    end

    -- set default path
    if not req.path then
        req.path = '/'
    end

    local tlscfg
    if req.scheme == 'https' then
        -- create tls config
        tlscfg = {}
        if opts.insecure == true then
            tlscfg.noverify_cert = true
            tlscfg.noverify_name = true
            tlscfg.noverify_time = true
        end
    end

    -- create client
    local sock, timeout

    if opts.sockfile == nil then
        sock, err, timeout = new_inet_client(req.hostname, port, {
            deadline = opts.deadline,
            tlscfg = tlscfg,
            servername = opts.servername,
        })
    elseif not is_string(opts.sockfile) then
        fatalf(2, 'opts.sockfile must be string')
    else
        sock, err, timeout = new_unix_client(opts.sockfile, {
            deadline = opts.deadline,
            tlscfg = tlscfg,
            servername = opts.servername,
        })
    end
    if not sock then
        if err then
            return nil, errorf('failed to fetch()', err)
        end
        return nil, nil, timeout
    end

    -- create new client connection
    local c = new_connection(sock)

    -- send request
    local n
    if opts.content == nil then
        n, err, timeout = req:write_header(c)
    elseif is_string(opts.content) then
        n, err, timeout = req:write(c, opts.content)
    elseif is_file(opts.content) then
        n, err, timeout = req:write_file(c, opts.content)
    elseif instanceof(opts.content, 'net.http.content') then
        n, err, timeout = req:write_content(c, opts.content)
    elseif instanceof(opts.content, 'net.http.form') then
        n, err, timeout = req:write_form(c, opts.content, opts.boundary)
    else
        c:close()
        fatalf(2,
               'opts.content must be string, net.http.content or net.http.form')
    end

    if err then
        c:close()
        return nil, errorf('failed to fetch()', err)
    elseif not n then
        c:close()
        return nil, nil, timeout
    end

    n, err, timeout = c:flush()
    if err then
        c:close()
        return nil, errorf('failed to fetch()', err)
    elseif not n then
        c:close()
        return nil, nil, timeout
    end

    -- read response
    local res
    res, err, timeout = c:read_response()
    if err then
        c:close()
        return nil, errorf('failed to fetch()', err)
    elseif not res then
        c:close()
        return nil, nil, timeout
    end

    return res
end

return fetch
