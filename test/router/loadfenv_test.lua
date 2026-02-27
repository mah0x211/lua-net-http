require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local loadfenv = require('net.http.router.loadfenv')

-- ============================================================
-- loadfenv()
-- ============================================================

function testcase.loadfenv_returns_table()
    -- test that loadfenv returns a table
    local env = loadfenv()
    assert.is_table(env)
end

function testcase.loadfenv_includes_version()
    -- test that _VERSION is present
    local env = loadfenv()
    assert.is_string(env._VERSION)
    assert.equal(env._VERSION, _VERSION)
end

function testcase.loadfenv_includes_safe_functions()
    -- test that safe standard functions are present
    local env = loadfenv()
    -- assert may be the testcase assert module (table) or built-in (function)
    assert(env.assert ~= nil)
    assert.is_func(env.error)
    assert.is_func(env.ipairs)
    assert.is_func(env.next)
    assert.is_func(env.pairs)
    assert.is_func(env.pcall)
    assert.is_func(env.print)
    assert.is_func(env.rawequal)
    assert.is_func(env.select)
    assert.is_func(env.tonumber)
    assert.is_func(env.tostring)
    assert.is_func(env.type)
    assert.is_func(env.xpcall)
end

function testcase.loadfenv_excludes_unsafe_functions()
    -- test that dangerous functions are NOT present
    local env = loadfenv()
    assert.equal(env.require, nil)
    assert.equal(env.loadfile, nil)
    assert.equal(env.load, nil)
    assert.equal(env.dofile, nil)
    assert.equal(env.getmetatable, nil)
    assert.equal(env.setmetatable, nil)
    assert.equal(env.rawget, nil)
    assert.equal(env.rawset, nil)
    assert.equal(env.collectgarbage, nil)
    assert.equal(env.getfenv, nil)
    assert.equal(env.setfenv, nil)
    assert.equal(env.module, nil)
    assert.equal(env.loadstring, nil)
end

function testcase.loadfenv_includes_io_table()
    -- test that io module subset is present
    local env = loadfenv()
    assert.is_table(env.io)
    assert.is_func(env.io.open)
    assert.is_func(env.io.close)
    assert.is_func(env.io.read)
    assert.is_func(env.io.write)
    assert.is_func(env.io.lines)
    assert.is_func(env.io.flush)
    -- stdin/stdout/stderr are excluded
    assert.equal(env.io.stdin, nil)
    assert.equal(env.io.stdout, nil)
    assert.equal(env.io.stderr, nil)
end

function testcase.loadfenv_includes_math_table()
    -- test that math module is present
    local env = loadfenv()
    assert.is_table(env.math)
    assert.is_func(env.math.floor)
    assert.is_func(env.math.ceil)
    assert.is_func(env.math.abs)
    assert.is_func(env.math.max)
    assert.is_func(env.math.min)
    assert.is_func(env.math.random)
end

function testcase.loadfenv_includes_os_table()
    -- test that os module subset is present
    local env = loadfenv()
    assert.is_table(env.os)
    assert.is_func(env.os.clock)
    assert.is_func(env.os.date)
    assert.is_func(env.os.time)
    assert.is_func(env.os.getenv)
    -- execute and exit are excluded for security
    assert.equal(env.os.execute, nil)
    assert.equal(env.os.exit, nil)
end

function testcase.loadfenv_includes_string_table()
    -- test that string module is present
    local env = loadfenv()
    assert.is_table(env.string)
    assert.is_func(env.string.format)
    assert.is_func(env.string.find)
    assert.is_func(env.string.match)
    assert.is_func(env.string.gmatch)
    assert.is_func(env.string.gsub)
    assert.is_func(env.string.sub)
    assert.is_func(env.string.len)
    assert.is_func(env.string.upper)
    assert.is_func(env.string.lower)
end

function testcase.loadfenv_includes_table_module()
    -- test that table module is present
    local env = loadfenv()
    assert.is_table(env.table)
    assert.is_func(env.table.insert)
    assert.is_func(env.table.remove)
    assert.is_func(env.table.concat)
    assert.is_func(env.table.sort)
end

function testcase.loadfenv_returns_independent_tables()
    -- test that each call returns a new independent table
    local env1 = loadfenv()
    local env2 = loadfenv()
    -- modifying one should not affect the other
    env1.my_custom_key = 'test_value'
    assert.equal(env2.my_custom_key, nil)
end

function testcase.loadfenv_utf8_table()
    -- test that utf8 is included (Lua 5.4)
    local env = loadfenv()
    -- utf8 may be nil on older Lua versions, but should be a table or nil
    if env.utf8 ~= nil then
        assert.is_table(env.utf8)
    end
end
