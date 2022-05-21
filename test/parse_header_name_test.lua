local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_header_name = parse.header_name

function testcase.parse_header_name()
    -- test that parse header-name
    assert(parse_header_name('Foo'))

    -- test that limit the maximum length of header-name
    local ok, err = parse_header_name('FooBarBaz', 4)
    assert.is_false(ok)
    assert.equal(err.type, parse.EHDRLEN)

    -- test that cannot parse invalid header-name
    ok, err = parse_header_name('Foo:')
    assert.is_false(ok)
    assert.equal(err.type, parse.EHDRNAME)
end

