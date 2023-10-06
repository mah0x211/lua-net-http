local testcase = require('testcase')
local assert = require('assert')
local parse = require('net.http.parse')
local parse_chunksize = parse.chunksize

function testcase.parse_chunksize()
    -- test that parse chunksize line
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
        local size, err, cur = parse_chunksize(v.line, ext)
        assert.equal(size, v.size)
        assert.is_nil(err)
        assert.equal(cur, #v.line)
        assert.equal(ext, v.ext)
    end

    -- test that limit the maximum length of chunksize-line
    local size, err, cur = parse_chunksize('71e20 ; foo; bar = baz\r\n', {}, 4)
    assert.is_nil(size)
    assert.equal(err.type, parse.ELEN)
    assert.is_nil(cur)

    -- test that return EAGAIN
    size, err = parse_chunksize('', {})
    assert.is_nil(size)
    assert.equal(err.type, parse.EAGAIN)
    size, err = parse_chunksize('ff', {})
    assert.is_nil(size)
    assert.equal(err.type, parse.EAGAIN)
    size, err = parse_chunksize('ff\r', {})
    assert.is_nil(size)
    assert.equal(err.type, parse.EAGAIN)
    size, err = parse_chunksize('ff ', {})
    assert.is_nil(size)
    assert.equal(err.type, parse.EAGAIN)
    size, err = parse_chunksize('ff ; ', {})
    assert.is_nil(size)
    assert.equal(err.type, parse.EAGAIN)
    size, err = parse_chunksize('ff ; foo', {})
    assert.is_nil(size)
    assert.equal(err.type, parse.EAGAIN)

    -- test that return EEOL
    size, err = parse_chunksize('ff\r\r', {})
    assert.is_nil(size)
    assert.equal(err.type, parse.EEOL)

    -- tset that return EEMPTY
    size, err = parse_chunksize('ff ; \r\n', {})
    assert.is_nil(size)
    assert.equal(err.type, parse.EEMPTY)

    -- test that return EILSEQ
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
        size, err = parse_chunksize(line, {})
        assert.is_nil(size)
        assert.equal(err.type, parse.EILSEQ)
    end
end
