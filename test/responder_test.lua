require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local new_responder = require('net.http.responder').new
local new_response = require('net.http.message.response').new
local parse_response = require('net.http.parse').response
local code2reason = require('net.http.status').code2reason

--- create_response creates a response object from the given string.
--- @param str string
--- @return net.http.message.response res
local function create_response(str)
    local res = new_response()
    local dict = res.header.dict
    local header = res.header
    res.header = dict
    local pos = assert(parse_response(str, res))
    res.header = header
    res.content = str:sub(pos + 1)
    return res
end

local TMPFILES = {}

--- create_tempfile creates a temporary file with the given extension and data.
--- @param ext string file extension (e.g. '.txt')
--- @param data string file content
--- @return string pathname
--- @return file* file object
local function create_tempfile(ext, data)
    local pathname = os.tmpname() .. ext

    local f = assert(io.open(pathname, 'w+'))
    f:write(data)
    f:seek('set')
    TMPFILES[#TMPFILES + 1] = pathname
    return pathname, f
end

function testcase.after_each()
    for _, pathname in ipairs(TMPFILES) do
        os.remove(pathname)
    end
    TMPFILES = {}
end

function testcase.new()
    local noop = function()
    end
    local writer = {
        write = noop,
        flush = noop,
    }
    local mime = {
        getmime = noop,
    }
    local filter = noop

    -- test that new responder instance
    local res = new_responder(writer, mime, filter)
    assert.re_match(res, '^net\\.http\\.responder: ')
    -- confirm that responder has a net.http.header instance as header
    assert.re_match(res.header, '^net\\.http\\.header: ')

    -- test that new responder instance without optional arguments
    res = new_responder(writer)
    assert.re_match(res, '^net\\.http\\.responder: ')

    -- test that throws an error if writer is nil
    local err = assert.throws(new_responder, nil, mime, filter)
    assert.match(err, 'writer is required')

    -- test that throws an error if writer has no required method
    err = assert.throws(new_responder, {}, mime, filter)
    assert.match(err, 'writer must have write() and flush() methods')

    -- test that throws an error if mime has no required method
    err = assert.throws(new_responder, writer, {}, filter)
    assert.match(err, 'mime must have a getmime() method')

    -- test that throws an error if filter is not a function
    err = assert.throws(new_responder, writer, mime, {})
    assert.match(err,
                 "bad argument 'filter' .+callable object expected, got table",
                 false)
end

function testcase.write()
    local data = ''
    local writer = {
        write = function(_, v)
            data = data .. v
            return #v
        end,
        flush = function()
        end,
    }
    local res = new_responder(writer)

    -- test that write() method write headers and data to writer
    local ok, err, timeout = res:write('foo')
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    -- confirm that data is written to writer
    local msg = create_response(data)
    assert.contains(msg, {
        reason = 'OK',
        status = 200,
        version = 1.1,
        content = 'foo',
        header = {
            dict = {
                ['content-length'] = {
                    val = {
                        '3',
                    },
                },
                ['content-type'] = {
                    val = {
                        'application/octet-stream',
                    },
                },
            },
        },
    })

    -- test that write() method write a data to writer after headers are sent
    data = ''
    ok, err, timeout = res:write('bar')
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    assert.equal(data, 'bar')

    -- test that returns error from writer.write() method
    writer.write = function()
        return nil, 'error', true -- timeout will be ignored
    end
    ok, err, timeout = res:write('foo')
    assert.is_false(ok)
    assert.match(err, 'error')
    assert.is_nil(timeout)

    -- test that returns timeout from writer.write() method
    writer.write = function()
        return nil, nil, true
    end
    ok, err, timeout = res:write('foo')
    assert.is_false(ok)
    assert.is_nil(err)
    assert.is_true(timeout)
end

function testcase.write_file()
    local data = ''
    local writer = {
        write = function(_, v)
            data = data .. v
            return #v
        end,
        flush = function()
        end,
    }
    local res = new_responder(writer)
    local _, file = create_tempfile('.txt', 'foo')

    -- test that write a file content with headers
    local ok, err, timeout = res:write_file(file)
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    -- confirm that data is written to writer
    local msg = create_response(data)
    assert.contains(msg, {
        reason = 'OK',
        status = 200,
        version = 1.1,
        content = 'foo',
        header = {
            dict = {
                ['content-length'] = {
                    val = {
                        '3',
                    },
                },
                ['content-type'] = {
                    val = {
                        'application/octet-stream',
                    },
                },
            },
        },
    })

    -- test that write a file content without headers after headers are sent
    data = ''
    ok, err, timeout = res:write_file(file)
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    assert.equal(data, 'foo')

    -- test that returns error from writer.write() method
    writer.write = function()
        return nil, 'error', true -- timeout will be ignored
    end
    ok, err, timeout = res:write_file(file)
    assert.is_false(ok)
    assert.match(err, 'error')
    assert.is_nil(timeout)

    -- test that returns timeout from writer.write() method
    writer.write = function()
        return nil, nil, true
    end
    ok, err, timeout = res:write_file(file)
    assert.is_false(ok)
    assert.is_nil(err)
    assert.is_true(timeout)

end

function testcase.flush()
    local ncall = 0
    local writer = {
        write = function()
        end,
        flush = function()
            ncall = ncall + 1
            return 0
        end,
    }
    local res = new_responder(writer)

    -- test that flush() method calls writer:flush() method
    local ok, err, timeout = res:flush()
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    assert.equal(ncall, 1)

    -- test that returns error from writer.flush() method
    writer.flush = function()
        return nil, 'error', true -- timeout will be ignored
    end
    ok, err, timeout = res:flush()
    assert.is_false(ok)
    assert.match(err, 'error')
    assert.is_nil(timeout)

    -- test that returns timeout from writer.flush() method
    writer.flush = function()
        return nil, nil, true
    end
    ok, err, timeout = res:flush()
    assert.is_false(ok)
    assert.is_nil(err)
    assert.is_true(timeout)
end

function testcase.reply_file()
    local data = ''
    local writer = {
        write = function(_, v)
            data = data .. v
            return #v
        end,
        flush = function()
        end,
    }
    local res = new_responder(writer)
    local pathname = create_tempfile('.html', 'foo')

    -- test that write a file content
    local ok, err, timeout = res:reply_file(200, pathname)
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    -- confirm that data is written to writer
    local msg = create_response(data)
    data = ''
    assert.contains(msg, {
        reason = 'OK',
        status = 200,
        version = 1.1,
        content = 'foo',
        header = {
            dict = {
                ['content-length'] = {
                    val = {
                        '3',
                    },
                },
                ['content-type'] = {
                    val = {
                        'text/html',
                    },
                },
            },
        },
    })

    -- test that can be called with a file object
    res = new_responder(writer)
    local f = assert(io.open(pathname, 'r'))
    ok, err, timeout = res:reply_file(202, f)
    f:close()
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    -- confirm that data is written to writer
    msg = create_response(data)
    data = ''
    assert.contains(msg, {
        reason = 'Accepted',
        status = 202,
        version = 1.1,
        content = 'foo',
        header = {
            dict = {
                ['content-length'] = {
                    val = {
                        '3',
                    },
                },
                ['content-type'] = {
                    val = {
                        'application/octet-stream',
                    },
                },
            },
        },
    })

    -- test that file() method cannot be called twice
    ok, err, timeout = res:reply_file(200, pathname)
    assert.is_false(ok)
    assert.match(err, 'cannot send a response message twice')
    assert.is_nil(timeout)

    -- test that Content-Length is 0 if 204 No Content status code
    res = new_responder(writer)
    ok, err, timeout = res:reply_file(204, pathname)
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    -- confirm that data is written to writer
    msg = create_response(data)
    data = ''
    assert.contains(msg, {
        reason = 'No Content',
        status = 204,
        version = 1.1,
        content = '',
        header = {
            dict = {
                ['content-length'] = {
                    val = {
                        '0',
                    },
                },
            },
        },
    })

    -- test that returns error if status is not a valid HTTP status code
    res = new_responder(writer)
    ok, err, timeout = res:reply_file(999, pathname)
    assert.is_false(ok)
    assert.match(err, 'unsupported status code')
    assert.is_nil(timeout)

    -- test that returns error if pathname is not a file
    res = new_responder(writer)
    ok, err, timeout = res:reply_file(200, './nonexistent')
    assert.is_false(ok)
    assert.match(err, 'failed to open a file')
    assert.is_nil(timeout)

    -- test that Content-Type header will be set to 'application/octet-stream'
    pathname = create_tempfile('.unknown', 'foo')
    data = ''
    ok, err, timeout = res:reply_file(200, pathname)
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    msg = create_response(data)
    data = ''
    assert.contains(msg, {
        reason = 'OK',
        status = 200,
        version = 1.1,
        content = 'foo',
        header = {
            dict = {
                ['content-length'] = {
                    val = {
                        '3',
                    },
                },
                ['content-type'] = {
                    val = {
                        'application/octet-stream',
                    },
                },
            },
        },
    })

    -- test that returns error if mime.getmime() returns a non-string value
    res = new_responder(writer, {
        getmime = function()
            return 123
        end,
    })
    ok, err, timeout = res:reply_file(200, pathname)
    assert.is_false(ok)
    assert.match(err, 'mime:getmime() returns non-string value: "number"')
    assert.is_nil(timeout)
end

function testcase.reply()
    local data = ''
    local writer = {
        write = function(_, v)
            data = data .. v
            return #v
        end,
        flush = function()
        end,
    }
    local res = new_responder(writer)

    -- test that reply() method write headers and data to writer
    local ok, err, timeout = res:reply(200, 'foo')
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    -- confirm that data is written to writer
    local msg = create_response(data)
    data = ''
    assert.contains(msg, {
        reason = 'OK',
        status = 200,
        version = 1.1,
        content = 'foo',
        header = {
            dict = {
                ['content-length'] = {
                    val = {
                        '3',
                    },
                },
                ['content-type'] = {
                    val = {
                        'application/octet-stream',
                    },
                },
            },
        },
    })

    -- test that reply() method cannot be called twice
    ok, err, timeout = res:reply(200, 'foo')
    assert.is_false(ok)
    assert.match(err, 'cannot send a response message twice')
    assert.is_nil(timeout)

    -- test that returns error if status is not a valid HTTP status code
    res = new_responder(writer)
    ok, err, timeout = res:reply(999, 'foo')
    assert.is_false(ok)
    assert.match(err, 'unsupported status code')
    assert.is_nil(timeout)

    -- test that write a no-content response
    ok, err, timeout = res:reply(204, 'hello')
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    msg = create_response(data)
    data = ''
    assert.contains(msg, {
        reason = 'No Content',
        status = 204,
        version = 1.1,
        content = '',
        header = {
            dict = {
                ['content-length'] = {
                    val = {
                        '0',
                    },
                },
            },
        },
    })

    -- test that data will be stringified if it is not a string
    res = new_responder(writer)
    ok, err, timeout = res:reply(200, 123)
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    msg = create_response(data)
    data = ''
    assert.contains(msg, {
        reason = 'OK',
        status = 200,
        version = 1.1,
        content = '123',
        header = {
            dict = {
                ['content-length'] = {
                    val = {
                        '3',
                    },
                },
                ['content-type'] = {
                    val = {
                        'application/octet-stream',
                    },
                },
            },
        },
    })

    -- test that write a status message as a response content if data is nil
    res = new_responder(writer)
    ok, err, timeout = res:reply(200)
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    msg = create_response(data)
    data = ''
    assert.contains(msg, {
        reason = 'OK',
        status = 200,
        version = 1.1,
        content = '200 OK',
        header = {
            dict = {
                ['content-length'] = {
                    val = {
                        '6',
                    },
                },
                ['content-type'] = {
                    val = {
                        'text/plain',
                    },
                },
            },
        },
    })

    -- test that returns error if filter() returns an error
    res = new_responder(writer, nil, function()
        return nil, 'filter error'
    end)
    ok, err, timeout = res:reply(200, 'foo')
    assert.is_false(ok)
    assert.match(err, 'filter error')
    assert.is_nil(timeout)

    -- test that write a JSON response
    res = new_responder(writer)
    ok, err, timeout = res:reply(200, {
        foo = 'bar',
    }, true)
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    msg = create_response(data)
    data = ''
    assert.contains(msg, {
        reason = 'OK',
        status = 200,
        version = 1.1,
        content = '{"foo":"bar"}',
        header = {
            dict = {
                ['content-length'] = {
                    val = {
                        '13',
                    },
                },
                ['content-type'] = {
                    val = {
                        'application/json',
                    },
                },
            },
        },
    })
end

function testcase.reply1XX_2xx()
    local data = ''
    local writer = {
        write = function(_, v)
            data = data .. v
            return #v
        end,
        flush = function()
        end,
    }

    -- test that 1xx Informational and 2xx Success responses
    for status, code in pairs({
        -- 1xx Informational responses
        continue = 100,
        switching_protocols = 101,
        processing = 102,
        -- 2xx Success responses
        ok = 200,
        created = 201,
        accepted = 202,
        non_authoritative_information = 203,
        no_content = 204,
        reset_content = 205,
        partial_content = 206,
        multi_status = 207,
        already_reported = 208,
        im_used = 226,
    }) do
        local res = new_responder(writer)
        local ok, err, timeout = res[status](res, 'hello')
        assert.is_nil(err)
        assert.is_nil(timeout)
        assert.is_true(ok)
        -- confirm that data is written to writer
        local msg = create_response(data)
        data = ''
        if code == 204 then
            assert.contains(msg, {
                reason = 'No Content',
                status = code,
                version = 1.1,
                content = '',
                header = {
                    dict = {
                        ['content-length'] = {
                            val = {
                                '0',
                            },
                        },
                    },
                },
            })
        else
            assert.contains(msg, {
                reason = code2reason(code),
                status = code,
                version = 1.1,
                content = 'hello',
                header = {
                    dict = {
                        ['content-length'] = {
                            val = {
                                '5',
                            },
                        },
                    },
                },
            })
        end
    end
end

function testcase.multiple_choices()
    local data = ''
    local writer = {
        write = function(_, v)
            data = data .. v
            return #v
        end,
        flush = function()
        end,
    }

    -- test that multiple_choices
    local res = new_responder(writer)
    local ok, err, timeout = res:multiple_choices('hello', 'http://example.com')
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    -- confirm that data is written to writer
    local msg = create_response(data)
    data = ''
    assert.contains(msg, {
        reason = code2reason(300),
        status = 300,
        version = 1.1,
        content = 'hello',
        header = {
            dict = {
                ['location'] = {
                    val = {
                        'http://example.com',
                    },
                },
                ['content-length'] = {
                    val = {
                        '5',
                    },
                },
            },
        },
    })

    -- test that returns error if uri is not a string
    ok, err, timeout = res:multiple_choices('hello', 123)
    assert.is_false(ok)
    assert.match(err, 'uri must be non-empty string')
    assert.is_nil(timeout)
end

function testcase.not_modified()
    local data = ''
    local writer = {
        write = function(_, v)
            data = data .. v
            return #v
        end,
        flush = function()
        end,
    }

    -- test that multiple_choices
    local res = new_responder(writer)
    local ok, err, timeout = res:not_modified('hello', 'http://example.com')
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.is_true(ok)
    -- confirm that data is written to writer
    local msg = create_response(data)
    data = ''
    assert.contains(msg, {
        reason = code2reason(304),
        status = 304,
        version = 1.1,
        content = 'hello',
        header = {
            dict = {
                ['content-location'] = {
                    val = {
                        'http://example.com',
                    },
                },
                ['content-length'] = {
                    val = {
                        '5',
                    },
                },
            },
        },
    })

    -- test that returns error if uri is not a string
    ok, err, timeout = res:not_modified('hello', 123)
    assert.is_false(ok)
    assert.match(err, 'uri must be non-empty string')
    assert.is_nil(timeout)
end

function testcase.reply3xx()
    local data = ''
    local writer = {
        write = function(_, v)
            data = data .. v
            return #v
        end,
        flush = function()
        end,
    }

    -- test that 3xx responses except 300 and 304 responses
    for status, code in pairs({
        moved_permanently = 301,
        found = 302,
        see_other = 303,
        use_proxy = 305,
        temporary_redirect = 307,
        permanent_redirect = 308,
    }) do
        local res = new_responder(writer)
        local ok, err, timeout = res[status](res, 'http://example.com', 'hello')
        assert.is_nil(err)
        assert.is_nil(timeout)
        assert.is_true(ok)
        -- confirm that data is written to writer
        local msg = create_response(data)
        data = ''
        assert.contains(msg, {
            reason = code2reason(code),
            status = code,
            version = 1.1,
            content = 'hello',
            header = {
                dict = {
                    ['location'] = {
                        val = {
                            'http://example.com',
                        },
                    },
                    ['content-length'] = {
                        val = {
                            '5',
                        },
                    },
                },
            },
        })

        -- test that returns error if uri is not a string
        ok, err, timeout = res[status](res, 123, 'hello')
        assert.is_false(ok)
        assert.match(err, 'uri must be non-empty string')
        assert.is_nil(timeout)
    end
end

function testcase.reply4xx5xx()
    local data = ''
    local writer = {
        write = function(_, v)
            data = data .. v
            return #v
        end,
        flush = function()
        end,
    }

    -- test that 4xx and 5xx responses
    for status, code in pairs({
        -- 4xx Client Error responses
        bad_request = 400,
        unauthorized = 401,
        payment_required = 402,
        forbidden = 403,
        not_found = 404,
        method_not_allowed = 405,
        not_acceptable = 406,
        proxy_authentication_required = 407,
        request_timeout = 408,
        conflict = 409,
        gone = 410,
        length_required = 411,
        precondition_failed = 412,
        payload_too_large = 413,
        request_uri_too_long = 414,
        unsupported_media_type = 415,
        requested_range_not_satisfiable = 416,
        expectation_failed = 417,
        unprocessable_entity = 422,
        locked = 423,
        failed_dependency = 424,
        upgrade_required = 426,
        precondition_required = 428,
        too_many_requests = 429,
        request_header_fields_too_large = 431,
        unavailable_for_legal_reasons = 451,
        -- 5xx Server Error responses
        internal_server_error = 500,
        not_implemented = 501,
        bad_gateway = 502,
        service_unavailable = 503,
        gateway_timeout = 504,
        http_version_not_supported = 505,
        variant_also_negotiates = 506,
        insufficient_storage = 507,
        loop_detected = 508,
        not_extended = 510,
        network_authentication_required = 511,
    }) do
        local res = new_responder(writer)
        local ok, err, timeout = res[status](res, 'hello')
        assert.is_nil(err)
        assert.is_nil(timeout)
        assert.is_true(ok)
        -- confirm that data is written to writer
        local msg = create_response(data)
        data = ''
        assert.contains(msg, {
            reason = code2reason(code),
            status = code,
            version = 1.1,
            content = 'hello',
            header = {
                dict = {
                    ['content-length'] = {
                        val = {
                            '5',
                        },
                    },
                },
            },
        })
    end
end
