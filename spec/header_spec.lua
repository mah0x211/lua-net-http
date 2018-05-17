local header = require('net.http.header')


describe('test net.http.header', function()
    local h

    setup(function()
        h = header.new()
    end)

    it('cannot set non-string field-name', function()
        for _, name in ipairs({
            true,
            0,
            {},
            function()end,
            coroutine.create(function()end),
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
            function()end,
            coroutine.create(function()end),
        }) do
            h:set('field-name', val)
            assert.is_equal(
                'field-name: ' .. tostring(val) .. '\r\n',
                h:get('field-name')
            )
        end
    end)

    it('can set multiple field-values', function()
        h:set('field-name', {
            'value1',
            'value2'
        })
        assert.is_equal(
            'field-name: value1\r\nfield-name: value2\r\n',
            h:get('field-name')
        )
    end)

    it('cannot delete the value with non-string field-name', function()
        for _, name in ipairs({
            true,
            0,
            {},
            function()end,
            coroutine.create(function()end),
        }) do
            assert.has_error(function()
                h:del(name)
            end)
        end
    end)

    it('can delete the specified field-name', function()
        h:set('field-name', 'value')
        assert.is_equal(
            'field-name: value\r\n',
            h:get('field-name')
        )
        assert.True( h:del('field-name') )
        assert.is_nil(h:get('field-name'))
    end)
end)

