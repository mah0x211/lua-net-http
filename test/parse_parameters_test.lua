local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_parameters = parse.parameters

function testcase.parse_parameters()
    -- test that parse parameters
    local params = {}
    assert.equal(parse_parameters(
                     'charset=hello ; Charset="utf-8"; format="flowed"; delsp=yes ',
                     params), parse.OK)
    assert.equal(params, {
        charset = 'utf-8',
        format = 'flowed',
        delsp = 'yes',
    })

    -- test that returns EAGAIN with empty-string
    assert.equal(parse_parameters('', {}), parse.EAGAIN)

    -- test that returns EAGAIN with unclosed quoted-string value
    assert.equal(parse_parameters('hello="world', {}), parse.EAGAIN)

    -- test that returns ELEN
    assert.equal(parse_parameters('hello=world', {}, 5), parse.ELEN)
end
