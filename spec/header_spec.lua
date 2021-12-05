local header = require('net.http.header')

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

    it('cannot set nil field-value', function()
        assert.has_error(function()
            h:set('field-name')
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
            assert.is_equal('field-name: ' .. tostring(val) .. '\r\n',
                            h:get('field-name'))
        end
    end)

    it('can set multiple field-values', function()
        h:set('field-name', {
            'value1',
            'value2',
        })
        assert.is_equal('field-name: value1\r\nfield-name: value2\r\n',
                        h:get('field-name'))
        h:set('field-name', {
            'value1',
        })
        assert.is_equal('field-name: value1\r\n', h:get('field-name'))
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
        assert.is_equal('field-name: hello\r\n', h:get('field-name'))

        h:set('field-name', 'world', true)
        assert.is_equal('field-name: hello\r\nfield-name: world\r\n',
                        h:get('field-name'))

        h:set('field-name', {
            'foo',
            'bar',
        }, true)
        assert.is_equal('field-name: hello\r\nfield-name: world\r\n' ..
                            'field-name: foo\r\nfield-name: bar\r\n',
                        h:get('field-name'))
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
        h:set('field-bar', 'bar-1')
        h:set('field-baz', 'baz-1')
        h:set('field-baz', 'baz-2', true)
        h:set('field-qux', 'qux-1')
        h:set('field-bar', 'bar-2', true)
        h:set('field-qux', 'qux-2', true)
        h:set('field-qux', 'qux-3', true)
        h:set('field-baz', 'baz-3', true)
        h:set('field-qux', 'qux-4', true)
        assert.is_equal('field-foo: foo\r\n', h:get('field-foo'))
        assert.is_equal(table.concat({
            'field-bar: bar-1',
            'field-bar: bar-2',
        }, '\r\n') .. '\r\n', h:get('field-bar'))
        assert.is_equal(table.concat({
            'field-baz: baz-1',
            'field-baz: baz-2',
            'field-baz: baz-3',
        }, '\r\n') .. '\r\n', h:get('field-baz'))
        assert.is_equal(table.concat({
            'field-qux: qux-1',
            'field-qux: qux-2',
            'field-qux: qux-3',
            'field-qux: qux-4',
        }, '\r\n') .. '\r\n', h:get('field-qux'))

        assert.True(h:del('field-qux'))
        assert.is_equal('field-foo: foo\r\n', h:get('field-foo'))
        assert.is_equal(table.concat({
            'field-bar: bar-1',
            'field-bar: bar-2',
        }, '\r\n') .. '\r\n', h:get('field-bar'))
        assert.is_equal(table.concat({
            'field-baz: baz-1',
            'field-baz: baz-2',
            'field-baz: baz-3',
        }, '\r\n') .. '\r\n', h:get('field-baz'))
        assert.is_nil(h:get('field-qux'))

        assert.True(h:del('field-foo'))
        assert.is_nil(h:get('field-foo'))
        assert.is_equal(table.concat({
            'field-bar: bar-1',
            'field-bar: bar-2',
        }, '\r\n') .. '\r\n', h:get('field-bar'))
        assert.is_equal(table.concat({
            'field-baz: baz-1',
            'field-baz: baz-2',
            'field-baz: baz-3',
        }, '\r\n') .. '\r\n', h:get('field-baz'))
        assert.is_nil(h:get('field-qux'))

        assert.True(h:del('field-bar'))
        assert.is_nil(h:get('field-foo'))
        assert.is_nil(h:get('field-bar'))
        assert.is_equal(table.concat({
            'field-baz: baz-1',
            'field-baz: baz-2',
            'field-baz: baz-3',
        }, '\r\n') .. '\r\n', h:get('field-baz'))
        assert.is_nil(h:get('field-qux'))

        assert.True(h:del('field-baz'))
        assert.is_nil(h:get('field-foo'))
        assert.is_nil(h:get('field-bar'))
        assert.is_nil(h:get('field-baz'))
        assert.is_nil(h:get('field-qux'))
    end)
end)

