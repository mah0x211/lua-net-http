local request = require('net.http.request')
local tolower = string.lower


describe('test net.http.request', function()
    it('cannot call with non-string method', function()
        for _, method in ipairs({
            true,
            0,
            {},
            function()end,
            coroutine.create(function()end),
        }) do
            assert.has_error(function()
                request.new( method, 'http://example.com/' )
            end)
        end
    end)

    it('returns an error if unsupported method is passed', function()
        local req, err = request.new( 'unknown-method', 'http://example.com/' )

        assert.is_nil( req )
        assert.is_not_nil( err )
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
            'TRACE'
        }) do
            local req, err = request.new( method, 'http://example.com/' )
            assert.is_not_nil( req )
            assert.is_nil( err )

            req, err = request.new( tolower( method ), 'http://example.com/' )
            assert.is_not_nil( req )
            assert.is_nil( err )
        end
    end)

    it('cannot call with non-string uri', function()
        for _, uri in ipairs({
            true,
            0,
            {},
            function()end,
            coroutine.create(function()end),
        }) do
            assert.has_error(function()
                request.new( 'get', uri )
            end)
        end
    end)

    it('returns an error if uri with no scheme is passed', function()
        local req, err = request.new( 'get', 'example.com' )
        assert.is_nil( req )
        assert.is_not_nil( err )
    end)

    it('returns an error if uri with unsupported scheme', function()
        local req, err = request.new( 'get', 'foo://example.com' )
        assert.is_nil( req )
        assert.is_not_nil( err )
    end)

    it('can use a custom port-number', function()
        local req, err = request.new( 'get', 'http://example.com' )
        assert.is_not_nil( req )
        assert.is_nil( err )
        assert.is_equal( '80', req.url.port )

        req, err = request.new( 'get', 'http://example.com:8080' )
        assert.is_not_nil( req )
        assert.is_nil( err )
        assert.is_equal( '8080', req.url.port )
    end)
end)

