require('luacov')
local assert = require('assertex')
local testcase = require('testcase')
local entity = require('net.http.entity')
local header = require('net.http').header
local strerror = require('net.http.parse').strerror
local EAGAIN = require('net.http.parse').EAGAIN
local EMSG = require('net.http.parse').EMSG

function testcase.init()
    -- test that the 'entity' field is added to the argument table
    local tbl = {}
    local msg = entity.init(tbl)
    assert.is_table(tbl.entity)
    assert.equal(tostring(tbl), tostring(msg))
end

function testcase.set_body()
    local msg = entity.init({
        header = header.new(),
    })

    -- test that sets a message body without content-type
    entity.setBody(msg, 'hello')
    assert(msg.entity.body, 'body is nil')
    assert.is_true(msg.entity.clen)
    assert.is_nil(msg.entity.ctype)
    assert.is_nil(msg.header:get('content-type'))
    assert.equal(msg.header:get('content-length'), {
        '5',
    })

    -- test that sets a message body with content-type
    entity.setBody(msg, 'hello', 'text/plain')
    assert(msg.entity.body, 'body is nil')
    assert.is_true(msg.entity.clen)
    assert.is_true(msg.entity.ctype)
    assert.equal(msg.header:get('content-type'), {
        'text/plain',
    })
    assert.equal(msg.header:get('content-length'), {
        '5',
    })
end

function testcase.unset_body()
    local msg = entity.init({
        header = header.new(),
    })

    -- test that unset a message body
    entity.setBody(msg, 'hello', 'text/plain')
    entity.unsetBody(msg)
    assert.is_nil(msg.entity.body)
    assert.is_nil(msg.entity.ctype)
    assert.is_nil(msg.header:get('content-type'))
    assert.is_nil(msg.header:get('content-length'))
end

function testcase.sendto()
    local data = ''
    local sock = setmetatable({}, {
        __index = {
            send = function(_, val)
                data = data .. val
                return #val
            end,
        },
    })
    local msg = entity.init({
        header = header.new(),
    })
    msg.header:set('my-header', {
        'hello',
        'world',
    })

    -- test that send message
    local exp = table.concat({
        'my-header: hello',
        'my-header: world',
        '\r\n',
    }, '\r\n')
    local len, err, timeout = entity.sendto(sock, msg)
    assert.equal(len, #exp)
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.equal(data, exp)

    -- test that send message with body data
    entity.setBody(msg, 'hello world!')
    exp = table.concat({
        'my-header: hello',
        'my-header: world',
        'content-length: 12\r\n',
        'hello world!',
    }, '\r\n')
    data = ''
    len, err, timeout = entity.sendto(sock, msg)
    assert.equal(len, #exp)
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.equal(data, exp)

    -- test that send message with chunked-data
    local nchunk = 3
    local n = 0
    local body = {
        read = function()
            n = n + 1
            if n > nchunk then
                return nil
            end
            return 'chunked-data-' .. n
        end,
    }
    msg = entity.init({
        header = header.new(),
    })
    entity.setBody(msg, body)
    local chunks = {}
    sock = setmetatable({}, {
        __index = {
            send = function(_, val)
                chunks[#chunks + 1] = val
                return #val
            end,
        },
    })
    exp = {
        'transfer-encoding: chunked\r\n' .. '\r\n',
        'e\r\n' .. 'chunked-data-1\r\n',
        'e\r\n' .. 'chunked-data-2\r\n',
        'e\r\n' .. 'chunked-data-3\r\n',
        '0\r\n\r\n',
    }
    len, err, timeout = entity.sendto(sock, msg)
    assert.equal(len, #table.concat(exp))
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.equal(chunks, exp)

    -- test that abort sending chunked messages
    n = 0
    msg = entity.init({
        header = header.new(),
    })
    entity.setBody(msg, body)
    chunks = {}
    sock = setmetatable({}, {
        __index = {
            send = function(_, val)
                if n == 3 then
                    return nil, 'abort'
                end
                chunks[#chunks + 1] = val
                return #val
            end,
        },
    })
    exp = {
        'transfer-encoding: chunked\r\n' .. '\r\n',
        'e\r\n' .. 'chunked-data-1\r\n',
        'e\r\n' .. 'chunked-data-2\r\n',
    }
    len, err, timeout = entity.sendto(sock, msg)
    assert.equal(len, #table.concat(exp))
    assert.equal('abort', err)
    assert.is_nil(timeout)
    assert.equal(chunks, exp)
end

function testcase.recvfrom()
    -- test that recv message
    local chunks = {
        'not hello',
        'hello',
        ' ',
        'world',
        '!',
    }
    local idx = 0
    local sock = setmetatable({}, {
        __index = {
            recv = function()
                idx = idx + 1
                if not chunks[idx] then
                    return nil, 'no data', false
                end

                return chunks[idx]
            end,
        },
    })
    local parser = function(buf, ent)
        if buf == 'not hello' then
            return EMSG
        elseif idx < #chunks then
            return EAGAIN
        end

        ent.data = buf
        return #buf
    end
    local res = {
        header = {},
    }
    local ok, excess, err, timeout, perr = entity.recvfrom(sock, parser, res)

    -- got parse error
    assert.is_false(ok)
    assert.is_nil(excess)
    assert.equal(err, strerror(EMSG))
    assert.is_nil(timeout)
    assert.equal(perr, EMSG)

    -- got response
    ok, excess, err, timeout = entity.recvfrom(sock, parser, res)
    assert.is_true(ok)
    assert.equal(excess, '')
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.equal(res, {
        data = 'hello world!',
        header = {},
    })

    -- got error
    ok, excess, err, timeout = entity.recvfrom(sock, parser, res)
    assert.is_false(ok)
    assert.is_nil(excess)
    assert.equal(err, 'no data')
    assert.is_false(timeout)
end
