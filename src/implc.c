/**
 *  Copyright (C) 2017 Masatoshi Teruya
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to
 *  deal in the Software without restriction, including without limitation the
 *  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 *  sell copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 *  IN THE SOFTWARE.
 *
 *  src/implc.c
 *  lua-net-http
 *  Created by Masatoshi Teruya on 17/10/11.
 */

#include <lauxlib.h>
#include <lua.h>

static int createtable_lua(lua_State *L)
{
    lua_Integer narr = luaL_optinteger(L, 1, 0);
    lua_Integer nrec = luaL_optinteger(L, 2, 0);

    lua_createtable(L, narr, nrec);

    return 1;
}

LUALIB_API int luaopen_net_http_util_implc(lua_State *L)
{
    struct luaL_Reg method[] = {
        {"createtable", createtable_lua},
        {NULL,          NULL           }
    };
    struct luaL_Reg *ptr = method;

    lua_newtable(L);
    while (ptr->name) {
        lua_pushstring(L, ptr->name);
        lua_pushcfunction(L, ptr->func);
        lua_rawset(L, -3);
        ptr++;
    }

    return 1;
}
