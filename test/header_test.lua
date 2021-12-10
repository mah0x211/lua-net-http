require('luacov')
local format = string.format
local assert = require('assertex')
local testcase = require('testcase')
local header = require('net.http').header

function testcase.set()
    local h = header.new()

    -- test that sets non-nil field-value
    for _, val in ipairs({
        'hello',
        true,
        false,
        0,
        function()
        end,
        coroutine.create(function()
        end),
    }) do
        assert(h:set('field-name', val))
        assert.equal(h:get('field-name'), {
            tostring(val),
        })
    end

    -- test that sets multiple field-values
    assert(h:set('field-name', {
        'value1',
        'value2',
    }))
    assert.equal(h:get('field-name'), {
        'value1',
        'value2',
    })

    -- test that overwrite an existing value
    assert(h:set('field-name', {
        'new-value',
    }))
    assert.equal(h:get('field-name'), {
        'new-value',
    })

    -- test that the specified field-name will be deleted with a nil value
    assert(h:set('field-name'))
    assert.is_nil(h:get('field-name'))

    -- test that return an error with invalid field-name
    local ok, err = h:set('invalid field name', 1)
    assert.is_false(ok)
    assert.match(err, 'invalid header field-name')

    -- test that throws an error with invalid field-name
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
        assert.match(err,
                     format('#1 .+ [(]string expected, got %s', type(name)),
                     false)
    end
    err = assert.throws(function()
        h:set(nil, 'val')
    end)
    assert.match(err, '#1 .+ [(]string expected, got nil', false)
end

function testcase.add()
    local h = header.new()

    -- test that can append field-values to existing value
    assert(h:set('field-name', 'hello'))
    assert(h:add('field-name', 'world'))
    assert.equal(h:get('field-name'), {
        'hello',
        'world',
    })
    assert(h:add('field-name', {
        'foo',
        'bar',
    }))
    assert.equal(h:get('field-name'), {
        'hello',
        'world',
        'foo',
        'bar',
    })
end

function testcase.get()
    local h = header.new()

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

function testcase.has_transfer_encoding_chunked()
    local h = header.new()

    -- test that returns true if transfer-encoding header contains a 'chunked' value
    assert.is_false(h:has_transfer_encoding_chunked())
    assert(h:set('transfer-encoding', 'gzip'))
    assert.is_false(h:has_transfer_encoding_chunked())
    assert(h:add('transfer-encoding', 'chunked'))
    assert.is_true(h:has_transfer_encoding_chunked())
end

function testcase.has_content_length()
    local h = header.new()

    -- test that returns true and length if valid content-length header is exists
    assert.is_false(h:has_content_length())
    assert(h:set('Content-Length', 'foo'))
    assert.is_false(h:has_content_length())
    assert(h:add('Content-Length', '123'))
    local ok, len = h:has_content_length()
    assert.is_true(ok)
    assert.equal(len, 123)
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
    local arr = {}
    for k, v in h:pairs() do
        arr[#arr + 1] = k .. ': ' .. v
    end
    assert.equal(arr, {
        'field-foo: foo',
        'field-foo: bar',
        'field-foo: baz',
        'field-qux: quux',
    })

end

