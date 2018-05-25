local Body = require('net.http.body')


describe('test net.http.body.new', function()
    it('cannot set non-string data or object that does not have a "read" method', function()
        for _, data in ipairs({
            true,
            0,
            {},
            function()end,
            coroutine.create(function()end),
        }) do
            assert.has_error(function()
                Body.new( data )
            end)
        end

        assert.has_error(function()
            Body.new( nil )
        end)
    end)

    it('can set string data', function()
        assert.has_no.errors(function()
            Body.new( 'hello' )
        end)
    end)

    it('can set object that have "read" or "recv" function', function()
        assert.has_no.errors(function()
            Body.new({
                read = function() end
            })
        end)

        assert.has_no.errors(function()
            Body.new({
                recv = function() end
            })
        end)
    end)

    it('can get length of string data', function()
        local b = Body.new( 'hello' )
        assert.are.equals( 5, b:length() )
    end)

    it('cannot get length of object data', function()
        local b = Body.new({
            read = function() end
        })
        assert.are.equals( nil, b:length() )
    end)

    it('can read data', function()
        local b = Body.new( 'hello' )
        assert.are.equals( 'hello', b:read() )
        assert.are.equals( 'hello', b:read() )

        b = Body.new({
            data = 'world',
            read = function( self )
                return self.data
            end
        })
        assert.are.equals( 'world', b:read() )
        assert.are.equals( 'world', b:read() )

        b = Body.new({
            data = 'world',
            recv = function( self )
                return self.data
            end
        })
        assert.are.equals( 'world', b:read() )
        assert.are.equals( 'world', b:read() )
    end)

    it('can read data of specified length', function()
        local b = Body.new( 'hello' )
        assert.are.equals( 'he', b:read(2) )
        assert.are.equals( 'hel', b:read(3) )

        b = Body.new({
            data = 'hello',
            read = function( self, len )
                if len then
                    return string.sub( self.data, 1, len )
                end
                return self.data
            end
        })
        assert.are.equals( 'he', b:read(2) )
        assert.are.equals( 'hel', b:read(3) )

        b = Body.new({
            data = 'hello',
            recv = function( self, len )
                if len then
                    return string.sub( self.data, 1, len )
                end

                return self.data
            end
        })
        assert.are.equals( 'he', b:read(2) )
        assert.are.equals( 'hel', b:read(3) )
    end)

    it('can set the amount of data to read', function()
        local b = Body.new( 'hello', 3 )
        assert.are.equals( 3, b:length() )
        assert.are.equals( 'hel', b:read() )
        assert.is_nil( b:read() )

        b = Body.new({
            data = 'world',
            read = function( self )
                return self.data
            end
        }, 3 )
        assert.is_nil( b:length() )
        assert.are.equals('wor', b:read())
        assert.is_nil( b:read() )

        b = Body.new({
            data = 'hello world!',
            recv = function( self, len )
                if len > 2 then
                    local amount = math.floor( len / 2 )
                    local data = string.sub( self.data, 1, amount )
                    self.data = string.sub( self.data, amount + 1 )
                    return data
                end

                return self.data
            end
        }, 12 )
        assert.is_nil( b:length() )
        assert.are.equals('hello ', b:read())
        assert.are.equals('wor', b:read())
        assert.are.equals('l', b:read())
        assert.are.equals('d!', b:read())
        assert.is_nil( b:read() )
    end)

    it('cannot set non-numeric value to the amount argument', function()
        for _, amount in ipairs({
            'str',
            true,
            false,
            {},
            function()end,
            coroutine.create(function()end)
        }) do
            assert.has_error(function()
                Body.new( 'hello', amount )
            end)
        end
    end)

    it('returns errors of reader', function()
        local b = Body.new({
            data = 'hello',
            read = function()
                return nil, 'no-data', false
            end
        }, 3 )
        local data, err, timeout = b:read()

        assert.is_nil( data )
        assert.is_equal( 'no-data', err )
        assert.is_falsy( timeout )
    end)
end)


describe('test net.http.body.newContentReader', function()
    it('cannot pass non-numeric value to amount argument', function()
        assert.has_error(function()
            Body.newContentReader( 'hello' )
        end)
        for _, amount in ipairs({
            'str',
            true,
            false,
            {},
            function()end,
            coroutine.create(function()end),
        }) do
            assert.has_error(function()
                Body.newContentReader( 'hello', amount )
            end)
        end

        assert.has_error(function()
            Body.newContentReader( 'hello', nil )
        end)
    end)

    it('cannot pass value except string or nil to buf argument', function()
        for _, buf in ipairs({
            true,
            false,
            0,
            {},
            function()end,
            coroutine.create(function()end),
        }) do
            assert.has_error(function()
                Body.newContentReader( 'hello', 5, buf )
            end)
        end
    end)

    it('reads the specified amount of data', function()
        local amount
        local b = Body.newContentReader({
            data = 'hello world',
            read = function( self, len )
                amount = len
                return self.data
            end
        }, 5 )

        b:read()
        assert.is_equals( 5, amount )
    end)

    it('will use buf as already loaded data', function()
        local amount
        local b = Body.newContentReader({
            data = 'hello',
            read = function( self, len )
                amount = len
                return self.data
            end
        }, 5, 'he' )

        b:read()
        assert.is_equals( 3, amount )
    end)

    it('never calls a read function after all data has been loaded', function()
        local ncall = 0
        local b = Body.newContentReader({
            data = 'hello',
            read = function( self )
                ncall = ncall + 1
                return self.data
            end
        }, 5 )

        b:read()
        assert.is_equals( 1, ncall )
        b:read()
        assert.is_equals( 1, ncall )
    end)

    it('returns errors of reader', function()
        local b = Body.newContentReader({
            data = 'hello',
            read = function()
                return nil, 'no-data', false
            end
        }, 5 )
        local data, trailer, err, timeout = b:read()

        assert.is_nil( data )
        assert.is_nil( trailer )
        assert.is_equals( 'no-data', err )
        assert.is_falsy( timeout )

        data, trailer, err, timeout = b:read()
        assert.is_nil( data )
        assert.is_nil( trailer )
        assert.is_nil( err )
        assert.is_nil( timeout )
    end)
end)


describe('test net.http.body.newChunkedReader', function()
    it('cannot pass value except string or nil to buf argument', function()
        for _, buf in ipairs({
            true,
            false,
            0,
            {},
            function()end,
            coroutine.create(function()end),
        }) do
            assert.has_error(function()
                Body.newChunkedReader( 'hello', buf )
            end)
        end

        assert.has_no.errors(function()
            Body.newChunkedReader( 'hello', nil )
        end)
    end)

    it('calls the read function without len argument ', function()
        local amount
        local msg = 'hello'
        local chunks = table.concat({
            tonumber( #msg, 16 ),
            msg,
            '0',
            '\r\n',
        }, '\r\n' )
        local b = Body.newChunkedReader({
            read = function( _, len )
                amount = len
                return chunks
            end
        })
        local data = b:read()

        assert.is_equal( msg, data )
        assert.is_nil( amount )
    end)

    it('will use buf as already loaded data', function()
        local msg = 'hello'
        local chunks = table.concat({
            tonumber( #msg, 16 ),
            msg,
            '0',
            '\r\n',
        }, '\r\n' )
        local b = Body.newChunkedReader({
            read = function()
                return string.sub( chunks, 3 )
            end
        }, string.sub( chunks, 1, 2 ) )
        local data = b:read()

        assert.is_equal( msg, data )
    end)

    it('never calls a read function after all data has been loaded', function()
        local ncall = 0
        local msg = 'hello'
        local chunks = table.concat({
            tonumber( #msg, 16 ),
            msg,
            '0',
            '\r\n',
        }, '\r\n' )
        local b = Body.newChunkedReader({
            read = function( self )
                ncall = ncall + 1
                return chunks
            end
        })
        local data = b:read()

        assert.is_equal( msg, data )
        assert.is_equals( 1, ncall )
        b:read()
        assert.is_equal( msg, data )
        assert.is_equals( 1, ncall )
    end)

    it('returns a trailer-part', function()
        local msg = 'hello'
        local chunks = table.concat({
            tonumber( #msg, 16 ),
            msg,
            '0',
            'Hello: trailer-part1-1',
            'Hello: trailer-part1-2',
            'World: trailer-part2',
            '\r\n'
        }, '\r\n' )
        local b = Body.newChunkedReader({
            read = function( self )
                return chunks
            end
        })
        local data, trailer = b:read()

        assert.is_equal( msg, data )
        assert.are.same( {
            hello = {
                'trailer-part1-1',
                'trailer-part1-2'
            },
            world = 'trailer-part2',
        }, trailer )

        data, trailer = b:read()
        assert.is_equal( msg, data )
        assert.are.same( {
            hello = {
                'trailer-part1-1',
                'trailer-part1-2'
            },
            world = 'trailer-part2',
        }, trailer )
    end)

    it('returns errors of reader', function()
        local ncall = 0
        local msg = 'hello'
        local chunks = table.concat({
            tonumber( #msg, 16 ),
            msg,
            '0',
            'Hello: trailer-part1-1',
            'Hello: trailer-part1-2',
            'World: trailer-part2',
            '\r\n'
        }, '\r\n' )
        local b, data, trailer, err, timeout

        -- failed by reading data
        b = Body.newChunkedReader({
            read = function( self )
                return nil, 'no-data', false
            end
        })
        data, trailer, err, timeout = b:read()
        assert.is_nil( data )
        assert.is_nil( trailer )
        assert.is_equals( 'no-data', err )
        assert.is_falsy( timeout )

        -- failed by reading invalid chunked data
        b = Body.newChunkedReader({
            read = function( self )
                return 'xyz\r\nhello'
            end
        })
        data, trailer, err, timeout = b:read()
        assert.is_nil( data )
        assert.is_nil( trailer )
        assert.is_equals( 'invalid chunk-size', err )
        assert.is_falsy( timeout )

        -- failed by reading the partial data
        b = Body.newChunkedReader({
            read = function( self )
                if ncall == 1 then
                    return nil, 'no-content', false
                end

                ncall = 1
                return string.sub( chunks, 1, 3 )
            end
        })
        data, trailer, err, timeout = b:read()
        assert.is_equal( 1, ncall )
        assert.is_nil( data )
        assert.is_nil( trailer )
        assert.is_equals( 'no-content', err )
        assert.is_falsy( timeout )

        -- failed by reading the partial data of trailer-part
        ncall = 0
        b = Body.newChunkedReader({
            read = function( self )
                if ncall == 1 then
                    return nil, 'no trailer-content', false
                end

                ncall = 1
                return string.sub(
                    chunks, 1, string.find( chunks, 'trailer-part1-1', 1, true )
                )
            end
        })
        data, trailer, err, timeout = b:read()
        assert.is_equal( 1, ncall )
        assert.is_nil( data )
        assert.is_nil( trailer )
        assert.is_equals( 'no trailer-content', err )
        assert.is_falsy( timeout )
    end)
end)

