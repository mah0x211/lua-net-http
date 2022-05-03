local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_cookie_value = parse.cookie_value

function testcase.parse_cookie_value()
    -- test that return OK
    assert.equal(parse_cookie_value(string.char(0x21)), parse.OK)
    for _, range in ipairs({
        {
            0x23,
            0x2B,
        },
        {
            0x2D,
            0x3A,
        },
        {
            0x3C,
            0x5B,
        },
        {
            0x5D,
            0x7E,
        },
    }) do
        for i = range[1], range[2] do
            assert.equal(parse_cookie_value(string.char(i)), parse.OK)
        end
    end

    -- test that return EAGAIN
    assert.equal(parse_cookie_value(''), parse.EAGAIN)

    -- test that return EILSEQ
    -- CTLs and whitespace
    for i = 0x0, 0x20 do
        assert.equal(parse_cookie_value(string.char(i)), parse.EILSEQ)
    end
    -- DQUOTE
    assert.equal(parse_cookie_value(string.char(0x22)), parse.EILSEQ)
    -- comma
    assert.equal(parse_cookie_value(string.char(0x2C)), parse.EILSEQ)
    -- semicolon
    assert.equal(parse_cookie_value(string.char(0x3B)), parse.EILSEQ)
    -- backslash
    assert.equal(parse_cookie_value(string.char(0x5C)), parse.EILSEQ)
    assert.equal(parse_cookie_value(string.char(0x7F)), parse.EILSEQ)
end

