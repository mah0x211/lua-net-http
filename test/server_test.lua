require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local sleep = require('testcase.timer').sleep
local fork = require('testcase.fork')
local execvp = require('exec').execvp
local mkstemp = require('mkstemp')
local error = require('error')
local errno = require('errno')
local fetch = require('net.http.fetch')
local new_response = require('net.http.message.response').new
local new_server = require('net.http.server').new

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

local SOCKFILE
local SOCKFILENAME

function testcase.before_each()
    local _
    SOCKFILE, _, SOCKFILENAME = assert(mkstemp('/tmp/test_sock_XXXXXX'))
    os.remove(SOCKFILENAME)
end

function testcase.after_each()
    SOCKFILE:close()
    SOCKFILE = nil
    os.remove(SOCKFILENAME)
    SOCKFILENAME = nil
    -- killproc()
end

function testcase.new_inet_server()
    -- test that create new Inet server
    local s, err = assert(new_server('127.0.0.1:8080', {
        reuseaddr = true,
        reuseport = true,
    }))
    assert.match(s, '^net.http.server.Inet: ', false)
    assert.is_nil(err)
    local ai = assert(s:getsockname())
    assert.equal(ai:addr(), '127.0.0.1')
    assert.equal(ai:port(), 8080)

    -- test that return err=EADDRINUSE
    local news
    news, err = new_server('127.0.0.1:8080')
    assert.is_nil(news)
    assert(error.is(err, errno.EADDRINUSE))
    assert(s:close())

    -- test that throws an error if addr is not string
    err = assert.throws(new_server)
    assert.match(err, 'addr must be string')

    -- test that throws an error if opts is not table
    err = assert.throws(new_server, '', true)
    assert.match(err, 'opts must be table')
end

function testcase.new_inet_tls_server()
    -- test that create new InetTLS server
    local s, err = assert(new_server('127.0.0.1:8080', {
        reuseaddr = true,
        reuseport = true,
        tlscfg = TLS_SERVER_CONFIG,
    }))
    assert.match(s, '^net.http.server.InetTLS: ', false)
    assert.is_nil(err)
    local ai = assert(s:getsockname())
    assert.equal(ai:addr(), '127.0.0.1')
    assert.equal(ai:port(), 8080)

    -- test that return err=EADDRINUSE
    local news
    news, err = new_server('127.0.0.1:8080', {
        tlscfg = TLS_SERVER_CONFIG,
    })
    assert.is_nil(news)
    assert(error.is(err, errno.EADDRINUSE))
    assert(s:close())
end

function testcase.new_unix_server()
    -- test that create new Unix server
    local s, err = assert(new_server(SOCKFILENAME))
    assert.match(s, '^net.http.server.Unix: ', false)
    assert.is_nil(err)
    local ai = assert(s:getsockname())
    assert.equal(ai:addr(), SOCKFILENAME)
    assert(s:close())

    -- test that return err=EADDRINUSE
    local news
    news, err = new_server(SOCKFILENAME)
    assert.is_nil(news)
    assert.equal(err.type, errno.EADDRINUSE)
end

function testcase.new_unix_tls_server()
    -- test that create new UnixTLS  server
    local s, err = assert(new_server(SOCKFILENAME, {
        tlscfg = TLS_SERVER_CONFIG,
    }))
    assert.match(s, '^net.http.server.UnixTLS: ', false)
    assert.is_nil(err)
    local ai = assert(s:getsockname())
    assert.equal(ai:addr(), SOCKFILENAME)
    assert(s:close())

    -- test that return err=EADDRINUSE
    local news
    news, err = new_server(SOCKFILENAME, {
        tlscfg = TLS_SERVER_CONFIG,
    })
    assert.is_nil(news)
    assert.equal(err.type, errno.EADDRINUSE)
end

function testcase.accept()
    -- test that accept connection
    local p = assert(fork())
    if p:is_child() then
        local s = assert(new_server(SOCKFILENAME, {
            reuseaddr = true,
            reuseport = true,
            tlscfg = TLS_SERVER_CONFIG,
        }))
        assert(s:listen())
        while true do
            local peer = assert(s:accept())
            assert.match(peer, '^net.http.connection: ', false)
            assert(peer:read_request())
            local res = new_response()
            assert(res:write(peer, 'hello world!'))
            assert(peer:flush())
            assert(peer:close())
            assert(s:close())
        end
    end

    sleep(0.05)
    local res = assert(fetch('https://127.0.0.1:8080', {
        sockfile = SOCKFILENAME,
        insecure = true,
    }))
    assert(res.content, 'no content')
    assert(res.content:read(), 'hello world!')
end

