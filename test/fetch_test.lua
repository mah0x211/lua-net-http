require('luacov')
local testcase = require('testcase')
local fork = require('testcase.fork')
local sleep = require('testcase.timer').sleep
local execvp = require('exec').execvp
local errno = require('errno')
local new_inet_server = require('net.stream.inet').server.new
local new_unix_server = require('net.stream.unix').server.new
local config = require('net.tls.config')
local fetch = require('net.http.fetch')

local STATUS_LINE = 'HTTP/1.1 200 OK\r\n'
local REPLY_HEADER = table.concat({
    'Accept-Ranges: bytes',
    'Age: 402700',
    'Cache-Control: max-age=604800',
    'Content-Type: text/html; charset=UTF-8',
    'Date: Tue, 31 May 2022 07:01:12 GMT',
    'Etag: "3147526947+ident"',
    'Expires: Tue, 07 Jun 2022 07:01:12 GMT',
    'Last-Modified: Thu, 17 Oct 2019 07:18:26 GMT',
    'Server: ECS (sab/571C)',
    'Vary: Accept-Encoding',
    'X-Cache: HIT',
    'Content-Length: 1256',
    '\r\n',
}, '\r\n')
local REPLY_BODY = table.concat({
    '<!doctype html>',
    '<html>',
    '<head>',
    '    <title>Example Domain</title>',
    '',
    '    <meta charset="utf-8" />',
    '    <meta http-equiv="Content-type" content="text/html; charset=utf-8" />',
    '    <meta name="viewport" content="width=device-width, initial-scale=1" />',
    '    <style type="text/css">',
    '    body {',
    '        background-color: #f0f0f2;',
    '        margin: 0;',
    '        padding: 0;',
    '        font-family: -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", "Open Sans", "Helvetica Neue", Helvetica, Arial, sans-serif;',
    '        ',
    '    }',
    '    div {',
    '        width: 600px;',
    '        margin: 5em auto;',
    '        padding: 2em;',
    '        background-color: #fdfdff;',
    '        border-radius: 0.5em;',
    '        box-shadow: 2px 3px 7px 2px rgba(0,0,0,0.02);',
    '    }',
    '    a:link, a:visited {',
    '        color: #38488f;',
    '        text-decoration: none;',
    '    }',
    '    @media (max-width: 700px) {',
    '        div {',
    '            margin: 0 auto;',
    '            width: auto;',
    '        }',
    '    }',
    '    </style>    ',
    '</head>',
    '',
    '<body>',
    '<div>',
    '    <h1>Example Domain</h1>',
    '    <p>This domain is for use in illustrative examples in documents. You may use this',
    '    domain in literature without prior coordination or asking for permission.</p>',
    '    <p><a href="https://www.iana.org/domains/example">More information...</a></p>',
    '</div>',
    '</body>',
    '</html>',
    '',
}, '\n')
local REPLY = STATUS_LINE .. REPLY_HEADER .. REPLY_BODY
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
    TLS_SERVER_CONFIG = config.new()
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

    local p = assert(fork())
    if p:is_child() then
        while true do
            local peer = assert(server:accept())
            assert(peer:recv())
            assert(peer:send(REPLY))
            sleep(0.05)
            peer:close()
        end
    end

    local data = ''
    local writer = {
        write = function(_, line)
            data = data .. line
            return #line
        end,
    }

    -- test that fetch content
    local res, err, timeout = fetch('https://' .. host, {
        method = 'POST',
        insecure = true,
    })
    assert.is_nil(err)
    assert.is_nil(timeout)
    data = ''
    res.header:write(writer)
    assert.equal(data, REPLY_HEADER)
    data = ''
    local len = res.content:size()
    local n = assert(res.content:write(writer))
    assert.equal(n, len)
    assert.equal(data, REPLY_BODY)

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
            assert(peer:send(REPLY))
            sleep(0.05)
            peer:close()
        end
    end

    local data = ''
    local writer = {
        write = function(_, line)
            data = data .. line
            return #line
        end,
    }

    -- test that fetch content
    local res, err, timeout = fetch('https://127.0.0.1:8080', {
        sockfile = SOCKFILE,
        insecure = true,
    })
    assert.is_nil(err)
    assert.is_nil(timeout)
    data = ''
    res.header:write(writer)
    assert.equal(data, REPLY_HEADER)
    data = ''
    local len = res.content:size()
    local n = assert(res.content:write(writer))
    assert.equal(n, len)
    assert.equal(data, REPLY_BODY)

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

