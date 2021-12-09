local assert = require('assertex')
local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_strerror = parse.strerror

function testcase.parse_strerror()
    -- test that returns the message string corresponding to error code
    for k, ec in pairs(parse) do
        if k:find('^E[A-Z]+$') then
            local msg = assert.is_string(parse_strerror(ec))
            assert.not_equal(msg, 'unknown error code')
        end
    end

    -- test that returns the unknown message string
    local msg = assert.is_string(parse_strerror(11))
    assert.equal(msg, 'unknown error')
end

