local assert = require('assertex')
local testcase = require('testcase')
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
        local size, cur = parse_chunksize(v.line, ext)
        assert.equal(size, v.size)
        assert.equal(cur, #v.line)
        assert.equal(ext, v.ext)
    end

    -- test that limit the maximum length of chunksize-line
    local size, cur = parse_chunksize('71e20 ; foo; bar = baz\r\n', {}, 4)
    assert.equal(size, parse.ELEN)
    assert.is_nil(cur)

    -- test that return EAGAIN
    assert.equal(parse_chunksize('', {}), parse.EAGAIN)
    assert.equal(parse_chunksize('ff', {}), parse.EAGAIN)
    assert.equal(parse_chunksize('ff\r', {}), parse.EAGAIN)
    assert.equal(parse_chunksize('ff ', {}), parse.EAGAIN)
    assert.equal(parse_chunksize('ff ; ', {}), parse.EAGAIN)
    assert.equal(parse_chunksize('ff ; foo', {}), parse.EAGAIN)

    -- test that return EEOL
    assert.equal(parse_chunksize('ff\r\r', {}), parse.EEOL)

    -- tset that return EEMPTY
    assert.equal(parse_chunksize('ff ; \r\n', {}), parse.EEMPTY)

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
        assert.equal(parse_chunksize(line, {}), parse.EILSEQ)
    end
end
