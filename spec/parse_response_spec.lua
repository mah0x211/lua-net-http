local ParseResponse = require('net.http.parse').response;


describe("test net.http.parser.request", function()
    it("can parse line terminated by CRLF", function()
        for _, msg in ipairs({
            {
                res = 0,
                val = "HTTP/1.0 200 OK\r\n" ..
                      "Host: example.com\r\n" ..
                      "\r\n",
                cmp = {
                    version = 10,
                    status = 200,
                    reason = "OK",
                    header = {
                        host = "example.com"
                    }
                }
            },
            {
                res = 0,
                val = "HTTP/1.1 200 OK\r\n" ..
                      "Host1: example.com\r\n" ..
                      "Host2: example.com\r\n" ..
                      "Host3: 1.example.com 2.example.com\t3.example.com\r\n" ..
                      "\r\n",
                cmp = {
                    version = 11,
                    status = 200,
                    reason = "OK",
                    header = {
                      host1 = 'example.com',
                      host2 = 'example.com',
                      host3 = '1.example.com 2.example.com\t3.example.com'
                    }
                }
            }
        }) do
            local res = {
                header = {}
            }
            local consumed = ParseResponse( res, msg.val )

            if msg.res < 0 then
                assert.are.equal( msg.res, consumed )
            else
                assert.are.equal( #msg.val, consumed )
                assert.are.same( msg.cmp, res )
            end
        end
    end)


    it("can parse line terminated by LF", function()
        for _, msg in ipairs({
            {
                res = 0,
                val = "HTTP/1.0 200 OK\n" ..
                      "Host: example.com\n" ..
                      "\n",
                cmp = {
                    version = 10,
                    status = 200,
                    reason = "OK",
                    header = {
                        host = "example.com",
                    }
                }
            },
            {
                res = 0,
                val = "HTTP/1.1 200 OK\n" ..
                      "Host1: example.com\n" ..
                      "Host2: example.com\n" ..
                      "Host3: 1.example.com 2.example.com\t3.example.com\n" ..
                      "\n",
                cmp = {
                    version = 11,
                    status = 200,
                    reason = "OK",
                    header = {
                        host1 = 'example.com',
                        host2 = 'example.com',
                        host3 = '1.example.com 2.example.com\t3.example.com',
                    }
                }
            },
        }) do
            local res = {
                header = {}
            }
            local consumed = ParseResponse( res, msg.val )

            if msg.res < 0 then
                assert.are.equal( msg.res, consumed )
            else
                assert.are.equal( #msg.val, consumed )
                assert.are.same( msg.cmp, res )
            end
        end
    end)


    it("insert multiple same name headers into array", function()
        local msg = {
            res = 0,
            val = "HTTP/1.1 200 OK\n" ..
                    "Host: example1.com\n" ..
                    "Host: example2.com\n" ..
                    "Host: example3.com\n" ..
                    "Host: 1.example.com 2.example.com\t3.example.com\n" ..
                    "\n",
            cmp = {
                version = 11,
                status = 200,
                reason = "OK",
                header = {
                    host = {
                        'example1.com',
                        'example2.com',
                        'example3.com',
                        '1.example.com 2.example.com\t3.example.com',
                    }
                }
            }
        }
        local res = {
            header = {}
        }
        local consumed = ParseResponse( res, msg.val )

        if msg.res < 0 then
            assert.are.equal( msg.res, consumed )
        else
            assert.are.equal( #msg.val, consumed )
            assert.are.same( msg.cmp, res )
        end
    end)
end)

