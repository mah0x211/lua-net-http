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
local isa = require('isa')
local is_string = isa.string
local is_table = isa.table
local new_errno = require('errno').new
local new_tls_config = require('net.tls.config').new
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
--- @return net.http.message.response res
--- @return error? err
--- @return string? timeout
local function fetch(uri, opts)
    if not is_string(uri) then
        error('uri must be string', 2)
    elseif opts == nil then
        opts = {}
    elseif not is_table(opts) then
        error('opts must be table', 2)
    end

    local req = new_request()

    -- set header
    if opts.header then
        if instanceof(opts.header, 'net.http.header') then
            req.header = opts.header
        elseif is_table(opts.header) then
            req.header = new_header(opts.header)
        else
            error('opts.header must be table or net.http.header', 2)
        end
    end

    -- set default User-Agent
    if not req.header:get('User-Agent') then
        req.header:set('User-Agent', DEFAULT_UA)
    end

    -- set uri
    local ok, err = req:set_uri(uri)
    if not ok then
        return nil, err
    end

    -- verify scheme
    if not req.scheme then
        return nil, new_errno('EINVAL', 'url scheme not defined')
    end
    local port = WELL_KNOWN_PORT[req.scheme]
    if not port then
        return nil, new_errno('EINVAL', 'unsupported url scheme')
    elseif req.port then
        -- use custom port
        port = req.port
    end

    -- set method
    if opts.method then
        ok, err = req:set_method(opts.method)
        if not ok then
            return nil, err
        end
    end

    -- set version
    if opts.version then
        ok, err = req:set_version(opts.version)
        if not ok then
            return nil, err
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
        tlscfg, err = new_tls_config()
        if not tlscfg then
            return nil, err
        elseif opts.insecure == true then
            tlscfg:insecure_noverifycert()
            tlscfg:insecure_noverifyname()
            tlscfg:insecure_noverifytime()
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
        error('opts.sockfile must be string', 2)
    else
        sock, err, timeout = new_unix_client(opts.sockfile, {
            deadline = opts.deadline,
            tlscfg = tlscfg,
            servername = opts.servername,
        })
    end
    if not sock then
        return nil, err, timeout
    end

    -- create new client connection
    local c = new_connection(sock)

    -- send request
    local _
    if opts.content == nil then
        _, err = req:write_header(c)
    elseif is_string(opts.content) then
        _, err = req:write(c, opts.content)
    elseif instanceof(opts.content, 'net.http.content') then
        req:set_content(opts.content)
        _, err = req:write_content(c)
    else
        error('opts.content must be string or net.http.content', 2)
    end
    if err then
        return nil, err
    end
    _, err = c:flush()
    if err then
        return nil, err
    end

    -- read response
    local res
    res, err = c:read_response()
    if not res then
        if err then
            return nil, err
        end
        return nil, new_errno('ECONNRESET', 'read response')
    end

    return res
end

return fetch
