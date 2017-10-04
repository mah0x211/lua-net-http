local parser = require('net.http.parser');


describe("test net.http.parser.request", function()
    it("can parse line terminated by CRLF", function()
        for idx, msg in ipairs({
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host: example.com\r\n" ..
                      "\r\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host = 'example.com',
                    }
                }
            },
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host1: example.com\r\n" ..
                      "Host2: example.com\r\n" ..
                      "\r\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host1 = 'example.com',
                        host2 = 'example.com',
                    }
                }
            },
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host1: example.com\r\n" ..
                      "Host2: example.com\r\n" ..
                      "Host3: 1.example.com 2.example.com\t3.example.com\r\n" ..
                       "\r\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host1 = 'example.com',
                        host2 = 'example.com',
                        host3 = '1.example.com 2.example.com\t3.example.com',
                    }
                }
            },
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host1: \r\n" ..
                      "Host2: example.com\r\n" ..
                      "Host3: 1.example.com 2.example.com\t3.example.com\r\n" ..
                      "\r\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host2 = 'example.com',
                        host3 = '1.example.com 2.example.com\t3.example.com',
                    }
                }
            },
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host1:\r\n" ..
                      "Host2: example.com\r\n" ..
                      "Host3: 1.example.com 2.example.com\t3.example.com\r\n" ..
                      "\r\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host2 = 'example.com',
                        host3 = '1.example.com 2.example.com\t3.example.com',
                    }
                }
            },
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host1:       \r\n" ..
                      "Host2: example.com\r\n" ..
                      "Host3: 1.example.com 2.example.com\t3.example.com\r\n" ..
                      "\r\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host2 = 'example.com',
                        host3 = '1.example.com 2.example.com\t3.example.com',
                    }
                }
            },
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host1: example.com\r\n" ..
                      "Host2: \r\n" ..
                      "Host3: 1.example.com 2.example.com\t3.example.com\r\n" ..
                      "\r\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host1 = 'example.com',
                        host3 = '1.example.com 2.example.com\t3.example.com',
                    }
                }
            },
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host1: example.com\r\n" ..
                      "Host2: example.com\r\n" ..
                      "Host3: \r\n" ..
                      "\r\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host1 = 'example.com',
                        host2 = 'example.com',
                    }
                }
            },
            -- invalid headers
            {
                res = parser.EHDRFMT,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host: 1.example.com\r\n" ..
                      " 2.example.com\r\n" ..
                      "\t 2.example.com\r\n" ..
                      "\r\n"
            },
            {
                res = parser.EHDRVAL,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host: example.com\rinvalid format\n" ..
                      "\r\n"
            },
            {
                res = parser.EHDRFMT,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "invalid header format\r\n" ..
                      "\r\n"
            },
            {
                limits = parser.getlimits({
                    HEADER_LEN_MAX = 10
                }),
                res = parser.EHDRLEN,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host: exceeded the maximum header length\r\n" ..
                      "\r\n"
            },
            {
                limits = parser.getlimits({
                    HEADER_NUM_MAX = 2
                }),
                res = parser.EHDRNUM,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host1: example.com\r\n" ..
                      "Host2: example.com\r\n" ..
                      "Host3: example.com\r\n" ..
                      "Host4: exceeded the maximum number of header\r\n" ..
                     "\r\n"
            },

        }) do
            local req = {
                header = {}
            }
            local consumed = parser.request( req, msg.val, msg.limits )

            if msg.res < 0 then
                assert.are.equal( msg.res, consumed )
            else
                assert.are.equal( #msg.val, consumed )
                assert.are.same( msg.cmp, req )
            end
        end
    end)


    it("can parse line terminated by LF", function()
        for idx, msg in ipairs({
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host: example.com\n" ..
                      "\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host = 'example.com',
                    }
                }
            },
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host1: example.com\n" ..
                      "Host2: example.com\n" ..
                      "\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host1 = 'example.com',
                        host2 = 'example.com',
                    }
                }
            },
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host1: example.com\n" ..
                      "Host2: example.com\n" ..
                      "Host3: 1.example.com 2.example.com\t3.example.com\n" ..
                       "\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host1 = 'example.com',
                        host2 = 'example.com',
                        host3 = '1.example.com 2.example.com\t3.example.com',
                    }
                }
            },
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host1: \n" ..
                      "Host2: example.com\n" ..
                      "Host3: 1.example.com 2.example.com\t3.example.com\n" ..
                      "\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host2 = 'example.com',
                        host3 = '1.example.com 2.example.com\t3.example.com',
                    }
                }
            },
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host1:\n" ..
                      "Host2: example.com\n" ..
                      "Host3: 1.example.com 2.example.com\t3.example.com\n" ..
                      "\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host2 = 'example.com',
                        host3 = '1.example.com 2.example.com\t3.example.com',
                    }
                }
            },
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host1:       \n" ..
                      "Host2: example.com\n" ..
                      "Host3: 1.example.com 2.example.com\t3.example.com\n" ..
                      "\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host2 = 'example.com',
                        host3 = '1.example.com 2.example.com\t3.example.com',
                    }
                }
            },
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host1: example.com\n" ..
                      "Host2: \n" ..
                      "Host3: 1.example.com 2.example.com\t3.example.com\n" ..
                      "\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host1 = 'example.com',
                        host3 = '1.example.com 2.example.com\t3.example.com',
                    }
                }
            },
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host1: example.com\n" ..
                      "Host2: example.com\n" ..
                      "Host3: \n" ..
                      "\n",
                cmp = {
                    method = 'GET',
                    path = '/foo/bar/baz',
                    ver = 1.0,
                    header = {
                        host1 = 'example.com',
                        host2 = 'example.com',
                    }
                }
            },
            -- invalid headers
            {
                res = parser.EHDRFMT,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host: 1.example.com\n" ..
                      " 2.example.com\n" ..
                      "\t 2.example.com\n" ..
                      "\n"
            },
            {
                res = parser.EHDRVAL,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host: example.com\rinvalid format\n" ..
                      "\n"
            },
            {
                res = parser.EHDRFMT,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "invalid header format\n" ..
                      "\n"
            },
            {
                limits = parser.getlimits({
                    HEADER_LEN_MAX = 10
                }),
                res = parser.EHDRLEN,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host: exceeded the maximum header length\n" ..
                      "\n"
            },
            {
                limits = parser.getlimits({
                    HEADER_NUM_MAX = 2
                }),
                res = parser.EHDRNUM,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host1: example.com\n" ..
                      "Host2: example.com\n" ..
                      "Host3: example.com\n" ..
                      "Host4: exceeded the maximum number of header\n" ..
                     "\n"
            },

        }) do
            local req = {
                header = {}
            }
            local consumed = parser.request( req, msg.val, msg.limits )

            if msg.res < 0 then
                assert.are.equal( msg.res, consumed )
            else
                assert.are.equal( #msg.val, consumed )
                assert.are.same( msg.cmp, req )
            end
        end
    end)
end)


