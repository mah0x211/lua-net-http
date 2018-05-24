local date = require('net.http.date')
local sleep = require('process').sleep


describe('test net.http.date', function()

    it('returns a date string', function()
        local d = date.now()

        assert.is_equal( 'string', type(d) )

        d = date.update()
        assert.is_equal( 'string', type(d) )
    end)

    it('returns a cached date string', function()
        local d1 = date.now()
        sleep(1)
        local d2 = date.now()

        assert.is_equal( d1, d2 )
    end)

    it('update a cached date string', function()
        local d1 = date.now()
        sleep(1)
        local d2 = date.update()

        assert.is_not_nil( d2 )
        assert.is_not_equal( d1, d2 )

        sleep(1)
        assert.is_equal( d2, date.now() )
    end)
end)

