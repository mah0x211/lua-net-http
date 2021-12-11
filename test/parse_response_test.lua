local assert = require('assertex')
local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_response = parse.response
local CR = '\r'
local LF = '\n'
local CRLF = CR .. LF

function testcase.parse_response()
    -- test that parse http 1.0 response message
    local msg = table.concat({
        'HTTP/1.0 200 OK',
        'Server: example-server',
        CRLF,
    }, CRLF)
    local res = {
        header = {},
    }
    assert.equal(parse_response(msg, res), #msg)
    local kv_server = {
        ord = 1,
        key = 'server',
        vals = {
            'example-server',
        },
    }
    assert.equal(res, {
        status = 200,
        reason = 'OK',
        version = 10,
        header = {
            kv_server,
            server = kv_server,
        },
    })

    -- test that parse http 1.1 response message
    msg = table.concat({
        'HTTP/1.1 200 OK',
        'Server: example-server',
        CRLF,
    }, CRLF)
    res = {
        header = {},
    }
    assert.equal(parse_response(msg, res), #msg)
    assert.equal(res, {
        status = 200,
        reason = 'OK',
        version = 11,
        header = {
            kv_server,
            server = kv_server,
        },
    })

    -- test that cannot parse response message of unsupported version
    msg = table.concat({
        'HTTP/1.5 200 OK',
        'Server: example-server',
        CRLF,
    }, CRLF)
    assert.equal(parse_response(msg, {}), parse.EVERSION)

    -- test that parse response message without header
    msg = 'HTTP/1.0 200 OK' .. CRLF .. CRLF
    res = {
        header = {},
    }
    assert.equal(#msg, parse_response(msg, res))
    assert.equal(res, {
        status = 200,
        reason = 'OK',
        version = 10,
        header = {},
    })

    -- test that parse response message lines that terminate by LF
    msg = 'HTTP/1.1 200 OK' .. LF .. LF
    res = {
        header = {},
    }
    assert.equal(parse_response(msg, res), #msg)
    assert.equal(res, {
        status = 200,
        reason = 'OK',
        version = 11,
        header = {},
    })

    -- test that cannot parse response message lines that not terminated by LF'
    msg = 'HTTP/1.1 200 OK' .. CR .. CR
    assert.equal(parse_response(msg, {}), parse.EEOL)

    -- test that limit the length of uri
    msg = table.concat({
        'HTTP/1.1 418 i\'m a tea pot',
        'Server: example-server',
        CRLF,
    }, CRLF)
    assert.equal(parse_response(msg, {}, 10), parse.ELEN)

    -- test that returns EAGAIN to the incomplete message
    msg = table.concat({
        'HTTP/1.0 200 OK',
        'Server: example-server',
        CRLF,
    }, CRLF)
    res = {
        header = {},
    }
    for i = 1, #msg - 1 do
        assert.equal(parse_response(string.sub(msg, 1, i), {
            header = {},
        }), parse.EAGAIN)
    end
    assert.equal(parse_response(msg, res), #msg)
    assert.equal(res, {
        status = 200,
        reason = 'OK',
        version = 10,
        header = {
            kv_server,
            server = kv_server,
        },
    })

    -- test that parse only response-line
    local line = 'HTTP/1.0 200 OK' .. CRLF
    msg = line .. 'Server: example-server' .. CRLF .. CRLF
    res = {}
    assert.equal(parse_response(msg, res), #line)
    assert.equal(res, {
        status = 200,
        reason = 'OK',
        version = 10,
    })
end
