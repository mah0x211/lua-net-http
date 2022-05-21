local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_cookie_value = parse.cookie_value

function testcase.parse_cookie_value()
    -- test that return OK
    assert(parse_cookie_value(string.char(0x21)))
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
            assert(parse_cookie_value(string.char(i)))
        end
    end

    -- test that return EAGAIN
    local ok, err = parse_cookie_value('')
    assert.is_false(ok)
    assert.equal(err.type, parse.EAGAIN)

    -- test that return EILSEQ
    -- CTLs and whitespace
    for i = 0x0, 0x20 do
        ok, err = parse_cookie_value(string.char(i))
        assert.is_false(ok)
        assert.equal(err.type, parse.EILSEQ)
    end

    -- DQUOTE
    ok, err = parse_cookie_value(string.char(0x22))
    assert.is_false(ok)
    assert.equal(err.type, parse.EILSEQ)

    -- comma
    ok, err = parse_cookie_value(string.char(0x2C))
    assert.is_false(ok)
    assert.equal(err.type, parse.EILSEQ)

    -- semicolon
    ok, err = parse_cookie_value(string.char(0x3B))
    assert.is_false(ok)
    assert.equal(err.type, parse.EILSEQ)

    -- backslash
    ok, err = parse_cookie_value(string.char(0x5C))
    assert.is_false(ok)
    assert.equal(err.type, parse.EILSEQ)

    ok, err = parse_cookie_value(string.char(0x7F))
    assert.is_false(ok)
    assert.equal(err.type, parse.EILSEQ)
end

