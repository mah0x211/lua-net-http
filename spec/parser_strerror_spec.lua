local Parser = require('net.http.parser')
local strerror = Parser.strerror


describe("test net.http.parser.strerror", function()
    it("returns the message string corresponding to error code", function()
        for k, errcode in pairs( Parser ) do
            if type( k ) == 'string' and type( errcode ) == 'number' then
                local msg = strerror( errcode )
                assert.is_equal( 'string', type( msg ) )
                assert.is_not_equal( 'unknown error code', msg )
            end
        end
    end)

    it("returns the unknown message string", function()
        local msg = strerror( 1.1 )
        assert.is_equal( 'string', type( msg ) )
        assert.is_equal( 'unknown error code', msg )
    end)
end)


