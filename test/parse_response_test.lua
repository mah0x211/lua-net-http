local testcase = require('testcase')
local assert = require('assert')
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
        idx = 1,
        key = 'Server',
        val = {
            'example-server',
        },
    }
    assert.equal(res, {
        status = 200,
        reason = 'OK',
        version = 1.0,
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
        version = 1.1,
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
    local pos, err = parse_response(msg, {})
    assert.is_nil(pos)
    assert.equal(err.type, parse.EVERSION)

    -- test that parse response message without header
    msg = 'HTTP/1.0 200 OK' .. CRLF .. CRLF
    res = {
        header = {},
    }
    assert.equal(parse_response(msg, res), #msg)
    assert.equal(res, {
        status = 200,
        reason = 'OK',
        version = 1.0,
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
        version = 1.1,
        header = {},
    })

    -- test that cannot parse response message lines that not terminated by LF'
    msg = 'HTTP/1.1 200 OK' .. CR .. CR
    pos, err = parse_response(msg, {})
    assert.is_nil(pos)
    assert.equal(err.type, parse.EEOL)

    -- test that limit the length of uri
    msg = table.concat({
        'HTTP/1.1 418 i\'m a tea pot',
        'Server: example-server',
        CRLF,
    }, CRLF)
    pos, err = parse_response(msg, {}, 10)
    assert.is_nil(pos)
    assert.equal(err.type, parse.ELEN)

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
        pos, err = parse_response(string.sub(msg, 1, i), {
            header = {},
        })
        assert.is_nil(pos)
        assert.equal(err.type, parse.EAGAIN)
    end
    assert.equal(parse_response(msg, res), #msg)
    assert.equal(res, {
        status = 200,
        reason = 'OK',
        version = 1.0,
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
        version = 1.0,
    })
end
