require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local error = require('error')
local new_message = require('net.http.message.request').new
local new_content = require('net.http.content').new
local new_chunked_content = require('net.http.content.chunked').new
local new_reader = require('net.http.reader').new
local new_writer = require('net.http.writer').new
local new_form = require('net.http.form').new
local new_connection = require('net.http.connection').new

function testcase.new()
    -- test that create new instance of net.http.message.request
    local m = assert(new_message())
    assert.match(tostring(m), '^net.http.message.request: ', false)
    assert.equal(m.method, 'GET')
    assert.equal(m.uri, '/')
    assert.equal(m.version, '1.1')
end

function testcase.set_method()
    local m = assert(new_message())

    -- test that set valid method
    assert(m:set_method('TRACE'))
    assert.equal(m.method, 'TRACE')

    -- test that return EINVAL if argument is invalid string
    local ok, err = m:set_method('HELLO')
    assert.is_false(ok)
    assert(error.is(err, errno.EINVAL))

    -- test that throws an error if argument is not string
    err = assert.throws(m.set_method, m)
    assert.match(err, 'method must be string')
    assert.equal(m.method, 'TRACE')
end

function testcase.set_uri()
    local m = assert(new_message())

    -- test that set valid uri
    assert(m:set_uri(
               'https://user:pswd@www.example.com:80/foo/../bar/./../hello?q=foo&q=bar&baa=baz#hash'))
    assert.contains(m, {
        uri = 'https://user:pswd@www.example.com:80/foo/../bar/./../hello?q=foo&q=bar&baa=baz#hash',
        scheme = 'https',
        userinfo = 'user:pswd',
        user = 'user',
        password = 'pswd',
        host = 'www.example.com:80',
        hostname = 'www.example.com',
        port = '80',
        path = '/hello',
        rawpath = '/foo/../bar/./../hello',
        query = '?q=foo&q=bar&baa=baz',
        fragment = 'hash',
    })

    -- test that set uri and parse query string
    assert(m:set_uri(
               'https://user:pswd@www.example.com:80/hello?q=foo&q=bar&baa=baz#hash',
               true))
    assert.contains(m, {
        uri = 'https://user:pswd@www.example.com:80/hello?q=foo&q=bar&baa=baz#hash',
        scheme = 'https',
        userinfo = 'user:pswd',
        user = 'user',
        password = 'pswd',
        host = 'www.example.com:80',
        hostname = 'www.example.com',
        port = '80',
        path = '/hello',
        rawpath = '/hello',
        query = '?q=foo&q=bar&baa=baz',
        query_params = {
            q = {
                'foo',
                'bar',
            },
            baa = {
                'baz',
            },
        },
        fragment = 'hash',
    })

    -- test that return EINVAL if argument is invalid uri string
    local ok, err = m:set_uri('http:// example.com')
    assert.is_false(ok)
    assert(error.is(err, errno.EINVAL))

    -- test that throws an error if argument is not string
    err = assert.throws(m.set_uri, m)
    assert.match(err, 'uri must be string')
end

function testcase.write_firstline()
    local wctx = {
        msg = '',
        write = function(self, s)
            if self.err then
                return nil, self.err
            end
            self.msg = self.msg .. s
            return #s
        end,
    }
    local w = new_writer(wctx)
    w:setbufsize(0)

    -- test that write firstline
    local m = assert(new_message())
    m.method = 'connect'
    m.uri = 'http://foo:bar@example.com/hello/world'
    m.version = 1.0
    wctx.msg = ''
    assert(m:write_firstline(w))
    assert.equal(wctx.msg, table.concat({
        'connect',
        ' ',
        '/hello/world',
        ' ',
        'HTTP/1.0',
        '\r\n',
    }))

    -- test that write firstline
    m = assert(new_message())
    m.method = 'connect'
    m.uri = ' http://example.com/hello/world'
    wctx.msg = ''
    local n, err = m:write_firstline(w)
    assert.is_nil(n)
    assert(error.is(err, errno.EINVAL))
    assert.match(err, 'invalid uri character .+ found at 1', false)
end

function testcase.read_form()
    local data = 'foo=bar&foo&foo=baz&qux=quux'
    local rctx = {
        read = function(self, n)
            if self.err then
                return nil, self.err
            elseif #data > 0 then
                local s = string.sub(data, 1, n)
                data = string.sub(data, n + 1)
                return s
            end
        end,
    }

    -- test that read from application/x-www-form-urlencoded content
    local m = assert(new_message())
    m.header:set('Content-Type', 'application/x-www-form-urlencoded')
    m.header:set('Content-Length', tostring(#data))
    m.content = new_content(new_reader(rctx), #data)
    local form, err = assert(m:read_form())
    assert.match(form, '^net.http.form: ', false)
    assert.is_nil(err)
    assert.equal(form.data, {
        foo = {
            'bar',
            '',
            'baz',
        },
        qux = {
            'quux',
        },
    })

    -- test that return empty form
    m = assert(new_message())
    m.method = 'POST'
    form, err = m:read_form()
    assert.is_table(form)
    assert.is_nil(err)
    assert.equal(tostring(form), tostring(m.form))
    for _ in form:pairs() do
        assert(false, 'form must be empty')
    end
end

function testcase.read_form_urlencoded()
    local data
    local rctx = {
        read = function(self, n)
            if self.err then
                return nil, self.err
            elseif #data > 0 then
                local s = string.sub(data, 1, n)
                data = string.sub(data, n + 1)
                return s
            end
        end,
    }
    local m
    local resetctx = function(ctype, msg)
        -- convert to chunked message
        if msg then
            math.randomseed(os.time())
            local maxlen = math.floor(#msg / 5)
            data = ''
            while #msg > 0 do
                local n = math.random(1, maxlen)
                if n > #msg then
                    n = #msg
                end
                data = data .. string.format('%x', n) .. '\r\n'
                data = data .. string.sub(msg, 1, n) .. '\r\n'
                msg = string.sub(msg, n + 1)
            end
            data = data .. '0\r\n\r\n'
        else
            data = ''
        end

        m = assert(new_message())
        if ctype then
            m.header:set('Content-Type', ctype)
        end
        m.content = new_chunked_content(new_reader(rctx))
    end

    -- test that read from application/x-www-form-urlencoded content
    resetctx('application/x-www-form-urlencoded', 'foo=bar&foo&foo=baz&qux=quux')
    local form, err = assert(m:read_form())
    assert.match(form, '^net.http.form: ', false)
    assert.is_nil(err)
    assert.equal(form.data, {
        foo = {
            'bar',
            '',
            'baz',
        },
        qux = {
            'quux',
        },
    })

    -- test that return false with no error
    resetctx()
    form, err = m:read_form()
    assert.is_nil(form)
    assert.is_nil(err)

    -- test that return false and boundary error
    resetctx('multipart/form-data')
    form, err = m:read_form()
    assert.is_nil(form)
    assert(error.is(err, errno.EINVAL))
    assert.match(err, 'boundary not defined')

    -- test that return false and boundary error
    resetctx('multipart/form-data')
    form, err = m:read_form()
    assert.is_nil(form)
    assert(error.is(err, errno.EINVAL))
    assert.match(err, 'boundary not defined')
end

function testcase.read_form_multipart()
    local data
    local rctx = {
        read = function(self, n)
            if self.err then
                return nil, self.err
            elseif #data > 0 then
                local s = string.sub(data, 1, n)
                data = string.sub(data, n + 1)
                return s
            end
        end,
    }
    local m
    local resetctx = function(ctype, msg)
        -- convert to chunked message
        math.randomseed(os.time())
        local maxlen = math.floor(#msg / 5)
        data = ''
        while #msg > 0 do
            local n = math.random(1, maxlen)
            if n > #msg then
                n = #msg
            end
            data = data .. string.format('%x', n) .. '\r\n'
            data = data .. string.sub(msg, 1, n) .. '\r\n'
            msg = string.sub(msg, n + 1)
        end
        data = data .. '0\r\n\r\n'

        m = assert(new_message())
        m.content = new_chunked_content(new_reader(rctx))
        m.header:set('Content-Type', ctype)
    end

    -- test that read from multipart/form-data content
    resetctx('multipart/form-data; boundary=test_boundary', table.concat({
        '--test_boundary',
        'X-Example: example header1',
        'X-Example: example header2',
        'Content-Disposition: form-data; name="foo"; filename="bar.txt"',
        '',
        'bar file',
        '--test_boundary',
        'Content-Disposition: form-data; name="foo"',
        '',
        'hello world',
        '--test_boundary',
        'Content-Disposition: form-data; name="foo"; filename="baz.txt"',
        '',
        'baz file',
        '--test_boundary',
        'Content-Disposition: form-data; name="qux"',
        '',
        'qux',
        '--test_boundary',
        'Content-Disposition: form-data; name="qux"',
        '',
        '',
        '--test_boundary--',
        '',
    }, '\r\n'))
    local form, err = m:read_form()
    assert.match(form, '^net.http.form: ', false)
    assert.is_nil(err)
    assert.contains(form.data.foo[1], {
        name = 'foo',
        header = {
            ['content-disposition'] = {
                'form-data; name="foo"; filename="bar.txt"',
            },
            ['x-example'] = {
                'example header1',
                'example header2',
            },
        },
        filename = 'bar.txt',
    })
    assert.equal(form.data.foo[1].file:read('*a'), 'bar file')
    assert.equal(form.data.foo[2], {
        name = 'foo',
        header = {
            ['content-disposition'] = {
                'form-data; name="foo"',
            },
        },
        data = 'hello world',
    })
    assert.contains(form.data.foo[3], {
        name = 'foo',
        header = {
            ['content-disposition'] = {
                'form-data; name="foo"; filename="baz.txt"',
            },
        },
        filename = 'baz.txt',
    })
    assert.equal(form.data.foo[3].file:read('*a'), 'baz file')
    assert.equal(form.data.qux, {
        {
            name = 'qux',
            header = {
                ['content-disposition'] = {
                    'form-data; name="qux"',
                },
            },
            data = 'qux',
        },
        {
            name = 'qux',
            header = {
                ['content-disposition'] = {
                    'form-data; name="qux"',
                },
            },
            data = '',
        },
    })

    -- test that return error
    resetctx('multipart/form-data; boundary=test_boundary', table.concat({
        '--test_boundary',
        'X-Example: example header1',
        'X-Example: example header2',
        'Content-Disposition: form-data; name="foo"; filename="bar.txt"',
        '',
        'bar file',
        '--test_boundary',
        'Content-Dispostion: form-data; name="foo"',
        '',
        'hello world',
        '--test_boundary',
        'Content-Disposition: form-data; name="foo"; filename="baz.txt"',
        '',
        'baz file',
        '--test_boundary--',
        '',
    }, '\r\n'))
    form, err = m:read_form()
    assert.is_nil(form)
    assert.match(err, 'form-multipart decode error')
end

function testcase.write_form_urlencoded()
    local data = ''
    local wctx = {
        write = function(self, s)
            if self.err then
                return nil, self.err
            end
            data = data .. s
            return #s
        end,
    }
    local w = new_writer(wctx)
    w:setbufsize(0)

    local form = new_form()
    local file = assert(io.tmpfile())
    file:write('hello world!')
    file:seek('set')
    form:add('foo', 'bar')
    form:add('foo', '')
    form:add('foo', 'baz')
    form:add('hello', {
        filename = 'hello.txt',
        file = file,
    })

    -- test that read from application/x-www-form-urlencoded content
    local m = assert(new_message())
    m.method = 'POST'
    data = ''
    local n, err = assert(m:write_form(w, form))
    assert.equal(n, #data)
    assert.is_nil(err)
    -- confirm
    local c = new_connection({
        read = function(_, nr)
            if #data == 0 then
                return nil
            end

            local s = string.sub(data, 1, nr)
            data = string.sub(data, nr + 1)
            return s
        end,
        write = function()
        end,
    })
    m = assert(c:read_request())
    assert(m:read_form())
    assert(m:read_form())
    form = m.form
    assert.match(form, '^net.http.form: ', false)
    assert.equal(form.data, {
        foo = {
            'bar',
            '',
            'baz',
        },
    })

    -- test that throws an error if form argument is invalid
    m = assert(new_message())
    err = assert.throws(m.write_form, m, w, {})
    assert.match(err, 'form must be net.http.form')

    -- test that throws an error if boundary argument is invalid
    err = assert.throws(m.write_form, m, w, form, true)
    assert.match(err, 'boundary must be string')
    -- test that throws an error if boundary argument is invalid
    err = assert.throws(m.write_form, m, w, form, 'foo bar baz')
    assert.match(err, 'boundary must be valid-boundary string')
end

function testcase.write_form_multipart()
    local data = ''
    local wctx = {
        write = function(self, s)
            if self.err then
                return nil, self.err
            end
            data = data .. s
            return #s
        end,
        writefile = function(self, file, len, offset, part)
            file:seek('set', offset)
            local s, err = file:read(len)
            if part.is_tmpfile then
                file:close()
            end

            if err then
                return nil, err
            end
            return self:write(s)
        end,
    }
    local w = new_writer(wctx)
    w:setbufsize(0)

    local form = new_form()
    local file = assert(io.tmpfile())
    file:write('hello world!')
    file:seek('set')
    form:add('foo', 'bar')
    form:add('foo', '')
    form:add('foo', 'baz')
    form:add('hello', {
        filename = 'hello.txt',
        file = file,
    })

    -- test that read from application/x-www-form-urlencoded content
    local m = assert(new_message())
    m.method = 'POST'
    data = ''
    local n, err = assert(m:write_form(w, form, 'test_boundary'))
    assert.equal(n, #data)
    assert.is_nil(err)
    -- confirm
    local c = new_connection({
        read = function(_, nr)
            if #data == 0 then
                return nil
            end

            local s = string.sub(data, 1, nr)
            data = string.sub(data, nr + 1)
            return s
        end,
        write = function()
        end,
    })
    m = assert(c:read_request())
    assert(m:read_form())
    assert.equal(#data, 0)
    assert.equal(c.reader:size(), 0)
    form = m.form
    assert.equal(form.data.foo, {
        {
            name = 'foo',
            header = {
                ['content-disposition'] = {
                    'form-data; name="foo"',
                },
            },
            data = 'bar',
        },
        {
            name = 'foo',
            header = {
                ['content-disposition'] = {
                    'form-data; name="foo"',
                },
            },
            data = '',
        },
        {
            name = 'foo',
            header = {
                ['content-disposition'] = {
                    'form-data; name="foo"',
                },
            },
            data = 'baz',
        },
    })
    assert.contains(form.data.hello, {
        {
            name = 'hello',
            header = {
                ['content-disposition'] = {
                    'form-data; name="hello"; filename="hello.txt"',
                },
            },
            filename = "hello.txt",
        },
    })
    assert.equal(form.data.hello[1].file:read('*a'), 'hello world!')
end

