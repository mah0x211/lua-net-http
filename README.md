lua-net-http
====

[![test](https://github.com/mah0x211/lua-net-http/actions/workflows/test.yml/badge.svg)](https://github.com/mah0x211/lua-net-http/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/mah0x211/lua-net-http/branch/master/graph/badge.svg)](https://codecov.io/gh/mah0x211/lua-net-http)

http module for lua.

**NOTE: this module is under heavy development.**


***


## Installation

```
luarocks install net-http
```


## Usage


### Server

```lua
local format = string.format
local server = require('net.http.server')
local responder = require('net.http.responder')

-- create server with SO_REUSEADDR option
local s = server.new('127.0.0.1:8080', {
    reuseaddr = true,
})
s:listen()

local conn = s:accept()
local req = conn:read_request()
-- dump request
print('REQUEST ===')
print(format('%s %s HTTP/%.1f', req.method, req.uri, req.version))
for _, k, v in req.header:pairs() do
    print(format('%s: %s', k, v))
end
print('')
local content = req.content:read()
print(content)
print('')

-- reply response
local res = responder.new(conn)
res.header:set('content-type', 'text/plain')
res:ok('reply ' .. (content or '') .. '\n')
res:flush()
conn:close()

-- $ lua ./server.lua
-- REQUEST ===
-- GET / HTTP/1.1
-- User-Agent: lua-net-http
-- Content-Length: 11
-- Content-Type: application/octet-stream
-- Host: 127.0.0.1:8080
--
-- foo/bar/baz
```

### Client

```lua
local format = string.format
local fetch = require('net.http.fetch')

-- request to server
local res = fetch('http://127.0.0.1:8080', {
    content = 'foo/bar/baz',
})
-- dump response
print('RESPONSE ===')
print(format('HTTP/%.1f %d %s', res.version, res.status, res.reason))
for _, k, v in res.header:pairs() do
    print(format('%s: %s', k, v))
end
print('')
print(res.content:read())
print('')

-- $ lua ./client.lua
-- RESPONSE ===
-- HTTP/1.1 200 OK
-- Content-Length: 17
-- Content-Type: application/octet-stream
-- Date: Thu, 02 Jun 2022 23:48:17 GMT
--
-- reply foo/bar/baz
```

