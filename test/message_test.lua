require('luacov')
local testcase = require('testcase')
local errno = require('errno')
local new_message = require('net.http.message').new
local new_reader = require('net.http.reader').new
local new_writer = require('net.http.writer').new
local new_content = require('net.http.content').new

function testcase.new()
    -- test that create new instance of net.http.message
    local m = assert(new_message())
    assert.match(tostring(m), '^net.http.message: ', false)
end

function testcase.set_version()
    local m = assert(new_message())

    -- test that set valid version
    for _, v in ipairs({
        0.9,
        1.0,
        1.1,
    }) do
        assert(m:set_version(v))
        assert.equal(m.version, v)
    end

    -- test that throws an error if argument is invalid version
    local ok, err = m:set_version(2.0)
    assert.is_false(ok)
    assert.equal(err.type, errno.EINVAL)

    -- test that throws an error if argument is not finite-number
    err = assert.throws(m.set_version, m)
    assert.match(err, 'version must be finite-number')
end

function testcase.set_content()
    local m = assert(new_message())

    -- test that set a content and reset content_sent field
    m.content_sent = 10
    m:set_content('foo')
    assert.equal(m.content, 'foo')
    assert.is_nil(m.content_sent)
end

function testcase.write_header()
    local rctx = {
        msg = 'hello world!',
        read = function(self, n)
            if self.err then
                return nil, self.err
            elseif #self.msg > 0 then
                local s = string.sub(self.msg, 1, n)
                self.msg = string.sub(self.msg, n + 1)
                return s
            end
        end,
    }
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
    local r = new_reader(rctx)
    local w = new_writer(wctx)
    local c = new_content(r, #rctx.msg)
    w:setbufsize(0)

    -- test that write header
    local m = assert(new_message())
    m.header:set('foo', 'bar')
    m.content = c
    assert(m:write_header(w))
    assert.equal(wctx.msg, table.concat({
        'Foo: bar',
        '',
        '',
    }, '\r\n'))

    -- test that cannot write header twice
    local err = assert.throws(m.write_header, m, w)
    assert.match(err, 'header has already been sent')
end

function testcase.write_content()
    local rctx = {
        msg = 'hello world!',
        read = function(self, n)
            if self.err then
                return nil, self.err
            elseif #self.msg > 0 then
                local s = string.sub(self.msg, 1, n)
                self.msg = string.sub(self.msg, n + 1)
                return s
            end
        end,
    }
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
    local r = new_reader(rctx)
    local w = new_writer(wctx)
    local c = new_content(r, #rctx.msg)
    w:setbufsize(0)

    -- test that write content
    local m = assert(new_message())
    m.header:set('foo', 'bar')
    assert(m:write_content(w, c))
    assert.equal(wctx.msg, table.concat({
        'Foo: bar',
        'Content-Length: 12',
        'Content-Type: application/octet-stream',
        '',
        'hello world!',
    }, '\r\n'))

    -- test that throws an error if content does not exists
    local err = assert.throws(m.write_content, m, w)
    assert.match(err, 'content must be net.http.content')
end

function testcase.write()
    local rctx = {
        msg = 'hello world!',
        read = function(self, n)
            if self.err then
                return nil, self.err
            elseif #self.msg > 0 then
                local s = string.sub(self.msg, 1, n)
                self.msg = string.sub(self.msg, n + 1)
                return s
            end
        end,
    }
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
    local r = new_reader(rctx)
    local w = new_writer(wctx)
    local c = new_content(r, #rctx.msg)
    w:setbufsize(0)

    -- test that write message
    local m = assert(new_message())
    m.header:set('foo', 'bar')
    m.content = c
    assert(m:write(w, 'foobar'))
    assert.equal(wctx.msg, table.concat({
        'Foo: bar',
        'Content-Length: 6',
        'Content-Type: application/octet-stream',
        '',
        'foobar',
    }, '\r\n'))

    -- test that can be written a string multiple times
    wctx.msg = ''
    assert(m:write(w, 'baz'))
    assert(m:write(w, 'qux'))
    assert.equal(wctx.msg, 'bazqux')

    -- test that write empty message
    wctx.msg = ''
    m = assert(new_message())
    m.header:set('foo', 'bar')
    assert(m:write(w))
    assert.equal(wctx.msg, table.concat({
        'Foo: bar',
        '',
        '',
    }, '\r\n'))

    -- test that throws an error if data is not string
    local err = assert.throws(m.write, m, w, true)
    assert.match(err, 'data must be string')
end

