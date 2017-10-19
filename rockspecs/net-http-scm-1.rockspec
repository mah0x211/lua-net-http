package = "net-http"
version = "scm-1"
source = {
    url = "git://github.com/mah0x211/lua-net-http.git"
}
description = {
    summary = "http module for lua",
    homepage = "https://github.com/mah0x211/lua-net-http",
    license = "MIT/X11",
    maintainer = "Masatoshi Teruya"
}
dependencies = {
    "lua >= 5.1",
    "idna >= 1.0.0",
    "gcfn >= 0.1.0",
    "net >= 0.18.0",
    "rfcvalid >= 0.6.0",
    "tointeger >= 0.1.0",
    "url >= 1.1.0",
}
build = {
    type = "builtin",
    modules = {
        ['net.http.body'] = "lib/body.lua",
        ['net.http.connection'] = "lib/connection.lua",
        ['net.http.date'] = "lib/date.lua",
        ['net.http.entity'] = "lib/entity.lua",
        ['net.http.header'] = "lib/header.lua",
        ['net.http.parser'] = "lib/parser.lua",
        ['net.http.request'] = "lib/request.lua",
        ['net.http.response'] = "lib/response.lua",
        ['net.http.server'] = "lib/server.lua",
        ['net.http.status'] = "lib/status.lua",
        ['net.http.util.implc'] = {
            sources = { "src/implc.c" }
        },
    }
}

