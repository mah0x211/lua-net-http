require('luacov')
local testcase = require('testcase')
local header = require('net.http.header')

function testcase.new()
    -- test that create new header
    local h = header.new()
    assert.match(h, '^net.http.header: ', false)

    -- test that create new header with initial header
    h = header.new({
        hello = 'world',
        foo = {
            'bar',
            'baz',
        },
    })
    assert.equal(h:get('hello', true), {
        'world',
    })
    assert.equal(h:get('foo', true), {
        'bar',
        'baz',
    })

    -- test that throws an error if header argument is invald
    local err = assert.throws(header.new, 'hello')
    assert.match(err, 'header must be table')
end

function testcase.set()
    local h = header.new()

    -- test that throwssets non-nil field-value
    assert(h:set('field-name', 'hello'))
    assert.equal(h:size(), 1)
    assert.equal(h:get('field-name', true), {
        'hello',
    })

    -- test that sets multiple field-values
    assert(h:set('field-name', {
        'value1',
        'value2',
    }))
    assert.equal(h:size(), 1)
    assert.equal(h:get('field-name', true), {
        'value1',
        'value2',
    })

    -- test that overwrite an existing value
    assert(h:set('field-name', {
        'new-value',
    }))
    assert.equal(h:size(), 1)
    assert.equal(h:get('field-name', true), {
        'new-value',
    })

    -- test that the specified field-name will be deleted with a nil value
    assert(h:set('field-name'))
    assert.equal(h:size(), 0)
    assert.is_nil(h:get('field-name'))

    -- test that return an error with invalid field-name
    local err = assert.throws(function()
        h:set('field name', 1)
    end)
    assert.match(err, 'invalid header field-name')

    -- test that throws an error if key is not string
    for _, name in ipairs({
        true,
        0,
        {},
        function()
        end,
        coroutine.create(function()
        end),
    }) do
        err = assert.throws(function()
            h:set(name, 'val')
        end)
        assert.match(err, 'invalid key: .+ %(string expected', false)
    end
    err = assert.throws(function()
        h:set(nil, 'val')
    end)
    assert.match(err, 'invalid key: .+ %(string expected', false)
end

function testcase.add()
    local h = header.new()

    -- test that can append field-values to existing value
    assert(h:set('field-name', 'hello'))
    assert(h:add('field-name', 'world'))
    assert.equal(h:get('field-name', true), {
        'hello',
        'world',
    })
    assert(h:add('field-name', {
        'foo',
        'bar',
    }))
    assert.equal(h:size(), 1)
    assert.equal(h:get('field-name', true), {
        'hello',
        'world',
        'foo',
        'bar',
    })
end

function testcase.get()
    local h = header.new()
    assert(h:set('field-name', {
        'hello',
        'world',
    }))

    -- test that return last value
    assert.equal(h:get('field-name'), 'world')

    -- test that return values if all argument is true
    assert.equal(h:get('field-name', true), {
        'hello',
        'world',
    })

    -- test that cannot get field-value with non-string field-name
    for _, name in ipairs({
        true,
        false,
        0,
        function()
        end,
        coroutine.create(function()
        end),
    }) do
        local err = assert.throws(function()
            h:get(name)
        end)
        assert.match(err, 'key must be string')
    end

    local err = assert.throws(function()
        h:get()
    end)
    assert.match(err, 'key must be string')
end

function testcase.is_transfer_encoding_chunked()
    local h = header.new()

    -- test that returns true if transfer-encoding header contains a 'chunked' value
    assert.is_false(h:is_transfer_encoding_chunked())
    assert(h:set('transfer-encoding', 'gzip'))
    assert.is_false(h:is_transfer_encoding_chunked())
    assert(h:add('transfer-encoding', 'chunked'))
    assert.is_true(h:is_transfer_encoding_chunked())
end

function testcase.content_length()
    local h = header.new()

    -- test that return content-length if valid content-length header is exists
    assert.is_nil(h:content_length())
    assert(h:set('Content-Length', 'foo'))
    assert.is_nil(h:content_length())
    assert(h:add('Content-Length', '123'))
    assert.equal(h:content_length(), 123)
end

function testcase.content_type()
    local h = header.new()

    -- test that return nil
    assert.is_nil(h:content_type())

    -- test that return content-type
    h:set('content-type', 'foo/bar')
    local mime, err, params = h:content_type()
    assert.is_nil(err)
    assert.equal(mime, 'foo/bar')
    assert.is_nil(params)

    -- test that use last value
    h:add('content-type', 'baa/baz')
    mime, err, params = h:content_type()
    assert.is_nil(err)
    assert.equal(mime, 'baa/baz')
    assert.is_nil(params)

    -- test that parse parameters
    h:add('content-type',
          'baa/baz ; charset=hello ; Charset="utf-8"; format=flowed; delsp=yes ')
    mime, err, params = h:content_type()
    assert.is_nil(err)
    assert.equal(mime, 'baa/baz')
    assert.equal(params, {
        charset = 'utf-8',
        format = 'flowed',
        delsp = 'yes',
    })

    -- test that returns invalid media-type format error
    h:set('content-type', 'foo/b@r')
    mime, err, params = h:content_type()
    assert.match(err, 'invalid media-type format')
    assert.is_nil(mime)
    assert.is_nil(params)

    -- test that returns invalid media-type parameters format error
    h:set('content-type', 'foo/bar ; n@me=value')
    mime, err, params = h:content_type()
    assert.match(err, 'invalid media-type parameters format')
    assert.is_nil(mime)
    assert.is_nil(params)
end

function testcase.pairs()
    local h = header.new()

    -- test that iterate over the names and values of headers
    assert(h:set('field-foo', {
        'foo',
        'bar',
        'baz',
    }))
    assert(h:set('field-qux', {
        'quux',
    }))
    assert.equal(h:size(), 2)
    local arr = {}
    for _, k, v in h:pairs() do
        arr[#arr + 1] = k .. ': ' .. v
    end
    assert.equal(arr, {
        'Field-Foo: foo',
        'Field-Foo: bar',
        'Field-Foo: baz',
        'Field-Qux: quux',
    })
end

function testcase.write()
    local h = header.new()
    assert(h:set('field-foo', {
        'foo',
        'bar',
        'baz',
    }))
    assert(h:set('field-qux', {
        'quux',
    }))
    assert.equal(h:size(), 2)

    -- test that send headers
    local arr = {}
    local len, err = h:write({
        write = function(_, data)
            arr[#arr + 1] = data
            return true
        end,
    })
    assert.equal(len, #table.concat(arr))
    assert.is_nil(err)
    assert.equal(arr, {
        'Field-Foo: foo\r\n',
        'Field-Foo: bar\r\n',
        'Field-Foo: baz\r\n',
        'Field-Qux: quux\r\n',
        '\r\n',
    })

    -- test that return error
    arr = {}
    len, err = h:write({
        write = function()
            return false, 'write-error'
        end,
    })
    assert.equal(len, 0)
    assert.equal(err, 'write-error')
    assert.equal(arr, {})
end

