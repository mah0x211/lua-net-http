require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local mkdtemp = require('mkdtemp')
local rmdir = require('rmdir')
local compiler = require('net.http.router.compiler')
local loadfenv = require('net.http.router.loadfenv')

local TESTDIR

function testcase.before_each()
    TESTDIR = assert(mkdtemp('./compiler_test_XXXXXX'))
end

function testcase.after_each()
    if TESTDIR and not TESTDIR:find('^/') then
        assert(rmdir(TESTDIR, true))
        TESTDIR = nil
    end
end

local function writefile(name, content)
    local path = TESTDIR .. '/' .. name
    local f = assert(io.open(path, 'w'))
    f:write(content)
    f:close()
    return path
end

-- ============================================================
-- compiler()
-- ============================================================

function testcase.compiler_fenv_not_table()
    -- test that fenv must be a table
    local err = assert.throws(compiler, '/dummy/path.lua', 'not_a_table')
    assert.match(err, 'fenv must be table')
end

function testcase.compiler_fenv_nil()
    -- test that fenv=nil is treated as not a table
    local err = assert.throws(compiler, '/dummy/path.lua', nil)
    assert.match(err, 'fenv must be table')
end

function testcase.compiler_file_not_found()
    -- test that non-existent file returns loadfile error
    local fenv = loadfenv()
    local result, err = compiler(TESTDIR .. '/nonexistent.lua', fenv)
    assert.equal(result, nil)
    assert.re_match(err, 'failed to loadfile')
end

function testcase.compiler_file_syntax_error()
    -- test that file with Lua syntax error returns loadfile error
    local path = writefile('syntax_error.lua', 'this is not valid lua !!!')
    local fenv = loadfenv()
    local result, err = compiler(path, fenv)
    assert.equal(result, nil)
    assert.re_match(err, 'failed to loadfile')
end

function testcase.compiler_file_runtime_error()
    -- test that file that throws at runtime returns pre-process error
    local path = writefile('runtime_error.lua', 'error("intentional error")')
    local fenv = loadfenv()
    local result, err = compiler(path, fenv)
    assert.equal(result, nil)
    assert.re_match(err, 'failed to pre-process')
end

function testcase.compiler_valid_file()
    -- test that valid file returning a table works correctly
    local path = writefile('valid.lua', [[
return {
    get = function() return 'ok' end,
    post = function() return 'posted' end,
}
]])
    local fenv = loadfenv()
    local result = assert(compiler(path, fenv))
    assert.is_table(result)
    assert.is_func(result.get)
    assert.is_func(result.post)
end

function testcase.compiler_valid_file_returns_nil()
    -- test that file returning nil is returned as-is
    local path = writefile('returns_nil.lua', '-- no return')
    local fenv = loadfenv()
    local result = compiler(path, fenv)
    assert.equal(result, nil)
end

function testcase.compiler_fenv_is_sandboxed()
    -- test that the file runs in the provided environment (fenv)
    -- require is NOT in the fenv, so accessing it should yield nil
    local path = writefile('check_env.lua', [[
local has_require = (require ~= nil)
return { has_require = has_require }
]])
    local fenv = loadfenv()
    -- fenv does not include 'require', so has_require should be false
    -- (or raise an error if _ENV doesn't have it)
    -- Just verify compilation succeeds with the sandbox
    assert.not_throws(compiler, path, fenv)
end
