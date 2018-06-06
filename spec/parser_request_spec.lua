local Parse = require('net.http.parse')
local ParseRequest = Parse.request

describe("test net.http.parse.request", function()
    it("can parse line terminated by CRLF", function()
        for _, msg in ipairs({
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host: example.com\r\n" ..
                      "\r\n",
                cmp = {
                    method = 'GET',
                    uri = '/foo/bar/baz',
                    version = 10,
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
                    uri = '/foo/bar/baz',
                    version = 10,
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
                    uri = '/foo/bar/baz',
                    version = 10,
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
                    uri = '/foo/bar/baz',
                    version = 10,
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
                    uri = '/foo/bar/baz',
                    version = 10,
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
                    uri = '/foo/bar/baz',
                    version = 10,
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
                    uri = '/foo/bar/baz',
                    version = 10,
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
                    uri = '/foo/bar/baz',
                    version = 10,
                    header = {
                        host1 = 'example.com',
                        host2 = 'example.com',
                    }
                }
            },
            -- invalid headers
            {
                res = Parse.EHDRNAME,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host: 1.example.com\r\n" ..
                      " 2.example.com\r\n" ..
                      "\t 2.example.com\r\n" ..
                      "\r\n"
            },
            {
                res = Parse.EHDREOL,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host: example.com\rinvalid format\n" ..
                      "\r\n"
            },
            {
                res = Parse.EHDRNAME,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "invalid header format\r\n" ..
                      "\r\n"
            },
            {
                MAX_HDRLEN = 10,
                res = Parse.EHDRLEN,
                val = "GET /foo/bar/baz HTTP/1.0\r\n" ..
                      "Host: exceeded the maximum header length\r\n" ..
                      "\r\n"
            },
            {
                MAX_HDRNUM = 2,
                res = Parse.EHDRNUM,
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
            local consumed = ParseRequest(
                req, msg.val, msg.MAX_MSGLEN, msg.MAX_HDRLEN, msg.MAX_HDRNUM
            )

            if msg.res < 0 then
                assert.are.equal( msg.res, consumed )
            else
                assert.are.equal( #msg.val, consumed )
                assert.are.same( msg.cmp, req )
            end
        end
    end)


    it("can parse line terminated by LF", function()
        for _, msg in ipairs({
            {
                res = 0,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host: example.com\n" ..
                      "\n",
                cmp = {
                    method = 'GET',
                    uri = '/foo/bar/baz',
                    version = 10,
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
                    uri = '/foo/bar/baz',
                    version = 10,
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
                    uri = '/foo/bar/baz',
                    version = 10,
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
                    uri = '/foo/bar/baz',
                    version = 10,
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
                    uri = '/foo/bar/baz',
                    version = 10,
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
                    uri = '/foo/bar/baz',
                    version = 10,
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
                    uri = '/foo/bar/baz',
                    version = 10,
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
                    uri = '/foo/bar/baz',
                    version = 10,
                    header = {
                        host1 = 'example.com',
                        host2 = 'example.com',
                    }
                }
            },
            -- invalid headers
            {
                res = Parse.EHDRNAME,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host: 1.example.com\n" ..
                      " 2.example.com\n" ..
                      "\t 2.example.com\n" ..
                      "\n"
            },
            {
                res = Parse.EHDREOL,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host: example.com\rinvalid format\n" ..
                      "\n"
            },
            {
                res = Parse.EHDRNAME,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "invalid header format\n" ..
                      "\n"
            },
            {
                MAX_HDRLEN = 10,
                res = Parse.EHDRLEN,
                val = "GET /foo/bar/baz HTTP/1.0\n" ..
                      "Host: exceeded the maximum header length\n" ..
                      "\n"
            },
            {
                MAX_HDRNUM = 2,
                res = Parse.EHDRNUM,
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
            local consumed = ParseRequest(
                req, msg.val, msg.MAX_MSGLEN, msg.MAX_HDRLEN, msg.MAX_HDRNUM
            )

            if msg.res < 0 then
                assert.are.equal( msg.res, consumed )
            else
                assert.are.equal( #msg.val, consumed )
                assert.are.same( msg.cmp, req )
            end
        end
    end)
end)


