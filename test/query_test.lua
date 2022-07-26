require('luacov')
local testcase = require('testcase')
local encode = require('net.http.query').encode

function testcase.encode()
    -- test that encode query table to string
    local str = assert(encode({
        'hello',
        foo = 'str',
        bar = {
            'hello',
            'world',
            baa = true,
            baz = 123.5,
            qux = {},
        },
    }))
    local kvpairs = {}
    for kv in string.gmatch(string.sub(str, 2), '([^&]+)') do
        kvpairs[#kvpairs + 1] = kv
    end
    table.sort(kvpairs)
    assert.equal(kvpairs, {
        'bar.baa=true',
        'bar.baz=123.5',
        'bar=hello',
        'bar=world',
        'foo=str',
    })

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

