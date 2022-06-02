rockspec_format = "3.0"
package = "net-http"
version = "scm-1"
source = {
    url = "git+https://github.com/mah0x211/lua-net-http.git"
}
description = {
    summary = "http module for lua",
    homepage = "https://github.com/mah0x211/lua-net-http",
    license = "MIT/X11",
    maintainer = "Masatoshi Fukunaga"
}
dependencies = {
    "lua >= 5.1",
    "halo >= 1.1.8",
    "base64mix >= 1.0.0",
    "bufio >= 0.4.0",
    "errno >= 0.3.0",
    "error >= 0.8.0",
    "isa >= 0.1.0",
    "net >= 0.24.0",
    "metamodule >= 0.2",
    "rfcvalid >= 0.6.0",
    "string-capitalize >= 0.1.0",
    "string-split >= 0.3.0",
    "string-trim >= 0.2.0",
    "stringex >= 0.1.0",
    "table-flatten >= 0.2.0",
    "tointeger >= 0.1.0",
    "url >= 1.4.0",
}
build = {
    type = "builtin",
    modules = {
        ['net.http'] = "http.lua",
        ['net.http.body'] = "lib/body.lua",
        ['net.http.connection'] = "lib/connection.lua",
        ['net.http.content'] = "lib/content.lua",
        ['net.http.content.chunked'] = "lib/content/chunked.lua",
        ['net.http.date'] = "lib/date.lua",
        ['net.http.entity'] = "lib/entity.lua",
        ['net.http.request'] = "lib/request.lua",
        ["net.http.header"] = "lib/header.lua",
        ["net.http.message"] = "lib/message.lua",
        ["net.http.message.request"] = "lib/message/request.lua",
        ["net.http.message.response"] = "lib/message/response.lua",
        ["net.http.query"] = "lib/query.lua",
        ['net.http.reader'] = "lib/reader.lua",
        ['net.http.response'] = "lib/response.lua",
        ['net.http.server'] = "lib/server.lua",
        ['net.http.status'] = "lib/status.lua",
        ['net.http.util.implc'] = {
            sources = { "src/implc.c" }
        },
        ['net.http.writer'] = "lib/writer.lua",
        ['net.http.parse'] = {
            incdirs = { "deps/lauxhlib" },
            sources = { "src/parse.c" }
        },
    }
}
