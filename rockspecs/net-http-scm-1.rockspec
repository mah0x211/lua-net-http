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
    "net >= 0.15.0",
    "rfcvalid >= 0.3.0"
}
build = {
    type = "builtin",
    modules = {
        ['net.http.parser'] = "lib/parser.lua",
        ['net.http.server'] = "lib/server.lua",
        ['net.http.status'] = "lib/status.lua",
    }
}

