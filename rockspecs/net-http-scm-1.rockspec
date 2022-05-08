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
    "bufio >= 0.4.0",
    "isa >= 0.1.0",
    "net >= 0.24.0",
    "metamodule >= 0.2",
    "rfcvalid >= 0.6.0",
    "stringex >= 0.1.0",
    "table-flatten >= 0.2.0",
    "tointeger >= 0.1.0",
    "url >= 1.2.1",
}
build = {
    type = "builtin",
    modules = {
        ['net.http'] = "http.lua",
        ['net.http.body'] = "lib/body.lua",
        ['net.http.content'] = "lib/content.lua",
        ['net.http.date'] = "lib/date.lua",
        ['net.http.entity'] = "lib/entity.lua",
        ['net.http.request'] = "lib/request.lua",
        ["net.http.header"] = "lib/header.lua",
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
