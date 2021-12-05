local Request = require('net.http.request')
local Status = require('net.http.status')
local ParseRequest = require('net.http.parse').request
local EAGAIN = require('net.http.parse').EAGAIN
local Date = require('net.http.date')
local split = require('string.split')
local TLSConfig = require("libtls.config")
local InetClient = require('net.stream.inet').client
local InetServer = require('net.stream.inet').server
local fork = require('process').fork
local signal = require('signal')
local tolower = string.lower
local toupper = string.upper

describe('test net.http.request', function()
    local pids = {}

    local function createServer(tlscfg)
        local sock, err = InetServer.new({
            host = '127.0.0.1',
            port = tlscfg and '5443' or '5000',
            tlscfg = tlscfg,
        })
        local pid

        assert.is_nil(err or sock:listen())

        pid, err = fork()
        if not pid then
            error(err)
        elseif pid == 0 then
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

                    local consumed = ParseRequest({
                        header = {},
                    }, data)
                    if consumed > 0 then
                        msg = string.sub(data, 1, consumed)

                        if string.find(msg, 'x-response: no-content', 1, true) then
                            c:send(Status.toLine(204, 1.1) .. table.concat({
                                'Date: ' .. Date.now(),
                                'Server: test-server',
                                '\r\n',
                            }, '\r\n'))
                        else
                            c:send(Status.toLine(200, 1.1) .. table.concat({
                                'Date: ' .. Date.now(),
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
        else
            sock:close()
            return pid
        end
    end

    setup(function()
        local cfg, err = TLSConfig.new()
        local ok

        if err then
            print(err)
            assert()
        end

        ok, err = cfg:set_keypair_file('cert/server.crt', 'cert/server.key')
        if not ok then
            print(err)
            assert()
        end

        pids[1] = createServer()
        pids[2] = createServer(cfg)
    end)

    teardown(function()
        signal.kill(signal.SIGKILL, pids[1])
        signal.kill(signal.SIGKILL, pids[2])
    end)

    it('cannot call with non-string method', function()
        for _, method in ipairs({
            true,
            0,
            {},
            function()
            end,
            coroutine.create(function()
            end),
        }) do
            assert.has_error(function()
                Request.new(method, 'http://example.com/')
            end)
        end
    end)

    it('returns an error if unsupported method is passed', function()
        local req, err = Request.new('unknown-method', 'http://example.com/')

        assert.is_nil(req)
        assert.is_not_nil(err)
    end)

    it('can be called with case-insensitive supported method', function()
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
            local req, err = Request.new(method, 'http://example.com/')
            assert.is_not_nil(req)
            assert.is_nil(err)

            req, err = Request.new(tolower(method), 'http://example.com/')
            assert.is_not_nil(req)
            assert.is_nil(err)
        end
    end)

    it('can create request via helper functions', function()
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
            local req, err = Request[method]('http://example.com/')
            assert.is_not_nil(req)
            assert.is_nil(err)
            assert.is_equal(req.method, toupper(method))
        end
    end)

    it('cannot call with non-string uri', function()
        for _, uri in ipairs({
            true,
            0,
            {},
            function()
            end,
            coroutine.create(function()
            end),
        }) do
            assert.has_error(function()
                Request.new('get', uri)
            end)
        end
    end)

    it('returns an error if uri with no scheme is passed', function()
        local req, err = Request.new('get', 'example.com')
        assert.is_nil(req)
        assert.is_not_nil(err)
    end)

    it('returns an error if uri with unsupported scheme', function()
        local req, err = Request.new('get', 'foo://example.com')
        assert.is_nil(req)
        assert.is_not_nil(err)
    end)

    it('returns an error if uri without hostname', function()
        local req, err = Request.new('get', 'http:///pathname')
        assert.is_nil(req)
        assert.is_not_nil(err)
    end)

    it('can use a custom port-number', function()
        local req = Request.new('get', 'http://example.com')
        assert.is_equal('80', req.url.port)

        req = Request.new('get', 'http://example.com:8080')
        assert.is_equal('8080', req.url.port)
    end)

    it('can change the method', function()
        local req = Request.new('get', 'http://example.com')

        assert.is_equal('GET', req.method)
        req:setMethod('post')
        assert.is_equal('POST', req.method)
    end)

    it('cannot change the method to un unsupported method', function()
        local req = Request.new('get', 'http://example.com')

        assert.is_not_nil(req:setMethod('hello'))
        assert.is_equal('GET', req.method)
    end)

    it('can change the query', function()
        local chktbl = {}
        local sortQueryParams = function(qry)
            local arr = split(string.sub(qry, 2), '&', nil, true)

            table.sort(arr)
            return '?' .. table.concat(arr, '&')
        end
        local req = Request.new('get', 'http://example.com?hello=world')

        assert.is_equal('?hello=world', req.url.query)
        -- setup chktbl
        for idx, qry in ipairs({
            '?foo=bar&baz=qux',
            '?foo.falsy=false&foo.bar.truthy=true&foo.bar.str=qux&num=1',
        }) do
            chktbl[idx] = sortQueryParams(qry)
        end

        req:setQuery({
            foo = 'bar',
            baz = 'qux',
        })
        assert.is_equal(chktbl[1], sortQueryParams(req.url.query))

        -- set nested table
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
        assert.is_equal(chktbl[2], sortQueryParams(req.url.query))
    end)

    it('can remove the query', function()
        local req = Request.new('get', 'http://example.com?hello=world')

        assert.is_equal('?hello=world', req.url.query)
        req:setQuery(nil)
        assert.is_nil(req.url.query)

        req:setQuery({
            hello = 'world',
        })
        assert.is_equal('?hello=world', req.url.query)

        req:setQuery({})
        assert.is_nil(req.url.query)
    end)

    it('cannot pass query that are not either table or nil', function()
        local req = Request.new('get', 'http://example.com?hello=world')

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
            assert.has_error(function()
                req:setQuery(qry)
            end)
            assert.is_equal('?hello=world', req.url.query)
        end
    end)

    it('returns the request-line', function()
        local req = Request.new('get', 'http://example.com?hello=world')

        assert.is_equal('GET http://example.com/?hello=world HTTP/1.1\r\n',
                        req:line())
    end)

    it('returns the request-line with port-number', function()
        local req = Request.new('get', 'http://example.com:80?hello=world')

        assert.is_equal('GET http://example.com:80/?hello=world HTTP/1.1\r\n',
                        req:line())
    end)

    it('can send message via socket', function()
        local req = Request.new('get', 'http://example.com:80?hello=world')
        local sock, err = InetClient.new({
            host = '127.0.0.1',
            port = '5000',
        })
        local expect = 'GET http://example.com:80/?hello=world HTTP/1.1\r\n' ..
                           'host: example.com\r\n' ..
                           'user-agent: lua-net-http\r\n' .. '\r\n'
        local res, body

        assert.is_not_nil(sock)
        assert.is_nil(err)

        res = req:sendto(sock)
        assert.is_equal('table', type(res))

        body = res.body:read()
        assert.is_equal(expect, body)
    end)

    it('can send message', function()
        local req = Request.new('get', 'http://127.0.0.1:5000?hello=world')
        local expect = 'GET http://127.0.0.1:5000/?hello=world HTTP/1.1\r\n' ..
                           'host: 127.0.0.1:5000\r\n' ..
                           'user-agent: lua-net-http\r\n' .. '\r\n'
        local res = req:send()
        local body

        assert.is_equal('table', type(res))
        body = res.body:read()
        assert.is_equal(expect, body)
    end)

    it('always has body field', function()
        local req = Request.new('get', 'http://127.0.0.1:5000?hello=world')
        local res

        req.header:set('X-Response', 'no-content')
        res = req:send()
        assert.is_equal('table', type(res))
        assert.is_not_nil(res.body)
        assert.is_nil(res.body:read())
    end)

    it('returns send-error', function()
        local req = Request.new('get', 'http://127.0.0.1:5000?hello=world')
        local fakesock = {
            send = function()
                return nil, 'send-error', false
            end,
        }
        local res, err, timeout = req:sendto(fakesock)

        assert.is_nil(res)
        assert.is_equal('send-error', err)
        assert.is_falsy(timeout)

        -- replace original method
        local _sendto = req.sendto
        req.sendto = function(self)
            return _sendto(self, fakesock)
        end

        res, err, timeout = req:send()
        assert.is_nil(res)
        assert.is_equal('send-error', err)
        assert.is_falsy(timeout)
    end)

    it('returns recv-error', function()
        local req = Request.new('get', 'http://127.0.0.1:5000?hello=world')
        local fakesock = {
            send = function(_, data)
                return #data
            end,
            recv = function()
                return nil, 'recv-error', false
            end,
        }
        local res, err, timeout = req:sendto(fakesock)
        local sent = false

        assert.is_nil(res)
        assert.is_equal('recv-error', err)
        assert.is_falsy(timeout)

        -- replace original method
        local _sendto = req.sendto
        req.sendto = function(self)
            sent = true
            return _sendto(self, fakesock)
        end
        res, err, timeout = req:send()
        assert.is_truthy(sent)
        assert.is_nil(res)
        assert.is_equal('recv-error', err)
        assert.is_falsy(timeout)

        -- return connection error
        req = Request.new('get', 'http://127.0.0.1:5001?hello=world')
        sent = false
        res, err, timeout = req:send()
        assert.is_falsy(sent)
        assert.is_nil(res)
        assert.is_not_nil(err)
        assert.is_falsy(timeout)
    end)

    it('cannot communicate with non-tls server via tls connection', function()
        local req = Request.new('get', 'https://127.0.0.1:5000/hello')
        local res, err, timeout = req:send()

        assert.is_nil(res)
        assert.is_not_nil(err)
        assert.is_falsy(timeout)
    end)

    it('cannot communicate with non-secure tls server', function()
        local req = Request.new('get', 'https://127.0.0.1:5443/hello')
        local res, err, timeout = req:send()

        assert.is_nil(res)
        assert.is_not_nil(err)
        assert.is_falsy(timeout)
    end)

    it('can communicate with non-secure tls server on insecure mode', function()
        local req = Request.new('get', 'https://127.0.0.1:5443/hello', true)
        local res = req:send()
        local expect = 'GET https://127.0.0.1:5443/hello HTTP/1.1\r\n' ..
                           'host: 127.0.0.1:5443\r\n' ..
                           'user-agent: lua-net-http\r\n' .. '\r\n'
        local body

        assert.is_equal('table', type(res))
        body = res.body:read()
        assert.is_equal(expect, body)
    end)
end)

