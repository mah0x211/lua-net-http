local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_request = parse.request
local CR = '\r'
local LF = '\n'
local CRLF = CR .. LF

function testcase.parse_http10()
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
end

function testcase.parse_http11()
    -- test that parse http 1.1 request message
    local msg = table.concat({
        'GET /foo/bar/baz/qux HTTP/1.1',
        'Host: example.com',
        CRLF,
    }, CRLF)
    local req = {
        header = {},
    }
    local kv_host = {
        idx = 1,
        key = 'Host',
        val = {
            'example.com',
        },
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
end

function testcase.parse_methods()
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
        local msg = method .. ' /foo/bar/baz/qux HTTP/1.1\r\n'
        local req = {}
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
end

function testcase.parse_unsupported_version()
    -- test that cannot parse request message of unsupported version
    local msg = table.concat({
        'GET /foo/bar/baz/qux HTTP/1.5',
        'Host: example.com',
        CRLF,
    }, CRLF)
    local pos, err = parse_request(msg, {
        header = {},
    })
    assert.is_nil(pos)
    assert.equal(err.type, parse.EVERSION)
end

function testcase.parse_without_header()
    -- test that parse request message without header
    local msg = 'GET /foo/bar/baz/qux HTTP/1.1' .. CRLF .. CRLF
    local req = {
        header = {},
    }
    assert.equal(parse_request(msg, req), #msg)
    assert.equal(req, {
        method = 'GET',
        uri = '/foo/bar/baz/qux',
        version = 1.1,
        header = {},
    })
end

function testcase.parse_terminated_by_lf()
    -- test that parse request message lines that terminate by LF
    local msg = 'GET /foo/bar/baz/qux HTTP/1.1' .. LF .. LF
    local req = {
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
    local pos, err = parse_request(msg, req)
    assert.is_nil(pos)
    assert.equal(err.type, parse.EEOL)
end

function testcase.parse_too_long_uri()
    -- test that limit the length of uri
    local msg = table.concat({
        'GET /foo/bar/baz/qux HTTP/1.0',
        'Host: example.com',
        CRLF,
    }, CRLF)
    local req = {
        header = {},
    }
    local pos, err = parse_request(msg, req, 10)
    assert.is_nil(pos)
    assert.equal(err.type, parse.ELEN)
end

function testcase.parse_incomplete_message()
    -- test that returns EAGAIN to the incomplete message
    local msg = table.concat({
        'GET /foo/bar/baz/qux HTTP/1.0',
        'Host: example.com',
        CRLF,
    }, CRLF)
    for i = 1, #msg - 1 do
        local pos, err = parse_request(string.sub(msg, 1, i), {
            header = {},
        })
        assert.is_nil(pos)
        assert.equal(err.type, parse.EAGAIN)
    end
end

function testcase.parse_partial_messages()
    -- test that parse partial messages
    local msg = ''
    local req = {
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
            local pos, err = parse_request(msg, req)
            assert.is_nil(pos)
            assert.equal(err.type, parse.EAGAIN)
        else
            assert.equal(parse_request(msg, req), #msg)
        end
    end
    local kv_host = {
        idx = 1,
        key = 'Host',
        val = {
            'example1.com',
            'example2.com',
            'example3.com',
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
end

function testcase.parse_only_request_line()
    -- test that only request-line is parsed if header table does not exists
    local line = 'GET /foo/bar/baz/qux HTTP/1.0\n'
    local msg = line .. 'Host: example.com\n' .. '\n'
    local req = {}
    assert.equal(parse_request(msg, req), #line)
    assert.equal(req, {
        method = 'GET',
        uri = '/foo/bar/baz/qux',
        version = 1.0,
    })
end

