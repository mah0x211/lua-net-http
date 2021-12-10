local assert = require('assertex')
local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_tchar = parse.tchar

function testcase.parse_tchar()
    -- test that return OK
    local delimiters = [["(),/:;<=>?@[\]{}]]
    for i = 0x21, 0x7E do
        local c = string.char(i)
        if not string.find(delimiters, c, nil, true) then
            assert.equal(parse_tchar(c), parse.OK)
        end
    end

    -- test that return EAGAIN\
    assert.equal(parse_tchar(''), parse.EAGAIN)

    -- test that return EILSEQ
    for i = 0x0, 0x20 do
        assert.equal(parse_tchar(string.char(i)), parse.EILSEQ)
    end
    assert.equal(parse_tchar(string.char(0x7F)), parse.EILSEQ)

    delimiters = [["(),/:;<=>?@[\]{}]]
    for i = 0x21, 0x7E do
        local c = string.char(i)
        if string.find(delimiters, c, nil, true) then
            assert.equal(parse_tchar(c), parse.EILSEQ)
        end
    end
end
