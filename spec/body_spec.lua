local Body = require('net.http.body')


describe('test net.http.body', function()
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

    it('returns error', function()
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

