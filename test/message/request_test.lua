require('luacov')
local testcase = require('testcase')
local errno = require('errno')
local new_message = require('net.http.message.request').new
local new_writer = require('net.http.writer').new

function testcase.new()
    -- test that create new instance of net.http.message.request
    local m = assert(new_message())
    assert.match(tostring(m), '^net.http.message.request: ', false)
    assert.equal(m.method, 'GET')
    assert.equal(m.uri, '/')
    assert.equal(m.version, '1.1')
end

function testcase.set_method()
    local m = assert(new_message())

    -- test that set valid method
    assert(m:set_method('TRACE'))
    assert.equal(m.method, 'TRACE')

    -- test that return EINVAL if argument is invalid string
    local ok, err = m:set_method('HELLO')
    assert.is_false(ok)
    assert.equal(err.type, errno.EINVAL)

    -- test that throws an error if argument is not string
    err = assert.throws(m.set_method, m)
    assert.match(err, 'method must be string')
    assert.equal(m.method, 'TRACE')
end

function testcase.set_uri()
    local m = assert(new_message())

    -- test that set valid uri
    assert(m:set_uri(
               'https://user:pswd@www.example.com:80/hello?q=foo&q=bar&baa=baz#hash'))
    assert.equal(m.uri,
                 'https://user:pswd@www.example.com:80/hello?q=foo&q=bar&baa=baz#hash')
    assert.equal(m.parsed_uri, {
        scheme = 'https',
        userinfo = 'user:pswd',
        user = 'user',
        password = 'pswd',
        host = 'www.example.com:80',
        hostname = 'www.example.com',
        port = '80',
        path = '/hello',
        query = '?q=foo&q=bar&baa=baz',
        fragment = 'hash',
    })

    -- test that set uri and parse query string
    assert(m:set_uri(
               'https://user:pswd@www.example.com:80/hello?q=foo&q=bar&baa=baz#hash',
               true))
    assert.equal(m.parsed_uri, {
        scheme = 'https',
        userinfo = 'user:pswd',
        user = 'user',
        password = 'pswd',
        host = 'www.example.com:80',
        hostname = 'www.example.com',
        port = '80',
        path = '/hello',
        query = '?q=foo&q=bar&baa=baz',
        query_params = {
            q = {
                'foo',
                'bar',
            },
            baa = {
                'baz',
            },
        },
        fragment = 'hash',
    })

    -- test that return EINVAL if argument is invalid uri string
    local ok, err = m:set_uri('http:// example.com')
    assert.is_false(ok)
    assert.equal(err.type, errno.EINVAL)

    -- test that throws an error if argument is not string
    err = assert.throws(m.set_uri, m)
    assert.match(err, 'uri must be string')
end

function testcase.write_firstline()
    local wctx = {
        msg = '',
        write = function(self, s)
            if self.err then
                return nil, self.err
            end
            self.msg = self.msg .. s
            return #s
        end,
    }
    local w = new_writer(wctx)
    w:setbufsize(0)

    -- test that write firstline
    local m = assert(new_message())
    m.method = 'connect'
    m.uri = 'http://foo:bar@example.com/hello/world'
    m.version = 1.0
    m.parsed_uri = nil
    wctx.msg = ''
    assert(m:write_firstline(w))
    assert.equal(wctx.msg, table.concat({
        'connect',
        ' ',
        '/hello/world',
        ' ',
        'HTTP/1.0',
        '\r\n',
    }))

    -- test that write firstline
    m.method = 'connect'
    m.uri = ' http://example.com/hello/world'
    m.parsed_uri = nil
    wctx.msg = ''
    local n, err = m:write_firstline(w)
    assert.equal(n, 0)
    assert.equal(err.type, errno.EINVAL)
    assert.match(err, 'invalid uri character .+ found at 1', false)
end
