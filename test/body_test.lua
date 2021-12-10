require('luacov')
local assert = require('assertex')
local testcase = require('testcase')
local body = require('net.http.body')

function testcase.new()
    -- test that create new body instance
    for _, v in ipairs({
        'hello',
        {
            read = function()
            end,
        },
        {
            recv = function()
            end,
        },
    }) do
        assert(body.new(v))
    end

    -- test that throws an error with invalid data
    for _, data in ipairs({
        true,
        0,
        {},
        function()
        end,
        coroutine.create(function()
        end),
    }) do
        assert.throws(function()
            body.new(data)
        end)
    end

    assert.throws(function()
        body.new(nil)
    end)
end

function testcase.length()
    -- test that returns length of string data
    local b = assert(body.new('hello'))
    assert.equal(b:length(), 5)

    -- test that returns nil
    b = assert(body.new({
        read = function()
        end,
    }))
    assert.is_nil(b:length())
end

function testcase.read()
    local read = function(self, len)
        local s = not len and self.data or string.sub(self.data, 1, len)
        return s .. ' via read method'
    end
    local recv = function(self, len)
        local s = not len and self.data or string.sub(self.data, 1, len)
        return s .. ' via recv method'
    end

    -- test that read data
    for _, v in ipairs({
        {
            arg = 'hello',
            cmp = 'hello',
        },
        {
            -- read data of specified length
            arg = 'hello',
            cmp = 'hel',
            nread = 3,
        },
        {
            -- read data via read method
            arg = {
                data = 'hello',
                read = read,
            },
            cmp = 'hel via read method',
            nread = 3,
        },
        {
            -- read data via recv method
            arg = {
                data = 'hello',
                recv = recv,
            },
            cmp = 'hel via recv method',
            nread = 3,
        },
    }) do
        local b = assert(body.new(v.arg))
        assert.equal(b:read(v.nread), v.cmp)
    end

    -- test that sets the amount of data to read
    local b = body.new('hello', 3)
    assert.equal(b:length(), 3)
    assert.equal(b:read(), 'hel')
    assert.is_nil(b:read())
    b = body.new({
        data = 'world',
        read = function(self)
            return self.data
        end,
    }, 3)
    assert.is_nil(b:length())
    assert.equal(b:read(), 'wor')
    assert.is_nil(b:read())

    b = body.new({
        data = 'hello world!',
        recv = function(self, len)
            if len > 2 then
                local amount = math.floor(len / 2)
                local data = string.sub(self.data, 1, amount)
                self.data = string.sub(self.data, amount + 1)
                return data
            end

            return self.data
        end,
    }, 12)
    assert.is_nil(b:length())
    assert.equal(b:read(), 'hello ')
    assert.equal(b:read(), 'wor')
    assert.equal(b:read(), 'l')
    assert.equal(b:read(), 'd!')
    assert.is_nil(b:read())

    -- test that return an error from reader
    b = body.new({
        data = 'hello',
        read = function()
            return nil, 'no-data', false
        end,
    }, 3)
    local data, err, timeout = b:read()
    assert.is_nil(data)
    assert.equal(err, 'no-data')
    assert.is_false(timeout)

    -- test that throw error with invalid amount arguments
    for _, amount in ipairs({
        'str',
        true,
        false,
        {},
        function()
        end,
        coroutine.create(function()
        end),
    }) do
        assert.throws(function()
            body.new('hello', amount)
        end)
    end
end

function testcase.nil_reader()
    -- test that always returns nil
    local b = body.newNilReader()
    assert.is_nil(b:read())
    assert.is_nil(b:length())
end

function testcase.content_reader()
    -- test that reads the specified amount of data
    local amount
    local b = body.newContentReader({
        data = 'hello world',
        read = function(self, len)
            amount = len
            return self.data
        end,
    }, nil, 5)
    assert.equal(b:read(), 'hello')
    assert.equal(amount, 5)

    -- test that the passed data is used as already loaded data
    b = body.newContentReader({
        data = 'hello',
        read = function(self, len)
            amount = len
            return self.data
        end,
    }, 'he', 5)
    assert.equal(b:read(), 'hehel')
    assert.equal(amount, 3)

    -- test that read function is never called after all data has been loaded
    local ncall = 0
    b = body.newContentReader({
        data = 'hello',
        read = function(self)
            ncall = ncall + 1
            return self.data
        end,
    }, nil, 5)
    b:read()
    assert.equal(ncall, 1)
    -- test that returns cached data
    assert.equal(b:read(), 'hello')
    assert.equal(ncall, 1)

    -- test that returns errors of reader
    ncall = 0
    b = body.newContentReader({
        data = 'hello',
        read = function()
            ncall = ncall + 1
            return nil, 'no-data', false
        end,
    }, nil, 5)
    local bdata, trailer, err, timeout = b:read()
    assert.equal(ncall, 1)
    assert.is_nil(bdata)
    assert.is_nil(trailer)
    assert.equal(err, 'no-data')
    assert.is_false(timeout)

    -- test that read function is never called after returninig an error
    bdata, trailer, err, timeout = b:read()
    assert.equal(ncall, 1)
    assert.is_nil(bdata)
    assert.is_nil(trailer)
    assert.is_nil(err)
    assert.is_nil(timeout)

    -- test that throws an error with invalid amount argument
    for _, v in ipairs({
        'str',
        true,
        false,
        {},
        function()
        end,
        coroutine.create(function()
        end),
    }) do
        assert.throws(function()
            body.newContentReader('hello', nil, v)
        end)
    end
    assert.throws(function()
        body.newContentReader('hello')
    end)

    -- test that throws an error with invalid data argument
    for _, v in ipairs({
        true,
        false,
        0,
        {},
        function()
        end,
        coroutine.create(function()
        end),
    }) do
        assert.throws(function()
            body.newContentReader('hello', v, 5)
        end)
    end
end

function testcase.chunk_reader()
    -- test that the passed data is used as already loaded data
    local msg = 'hello'
    local data = table.concat({
        string.format('%02x', #msg),
        msg,
        '0',
        '\r\n',
    }, '\r\n')
    local b = body.newChunkedReader({
        read = function()
            return string.sub(data, 3)
        end,
    }, string.sub(data, 1, 2))
    assert.equal(b:read(), msg)

    -- test that calls the read function without len argument
    local amount
    b = body.newChunkedReader({
        read = function(_, len)
            amount = len
            return data
        end,
    })
    assert.equal(b:read(), msg)
    assert.is_nil(amount)

    -- test that read function is never called after all data has been loaded
    local ncall = 0
    b = body.newChunkedReader({
        read = function()
            ncall = ncall + 1
            return data
        end,
    })
    assert.equal(b:read(), msg)
    assert.equal(ncall, 1)
    -- test that returns cached data
    assert.equal(b:read(), msg)
    assert.equal(ncall, 1)

    -- test that returns a trailer-part
    data = table.concat({
        string.format('%02x', #msg),
        msg,
        '0',
        'Hello: trailer-part1-1',
        'Hello: trailer-part1-2',
        'World: trailer-part2',
        '\r\n',
    }, '\r\n')
    ncall = 0
    b = body.newChunkedReader({
        read = function()
            ncall = ncall + 1
            return data
        end,
    })
    local bdata, trailer, err, timeout = b:read()
    assert.equal(ncall, 1)
    assert.equal(bdata, msg)
    assert.equal(trailer, {
        hello = {
            'trailer-part1-1',
            'trailer-part1-2',
        },
        world = 'trailer-part2',
    })
    assert.is_nil(err)
    assert.is_nil(timeout)

    -- test that returns cached data
    bdata, trailer, err, timeout = b:read()
    assert.equal(ncall, 1)
    assert.equal(bdata, msg)
    assert.equal(trailer, {
        hello = {
            'trailer-part1-1',
            'trailer-part1-2',
        },
        world = 'trailer-part2',
    })
    assert.is_nil(err)
    assert.is_nil(timeout)

    -- test that return an error from reader
    b = body.newChunkedReader({
        read = function()
            return nil, 'no-data', false
        end,
    })
    bdata, trailer, err, timeout = b:read()
    assert.is_nil(bdata)
    assert.is_nil(trailer)
    assert.equal(err, 'no-data')
    assert.is_false(timeout)

    -- test that read function is never called after returninig an error
    bdata, trailer, err, timeout = b:read()
    assert.equal(ncall, 1)
    assert.is_nil(bdata)
    assert.is_nil(trailer)
    assert.is_nil(err)
    assert.is_nil(timeout)

    -- test that failed to read invalid chunked data
    b = body.newChunkedReader({
        read = function()
            return 'xyz\r\nhello'
        end,
    })
    bdata, trailer, err, timeout = b:read()
    assert.is_nil(bdata)
    assert.is_nil(trailer)
    assert.equal(err, 'invalid chunk-size')
    assert.is_nil(timeout)

    -- test that failed to read the partial data
    b = body.newChunkedReader({
        read = function()
            if ncall == 1 then
                return nil, 'no-content', false
            end
            ncall = 1
            return string.sub(data, 1, 3)
        end,
    })
    bdata, trailer, err, timeout = b:read()
    assert.equal(ncall, 1)
    assert.is_nil(bdata)
    assert.is_nil(trailer)
    assert.equal(err, 'no-content')
    assert.is_false(timeout)

    -- failed by reading the partial data of trailer-part
    ncall = 0
    b = body.newChunkedReader({
        read = function()
            if ncall == 1 then
                return nil, 'no trailer-content', false
            end

            ncall = 1
            return string.sub(data, 1,
                              string.find(data, 'trailer-part1-1', 1, true))
        end,
    })
    bdata, trailer, err, timeout = b:read()
    assert.equal(ncall, 1)
    assert.is_nil(bdata)
    assert.is_nil(trailer)
    assert.equal(err, 'no trailer-content')
    assert.is_false(timeout)

    -- failed by reading the invalid trailer-part
    b = body.newChunkedReader({
        read = function()
            return table.concat({
                string.format('%02x', #msg),
                msg,
                '0',
                'Hello trailer-part1-1',
                'Hello: trailer-part1-2',
                'World: trailer-part2',
                '\r\n',
            }, '\r\n')
        end,
    })
    bdata, trailer, err, timeout = b:read()
    assert.is_nil(bdata)
    assert.is_nil(trailer)
    assert.match(err, 'invalid .+ field%-name', false)
    assert.is_nil(timeout)

    -- test that throws an error with invalid data argument
    for _, v in ipairs({
        true,
        false,
        0,
        {},
        function()
        end,
        coroutine.create(function()
        end),
    }) do
        assert.throws(function()
            body.newChunkedReader('hello', v)
        end)
    end
end

function testcase.new_reader_from_header()
    -- test that returns the result of newNilReader
    local b = body.newReaderFromHeader({}, 'hello')
    assert.is_nil(b:length())
    assert.is_nil(b:read())

    -- test that returns the result of newContentReader
    b = body.newReaderFromHeader({
        ['content-length'] = '5',
    }, 'hello')
    assert.equal(b:length(), 5)
    assert.equal(b:read(), 'hello')

    -- test that returns the result of newChunkedReader
    b = body.newReaderFromHeader({
        ['transfer-encoding'] = 'chunked',
    }, '5\r\nhello\r\n0\r\nhello: world\r\n\r\n')
    local bdata, trailer = b:read()
    assert.is_nil(b:length())
    assert.equal(bdata, 'hello')
    assert.equal(trailer, {
        hello = 'world',
    })

    -- test that throws an error with invalid header argument
    for _, v in ipairs({
        'str',
        true,
        false,
        0,
        function()
        end,
        coroutine.create(function()
        end),
    }) do
        local err = assert.throws(function()
            body.newReaderFromHeader(v, 'hello')
        end)
        assert.match(err, 'header must be table')
    end
    local err = assert.throws(function()
        body.newReaderFromHeader(nil, 'hello')
    end)
    assert.match(err, 'header must be table')
end
