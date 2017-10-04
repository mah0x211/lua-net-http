local parser = require('net.http.parser');


describe("test net.http.parser.request", function()
    it("can parse line terminated by CRLF", function()
        for idx, msg in ipairs({
            {
                res = 0,
                val = "HTTP/1.0 200 OK\r\n" ..
                      "Host: example.com\r\n" ..
                      "\r\n",
                cmp = {
                    ver = 1.0,
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
                    ver = 1.1,
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
            local consumed = parser.response( res, msg.val, msg.limits )

            if msg.res < 0 then
                assert.are.equal( msg.res, consumed )
            else
                assert.are.equal( #msg.val, consumed )
                assert.are.same( msg.cmp, res )
            end
        end
    end)


    it("can parse line terminated by LF", function()
        for idx, msg in ipairs({
            {
                res = 0,
                val = "HTTP/1.0 200 OK\n" ..
                      "Host: example.com\n" ..
                      "\n",
                cmp = {
                    ver = 1.0,
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
                    ver = 1.1,
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
            local consumed = parser.response( res, msg.val, msg.limits )

            if msg.res < 0 then
                assert.are.equal( msg.res, consumed )
            else
                assert.are.equal( #msg.val, consumed )
                assert.are.same( msg.cmp, res )
            end
        end
    end)
end)

