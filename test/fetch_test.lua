require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local fork = require('testcase.fork')
local sleep = require('testcase.timer').sleep
local execvp = require('exec').execvp
local error = require('error')
local errno = require('errno')
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

    local line = p.stderr:read()
    while line do
        print(line)
        line = p.stderr:read()
    end

    local res = assert(p:close())
    if res.exit ~= 0 then
        error('failed to generate cert files')
    end
    TLS_SERVER_CONFIG = {
        cert = 'cert.pem',
        key = 'cert.key',
    }
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
            assert(res:write(peer, msg))
            sleep(0.05)
            peer:close()
        end
    end

    -- test that fetch content
    local res, err, timeout = fetch('https://' .. host, {
        method = 'GET',
        header = {
            foo = {
                'bar',
                'baz',
            },
        },
        insecure = true,
    })
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.contains(res.header.dict, {
        ['content-length'] = {
            val = {
                '87',
            },
        },
        ['content-type'] = {
            val = {
                'application/octet-stream',
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
        'GET / HTTP/1.1',
        'Foo: bar',
        'Foo: baz',
        'User-Agent: lua-net-http',
        'Host: ' .. host,
        '',
        '',
    }, '\r\n'))

    -- test that cannot connect to uri
    res, err, timeout = fetch('https://localhost:80', {
        insecure = true,
    })
    assert.is_nil(res)
    assert(error.is(err, errno.ECONNREFUSED))
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
    assert.match(err, 'verify failed')

    -- test that throws an error if uri is not string
    err = assert.throws(fetch, true)
    assert.match(err, 'uri must be string')

    -- test that throws an error if opts is not table
    err = assert.throws(fetch, 'http://' .. host, true)
    assert.match(err, 'opts must be table')

    -- test that throws an error if opts.header is invalid
    err = assert.throws(fetch, 'https://' .. host, {
        header = 123,
    })
    assert.match(err, 'opts.header must be table or net.http.header')

    -- test that throws an error if opts.content is invalid
    err = assert.throws(fetch, 'https://' .. host, {
        content = 123,
    })
    assert.match(err,
                 'opts.content must be string, net.http.content or net.http.form')
end

function testcase.fetch_with_string_content()
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
            assert(res:write(peer, msg))
            sleep(0.05)
            peer:close()
        end
    end

    -- test that fetch content
    local res, err, timeout = fetch('https://' .. host, {
        method = 'POST',
        header = {
            foo = {
                'bar',
                'baz',
            },
        },
        content = 'hello world!',
        insecure = true,
    })
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.contains(res.header.dict, {
        ['content-length'] = {
            val = {
                '160',
            },
        },
        ['content-type'] = {
            val = {
                'application/octet-stream',
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
        'Foo: bar',
        'Foo: baz',
        'User-Agent: lua-net-http',
        'Content-Length: 12',
        'Content-Type: application/octet-stream',
        'Host: ' .. host,
        '',
        'hello world!',
    }, '\r\n'))

    -- test that cannot connect to uri
    res, err, timeout = fetch('https://localhost:80', {
        insecure = true,
    })
    assert.is_nil(res)
    assert(error.is(err, errno.ECONNREFUSED))
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
    assert.match(err, 'verify failed')

    -- test that throws an error if uri is not string
    err = assert.throws(fetch, true)
    assert.match(err, 'uri must be string')

    -- test that throws an error if opts is not table
    err = assert.throws(fetch, 'http://' .. host, true)
    assert.match(err, 'opts must be table')

    -- test that throws an error if opts.header is invalid
    err = assert.throws(fetch, 'https://' .. host, {
        header = 123,
    })
    assert.match(err, 'opts.header must be table or net.http.header')

    -- test that throws an error if opts.content is invalid
    err = assert.throws(fetch, 'https://' .. host, {
        content = 123,
    })
    assert.match(err,
                 'opts.content must be string, net.http.content or net.http.form')
end

function testcase.fetch_with_file_content()
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
            assert(res:write(peer, msg))
            sleep(0.05)
            peer:close()
        end
    end

    -- test that fetch with content
    local f = assert(io.tmpfile())
    f:write('hello world!')
    f:seek('set')
    local res, err, timeout = fetch('https://' .. host, {
        method = 'POST',
        header = {
            foo = {
                'bar',
                'baz',
            },
        },
        content = f,
        insecure = true,
    })
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.contains(res.header.dict, {
        ['content-length'] = {
            val = {
                '160',
            },
        },
        ['content-type'] = {
            val = {
                'application/octet-stream',
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
        'Foo: bar',
        'Foo: baz',
        'User-Agent: lua-net-http',
        'Content-Length: 12',
        'Content-Type: application/octet-stream',
        'Host: ' .. host,
        '',
        'hello world!',
    }, '\r\n'))
end

function testcase.fetch_with_content()
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
            assert(res:write(peer, msg))
            sleep(0.05)
            peer:close()
        end
    end

    -- test that fetch with content
    local f = assert(io.tmpfile())
    f:write('hello world!')
    f:seek('set')
    local res, err, timeout = fetch('https://' .. host, {
        method = 'POST',
        header = {
            foo = {
                'bar',
                'baz',
            },
        },
        content = new_content(f, 12),
        insecure = true,
    })
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.contains(res.header.dict, {
        ['content-length'] = {
            val = {
                '160',
            },
        },
        ['content-type'] = {
            val = {
                'application/octet-stream',
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
        'Foo: bar',
        'Foo: baz',
        'User-Agent: lua-net-http',
        'Content-Length: 12',
        'Content-Type: application/octet-stream',
        'Host: ' .. host,
        '',
        'hello world!',
    }, '\r\n'))
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
    assert(error.is(err, errno.ENOENT))
    assert.is_nil(timeout)

    -- test that throws an error if sockfile is not string
    err = assert.throws(fetch, 'https://127.0.0.1:8080', {
        sockfile = {},
    })
    assert.match(err, 'opts.sockfile must be string')
end

