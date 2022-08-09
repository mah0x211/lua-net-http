require('luacov')
local testcase = require('testcase')
local sleep = require('testcase.timer').sleep
local errno = require('errno')
local date = require('net.http.date')
local new_message = require('net.http.message.response').new
local new_writer = require('net.http.writer').new

function testcase.new()
    -- test that create new instance of net.http.message.response
    local m = assert(new_message())
    assert.match(tostring(m), '^net.http.message.response: ', false)
    assert.equal(m.status, 200)
    assert.equal(m.version, 1.1)
end

function testcase.set_status()
    local m = assert(new_message())

    -- test that set valid status
    assert(m:set_status(100))
    assert.equal(m.status, 100)

    -- test that return EINVAL if argument is invalid status
    local ok, err = m:set_status(999)
    assert.is_false(ok)
    assert.equal(err.type, errno.EINVAL)

    -- test that throws an error if argument is not integer
    err = assert.throws(m.set_status, m)
    assert.match(err, 'code must be integer')
    assert.equal(m.status, 100)
end

function testcase.write_firstline()
    local wctx = {
        msg = '',
        write = function(self, s)
            if self.err then
                return nil, self.err
            end
            self.msg = self.msg .. s
            return #s
        end,
    }
    local w = new_writer(wctx)
    w:setbufsize(0)

    -- test that write firstline
    local now = date.now()
    local m = assert(new_message())
    m.status = 100
    m.version = 1.0
    wctx.msg = ''
    assert(m:write_firstline(w))
    assert.equal(wctx.msg, 'HTTP/1.0 100 Continue\r\n')
    assert.equal(m.header:get('Date'), now)

    -- test that write custome status-line
    sleep(1.2)
    now = date.update()
    m.status = 50
    m.version = 2.5
    m.reason = 'My Status'
    wctx.msg = ''
    assert(m:write_firstline(w))
    assert.equal(wctx.msg, 'HTTP/2.5 50 My Status\r\n')
    assert.equal(m.header:get('Date'), now)
end
