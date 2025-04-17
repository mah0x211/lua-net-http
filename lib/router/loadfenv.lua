--
-- Copyright (C) 2025 Masatoshi Fukunaga
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
-- modules
local pairs = pairs

--- shallow_copy
--- @param tbl table|nil
--- @return table|nil
local function shallow_copy(tbl)
    if tbl ~= nil then
        local newtbl = {}
        for k, v in pairs(tbl) do
            newtbl[k] = v
        end
        return newtbl
    end
end

--- loadfenv
--- @return table<string, string|function|table>
local function loadfenv()
    -- unsafe functions are commented out
    return {
        _VERSION = _VERSION,

        -- Lua 5.1
        assert = assert,
        -- collectgarbage = collectgarbage,
        -- dofile,
        error = error,
        -- getfenv = getfenv,
        -- getmetatable = getmetatable,
        ipairs = ipairs,
        -- load = load,
        -- loadfile = loadfile,
        -- loadstring = loadstring,
        -- module = module,
        next = next,
        pairs = pairs,
        pcall = pcall,
        print = print,
        rawequal = rawequal,
        -- rawget = rawget,
        -- rawset = rawset,
        -- require = require,
        select = select,
        -- setfenv = setfenv,
        -- setmetatable = setmetatable,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        unpack = unpack or table.unpack,
        xpcall = xpcall,

        -- Lua 5.4
        warn = warn,

        -- this module is only defined in Lua 5.2
        -- bit32 = {
        --     arshift = bit32.arshift,
        --     band = bit32.band,
        --     bnot = bit32.bnot,
        --     bor = bit32.bor,
        --     btest = bit32.btest,
        --     bxor = bit32.bxor,
        --     extract = bit32.extract,
        --     lrotate = bit32.lrotate,
        --     lshift = bit32.lshift,
        --     replace = bit32.replace,
        --     rrotate = bit32.rrotate,
        --     rshift = bit32.rshift,
        -- },

        -- coroutine = {
        --     -- Lua 5.1
        --     create = coroutine.create,
        --     resume = coroutine.resume,
        --     running = coroutine.running,
        --     status = coroutine.status,
        --     wrap = coroutine.wrap,
        --     yield = coroutine.yield,

        --     -- Lua 5.3
        --     isyieldable = coroutine.isyieldable,
        -- },

        -- debug = {
        --     -- Lua 5.1
        --     debug = debug.debug,
        --     getfenv = debug.getfenv,
        --     gethook = debug.gethook,
        --     getinfo = debug.getinfo,
        --     getlocal = debug.getlocal,
        --     getmetatable = debug.getmetatable,
        --     getregistry = debug.getregistry,
        --     getupvalue = debug.getupvalue,
        --     setfenv = debug.setfenv,
        --     sethook = debug.sethook,
        --     setlocal = debug.setlocal,
        --     setmetatable = debug.setmetatable,
        --     setupvalue = debug.setupvalue,
        --     traceback = debug.traceback,

        --     -- Lua 5.2
        --     getuservalue = debug.getuservalue,
        --     setuservalue = debug.setuservalue,
        --     upvalueid = debug.upvalueid,
        --     upvaluejoin = debug.upvaluejoin,
        -- },

        io = {
            -- Lua 5.1
            close = io.close,
            flush = io.flush,
            input = io.input,
            lines = io.lines,
            open = io.open,
            output = io.output,
            popen = io.popen,
            read = io.read,
            -- stderr = io.stderr,
            -- stdin = io.stdin,
            -- stdout = io.stdout,
            tmpfile = io.tmpfile,
            type = io.type,
            write = io.write,
        },

        math = {
            -- Lua 5.1
            abs = math.abs,
            acos = math.acos,
            asin = math.asin,
            atan = math.atan,
            atan2 = math.atan2,
            ceil = math.ceil,
            cos = math.cos,
            cosh = math.cosh,
            deg = math.deg,
            exp = math.exp,
            floor = math.floor,
            fmod = math.fmod,
            frexp = math.frexp,
            huge = math.huge,
            ldexp = math.ldexp,
            log = math.log,
            log10 = math.log10,
            max = math.max,
            min = math.min,
            modf = math.modf,
            pi = math.pi,
            pow = math.pow,
            rad = math.rad,
            random = math.random,
            randomseed = math.randomseed,
            sin = math.sin,
            sinh = math.sinh,
            sqrt = math.sqrt,
            tan = math.tan,
            tanh = math.tanh,

            -- Lua 5.3
            maxinteger = math.maxinteger,
            mininteger = math.mininteger,
            tointeger = math.tointeger,
            type = math.type,
            ult = math.ult,
        },

        os = {
            -- Lua 5.1
            clock = os.clock,
            date = os.date,
            difftime = os.difftime,
            -- execute = os.execute,
            -- exit = os.exit,
            getenv = os.getenv,
            remove = os.remove,
            rename = os.rename,
            time = os.time,
            tmpname = os.tmpname,
        },

        -- package = {
        --     -- Lua 5.1
        --     cpath = package.cpath,
        --     loaded = package.loaded,
        --     loadlib = package.loadlib,
        --     path = package.path,
        --     preload = package.preload,
        --     seeall = package.seeall,

        --     -- Lua 5.2
        --     config = package.config,
        --     searchers = package.searchers,
        --     searchpath = package.searchpath,
        -- },

        string = {
            -- Lua 5.1
            byte = string.byte,
            char = string.char,
            dump = string.dump,
            find = string.find,
            format = string.format,
            gmatch = string.gmatch,
            gsub = string.gsub,
            len = string.len,
            lower = string.lower,
            match = string.match,
            rep = string.rep,
            reverse = string.reverse,
            sub = string.sub,
            upper = string.upper,

            -- Lua 5.3
            pack = string.pack,
            packsize = string.packsize,
            unpack = string.unpack,
        },

        table = {
            -- Lua 5.1
            concat = table.concat,
            insert = table.insert,
            maxn = table.maxn,
            remove = table.remove,
            sort = table.sort,

            -- Lua 5.2
            pack = table.pack,
            unpack = table.unpack,

            -- Lua 5.3
            move = table.move,
        },

        -- Lua 5.3
        utf8 = shallow_copy(utf8),
    }
end

return loadfenv
