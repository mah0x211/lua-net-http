local Parse = require('net.http.parse')
local ParseHeaderValue = Parse.header_value

describe("test net.http.parse.header_value", function()
    it('can parse header-value', function()
        assert.are.equal('FooBar', ParseHeaderValue('FooBar'))
    end)

    it("can limit the maximum length of header-value", function()
        local s, err = ParseHeaderValue('FooBarBaz', 4)
        assert.is_nil(s)
        assert.are.equal(Parse.EHDRLEN, err)
    end)

    it('cannot parse invalid header-value', function()
        local s, rv = ParseHeaderValue('Foo\n')
        assert.is_nil(s)
        assert.are.equals(Parse.EHDRVAL, rv)
    end)
end)

