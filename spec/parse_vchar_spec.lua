local Parse = require('net.http.parse')
local ParseVChar = Parse.vchar

describe("test net.http.parse.vchar", function()
    it('return OK', function()
        for i = 0x21, 0x7E do
            local c = string.char(i)
            assert.are.equal(Parse.OK, ParseVChar(c))
        end
    end)

    it('return EAGAIN', function()
        assert.are.equal(Parse.EAGAIN, ParseVChar(''))
    end)

    it("return EILSEQ", function()
        for i = 0x0, 0x20 do
            assert.are.equal(Parse.EILSEQ, ParseVChar(string.char(i)))
        end
        assert.are.equal(Parse.EILSEQ, ParseVChar(string.char(0x7F)))
    end)
end)

