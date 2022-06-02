require('luacov')
local testcase = require('testcase')
local fork = require('testcase.fork')
local sleep = require('testcase.timer').sleep
local execvp = require('exec').execvp
local errno = require('errno')
local new_tls_config = require('net.tls.config').new
local new_inet_server = require('net.stream.inet').server.new
local new_unix_server = require('net.stream.unix').server.new
local new_response = require('net.http.message.response').new
local new_content = require('net.http.content').new
local now = require('net.http.date').now
local fetch = require('net.http.fetch')

local TLS_SERVER_CONFIG

function testcase.before_all()
    local p = assert(execvp('openssl', {
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-x509',
        '-days',
        '1',
        '-keyout',
        'cert.key',
        '-out',
        'cert.pem',
        '-subj',
        '/C=US/CN=www.example.com',
    }))

    for line in p.stderr:lines() do
        print(line)
    end

    local res = assert(p:waitpid())
    if res.exit ~= 0 then
        error('failed to generate cert files')
    end
    TLS_SERVER_CONFIG = new_tls_config()
    assert(TLS_SERVER_CONFIG:set_keypair_file('cert.pem', 'cert.key'))
end

local SOCKFILE = '/tmp/example.sock'
function testcase.before_each()
    os.remove(SOCKFILE)
end

function testcase.fetch()
    local hostname = '127.0.0.1'
    local server = assert(new_inet_server(hostname, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = TLS_SERVER_CONFIG,
    }))
    assert(server:listen())
    local port = assert(server:getsockname()):port()
    local host = hostname .. ':' .. port

    -- create server
    local p = assert(fork())
    if p:is_child() then
        while true do
            local peer = assert(server:accept())
            local msg = assert(peer:recv())
            local res = new_response()
            res.header:set('Content-Type', 'text/plain')
            assert(res:write(peer, msg))
            sleep(0.05)
            peer:close()
        end
    end

    -- test that fetch content
    local f = assert(io.tmpfile())
    f:write('hello world!')
    f:seek('set')
    local res, err, timeout = fetch('https://' .. host, {
        method = 'POST',
        content = new_content(f, 12),
        insecure = true,
    })
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.contains(res.header.dict, {
        ['content-length'] = {
            val = {
                '100',
            },
        },
        ['content-type'] = {
            val = {
                'text/plain',
            },
        },
        ['date'] = {
            val = {
                now(),
            },
        },
    })
    local len = res.content:size()
    local content = assert(res.content:read())
    assert.equal(#content, len)
    assert.equal(content, table.concat({
        'POST / HTTP/1.1',
        'User-Agent: lua-net-http',
        'Content-Length: 12',
        'Host: ' .. host,
        '',
        'hello world!',
    }, '\r\n'))

    -- test that cannot connect to uri
    res, err, timeout = fetch('https://localhost:80', {
        insecure = true,
    })
    assert.is_nil(res)
    assert.equal(err.type, errno.ECONNREFUSED)
    assert.is_nil(timeout)

    -- test that return error if uri is invalid
    res, err, timeout = fetch('https:// ' .. host)
    assert.is_nil(res)
    assert.is_nil(timeout)
    assert.match(err, 'invalid uri character')

    -- test that return error if method is invalid
    res, err, timeout = fetch('https://' .. host, {
        method = 'HELLO',
    })
    assert.is_nil(res)
    assert.is_nil(timeout)
    assert.match(err, 'method must be')

    -- test that return error if version is invalid
    res, err, timeout = fetch('https://' .. host, {
        version = 5,
    })
    assert.is_nil(res)
    assert.is_nil(timeout)
    assert.match(err, 'version must be')

    -- test that return error if cannot establish a secure connection
    res, err, timeout = fetch('https://' .. host)
    assert.is_nil(res)
    assert.is_nil(timeout)
    assert.match(err, 'verification failed')

    -- test that throws an error if uri is not string
    err = assert.throws(fetch, true)
    assert.match(err, 'uri must be string')

    -- test that throws an error if opts is not table
    err = assert.throws(fetch, 'http://' .. host, true)
    assert.match(err, 'opts must be table')
end

function testcase.fetch_via_sockfile()
    local server = assert(new_unix_server(SOCKFILE, TLS_SERVER_CONFIG))
    assert(server:listen())

    local p = assert(fork())
    if p:is_child() then
        while true do
            local peer = assert(server:accept())
            assert(peer:recv())
            assert(peer:send(table.concat({
                'HTTP/1.1 200 OK',
                'Content-Type: text/plain; charset=UTF-8',
                'Content-Length: 12',
                '',
                'hello world!',
            }, '\r\n')))
            sleep(0.05)
            peer:close()
        end
    end

    -- test that fetch content
    local res, err, timeout = fetch('https://127.0.0.1:8080', {
        sockfile = SOCKFILE,
        content = 'helllo world!',
        insecure = true,
    })
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.contains(res.header.dict, {
        ['content-length'] = {
            val = {
                '12',
            },
        },
        ['content-type'] = {
            val = {
                'text/plain; charset=UTF-8',
            },
        },
    })
    local len = res.content:size()
    local content = assert(res.content:read())
    assert.equal(#content, len)
    assert.equal(content, 'hello world!')

    -- test that cannot connect to sockfile
    res, err, timeout = fetch('https://127.0.0.1:8080', {
        sockfile = '/tmp/unknown/sockfile',
        insecure = true,
    })
    assert.is_nil(res)
    assert.equal(err.type, errno.ENOENT)
    assert.is_nil(timeout)

    -- test that throws an error if sockfile is not string
    err = assert.throws(fetch, 'https://127.0.0.1:8080', {
        sockfile = {},
    })
    assert.match(err, 'opts.sockfile must be string')
end

