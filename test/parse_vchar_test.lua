local testcase = require('testcase')
local assert = require('assert')
local parse = require('net.http.parse')
local parse_vchar = parse.vchar

function testcase.parse_vchar()
    -- test that true
    for i = 0x21, 0x7E do
        local c = string.char(i)
        assert(parse_vchar(c))
    end

    -- test that return EAGAIN
    local ok, err = parse_vchar('')
    assert.is_false(ok)
    assert.equal(err.type, parse.EAGAIN)

    -- test that return EILSEQ
    for i = 0x0, 0x20 do
        ok, err = parse_vchar(string.char(i))
        assert.is_false(ok)
        assert.equal(err.type, parse.EILSEQ)
    end
    ok, err = parse_vchar(string.char(0x7F))
    assert.is_false(ok)
    assert.equal(err.type, parse.EILSEQ)
end

