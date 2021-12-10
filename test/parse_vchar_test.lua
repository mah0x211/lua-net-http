local assert = require('assertex')
local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_vchar = parse.vchar

function testcase.parse_vchar()
    -- test that return OK
    for i = 0x21, 0x7E do
        local c = string.char(i)
        assert.equal(parse_vchar(c), parse.OK)
    end

    -- test that return EAGAIN
    assert.equal(parse_vchar(''), parse.EAGAIN)

    -- test that return EILSEQ
    for i = 0x0, 0x20 do
        assert.equal(parse_vchar(string.char(i)), parse.EILSEQ)
    end
    assert.equal(parse_vchar(string.char(0x7F)), parse.EILSEQ)
end

