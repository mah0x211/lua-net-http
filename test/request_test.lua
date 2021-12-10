require('luacov')
local assert = require('assertex')
local testcase = require('testcase')
local string = require('stringex')
local signal = require('signal')
local fork = require('process').fork
local tls_config = require("libtls.config")
local inet_client = require('net.stream.inet').client
local inet_server = require('net.stream.inet').server
local request = require('net.http.request')
local status = require('net.http.status')
local date = require('net.http.date')
local parse = require('net.http.parse')
local parse_request = parse.request
local EAGAIN = parse.EAGAIN

local function create_server(tlscfg)
    local sock = assert(inet_server.new({
        host = '127.0.0.1',
        port = tlscfg and '5443' or '5000',
        tlscfg = tlscfg,
    }))
    local err = sock:listen()
    assert(not err, err)

    local pid = assert(fork())
    if pid ~= 0 then
        sock:close()
        return pid
    end

    -- child
    while true do
        local c = assert(sock:accept())
        local data = ''

        while true do
            local msg, rerr, timeout = c:recv(4096);

            if not msg or rerr or timeout then
                break
            end
            data = data .. msg

            local consumed = parse_request(data, {
                header = {},
            })
            if consumed > 0 then
                msg = string.sub(data, 1, consumed)

                if string.find(msg, 'x-response: no-content', 1, true) then
                    c:send(status.toLine(204, 1.1) .. table.concat({
                        'Date: ' .. date.now(),
                        'Server: test-server',
                        '\r\n',
                    }, '\r\n'))
                else
                    c:send(status.toLine(200, 1.1) .. table.concat({
                        'Date: ' .. date.now(),
                        'Server: test-server',
                        'Content-Length: ' .. #msg,
                        'Content-Type: text/plain',
                        '',
                        msg,
                    }, '\r\n'))
                end
                break
            elseif consumed ~= EAGAIN then
                break
            end
        end

        c:close()
    end
end

local PID = {}

function testcase.before_all()
    local cfg = assert(tls_config.new())

    assert(cfg:set_keypair_file('../cert/cert.crt', '../cert/cert.key'))
    PID[1] = create_server()
    PID[2] = create_server(cfg)
end

function testcase.after_all()
    signal.kill(signal.SIGKILL, PID[1])
    signal.kill(signal.SIGKILL, PID[2])
end

function testcase.new()
    -- test that create request instance
    for _, method in ipairs({
        'CONNECT',
        'DELETE',
        'GET',
        'HEAD',
        'OPTIONS',
        'POST',
        'PUT',
        'TRACE',
    }) do
        assert(request.new(method, 'http://127.0.0.1:5000/'))
        -- method is not casecensitive
        assert(request.new(string.lower(method), 'http://127.0.0.1:5000/'))
    end

    -- test that use a custom port-number
    local req, err = request.new('get', 'http://127.0.0.1')
    assert(req, err)
    assert.equal(req.url.port, '80')
    req = assert(request.new('get', 'http://127.0.0.1:8080'))
    assert.equal(req.url.port, '8080')

    -- test that create with query parameters
    req = assert(request.new('get', 'http://127.0.0.1:5000?hello=world'))
    assert.equal(req.url.query, '?hello=world')

    -- test that returns an error if unsupported method is passed
    req, err = request.new('unknown-method', 'http://127.0.0.1:5000/')
    assert.is_nil(req)
    assert.match(err, 'unsupported method')

    -- test that returns an error if uri with no scheme is passed
    req, err = request.new('get', '127.0.0.1')
    assert.is_nil(req)
    assert.match(err, 'scheme required')

    -- test that returns an error if uri with unsupported scheme
    req, err = request.new('get', 'foo://127.0.0.1:5000')
    assert.is_nil(req)
    assert.match(err, 'unsupported scheme')

    -- test that returns an error if uri without hostname
    req, err = request.new('get', 'http:///pathname')
    assert.is_nil(req)
    assert.match(err, 'hostname required')

    -- test that throws an error with invalid method arguments
    for _, method in ipairs({
        true,
        0,
        {},
        function()
        end,
        coroutine.create(function()
        end),
    }) do
        err = assert.throws(function()
            request.new(method, 'http://127.0.0.1:5000/')
        end)
        assert.match(err, 'method must be string')
    end

    -- test that throws an error with invalid uri arguments
    for _, uri in ipairs({
        true,
        0,
        {},
        function()
        end,
        coroutine.create(function()
        end),
    }) do
        err = assert.throws(function()
            request.new('get', uri)
        end)
        assert.match(err, 'uri must be string')
    end
end

function testcase.new_via_helper_funcs()
    -- test that create request via helper functions
    for _, method in ipairs({
        'connect',
        'delete',
        'get',
        'head',
        'options',
        'post',
        'put',
        'trace',
    }) do
        assert(request[method]('http://127.0.0.1:5000/'))
    end
end

function testcase.set_method()
    local req = assert(request.new('get', 'http://127.0.0.1:5000'))
    assert.equal(req.method, 'GET')

    -- test that change the method
    assert.is_nil(req:setMethod('post'))
    assert.equal(req.method, 'POST')

    -- test that cannot change the method to un unsupported method
    local err = req:setMethod('hello')
    assert.match(err, 'unsupported method')
    assert.equal(req.method, 'POST')
end

function testcase.set_query()
    local sort_params = function(qry)
        local arr = string.split(string.sub(qry, 2), '&', true)
        table.sort(arr)
        return '?' .. table.concat(arr, '&')
    end

    local req = assert(request.new('get', 'http://127.0.0.1:5000?foo=bar'))
    assert.equal(req.url.query, '?foo=bar')

    -- test that change the query
    req:setQuery({
        foo = {
            bar = {
                str = 'qux',
                truthy = true,
            },
            falsy = false,
        },
        num = 1,
    })
    assert.equal(sort_params(req.url.query), sort_params(
                     '?foo.falsy=false&foo.bar.truthy=true&foo.bar.str=qux&num=1'))

    -- test that remove the query with nil
    req = assert(request.new('get', 'http://127.0.0.1:5000?hello=world'))
    assert.equal(req.url.query, '?hello=world')
    req:setQuery(nil)
    assert.is_nil(req.url.query)

    -- test that remove the query with empty table
    req = assert(request.new('get', 'http://127.0.0.1:5000?hello=world'))
    assert.equal(req.url.query, '?hello=world')
    req:setQuery({})
    assert.is_nil(req.url.query)

    -- test that throws an error with invalid arguments
    req = assert(request.new('get', 'http://127.0.0.1:5000?hello=world'))
    for _, qry in ipairs({
        'hello',
        true,
        false,
        0,
        1,
        -1,
        function()
        end,
        coroutine.create(function()
        end),
    }) do
        local err = assert.throws(function()
            req:setQuery(qry)
        end)
        assert.match(err, 'qry must be table or nil')
        assert.equal(req.url.query, '?hello=world')
    end
end

function testcase.line()
    -- test that returns the request-line
    local req = assert(request.new('get', 'http://127.0.0.1:5000?hello=world'))
    assert.equal(req:line(),
                 'GET http://127.0.0.1:5000/?hello=world HTTP/1.1\r\n')

    -- test that returns the request-line with port-number
    req = assert(request.new('get', 'http://127.0.0.1:5000?hello=world'))
    assert.equal(req:line(),
                 'GET http://127.0.0.1:5000/?hello=world HTTP/1.1\r\n')
end

function testcase.sendto()
    -- test that send message via socket
    local req = assert(request.new('get', 'http://127.0.0.1:5000?hello=world'))
    local sock = assert(inet_client.new({
        host = '127.0.0.1',
        port = '5000',
    }))
    local exp = 'GET http://127.0.0.1:5000/?hello=world HTTP/1.1\r\n' ..
                    'host: 127.0.0.1:5000\r\n' .. 'user-agent: lua-net-http\r\n' ..
                    '\r\n'
    local res, err, timeout = req:sendto(sock)
    assert(res, err)
    assert.is_nil(timeout)
    assert.equal(res.body:read(), exp)
end

function testcase.send()
    -- test that send message
    local req = assert(request.new('get', 'http://127.0.0.1:5000?hello=world'))
    local exp = 'GET http://127.0.0.1:5000/?hello=world HTTP/1.1\r\n' ..
                    'host: 127.0.0.1:5000\r\n' .. 'user-agent: lua-net-http\r\n' ..
                    '\r\n'
    local res, err, timeout = req:send()
    assert(res, err)
    assert.is_nil(timeout)
    assert.equal(res.body:read(), exp)

    -- test that response has a body field even if it is no-content response
    req = assert(request.new('get', 'http://127.0.0.1:5000?hello=world'))
    req.header:set('x-response', 'no-content')
    res = assert(req:send())
    assert.is_nil(res.body:read())
end

function testcase.tls_communication()
    -- test that cannot communicate with non-tls server via tls connection
    local req = assert(request.new('get', 'https://127.0.0.1:5000/hello'))
    local res, err, timeout = req:send()
    assert.is_nil(res)
    assert.is_nil(timeout)
    assert.match(err, 'handshake')

    -- test that communicate with non-secure tls server on insecure mode
    req = assert(request.new('get', 'https://127.0.0.1:5443/hello', true))
    res = assert(req:send())
    local exp = 'GET https://127.0.0.1:5443/hello HTTP/1.1\r\n' ..
                    'host: 127.0.0.1:5443\r\n' .. 'user-agent: lua-net-http\r\n' ..
                    '\r\n'
    assert.equal(res.body:read(), exp)

    -- test that cannot communicate with non-secure tls server
    req = assert(request.new('get', 'https://127.0.0.1:5443/hello'))
    res, err, timeout = req:send()
    assert.is_nil(res)
    assert.is_nil(timeout)
    assert.match(err, 'verification failed')
end

function testcase.send_error()
    -- test that returns send-error
    local req = assert(request.new('get', 'http://127.0.0.1:5000?hello=world'))
    local sock = {
        send = function()
            return nil, 'send-error', false
        end,
    }
    local res, err, timeout = req:sendto(sock)
    assert.is_nil(res)
    assert.is_false(timeout)
    assert.match(err, 'send-error')
end

function testcase.recv_error()
    -- test that returns recv-error
    local req = assert(request.new('get', 'http://127.0.0.1:5000?hello=world'))
    local sock = {
        send = function(_, data)
            return #data
        end,
        recv = function()
            return nil, 'recv-error', false
        end,
    }
    local res, err, timeout = req:sendto(sock)
    assert.is_nil(res)
    assert.is_false(timeout)
    assert.match(err, 'recv-error')
end
