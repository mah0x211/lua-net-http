require('luacov')
local testcase = require('testcase')
local encode = require('net.http.query').encode

function testcase.encode()
    -- test that encode query table to string
    assert.equal(encode({
        'hello',
        foo = 'str',
        bar = {
            baa = true,
            baz = 123.5,
            qux = {},
        },
    }), '?bar.baa=true&bar.baz=123.5&foo=str')

    -- test that return empty-string
    assert.equal(encode({
        'hello',
        bar = {
            qux = {},
        },
    }), '')

    -- test that throws an error if query is not table
    local err = assert.throws(encode, 'hello')
    assert.match(err, 'query must be table')
end

