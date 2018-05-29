local Server = require('net.http.server')
local Request = require('net.http.request')
local signal = require('signal')
local fork = require('process').fork


describe('test net.http.server', function()
    local server, pid

    after_each(function()
        if server then
            server:close()
            server = nil
        end

        if pid then
            signal.kill( signal.SIGKILL, pid )
            pid = nil
        end
    end)

    it('can listen 127.0.0.1:5000', function()
        local err

        server, err = Server.new({
            host = '127.0.0.1',
            port = '5000',
        })
        assert.is_not_nil( server )
        assert.is_nil( err )

        err = server:listen()
        assert.is_nil( err )
    end)

    it('can listen ./server.sock', function()
        local ok, err

        server, err = Server.new({
            path = './server.sock',
        })
        assert.is_not_nil( server )
        assert.is_nil( err )
        err = server:listen()
        assert.is_nil( err )

        ok, err = os.remove( './server.sock' )
        assert.is_truthy( ok )
        assert.is_nil( err )
    end)

    it('can communicate with client', function()
        local err

        pid, err = fork()
        assert.is_nil( err )
        -- client
        if pid == 0 then
            local req = Request.new( 'get', 'http://127.0.0.1:5000/hello' )
            local idx = 0
            local chunks = {
                'hello',
                ' ',
                'world',
                '!',
            }
            -- set body as chunked data
            req:setBody({
                read = function()
                    idx = idx + 1
                    return chunks[idx]
                end
            }, 'client/message')
            req:send()
            return
        end

        server = Server.new({
            host = '127.0.0.1',
            port = '5000',
        })
        server:listen()
        local c = server:accept()
        assert.is_not_nil( c )

        local req, timeout
        req, err, timeout = c:recvRequest()
        assert.is_not_nil( req )
        assert.is_nil( err )
        assert.is_nil( timeout )
        assert.is_equal( 'hello world!', req.body:read() )
    end)
end)

