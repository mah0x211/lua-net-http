local testcase = require('testcase')
local assert = require('assert')
local parse = require('net.http.parse')
local parse_header_value = parse.header_value

function testcase.parse_header_value()
    -- test that parse header-value
    assert(parse_header_value('FooBar'))

    -- test that limit the maximum length of header-value
    local ok, err = parse_header_value('FooBarBaz', 4)
    assert.is_false(ok)
    assert.equal(err.type, parse.EHDRLEN)

    -- test that cannot parse invalid header-value
    ok, err = parse_header_value('Foo\n')
    assert.is_false(ok)
    assert.equal(err.type, parse.EHDRVAL)
end

