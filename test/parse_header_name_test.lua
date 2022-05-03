local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_header_name = parse.header_name

function testcase.parse_header_name()
    -- test that parse header-name
    assert.equal(parse_header_name('Foo'), 'foo')

    -- test that limit the maximum length of header-name
    local s, err = parse_header_name('FooBarBaz', 4)
    assert.is_nil(s)
    assert.equal(err, parse.EHDRLEN)

    -- test that cannot parse invalid header-name
    s, err = parse_header_name('Foo:')
    assert.is_nil(s)
    assert.equal(err, parse.EHDRNAME)
end

