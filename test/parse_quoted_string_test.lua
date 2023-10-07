local testcase = require('testcase')
local assert = require('assert')
local parse = require('net.http.parse')
local parse_quoted_string = parse.quoted_string

function testcase.parse_quoted_string()
    -- test that return true
    for _, range in ipairs({
        {
            -- HT
            0x9,
            0x9,
        },
        {
            0x20, -- SP
            0x21,
        },
        {
            0x23,
            0x5B,
        },
        {
            0x5D,
            0x7E,
        },
    }) do
        for i = range[1], range[2] do
            local c = '"' .. string.char(i) .. '"'
            assert(parse_quoted_string(c))
        end
    end

    -- test that return true
    assert(parse_quoted_string([["quoted '\"' pair"]]))

    -- test that return EAGAIN
    local ok, err = parse_quoted_string('')
    assert.is_false(ok)
    assert.equal(err.type, parse.EAGAIN)

    -- test that return ELEN
    ok, err = parse_quoted_string('"foo-bar-baz"', 3)
    assert.is_false(ok)
    assert.equal(err.type, parse.ELEN)

    -- test that return EILSEQ
    for _, range in ipairs({
        {
            0x0,
            0x8,
        },
        {
            0x10,
            0x19,
        },
        {
            0x7F,
            0x7F,
        },
    }) do
        for i = range[1], range[2] do
            local c = '"' .. string.char(i) .. '"'
            ok, err = parse_quoted_string(c)
            assert.is_false(ok)
            assert.equal(err.type, parse.EILSEQ)
        end
    end
end
