local header = require('net.http').header

describe('test net.http.header', function()
    local h

    before_each(function()
        h = header.new()
    end)

    it('cannot set non-string field-name', function()
        for _, name in ipairs({
            true,
            0,
            {},
            function()
            end,
            coroutine.create(function()
            end),
        }) do
            assert.has_error(function()
                h:set(name, 'val')
            end)
        end

        assert.has_error(function()
            h:set(nil, 'val')
        end)
    end)

    it('can set non-nil field-value', function()
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
            h:set('field-name', val)
            assert.is_same({
                tostring(val),
            }, h:get('field-name'))
        end
    end)

    it('can set multiple field-values', function()
        h:set('field-name', {
            'value1',
            'value2',
        })
        assert.is_same({
            'value1',
            'value2',
        }, h:get('field-name'))

        h:set('field-name', {
            'value1',
        })
        assert.is_same({
            'value1',
        }, h:get('field-name'))
    end)

    it('cannot get field-value with non-string field-name', function()
        for _, name in ipairs({
            true,
            false,
            0,
            function()
            end,
            coroutine.create(function()
            end),
        }) do
            assert.has_error(function()
                h:get(name)
            end)
        end

        assert.has_error(function()
            h:get(nil)
        end)
    end)

    it('can append field-values to existing value', function()
        h:set('field-name', 'hello')
        assert.is_same({
            'hello',
        }, h:get('field-name'))

        h:add('field-name', 'world')
        assert.is_same({
            'hello',
            'world',
        }, h:get('field-name'))

        h:add('field-name', {
            'foo',
            'bar',
        }, true)
        assert.is_same({
            'hello',
            'world',
            'foo',
            'bar',
        }, h:get('field-name'))
    end)

    it('cannot delete the value with non-string field-name', function()
        for _, name in ipairs({
            true,
            0,
            {},
            function()
            end,
            coroutine.create(function()
            end),
        }) do
            assert.has_error(function()
                h:del(name)
            end)
        end
    end)

    it('can delete the specified field-name', function()
        h:set('field-foo', 'foo')
        assert.is_true(h:set('field-foo'))
        assert.is_nil(h:get('field-foo'))
        assert.is_false(h:set('field-foo'))
    end)

    it('can iterate through the fields', function()
        h:set('field-foo', {
            'foo',
            'bar',
            'baz',
        })
        h:set('field-qux', {
            'quux',
        })
        local arr = {}
        for k, v in h:pairs() do
            arr[#arr + 1] = k .. ': ' .. v
        end
        assert.are.same({
            'field-foo: foo',
            'field-foo: bar',
            'field-foo: baz',
            'field-qux: quux',
        }, arr)
    end)

    it('can check that it contains chunked transfer encoding header', function()
        assert.is_false(h:has_transfer_encoding_chunked())
        h:set('Transfer-Encoding', 'chunked')
        assert.is_true(h:has_transfer_encoding_chunked())
    end)

    it('can check that it contains valid content-length header', function()
        assert.is_false(h:has_content_length())
        h:set('Content-Length', 'foo')
        assert.is_false(h:has_content_length())
        h:add('Content-Length', '123')
        local ok, len = h:has_content_length()
        assert.is_true(ok)
        assert.is_equal(123, len)
    end)
end)

