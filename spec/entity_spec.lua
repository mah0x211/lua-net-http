local entity = require('net.http.entity')
local header = require('net.http.header')


describe('test net.http.entity', function()
    local msg

    before_each(function()
        msg = setmetatable({
            header = header.new()
        },{
            __index = {
                line = function()
                    return 'message-line\r\n'
                end
            }
        })
        msg.header:set('my-header', {
            'hello',
            'world'
        })
    end)

    it('set a message body', function()
        entity.setBody( msg, 'hello' )
        assert.is_not_nil( msg.body )
        assert.is_nil( msg.ctype )
        assert.is_nil( msg.header:get('content-type') )
    end)

    it('set a message body and content-type header', function()
        entity.setBody( msg, 'hello', 'text/plain' )
        assert.is_not_nil( msg.body )
        assert.is_true( msg.ctype )
        assert.is_equal(
            'Content-Type: text/plain\r\n',
            msg.header:get('content-type')
        )
    end)

    it('unset a message body', function()
        entity.setBody( msg, 'hello', 'text/plain' )
        assert.is_not_nil( msg.body )
        assert.is_true( msg.ctype )
        assert.is_equal(
            'Content-Type: text/plain\r\n',
            msg.header:get('content-type')
        )
        entity.unsetBody( msg )
        assert.is_nil( msg.body )
        assert.is_nil( msg.ctype )
        assert.is_nil( msg.header:get('content-type') )
    end)

    it('can send message', function()
        local data
        local conn = setmetatable({},{
            __index = {
                send = function( _, val )
                    data = val
                    return #val
                end
            }
        })
        local expect = 'message-line\r\n' ..
                        'my-header: hello\r\n' ..
                        'my-header: world\r\n' ..
                        '\r\n'

        assert.is_equal( #expect, entity.send( msg, conn ) )
        assert.is_equal( expect, data )
    end)

    it('can send message with string-data', function()
        local data
        local conn = setmetatable({},{
            __index = {
                send = function( _, val )
                    data = val
                    return #val
                end
            }
        })
        local expect = 'message-line\r\n' ..
                        'my-header: hello\r\n' ..
                        'my-header: world\r\n' ..
                        'Content-Length: 12\r\n' ..
                        '\r\n' ..
                        'hello world!'

        entity.setBody( msg, 'hello world!')
        assert.is_equal( #expect, entity.send( msg, conn ) )
        assert.is_equal( expect, data )
    end)


    it('can send message with chunked-data', function()
        local chunks = {}
        local conn = setmetatable({},{
            __index = {
                send = function( _, val )
                    chunks[#chunks + 1] = val
                    return #val
                end
            }
        })
        local expect = {
            [1] = 'message-line\r\n' ..
                    'my-header: hello\r\n' ..
                    'my-header: world\r\n' ..
                    'Transfer-Encoding: chunked\r\n' ..
                    '\r\n' ..
                    'e\r\n' ..
                    'chunked-data-1\r\n',
            [2] = 'e\r\n' ..
                    'chunked-data-2\r\n',
            [3] = 'e\r\n' ..
                    'chunked-data-3\r\n',
            [4] = '0\r\n\r\n'
        }
        local nchunk = 3
        local n = 0

        entity.setBody( msg, {
            read = function()
                n = n + 1
                if n > nchunk then
                    return nil
                end

                return 'chunked-data-' .. n
            end
        })
        assert.is_equal( #table.concat( expect ), entity.send( msg, conn ) )
        assert.are.same( expect, chunks )
    end)
end)

