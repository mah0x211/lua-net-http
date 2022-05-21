local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_request = parse.request
local CR = '\r'
local LF = '\n'
local CRLF = CR .. LF

function testcase.parse_request()
    -- test that parse http 1.0 request message
    local msg = table.concat({
        'GET /foo/bar/baz/qux HTTP/1.0',
        'Host: example.com',
        CRLF,
    }, CRLF)
    local req = {
        header = {},
    }
    assert.equal(parse_request(msg, req), #msg)
    local kv_host = {
        idx = 1,
        key = 'Host',
        val = {
            'example.com',
        },
    }
    assert.equal(req, {
        method = 'GET',
        uri = '/foo/bar/baz/qux',
        version = 1.0,
        header = {
            kv_host,
            host = kv_host,
        },
    })

    -- test that parse http 1.1 request message
    msg = table.concat({
        'GET /foo/bar/baz/qux HTTP/1.1',
        'Host: example.com',
        CRLF,
    }, CRLF)
    req = {
        header = {},
    }
    assert.equal(parse_request(msg, req), #msg)
    assert.equal(req, {
        method = 'GET',
        uri = '/foo/bar/baz/qux',
        version = 1.1,
        header = {
            kv_host,
            host = kv_host,
        },
    })

    -- test that parse supported request methods
    for _, method in ipairs({
        'GET',
        'HEAD',
        'POST',
        'PUT',
        'DELETE',
        'OPTIONS',
        'TRACE',
        'CONNECT',
    }) do
        msg = method .. ' /foo/bar/baz/qux HTTP/1.1\r\n'
        req = {}
        assert.equal(parse_request(msg, req), #msg)
        assert.equal(req, {
            method = method,
            uri = '/foo/bar/baz/qux',
            version = 1.1,
        })
    end

    -- test that cannot parse unsupported request method
    local pos, err = parse_request('FOO /foo/bar/baz/qux HTTP/1.1\r\n', {})
    assert.is_nil(pos)
    assert.equal(err.type, parse.EMETHOD)

    -- test that cannot parse request message of unsupported version
    msg = table.concat({
        'GET /foo/bar/baz/qux HTTP/1.5',
        'Host: example.com',
        CRLF,
    }, CRLF)
    pos, err = parse_request(msg, {
        header = {},
    })
    assert.is_nil(pos)
    assert.equal(err.type, parse.EVERSION)

    -- test that parse request message without header
    msg = 'GET /foo/bar/baz/qux HTTP/1.1' .. CRLF .. CRLF
    req = {
        header = {},
    }
    assert.equal(parse_request(msg, req), #msg)
    assert.equal(req, {
        method = 'GET',
        uri = '/foo/bar/baz/qux',
        version = 1.1,
        header = {},
    })

    -- test that parse request message lines that terminate by LF
    msg = 'GET /foo/bar/baz/qux HTTP/1.1' .. LF .. LF
    req = {
        header = {},
    }
    assert.equal(parse_request(msg, req), #msg)
    assert.equal(req, {
        method = 'GET',
        uri = '/foo/bar/baz/qux',
        version = 1.1,
        header = {},
    })

    -- test that cannot parse request message lines that not terminated by LF'
    msg = 'GET /foo/bar/baz/qux HTTP/1.1' .. CR .. CR
    req = {
        header = {},
    }
    pos, err = parse_request(msg, req)
    assert.is_nil(pos)
    assert.equal(err.type, parse.EEOL)

    -- test that limit the length of uri
    msg = table.concat({
        'GET /foo/bar/baz/qux HTTP/1.0',
        'Host: example.com',
        CRLF,
    }, CRLF)
    req = {
        header = {},
    }
    pos, err = parse_request(msg, req, 10)
    assert.is_nil(pos)
    assert.equal(err.type, parse.ELEN)

    -- test that returns EAGAIN to the incomplete message
    msg = table.concat({
        'GET /foo/bar/baz/qux HTTP/1.0',
        'Host: example.com',
        CRLF,
    }, CRLF)
    for i = 1, #msg - 1 do
        pos, err = parse_request(string.sub(msg, 1, i), {
            header = {},
        })
        assert.is_nil(pos)
        assert.equal(err.type, parse.EAGAIN)
    end

    -- test that parse partial messages
    msg = ''
    req = {
        header = {},
    }
    for i, chunk in ipairs({
        'GET /foo/bar/baz/qux HTTP/1.0\r\n',
        'Host: example1.com\r\n',
        'Host: example2.com\r\n',
        'Host: example3.com\r\n',
        '\r\n',
    }) do
        msg = msg .. chunk
        if i < 5 then
            pos, err = parse_request(msg, req)
            assert.is_nil(pos)
            assert.equal(err.type, parse.EAGAIN)
        else
            assert.equal(parse_request(msg, req), #msg)
        end
    end
    kv_host.val = {
        'example1.com',
        'example2.com',
        'example3.com',
    }
    assert.equal(req, {
        method = 'GET',
        uri = '/foo/bar/baz/qux',
        version = 1.0,
        header = {
            kv_host,
            host = kv_host,
        },
    })

    -- test that only request-line is parsed if header table does not exists
    local line = 'GET /foo/bar/baz/qux HTTP/1.0\n'
    msg = line .. 'Host: example.com\n' .. '\n'
    req = {}
    assert.equal(parse_request(msg, req), #line)
    assert.equal(req, {
        method = 'GET',
        uri = '/foo/bar/baz/qux',
        version = 1.0,
    })
end

