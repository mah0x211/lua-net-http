local Parse = require('net.http.parse')
local ParseHeaderName = Parse.header_name

describe("test net.http.parse.header_name", function()
    it('can parse header-name', function()
        assert.are.equal('foo', ParseHeaderName('Foo'))
    end)

    it("can limit the maximum length of header-name", function()
        local s, err = ParseHeaderName('FooBarBaz', 4)
        assert.is_nil(s)
        assert.are.equal(Parse.EHDRLEN, err)
    end)

    it('cannot parse invalid header-name', function()
        local s, rv = ParseHeaderName('Foo:')
        assert.is_nil(s)
        assert.are.equals(Parse.EHDRNAME, rv)
    end)
end)

