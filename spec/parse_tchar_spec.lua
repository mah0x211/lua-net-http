local Parse = require('net.http.parse')
local ParseTChar = Parse.tchar

describe("test net.http.parse.tchar", function()
    it('return OK', function()
        local delimiters = [["(),/:;<=>?@[\]{}]]
        for i = 0x21, 0x7E do
            local c = string.char(i)
            if not string.find(delimiters, c, nil, true) then
                assert.are.equal(Parse.OK, ParseTChar(c))
            end
        end
    end)

    it('return EAGAIN', function()
        assert.are.equal(Parse.EAGAIN, ParseTChar(''))
    end)

    it("return EILSEQ", function()
        for i = 0x0, 0x20 do
            assert.are.equal(Parse.EILSEQ, ParseTChar(string.char(i)))
        end
        assert.are.equal(Parse.EILSEQ, ParseTChar(string.char(0x7F)))

        local delimiters = [["(),/:;<=>?@[\]{}]]
        for i = 0x21, 0x7E do
            local c = string.char(i)
            if string.find(delimiters, c, nil, true) then
                assert.are.equal(Parse.EILSEQ, ParseTChar(c))
            end
        end
    end)
end)

