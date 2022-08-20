require('luacov')
local testcase = require('testcase')
local new_reader = require('net.http.reader').new
local new_writer = require('net.http.writer').new
local new_content = require('net.http.content').new

function testcase.copy()
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
            self.msg = self.msg .. s
            return #s
        end,
    }
    local r = new_reader(rctx)
    local w = new_writer(wctx)
    local c = new_content(r, #rctx.msg)
    w:setbufsize(0)

    -- test that copy content
    assert.equal(c:size(), 12)
    local n, err = c:copy(w)
    assert.equal(n, 12)
    assert.equal(c:size(), 0)
    assert.is_nil(err)
    assert.equal(rctx.msg, '')
    assert.equal(wctx.msg, 'hello world!')

    -- test that return 0 if content is already consumed
    n, err = c:copy(w)
    assert.equal(n, 0)
    assert.is_nil(err)

    -- test that return error if writer returns error
    rctx.msg = 'hello'
    wctx.write = function(self, s)
        self.msg = s
        return #s, 'write-error'
    end
    c = new_content(r, #rctx.msg)
    n, err = c:copy(w, 100)
    assert.equal(n, 5)
    assert.equal(err, 'write-error')
    assert.equal(rctx.msg, '')
    assert.equal(wctx.msg, 'hello')

    -- test that throws an error if len is not uint
    err = assert.throws(new_content, r, true)
    assert.match(err, 'len must be uint')

    -- test that throws an error if chunksize is not uint
    c = new_content(r, #rctx.msg)
    err = assert.throws(c.copy, c, w, true)
    assert.match(err, 'chunksize must be uint greater than 0')

    -- test that throws an error if chunksize is not greater than 0
    err = assert.throws(c.copy, c, w, 0)
    assert.match(err, 'chunksize must be uint greater than 0')
end

function testcase.dispose()
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
    local r = new_reader(rctx)
    local c = new_content(r, #rctx.msg)

    -- test that dispose content
    assert.equal(c:size(), 12)
    local n, err = c:dispose()
    assert.equal(n, 12)
    assert.is_nil(err)

    -- test that return 0 if content is already consumed
    n, err = c:dispose()
    assert.equal(n, 0)
    assert.is_nil(err)
end

function testcase.read()
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
    local r = new_reader(rctx)
    local c = new_content(r, #rctx.msg)

    -- test that read content
    assert.equal(c:size(), 12)
    local s, err = c:read(5)
    assert.equal(s, 'hello')
    assert.is_nil(err)

    -- test that read content
    assert.equal(c:size(), 7)
    s, err = c:read()
    assert.equal(s, ' world!')
    assert.is_nil(err)

    -- test that return nil if content is already consumed
    s, err = c:read()
    assert.is_nil(s)
    assert.is_nil(err)

    -- test that throws an error if chunksize is not greater than 0
    err = assert.throws(c.read, c, 0)
    assert.match(err, 'chunksize must be uint greater than 0')
end

function testcase.readall()
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
    local r = new_reader(rctx)
    local c = new_content(r, #rctx.msg)

    -- test that read all content
    assert.equal(c:size(), 12)
    local s, err = c:readall()
    assert.equal(s, 'hello world!')
    assert.is_nil(err)
    assert.equal(c:size(), 0)

    -- test that return nil if content is already consumed
    s, err = c:readall()
    assert.is_nil(s)
    assert.is_nil(err)

    -- test that throws an error if chunksize is not greater than 0
    err = assert.throws(c.read, c, 0)
    assert.match(err, 'chunksize must be uint greater than 0')
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
            self.msg = self.msg .. s
            return #s
        end,
    }
    local r = new_reader(rctx)
    local w = new_writer(wctx)
    local c = new_content(r, #rctx.msg)
    w:setbufsize(0)

    -- test that write 100 bytes
    local n, err = c:write(w, 100)
    assert.equal(n, 12)
    assert.is_nil(err)
    assert.equal(rctx.msg, '')
    assert.equal(wctx.msg, 'hello world!')

    -- test that return 0 if content is already consumed
    n, err = c:write(w, 100)
    assert.equal(n, 0)
    assert.is_nil(err)
end

