require('luacov')
local testcase = require('testcase')
local signal = require('signal')
local fork = require('process').fork
local getpid = require('process').getpid
local server = require('net.http.server')
local request = require('net.http.request')
local SOCKFILE = 'server.sock'
local PIDFILE = 'child.pid'

local function newproc()
    local pid = assert(fork())
    if pid == 0 then
        local fh = assert(io.open(PIDFILE, 'w+'))
        fh:write(getpid())
        fh:close()
        return true
    end

    return false
end

local function killproc()
    local fh = io.open(PIDFILE)

    if fh then
        os.remove(PIDFILE)

        local pid = fh:read('*a')
        fh:close()
        if string.find(pid, '%d+') then
            pid = tonumber(pid)
            if pid then
                signal.kill(signal.SIGKILL, pid)
            end
        end
    end
end

function testcase.after_each()
    os.remove(SOCKFILE)
    killproc()
end

function testcase.listen()
    -- test that listen 127.0.0.1:5000
    local s = assert(server.new({
        host = '127.0.0.1',
        port = '5000',
    }))
    s:close()

    -- test that listen ./server.sock
    s = assert(server.new({
        path = SOCKFILE,
    }))
    s:close()
end

function testcase.accept()
    -- client
    if newproc() then
        local req = request.new('get', 'http://127.0.0.1:5000/hello')
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
            end,
        }, 'client/message')
        req:send()
        return
    end

    -- test that communicate with client
    local s = assert(server.new({
        host = '127.0.0.1',
        port = '5000',
    }))
    -- accept client
    local c = assert(s:accept())
    c:close()
end

