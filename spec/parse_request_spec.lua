local Parse = require('net.http.parse')
local ParseRequest = Parse.request

describe('test net.http.parse.request', function()
    it('can parse http 1.0 request message', function()
        local msg = 'GET /foo/bar/baz/qux HTTP/1.0\r\n' ..
                        'Host: example.com\r\n' .. '\r\n'
        local req = {header = {}}

        assert.are.equal(#msg, ParseRequest(msg, req))
        assert.are.same({
            method = 'GET',
            uri = '/foo/bar/baz/qux',
            version = 10,
            header = {host = 'example.com'},
        }, req)
    end)

    it('can parse http 1.1 request message', function()
        local msg = 'GET /foo/bar/baz/qux HTTP/1.1\r\n' ..
                        'Host: example.com\r\n' .. '\r\n'
        local req = {header = {}}

        assert.are.equal(#msg, ParseRequest(msg, req))
        assert.are.same({
            method = 'GET',
            uri = '/foo/bar/baz/qux',
            version = 11,
            header = {host = 'example.com'},
        }, req)
    end)

    it('cannot parse request message of unsupported version', function()
        local msg = 'GET /foo/bar/baz/qux HTTP/1.5\r\n' ..
                        'Host: example.com\r\n' .. '\r\n'

        assert.are.equal(Parse.EVERSION, ParseRequest(msg, {header = {}}))
    end)

    it('can parse request message without header', function()
        local msg = 'GET /foo/bar/baz/qux HTTP/1.1\r\n' .. '\r\n'
        local req = {header = {}}

        assert.are.equal(#msg, ParseRequest(msg, req))
        assert.are.same({
            method = 'GET',
            uri = '/foo/bar/baz/qux',
            version = 11,
            header = {},
        }, req)
    end)

    it('can parse request message lines that terminate by LF', function()
        local msg = 'GET /foo/bar/baz/qux HTTP/1.1\n' .. '\n'
        local req = {header = {}}

        assert.are.equal(#msg, ParseRequest(msg, req))
        assert.are.same({
            method = 'GET',
            uri = '/foo/bar/baz/qux',
            version = 11,
            header = {},
        }, req)
    end)

    it('cannot parse request message lines that not terminated by LF',
       function()
        local msg = 'GET /foo/bar/baz/qux HTTP/1.1\r' .. '\r'
        local req = {header = {}}

        assert.are.equal(Parse.EEOL, ParseRequest(msg, req))
    end)

    it('can limit the length of uri', function()
        local msg =
            'GET /foo/bar/baz/qux HTTP/1.0\n' .. 'Host: example.com\n' .. '\n'
        local req = {header = {}}

        assert.are.equal(Parse.ELEN, ParseRequest(msg, req, 10))
    end)

    it('returns EAGAIN to the incomplete message', function()
        local msg =
            'GET /foo/bar/baz/qux HTTP/1.0\n' .. 'Host: example.com\n' .. '\n'
        local req = {header = {}}

        for i = 1, #msg - 1 do
            assert.are.equal(Parse.EAGAIN,
                             ParseRequest(string.sub(msg, 1, i), {header = {}}))
        end
        assert.are.equal(#msg, ParseRequest(msg, req))
        assert.are.same({
            method = 'GET',
            uri = '/foo/bar/baz/qux',
            version = 10,
            header = {host = 'example.com'},
        }, req)
    end)

    it('can parse partial messages', function()
        local req = {header = {}}
        local msg = ''

        for i, chunk in ipairs({
            'GET /foo/bar/baz/qux HTTP/1.0\n', 'Host: example1.com\n',
            'Host: example2.com\n', 'Host: example3.com\n', '\n'}) do
            msg = msg .. chunk
            if i < 5 then
                assert.are.equal(Parse.EAGAIN, ParseRequest(msg, req))
            else
                assert.are.equal(#msg, ParseRequest(msg, req))
            end
        end

        assert.are.same({
            method = 'GET',
            uri = '/foo/bar/baz/qux',
            version = 10,
            header = {host = {'example1.com', 'example2.com', 'example3.com'}},
        }, req)
    end)

    it('parse only request-line', function()
        local line = 'GET /foo/bar/baz/qux HTTP/1.0\n'
        local msg = line .. 'Host: example.com\n' .. '\n'
        local req = {}

        assert.are.equal(#line, ParseRequest(msg, req))
        assert.are.same(
            {method = 'GET', uri = '/foo/bar/baz/qux', version = 10}, req)
    end)

    it('cannot parse request message for unsupported method', function()
        for _, method in ipairs({
            'GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'TRACE',
            'CONNECT'}) do
            local msg = method .. ' /foo/bar/baz/qux HTTP/1.1\r\n'
            local req = {}

            assert.are.equal(#msg, ParseRequest(msg, req))
            assert.are.same({
                method = method,
                uri = '/foo/bar/baz/qux',
                version = 11,
            }, req)
        end

        assert.are.equal(Parse.EMETHOD,
                         ParseRequest('FOO /foo/bar/baz/qux HTTP/1.1\r\n', {}))
    end)
end)

