local header = require('net.http.header')


describe('test net.http.header', function()
    local h

    setup(function()
        h = header.new()
    end)

    it('cannot set non-string name', function()
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

    it('cannot set nil value', function()
        assert.has_error(function()
            h:set('field-name')
        end)
    end)


end)

