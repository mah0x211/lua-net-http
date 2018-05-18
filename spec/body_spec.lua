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
                Body.new(data)
            end)
        end

        assert.has_error(function()
            Body.new(nil)
        end)
    end)

    it('can set string data', function()
        assert.has_no.errors(function()
            Body.new('hello')
        end)
    end)

    it('can set object that have a "read" function', function()
        assert.has_no.errors(function()
            Body.new({
                read = function() end
            })
        end)
    end)

    it('can get length of string data', function()
        local b = Body.new('hello')
        assert.are.equals(5, b:length())
    end)

    it('cannot get length of object data', function()
        local b = Body.new({
            read = function() end
        })
        assert.are.equals(nil, b:length())
    end)

    it('can read data', function()
        local b = Body.new('hello')
        assert.are.equals('hello', b:read())
        assert.are.equals(nil, b:length())

        b = Body.new({
            data = 'world',
            read = function( self )
                return self.data
            end
        })
        assert.are.equals('world', b:read())
    end)

    it('can read partial data', function()
        local b = Body.new('hello')
        assert.are.equals('he', b:read(2))
        assert.are.equals('llo', b:read(3))
        assert.are.equals(nil, b:read(1))
    end)
end)

