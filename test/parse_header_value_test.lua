local assert = require('assertex')
local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_header_value = parse.header_value

function testcase.parse_header_value()
    -- test that parse header-value
    assert.equal(parse_header_value('FooBar'), 'FooBar')

    -- test that limit the maximum length of header-value
    local s, err = parse_header_value('FooBarBaz', 4)
    assert.is_nil(s)
    assert.equal(err, parse.EHDRLEN)

    -- test that cannot parse invalid header-value
    s, err = parse_header_value('Foo\n')
    assert.is_nil(s)
    assert.equal(err, parse.EHDRVAL)
end

