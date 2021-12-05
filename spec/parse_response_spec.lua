local Parse = require('net.http.parse')
local ParseResponse = Parse.response

describe('test net.http.parse.response', function()
    it('can parse http 1.0 response message', function()
        local msg = 'HTTP/1.0 200 OK\r\n' .. 'Server: example-server\r\n' ..
                        '\r\n'
        local res = {
            header = {},
        }

        assert.are.equal(#msg, ParseResponse(msg, res))
        assert.are.same({
            status = 200,
            reason = 'OK',
            version = 10,
            header = {
                server = 'example-server',
            },
        }, res)
    end)

    it('can parse http 1.1 response message', function()
        local msg = 'HTTP/1.1 200 OK\r\n' .. 'Server: example-server\r\n' ..
                        '\r\n'
        local res = {
            header = {},
        }

        assert.are.equal(#msg, ParseResponse(msg, res))
        assert.are.same({
            status = 200,
            reason = 'OK',
            version = 11,
            header = {
                server = 'example-server',
            },
        }, res)
    end)

    it('cannot parse response message of unsupported version', function()
        local msg = 'HTTP/1.5 200 OK\r\n' .. 'Server: example-server\r\n' ..
                        '\r\n'
        assert.are.equal(Parse.EVERSION, ParseResponse(msg, {}))
    end)

    it('can parse response message without header', function()
        local msg = 'HTTP/1.0 200 OK\r\n' .. '\r\n'
        local res = {
            header = {},
        }

        assert.are.equal(#msg, ParseResponse(msg, res))
        assert.are.same({
            status = 200,
            reason = 'OK',
            version = 10,
            header = {},
        }, res)
    end)

    it('can parse response message lines that terminate by LF', function()
        local msg = 'HTTP/1.1 200 OK\n' .. '\n'
        local res = {
            header = {},
        }

        assert.are.equal(#msg, ParseResponse(msg, res))
        assert.are.same({
            status = 200,
            reason = 'OK',
            version = 11,
            header = {},
        }, res)
    end)

    it('cannot parse response message lines that not terminated by LF',
       function()
        local msg = 'HTTP/1.1 200 OK\r' .. '\r'

        assert.are.equal(Parse.EEOL, ParseResponse(msg, {}))
    end)

    it("can limit the length of uri", function()
        local msg = 'HTTP/1.1 418 i\'m a tea pot\n' ..
                        'Server: example-server\n' .. '\n'

        assert.are.equal(Parse.EMSGLEN, ParseResponse(msg, {}, 10))
    end)

    it('returns EAGAIN to the incomplete message', function()
        local msg = 'HTTP/1.0 200 OK\r\n' .. 'Server: example-server\r\n' ..
                        '\r\n'
        local res = {
            header = {},
        }

        for i = 1, #msg - 1 do
            assert.are.equal(Parse.EAGAIN,
                             ParseResponse(string.sub(msg, 1, i), {
                header = {},
            }))
        end
        assert.are.equal(#msg, ParseResponse(msg, res))
        assert.are.same({
            status = 200,
            reason = 'OK',
            version = 10,
            header = {
                server = 'example-server',
            },
        }, res)
    end)

    it('parse only response-line', function()
        local line = 'HTTP/1.0 200 OK\r\n'
        local msg = line .. 'Server: example-server\n' .. '\n'
        local res = {}

        assert.are.equal(#line, ParseResponse(msg, res))
        assert.are.same({
            status = 200,
            reason = 'OK',
            version = 10,
        }, res)
    end)
end)

