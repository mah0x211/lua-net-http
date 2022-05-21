local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_parameters = parse.parameters

function testcase.parse_parameters()
    -- test that parse parameters
    local params = {}
    assert(parse_parameters(
               'charset=hello ; Charset="utf-8"; format="flowed"; delsp=yes ',
               params))
    assert.equal(params, {
        charset = 'utf-8',
        format = 'flowed',
        delsp = 'yes',
    })

    -- test that returns EAGAIN with empty-string
    local ok, err = parse_parameters('', {})
    assert.is_false(ok)
    assert.equal(err.type, parse.EAGAIN)

    -- test that returns EAGAIN with unclosed quoted-string value
    ok, err = parse_parameters('hello="world', {})
    assert.is_false(ok)
    assert.equal(err.type, parse.EAGAIN)

    -- test that returns ELEN
    ok, err = parse_parameters('hello=world', {}, 5)
    assert.is_false(ok)
    assert.equal(err.type, parse.ELEN)
end
