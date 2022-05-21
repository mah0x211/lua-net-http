local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_tchar = parse.tchar

function testcase.parse_tchar()
    -- test that return OK
    local delimiters = [["(),/:;<=>?@[\]{}]]
    for i = 0x21, 0x7E do
        local c = string.char(i)
        if not string.find(delimiters, c, nil, true) then
            assert(parse_tchar(c))
        end
    end

    -- test that return EAGAIN
    local ok, err = parse_tchar('')
    assert.is_false(ok)
    assert.equal(err.type, parse.EAGAIN)

    -- test that return EILSEQ
    for i = 0x0, 0x20 do
        ok, err = parse_tchar(string.char(i))
        assert.is_false(ok)
        assert.equal(err.type, parse.EILSEQ)
    end
    ok, err = parse_tchar(string.char(0x7F))
    assert.is_false(ok)
    assert.equal(err.type, parse.EILSEQ)

    delimiters = [["(),/:;<=>?@[\]{}]]
    for i = 0x21, 0x7E do
        local c = string.char(i)
        if string.find(delimiters, c, nil, true) then
            ok, err = parse_tchar(c)
            assert.is_false(ok)
            assert.equal(err.type, parse.EILSEQ)
        end
    end
end
