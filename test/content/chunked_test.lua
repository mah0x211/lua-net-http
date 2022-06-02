require('luacov')
local testcase = require('testcase')
local new_reader = require('net.http.reader').new
local new_writer = require('net.http.writer').new
local new_chunked_content = require('net.http.content.chunked').new

function testcase.copy()
    local rctx = {
        msg = '',
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
    local r, w, c
    local resetctx = function(rmsg, wmsg)
        rctx.msg = rmsg or ''
        wctx.msg = wmsg or ''
        r = new_reader(rctx)
        w = new_writer(wctx)
        c = new_chunked_content(r)
        w:setbufsize(0)
    end

    -- test that copy chunked-encoded message
    resetctx(table.concat({
        '6',
        'hello ',
        '6; ext-name=ext-value; ext-name2',
        'world!',
        '0',
        'Trailer-Name: Trailer-Value',
        '\r\n',
    }, '\r\n'))
    local n, err = c:copy(w, 2)
    assert.equal(n, 12)
    assert.is_nil(err)
    assert.equal(rctx.msg, '')
    assert.equal(wctx.msg, 'hello world!')

    -- test that read with handler
    resetctx(table.concat({
        '6',
        'hello ',
        '6; ext-name=ext-value; ext-name2',
        'world!',
        '0; ext-name=last-ext-value; last-ext',
        'Trailer-Name: Trailer-Value',
        '\r\n',
    }, '\r\n'))
    local h = {
        exts = {},
        read_chunk = function(self, s, ext)
            self.exts[#self.exts + 1] = ext
            return s
        end,
        read_last_chunk = function(self, ext)
            self.exts[#self.exts + 1] = ext
        end,
        read_trailer = function(self, trailer)
            self.trailer = trailer
        end,
    }
    n, err = c:copy(w, 2, h)
    assert.equal(n, 12)
    assert.is_nil(err)
    assert.equal(rctx.msg, '')
    assert.equal(wctx.msg, 'hello world!')
    assert.contains(h, {
        exts = {
            {},
            {
                ['ext-name'] = 'ext-value',
                ['ext-name2'] = '',
            },
            {
                ['ext-name'] = 'last-ext-value',
                ['last-ext'] = '',
            },
        },
        trailer = {
            ['trailer-name'] = {
                idx = 1,
                key = 'Trailer-Name',
                val = {
                    'Trailer-Value',
                },
            },
        },
    })

    -- test that return an error if invalid chunk-size
    resetctx('5x\r\nhello\r\n0\r\n')
    n, err = c:copy(w)
    assert.is_nil(n)
    assert.match(err, 'illegal byte sequence')
    assert.equal(rctx.msg, '')
    assert.equal(wctx.msg, '')

    -- test that return an error if invalid terminator of chunk-size
    resetctx('5\rhello\r\n0\r\n')
    n, err = c:copy(w)
    assert.is_nil(n)
    assert.match(err, 'invalid end-of-line terminator')
    assert.equal(rctx.msg, '')
    assert.equal(wctx.msg, '')

    -- test that return an error if invalid terminator of chunk-data
    resetctx('5\r\nhello\r0\r\n')
    n, err = c:copy(w)
    assert.is_nil(n)
    assert.match(err, 'invalid end-of-line terminator')
    assert.equal(rctx.msg, '')
    assert.equal(wctx.msg, '')

    -- test that return an error if invalid terminator of trailer-part
    resetctx('0\r\nTrailer Name: Trailer-Value\r\n\r\n')
    n, err = c:copy(w)
    assert.is_nil(n)
    assert.match(err, 'invalid header field-name')
    assert.equal(rctx.msg, '')
    assert.equal(wctx.msg, '')

    -- test that aborted by handler.read_trailer
    resetctx('c\r\nhello world!\r\n0\r\nTrailer-Name: Trailer-Value\r\n\r\n')
    h.read_trailer = function()
        return 'abort by read_trailer'
    end
    n, err = c:copy(w, 5, h)
    assert.is_nil(n)
    assert.equal(err, 'abort by read_trailer')

    -- test that aborted by handler.read_last_chunk
    resetctx('c\r\nhello world!\r\n0\r\nTrailer-Name: Trailer-Value\r\n\r\n')
    h.read_last_chunk = function()
        return 'abort by read_last_chunk'
    end
    n, err = c:copy(w, 5, h)
    assert.is_nil(n)
    assert.equal(err, 'abort by read_last_chunk')

    -- test that aborted by handler.read_chunk
    resetctx('c\r\nhello world!\r\n0\r\nTrailer-Name: Trailer-Value\r\n\r\n')
    h.read_chunk = function()
        return nil, 'abort by read_chunk'
    end
    n, err = c:copy(w, 5, h)
    assert.is_nil(n)
    assert.equal(err, 'abort by read_chunk')

    -- test that throws an error if content is already consumed
    err = assert.throws(c.copy, c, w, true)
    assert.match(err, 'content is already consumed')

    -- test that throws an error if chunksize is not uint
    resetctx('c\r\nhello world!\r\n0\r\n\r\n')
    err = assert.throws(c.copy, c, w, true)
    assert.match(err, 'chunksize must be uint greater than 0')

    -- test that throws an error if chunksize is not greater than 0
    err = assert.throws(c.copy, c, w, 0)
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
    local r, w, c
    local resetctx = function(rmsg, wmsg)
        rctx.msg = rmsg or ''
        wctx.msg = wmsg or ''
        r = new_reader(rctx)
        w = new_writer(wctx)
        c = new_chunked_content(r)
        w:setbufsize(0)
    end

    -- test that write chunked-encoded message
    resetctx('hello world!')
    local n, err = c:write(w)
    assert.equal(n, 12)
    assert.is_nil(err)
    assert.equal(rctx.msg, '')
    assert.equal(wctx.msg, table.concat({
        string.format('%x', 12),
        'hello world!',
        '0',
        '\r\n',
    }, '\r\n'))

    -- test that write with handler
    resetctx('hello world!')
    local h = {
        write_chunk = function(self, wr, s)
            return wr:writeout(table.concat({
                string.format('%x; ext-%d', #s, #s),
                s,
                '',
            }, '\r\n'))
        end,
        write_last_chunk = function(self, wr)
            return wr:writeout('0\r\n')
        end,
        write_trailer = function(self, wr)
            return wr:writeout('Trailer-Name: Trailer-Value\r\n\r\n')
        end,
    }
    n, err = c:write(w, 5, h)
    assert.equal(n, 12)
    assert.is_nil(err)
    assert.equal(rctx.msg, '')
    assert.equal(wctx.msg, table.concat({
        '5; ext-5',
        'hello',
        '5; ext-5',
        ' worl',
        '2; ext-2',
        'd!',
        '0',
        'Trailer-Name: Trailer-Value',
        '\r\n',
    }, '\r\n'))

    -- test that aborted by handler.write_trailer
    resetctx('hello world!')
    h.write_trailer = function()
        return nil, 'abort by write_trailer', false
    end
    n, err = c:write(w, 5, h)
    assert.is_nil(n)
    assert.equal(err, 'abort by write_trailer')

    -- test that aborted by handler.write_last_chunk
    resetctx('hello world!')
    h.write_last_chunk = function()
        return nil, 'abort by write_last_chunk', false
    end
    n, err = c:write(w, 5, h)
    assert.is_nil(n)
    assert.equal(err, 'abort by write_last_chunk')

    -- test that aborted by handler.write_chunk
    resetctx('hello world!')
    h.write_chunk = function()
        return nil, 'abort by write_chunk', false
    end
    n, err = c:write(w, 5, h)
    assert.is_nil(n)
    assert.equal(err, 'abort by write_chunk')

    -- test that throws an error if content is already consumed
    err = assert.throws(c.write, c, w, true)
    assert.match(err, 'content is already consumed')

    -- test that throws an error if chunksize is not uint
    resetctx('hello world!')
    err = assert.throws(c.write, c, w, true)
    assert.match(err, 'chunksize must be uint greater than 0')

    -- test that throws an error if chunksize is not greater than 0
    err = assert.throws(c.write, c, w, 0)
    assert.match(err, 'chunksize must be uint greater than 0')
end

