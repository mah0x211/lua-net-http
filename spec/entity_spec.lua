local Entity = require('net.http.entity')
local header = require('net.http.header')
local EAGAIN = require('net.http.parser').EAGAIN


describe('test net.http.entity', function()
    local msg

    before_each(function()
        msg = setmetatable( Entity.init({
            header = header.new()
        }),{
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
        Entity.setBody( msg, 'hello' )
        assert.is_not_nil( msg.entity.body )
        assert.is_nil( msg.entity.ctype )
        assert.is_nil( msg.header:get('content-type') )
    end)

    it('set a message body and content-type header', function()
        Entity.setBody( msg, 'hello', 'text/plain' )
        assert.is_not_nil( msg.entity.body )
        assert.is_true( msg.entity.ctype )
        assert.is_equal(
            'Content-Type: text/plain\r\n',
            msg.header:get('content-type')
        )
    end)

    it('unset a message body', function()
        Entity.setBody( msg, 'hello', 'text/plain' )
        assert.is_not_nil( msg.entity.body )
        assert.is_true( msg.entity.ctype )
        assert.is_equal(
            'Content-Type: text/plain\r\n',
            msg.header:get('content-type')
        )
        Entity.unsetBody( msg )
        assert.is_nil( msg.entity.body )
        assert.is_nil( msg.entity.ctype )
        assert.is_nil( msg.header:get('content-type') )
    end)

    it('can send message', function()
        local data
        local sock = setmetatable({},{
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

        assert.is_equal( #expect, Entity.sendto( msg, sock ) )
        assert.is_equal( expect, data )
    end)

    it('can send message with string-data', function()
        local data
        local sock = setmetatable({},{
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

        Entity.setBody( msg, 'hello world!')
        assert.is_equal( #expect, Entity.sendto( msg, sock ) )
        assert.is_equal( expect, data )
    end)


    it('can send message with chunked-data', function()
        local chunks = {}
        local sock = setmetatable({},{
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

        Entity.setBody( msg, {
            read = function()
                n = n + 1
                if n > nchunk then
                    return nil
                end

                return 'chunked-data-' .. n
            end
        })
        assert.is_equal( #table.concat( expect ), Entity.sendto( msg, sock ) )
        assert.are.same( expect, chunks )
    end)

    it('can abort sending chunked messages', function()
        local nchunk = 3
        local n = 0
        local chunks = {}
        local sock = setmetatable({},{
            __index = {
                send = function( _, val )
                    if n == 3 then
                        return nil, 'abort'
                    end
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
        }

        Entity.setBody( msg, {
            read = function()
                n = n + 1
                if n > nchunk then
                    return nil
                end

                return 'chunked-data-' .. n
            end
        })

        local len, err = Entity.sendto( msg, sock )
        assert.is_equal( #table.concat( expect ), len )
        assert.are.same( expect, chunks )
        assert.is_equal( 'abort', err )
    end)

    it('can recv message', function()
        local chunks = {
            'not hello',
            'hello',
            ' ',
            'world',
            '!'
        }
        local idx = 0
        local sock = setmetatable({},{
            __index = {
                recv = function()
                    idx = idx + 1
                    if not chunks[idx] then
                        return nil, 'no data', false
                    end

                    return chunks[idx]
                end
            }
        })
        local parser = function( buf, entity )
            if buf == 'not hello' then
                return -2
            elseif idx < #chunks then
                return EAGAIN
            end

            entity.data = buf
            return #buf
        end
        local res, err, timeout, perr = Entity.recvfrom( msg, sock, parser )

        -- got parse error
        assert.is_nil( res )
        assert.is_nil( err )
        assert.is_nil( timeout )
        assert.is_equal( -2, perr )

        -- got response
        res, err, timeout = Entity.recvfrom( msg, sock, parser )
        assert.is_equal( 'table', type( res ) )
        assert.is_equal( 'table', type( res.header ) )
        assert.is_nil( err )
        assert.is_nil( timeout )
        assert.is_equal( 'hello world!', res.data )

        -- got error
        res, err, timeout = Entity.recvfrom( msg, sock, parser )
        assert.is_nil( res )
        assert.is_equal( 'no data', err )
        assert.is_falsy( timeout )
    end)
end)

