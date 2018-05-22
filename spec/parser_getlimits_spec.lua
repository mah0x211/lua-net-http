local getlimits = require('net.http.parser').getlimits;
math.randomseed(os.time())


describe("test net.http.parser.getlimits", function()
    it("returns the restriction table", function()
        local limits = getlimits()

        assert.is_equal( 'table', type( limits ) )
        for _, k in pairs({
            'REASON_LEN_MAX',
            'URI_LEN_MAX',
            'HEADER_LEN_MAX',
            'HEADER_NUM_MAX'
        }) do
            assert.is_equal( 'number', type( limits[k] ) )
        end
    end)

    it("can overwrite the restriction table with arguments", function()
        local n = math.random(1000)
        local def = {
            REASON_LEN_MAX = n + 1,
            URI_LEN_MAX = n + 2,
            HEADER_LEN_MAX = n + 3,
            HEADER_NUM_MAX = n + 4
        }
        local limits = getlimits( def )

        assert.is_equal( 'table', type( limits ) )
        for k, v in pairs( def ) do
            assert.is_equal( v, limits[k] )
        end
    end)

    it("cannot pass a non-table argument", function()
        for _, arg in ipairs({
            'str',
            0,
            1,
            true,
            false,
            function()end,
            coroutine.create(function()end)
        }) do
            assert.has_error(function()
                getlimits( arg )
            end)
        end
    end)

    it("accepts only unsigned integer values", function()
        for _, def in ipairs({
            { REASON_LEN_MAX = 'str' },
            { REASON_LEN_MAX = -1 },
            { REASON_LEN_MAX = true },
            { REASON_LEN_MAX = false },
            { REASON_LEN_MAX = {} },
            { REASON_LEN_MAX = function()end },
            { REASON_LEN_MAX = coroutine.create(function()end) },
        }) do
            assert.has_error(function()
                getlimits( def )
            end)
        end
    end)
end)


