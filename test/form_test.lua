require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local new_reader = require('net.http.reader').new
local new_form = require('net.http.form').new
local decode_form = require('net.http.form').decode

function testcase.new()
    -- test that create new instance of net.http.form
    local m = assert(new_form())
    assert.match(tostring(m), '^net.http.form: ', false)
end

function testcase.decode_urlencoded()
    local data
    local reader = new_reader({
        read = function(self, n)
            if self.err then
                return nil, self.err
            elseif #data > 0 then
                local s = string.sub(data, 1, n)
                data = string.sub(data, n + 1)
                return s
            end
        end,
    })

    -- test that read from application/x-www-form-urlencoded content
    data = 'foo=bar&foo&foo=baz&qux=quux'
    local form, err = assert(decode_form(reader))
    assert.equal(data, '')
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

    -- test that return err
    data = 'foo=bar&foo&foo=b%az&qux=quux'
    form, err = decode_form(reader)
    assert.is_nil(form)
    assert.match(err.type, '^form.urlencoded.decode', false)
end

function testcase.decode_multipart()
    local data
    local reader = new_reader({
        read = function(self, n)
            if self.err then
                return nil, self.err
            elseif #data > 0 then
                local s = string.sub(data, 1, n)
                data = string.sub(data, n + 1)
                return s
            end
        end,
    })

    -- test that read from multipart/form-data content
    data = table.concat({
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
    }, '\r\n')
    local form = assert(decode_form(reader, nil, 'test_boundary'))
    assert.equal(data, '')
    assert.match(form, '^net.http.form: ', false)
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
end

