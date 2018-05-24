local request = require('net.http.request')
local split = require('string.split')
local tolower = string.lower
local toupper = string.upper


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

    it('can create request via helper functions', function()
        for _, method in ipairs({
            'connect',
            'delete',
            'get',
            'head',
            'options',
            'post',
            'put',
            'trace'
        }) do
            local req, err = request[method]( 'http://example.com/' )
            assert.is_not_nil( req )
            assert.is_nil( err )
            assert.is_equal( req.method, toupper( method ) )
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

    it('returns an error if uri without hostname', function()
        local req, err = request.new( 'get', 'http:///pathname' )
        assert.is_nil( req )
        assert.is_not_nil( err )
    end)

    it('can use a custom port-number', function()
        local req = request.new( 'get', 'http://example.com' )
        assert.is_equal( '80', req.url.port )

        req = request.new( 'get', 'http://example.com:8080' )
        assert.is_equal( '8080', req.url.port )
    end)

    it('can change the method', function()
        local req = request.new( 'get', 'http://example.com' )

        assert.is_equal( 'GET', req.method )
        req:setMethod('post')
        assert.is_equal( 'POST', req.method )
    end)

    it('cannot change the method to un unsupported method', function()
        local req = request.new( 'get', 'http://example.com' )

        assert.is_not_nil( req:setMethod('hello') )
        assert.is_equal( 'GET', req.method )
    end)

    it('can change the query', function()
        local chktbl = {}
        local sortQueryParams = function( qry )
            local arr = split( string.sub( qry, 2 ), '&', nil, true )

            table.sort( arr )
            return '?' .. table.concat( arr, '&' )
        end
        local req = request.new( 'get', 'http://example.com?hello=world' )

        assert.is_equal( '?hello=world', req.url.query )
        -- setup chktbl
        for idx, qry in ipairs({
            '?foo=bar&baz=qux',
            '?foo.falsy=false&foo.bar.truthy=true&foo.bar.str=qux&num=1',
        }) do
            chktbl[idx] = sortQueryParams( qry )
        end

        req:setQuery({
            foo = 'bar',
            baz = 'qux'
        })
        assert.is_equal( chktbl[1], sortQueryParams( req.url.query ) )

        -- set nested table
        req:setQuery({
            foo = {
                bar = {
                    str = 'qux',
                    truthy = true
                },
                falsy = false,
            },
            num = 1
        })
        assert.is_equal( chktbl[2], sortQueryParams( req.url.query ) )
    end)

    it('can remove the query', function()
        local req = request.new( 'get', 'http://example.com?hello=world' )

        assert.is_equal( '?hello=world', req.url.query )
        req:setQuery(nil)
        assert.is_nil( req.url.query )

        req:setQuery({
            hello = 'world'
        })
        assert.is_equal( '?hello=world', req.url.query )

        req:setQuery({})
        assert.is_nil( req.url.query )
    end)

    it('cannot pass query that are not either table or nil', function()
        local req = request.new( 'get', 'http://example.com?hello=world' )

        for _, qry in ipairs({
            'hello',
            true,
            false,
            0,
            1,
            -1,
            function()end,
            coroutine.create(function() end)
        }) do
            assert.has_error(function()
                req:setQuery(qry)
            end)
            assert.is_equal( '?hello=world', req.url.query )
        end
    end)

    it('returns the request-line', function()
        local req = request.new( 'get', 'http://example.com?hello=world' )

        assert.is_equal(
            'GET http://example.com/?hello=world HTTP/1.1\r\n', req:line()
        )
    end)

    it('returns the request-line with port-number', function()
        local req = request.new( 'get', 'http://example.com:80?hello=world' )

        assert.is_equal(
            'GET http://example.com:80/?hello=world HTTP/1.1\r\n', req:line()
        )
    end)

    it('can send message via socket', function()
        local req = request.new( 'get', 'http://example.com:80?hello=world' )
        local data
        local conn = setmetatable({},{
            __index = {
                send = function( _, val )
                    data = val
                    return #val
                end
            }
        })
        local expect = 'GET http://example.com:80/?hello=world HTTP/1.1\r\n' ..
                        'Host: example.com\r\n' ..
                        'User-Agent: lua-net-http\r\n' ..
                        '\r\n'

        assert.is_equal( #expect, req:sendto( conn ) )
        assert.is_equal( expect, data )
    end)
end)

