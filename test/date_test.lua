require('luacov')
local testcase = require('testcase')
local sleep = require('testcase.timer').sleep
local date = require('net.http.date')

function testcase.now()
    -- test that now() returns a date string
    local d = assert.is_string(date.now())

    -- test that now() return same string
    sleep(1.2)
    assert.equal(date.now(), d)
end

function testcase.update()
    -- test that update() returns a date string
    assert.is_string(date.update())

    -- test that update a cached date string
    local now1 = assert.is_string(date.now())
    sleep(1.2)
    local update = assert.is_string(date.update())
    local now2 = assert.is_string(date.now())

    assert.not_equal(now1, update)
    assert.not_equal(now1, now2)
    assert.equal(update, now2)
end

