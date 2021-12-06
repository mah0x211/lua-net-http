local Parse = require('net.http.parse')
local ParseCookieValue = Parse.cookie_value

describe("test net.http.parse.cookie_value", function()
    it('return OK', function()
        assert.are.equal(Parse.OK, ParseCookieValue(string.char(0x21)))
        for _, range in ipairs({
            {0x23, 0x2B},
            {0x2D, 0x3A},
            {0x3C, 0x5B},
            {0x5D, 0x7E},
        }) do
            for i = range[1], range[2] do
                assert.are.equal(Parse.OK, ParseCookieValue(string.char(i)))
            end
        end
    end)

    it("return EAGAIN", function()
        assert.are.equal(Parse.EAGAIN, ParseCookieValue(''))
    end)

    it("return EILSEQ", function()
        -- CTLs and whitespace
        for i = 0x0, 0x20 do
            assert.are.equal(Parse.EILSEQ, ParseCookieValue(string.char(i)))
        end
        -- DQUOTE
        assert.are.equal(Parse.EILSEQ, ParseCookieValue(string.char(0x22)))
        -- comma
        assert.are.equal(Parse.EILSEQ, ParseCookieValue(string.char(0x2C)))
        -- semicolon
        assert.are.equal(Parse.EILSEQ, ParseCookieValue(string.char(0x3B)))
        -- backslash
        assert.are.equal(Parse.EILSEQ, ParseCookieValue(string.char(0x5C)))
        assert.are.equal(Parse.EILSEQ, ParseCookieValue(string.char(0x7F)))
    end)
end)

