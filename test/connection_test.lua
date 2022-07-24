require('luacov')
local testcase = require('testcase')
local new_connection = require('net.http.connection').new
local parse = require('net.http.parse')

function testcase.new()
    -- test that create new incoming connection
    local c = new_connection({
        read = function()
        end,
        write = function()
        end,
    })
    assert.match(tostring(c), '^net.http.connection: ', false)

    -- test that throws an error if sock has no read function
    local err = assert.throws(new_connection, {})
    assert.match(err, 'reader.read must be function')

    -- test that throws an error if sock has no read function
    err = assert.throws(new_connection, {
        read = function()
        end,
    })
    assert.match(err, 'writer.write must be function')
end

function testcase.close()
    local c = new_connection({
        read = function()
        end,
        write = function()
        end,
        close = function()
            return true, 'close error'
        end,
    })

    -- test that call sock.close method
    local ok, err = c:close()
    assert.is_true(ok)
    assert.equal(err, 'close error')
end

function testcase.write()
    local c = new_connection({
        read = function()
        end,
        write = function()
            return nil, 'write error'
        end,
    })

    -- test that call sock.write method
    c.writer:setbufsize(0)
    local n, err = c:write('foo')
    assert.equal(n, 0)
    assert.equal(err, 'write error')
end

function testcase.flush()
    local c = new_connection({
        read = function()
        end,
        write = function()
            return nil, 'write error'
        end,
    })
    local n, err = c:write('foo')
    assert.equal(n, 3)
    assert.is_nil(err)

    -- test that call sock.flush method
    n, err = c:flush()
    assert.equal(n, 0)
    assert.equal(err, 'write error')
end

function testcase.read_request()
    local data = table.concat({
        'POST /foo/bar/baz HTTP/1.1',
        'Host: www.example.com',
        'Content-Type: application/x-www-form-urlencoded',
        'Content-Length: 4',
        'Connection: close',
        '',
        'q=42',
        '',
        '',
        'POST /hello/world HTTP/1.1',
        'Host: www.example.com',
        'Content-Type: application/x-www-form-urlencoded',
        'Transfer-Encoding: chunked',
        '',
        '1',
        'h',
        '4',
        'ello',
        '2',
        '=w',
        '3',
        'orl',
        '1',
        'd',
        '0',
        '',
        '',
    }, '\r\n')
    local c = new_connection({
        read = function(_, n)
            if #data == 0 then
                return nil
            end

            local s = string.sub(data, 1, n)
            data = string.sub(data, n + 1)
            return s
        end,
        write = function()
        end,
    })

    -- test that read request message
    local msg, err = assert(c:read_request())
    assert.is_nil(err)
    assert.match(tostring(msg), '^net.http.message.request: ', false)
    assert.contains(msg, {
        method = 'POST',
        uri = '/foo/bar/baz',
        parsed_uri = {
            path = '/foo/bar/baz',
        },
        version = 1.1,
        header = {
            dict = {
                host = {
                    idx = 1,
                    key = 'Host',
                    val = {
                        'www.example.com',
                    },
                },
                ['content-type'] = {
                    idx = 2,
                    key = 'Content-Type',
                    val = {
                        'application/x-www-form-urlencoded',
                    },
                },
                ['content-length'] = {
                    idx = 3,
                    key = 'Content-Length',
                    val = {
                        '4',
                    },
                },
                ['connection'] = {
                    idx = 4,
                    key = 'Connection',
                    val = {
                        'close',
                    },
                },
            },
        },
    })
    assert(msg.content ~= nil, 'content is nil')
    assert.equal(msg.content:read(), 'q=42')

    -- test that read next request message
    msg, err = c:read_request()
    assert.is_nil(err)
    assert.contains(msg, {
        method = 'POST',
        uri = '/hello/world',
        parsed_uri = {
            path = '/hello/world',
        },
        version = 1.1,
        header = {
            dict = {
                host = {
                    idx = 1,
                    key = 'Host',
                    val = {
                        'www.example.com',
                    },
                },
                ['content-type'] = {
                    idx = 2,
                    key = 'Content-Type',
                    val = {
                        'application/x-www-form-urlencoded',
                    },
                },
                ['transfer-encoding'] = {
                    idx = 3,
                    key = 'Transfer-Encoding',
                    val = {
                        'chunked',
                    },
                },
            },
        },
    })
    assert.is_true(msg.content.is_chunked)
    assert.equal(msg.content:read(), 'hello=world')

    -- test that read empty request
    msg, err = c:read_request()
    assert.is_nil(msg)
    assert.is_nil(err)

    -- test that content is treated as chunked content if both of content-length
    -- and transfer-encoding-chunked header are defined
    data = table.concat({
        'POST /foo/bar/baz HTTP/1.1',
        'Host: www.example.com',
        'Content-Type: application/x-www-form-urlencoded',
        'Content-Length: 4',
        'Transfer-Encoding: chunked',
        '',
        '',
    }, '\r\n')
    msg, err = c:read_request()
    assert.contains(msg, {
        method = 'POST',
        uri = '/foo/bar/baz',
        parsed_uri = {
            path = '/foo/bar/baz',
        },
        version = 1.1,
        header = {
            dict = {
                host = {
                    idx = 1,
                    key = 'Host',
                    val = {
                        'www.example.com',
                    },
                },
                ['content-type'] = {
                    idx = 2,
                    key = 'Content-Type',
                    val = {
                        'application/x-www-form-urlencoded',
                    },
                },
                ['content-length'] = {
                    idx = 3,
                    key = 'Content-Length',
                    val = {
                        '4',
                    },
                },
                ['transfer-encoding'] = {
                    idx = 4,
                    key = 'Transfer-Encoding',
                    val = {
                        'chunked',
                    },
                },
            },
        },
    })
    assert.is_nil(err)
    assert.is_true(msg.content.is_chunked)

    -- test that return EMSG if request uri is invalid
    data = table.concat({
        'GET /foo<bar/baz HTTP/1.1',
        'Host: www.example.com',
        '',
        '',
    }, '\r\n')
    msg, err = c:read_request()
    assert.is_nil(msg)
    assert.equal(err.type, parse.EMSG)

    -- test that return EVERSION if request version is unknown
    data = table.concat({
        'GET /foo/bar/baz HTTP/11',
        'Host: www.example.com',
        '',
        '',
    }, '\r\n')
    msg, err = c:read_request()
    assert.is_nil(msg)
    assert.equal(err.type, parse.EVERSION)

    -- test that return EMETHOD if previous content is not discarded
    data = table.concat({
        'POST /foo/bar/baz HTTP/1.1',
        'Host: www.example.com',
        'Content-Type: application/x-www-form-urlencoded',
        'Content-Length: 4',
        'Connection: close',
        '',
        'q=42',
        '',
        '',
        'GET /hello/world HTTP/1.1',
        'Host: www.example.com',
        '',
        '',
    }, '\r\n')
    msg, err = c:read_request()
    assert(msg ~= nil, 'msg is nil')
    assert.is_nil(err)
    assert(msg.content ~= nil, 'content is nil')
    msg, err = c:read_request()
    assert.is_nil(msg)
    assert.equal(err.type, parse.EMETHOD)
end

function testcase.read_response()
    local data = table.concat({
        'HTTP/1.1 200 OK',
        'Content-Type: text/html; charset=UTF-8',
        'Content-Length: 5',
        'Connection: close',
        '',
        'hello',
        '',
        '',
        'HTTP/1.0 418 I\'m a teapot',
        'Content-Type: text/plain',
        'Transfer-Encoding: chunked',
        '',
        '1',
        'h',
        '4',
        'ello',
        '2',
        ' w',
        '3',
        'orl',
        '1',
        'd',
        '0',
        '',
        '',
    }, '\r\n')
    local c = new_connection({
        read = function(_, n)
            if #data == 0 then
                return nil
            end

            local s = string.sub(data, 1, n)
            data = string.sub(data, n + 1)
            return s
        end,
        write = function()
        end,
    })

    -- test that read response message
    local msg, err = assert(c:read_response())
    assert.is_nil(err)
    assert.match(tostring(msg), '^net.http.message.response: ', false)
    assert.contains(msg, {
        reason = 'OK',
        status = 200,
        version = 1.1,
        header = {
            dict = {
                ['content-type'] = {
                    idx = 1,
                    key = 'Content-Type',
                    val = {
                        'text/html; charset=UTF-8',
                    },
                },
                ['content-length'] = {
                    idx = 2,
                    key = 'Content-Length',
                    val = {
                        '5',
                    },
                },
                ['connection'] = {
                    idx = 3,
                    key = 'Connection',
                    val = {
                        'close',
                    },
                },
            },
        },
    })
    assert(msg.content ~= nil, 'content is nil')
    assert.equal(msg.content:read(), 'hello')

    -- test that read next response message
    msg, err = c:read_response()
    assert.is_nil(err)
    assert.contains(msg, {
        reason = 'I\'m a teapot',
        status = 418,
        version = 1.0,
        header = {
            dict = {
                ['content-type'] = {
                    idx = 1,
                    key = 'Content-Type',
                    val = {
                        'text/plain',
                    },
                },
                ['transfer-encoding'] = {
                    idx = 2,
                    key = 'Transfer-Encoding',
                    val = {
                        'chunked',
                    },
                },
            },
        },
    })
    assert.is_true(msg.content.is_chunked)
    assert.equal(msg.content:read(), 'hello world')

    -- test that read empty response
    msg, err = c:read_response()
    assert.is_nil(msg)
    assert.is_nil(err)

    -- test that return ESTATUS if response status is invalid
    data = table.concat({
        'HTTP/1.1 2000 world',
        'Host: www.example.com',
        '',
        '',
    }, '\r\n')
    msg, err = c:read_response()
    assert.is_nil(msg)
    assert.equal(err.type, parse.ESTATUS)

    -- test that return EMSG if response message is invalid
    data = table.concat({
        'HTTP/1.1 200 O\vK',
        'Host: www.example.com',
        '',
        '',
    }, '\r\n')
    msg, err = c:read_response()
    assert.is_nil(msg)
    assert.equal(err.type, parse.EMSG)
end

