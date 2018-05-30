local Server = require('net.http.server')
local Request = require('net.http.request')
local signal = require('signal')
local fork = require('process').fork
local getpid = require('process').getpid


describe('test net.http.server', function()
    local pidfile = 'child.pid'
    local sockfile = 'server.sock'
    local server


    local function setpid()
        local fh, err = io.open( pidfile, 'w+' )
        local pid = getpid()

        assert.is_nil( err )
        fh:write( pid )

        return pid
    end

    local function delpid( pid )
        if not pid then
            local fh, err = io.open( pidfile )

            if fh then
                local pid = fh:read('*a')

                fh:close()
                os.remove( pidfile )
                if string.find( pid, '%d+' ) then
                    pid = tonumber( pid )
                end
            end
        end

        if pid then
            signal.kill( signal.SIGKILL, pid )
        end
    end

    teardown(function()
        os.remove( sockfile )
        delpid()
    end)


    after_each(function()
        if server then
            server:close()
            server = nil
        end

        delpid()
        -- local pid = pidfile:read('*a')
        -- if string.find( pid, '%d+' ) then
        --     signal.kill( signal.SIGKILL, tonumber( pid ) )
        -- end
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
            path = sockfile,
        })
        assert.is_not_nil( server )
        assert.is_nil( err )
        err = server:listen()
        assert.is_nil( err )

        ok, err = os.remove( sockfile )
        assert.is_truthy( ok )
        assert.is_nil( err )
    end)

    it('can communicate with client', function()
        local pid, err = fork()

        assert.is_nil( err )
        -- client
        if pid == 0 then
            pid = setpid()

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

            delpid( pid )
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


    it('returns receive error', function()
        local err

        pid, err = fork()
        assert.is_nil( err )
        -- client
        if pid == 0 then
            pid = setpid()

            local req = Request.new( 'get', 'http://127.0.0.1:5000/hello' )
            -- set body as chunked data
            req:setBody('hello world!', 'client/message')
            req:send()

            delpid( pid )
        end

        server = Server.new({
            host = '127.0.0.1',
            port = '5000',
        })
        server:listen()
        local c = server:accept()
        assert.is_not_nil( c )


        -- replace original method
        c.recv = function( self )
            return nil, 'recv-error', false
        end

        local req, timeout
        req, err, timeout = c:recvRequest()
        assert.is_nil( req )
        assert.is_equal( 'recv-error', err )
        assert.is_falsy( timeout )
    end)
end)

