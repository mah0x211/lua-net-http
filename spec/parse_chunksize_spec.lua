local Parse = require('net.http.parse')
local ParseChunkSize = Parse.chunksize

describe("test net.http.parse.chunksize", function()
    it('can parse chunksize line', function()
        for _, v in ipairs({
            {
                line = 'ffffffff\r\n',
                size = 0xffffffff,
                ext = {},
            },
            {
                line = '1e20 ; foo\r\n',
                size = 0x1e20,
                ext = {
                    foo = '',
                },
            },
            {
                line = '71e20 ; foo; bar = baz ; qux = "qu\\"ux"\r\n',
                size = 0x71e20,
                ext = {
                    foo = '',
                    bar = 'baz',
                    qux = 'qu\\"ux',
                },
            },
        }) do
            local ext = {}
            local size, cur = ParseChunkSize(v.line, ext)
            assert.are.equal(v.size, size)
            assert.are.equal(#v.line, cur)
            assert.are.same(v.ext, ext)
        end
    end)

    it("can limit the maximum length of chunksize-line", function()
        local size, cur = ParseChunkSize('71e20 ; foo; bar = baz\r\n', {}, 4)
        assert.are.equal(Parse.ELEN, size)
        assert.is_nil(cur)
    end)

    it("return EAGAIN", function()
        assert.are.equal(Parse.EAGAIN, ParseChunkSize('', {}))
        assert.are.equal(Parse.EAGAIN, ParseChunkSize('ff', {}))
        assert.are.equal(Parse.EAGAIN, ParseChunkSize('ff\r', {}))
        assert.are.equal(Parse.EAGAIN, ParseChunkSize('ff ', {}))
        assert.are.equal(Parse.EAGAIN, ParseChunkSize('ff ; ', {}))
        assert.are.equal(Parse.EAGAIN, ParseChunkSize('ff ; foo', {}))
    end)

    it("return EEOL", function()
        assert.are.equal(Parse.EEOL, ParseChunkSize('ff\r\r', {}))
    end)

    it("return EEMPTY", function()
        assert.are.equal(Parse.EEMPTY, ParseChunkSize('ff ; \r\n', {}))
    end)

    it("return EILSEQ", function()
        for _, line in ipairs({
            'xf\r\n', -- invalid hexdigit
            '1e20 \r', -- not ';' after BWS
            '1e20 ; foo bar\r', -- not ';' or '=' or CR after ext-name
            '1e20 ; foo = bar =', -- not ';' or CR after ext-value
            '1e20 ; foo = "bar\r', -- invalid quoted-string
            '1e20 ; foo = "ba"r"', -- invalid quoted-pair
            '1e20 ; foo = "bar\\\baz"', -- invalid quoted-pair
            '1e20 ; foo = "bar" =', -- not ';' or CR after ext-value
        }) do
            assert.are.equal(Parse.EILSEQ, ParseChunkSize(line, {}))
        end
    end)
end)

