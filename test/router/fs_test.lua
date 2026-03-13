require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local mkdtemp = require('mkdtemp')
local mkdir = require('mkdir')
local rmdir = require('rmdir')

local new_fs = require('net.http.router.fs')

local TESTDIR

function testcase.before_each()
    TESTDIR = assert(mkdtemp('./fs_test_XXXXXX'))
end

function testcase.after_each()
    assert(rmdir(TESTDIR, true))
end

local function writefile(relpath, content)
    local path = TESTDIR .. relpath
    local dir = path:match('^(.+)/[^/]+$')
    assert(mkdir(dir, nil, true, false))
    local f = assert(io.open(path, 'w'))
    f:write(content or '')
    f:close()
end

function testcase.new()
    -- test that create a new fs instance
    local fs = assert(new_fs(TESTDIR))
    assert.re_match(fs, '^net[.]http[.]router[.]fs: ')

    -- test that rootdir must be string
    local err = assert.throws(new_fs, 123)
    assert.re_match(err, "bad argument 'rootdir'")

    -- test that rootdir must be an existing directory
    err = assert.throws(new_fs, '/nonexistent/path/that/does/not/exist')
    assert.not_nil(err)
end

function testcase.new_with_follow_symlink_option()
    -- test that follow_symlink option is accepted
    assert.not_throws(new_fs, TESTDIR, {
        follow_symlink = true,
    })
    assert.not_throws(new_fs, TESTDIR, {
        follow_symlink = false,
    })

    -- test that follow_symlink must be boolean
    local err = assert.throws(new_fs, TESTDIR, {
        follow_symlink = 1,
    })
    assert.re_match(err, "bad argument 'opts.follow_symlink'")
end

function testcase.new_with_loadfenv_option()
    -- test that loadfenv option is accepted
    assert.not_throws(new_fs, TESTDIR, {
        loadfenv = function()
            return {}
        end,
    })

    -- test that loadfenv must be callable
    local err = assert.throws(new_fs, TESTDIR, {
        loadfenv = 1,
    })
    assert.re_match(err, "bad argument 'opts.loadfenv'")
end

function testcase.new_with_compiler_option()
    -- test that compiler option is accepted
    assert.not_throws(new_fs, TESTDIR, {
        compiler = function(pathname, fenv)
            return {}
        end,
    })

    -- test that compiler must be callable
    local err = assert.throws(new_fs, TESTDIR, {
        compiler = 1,
    })
    assert.re_match(err, "bad argument 'opts.compiler'")
end

function testcase.new_with_precheck_option()
    -- test that precheck option is accepted
    assert.not_throws(new_fs, TESTDIR, {
        precheck = function(pathinfo, stat)
            return true
        end,
    })

    -- test that precheck must be callable
    local err = assert.throws(new_fs, TESTDIR, {
        precheck = 1,
    })
    assert.re_match(err, "bad argument 'opts.precheck'")
end

function testcase.new_delegates_router_opts()
    -- test that invalid router options cause an error (delegated to router)
    local err = assert.throws(new_fs, TESTDIR, {
        trim_extensions = 'not_a_table',
    })
    assert.re_match(err, "bad argument 'opts.trim_extensions'")
end

function testcase.build_empty_dir()
    -- test that build() succeeds on an empty directory
    local fs = assert(new_fs(TESTDIR))
    local ok, err = fs:build()
    assert.is_true(ok)
    assert.is_nil(err)
end

function testcase.build_with_static_file()
    -- test that a plain HTML file is registered as a static file
    writefile('/page.html', '<html></html>')

    local fs = assert(new_fs(TESTDIR))
    assert(fs:build())

    local route = fs:lookup('/page')
    assert.not_nil(route)
    assert.equal(route.route, '/page')
    assert.not_nil(route.finfo)
    assert.equal(route.finfo.pathname, '/page.html')
end

function testcase.build_with_index_file()
    -- test that index.html produces a route of '/'
    writefile('/index.html', '<html></html>')

    local fs = assert(new_fs(TESTDIR))
    assert(fs:build())

    local route = fs:lookup('/')
    assert.not_nil(route)
    assert.equal(route.route, '/')
end

function testcase.build_with_script_file()
    -- test that a @-prefixed .lua script is registered as a content handler
    writefile('/@index.lua', [[
return {
    get = function() end,
    post = function() end,
}
]])

    local fs = assert(new_fs(TESTDIR, {
        trim_extensions = {
            '.lua',
        },
    }))
    assert(fs:build())

    local route = fs:lookup('/')
    assert.not_nil(route)
    assert.not_nil(route.handlers)
    assert.not_nil(route.handlers.get)
    assert.not_nil(route.handlers.post)
    assert.is_func(route.handlers.get.handler)
end

function testcase.build_with_filter_script()
    -- test that a #-prefixed .lua script is registered as a filter handler
    writefile('/#1.cors.lua', [[
return {
    ['@all'] = function() end,
}
]])

    local fs = assert(new_fs(TESTDIR))
    assert(fs:build())

    local route = fs:lookup('/')
    assert.not_nil(route)
    assert.not_nil(route.filters)
    assert.not_nil(route.filters.handlers)
end

function testcase.build_with_precheck_skip()
    -- test that precheck returning false,nil causes the file to be skipped
    writefile('/page.html', '<html></html>')
    writefile('/skip.html', '<html></html>')

    local skipped = {}
    local fs = assert(new_fs(TESTDIR, {
        precheck = function(pathinfo, stat)
            if pathinfo.name == 'skip' then
                skipped[#skipped + 1] = pathinfo.pathname
                return false
            end
            return true
        end,
    }))
    assert(fs:build())

    assert.not_nil(fs:lookup('/page'))
    assert.is_nil(fs:lookup('/skip'))
    assert.equal(#skipped, 1)
end

function testcase.build_with_precheck_abort()
    -- test that precheck returning false,err causes build() to fail
    writefile('/page.html', '<html></html>')

    local fs = assert(new_fs(TESTDIR, {
        precheck = function(pathinfo, stat)
            return false, 'precheck rejected ' .. pathinfo.pathname
        end,
    }))

    local ok, err = fs:build()
    assert.is_nil(ok)
    assert.re_match(err, 'precheck rejected')
end

function testcase.build_error_invalid_lua()
    -- test that a .lua file with syntax errors causes build() to fail
    writefile('/@handler.lua', 'invalid lua syntax {{{')

    local fs = assert(new_fs(TESTDIR))
    local ok, err = fs:build()
    assert.is_nil(ok)
    assert.not_nil(err)
end

function testcase.build_error_empty_return()
    -- test that a .lua file returning an empty table causes build() to fail
    writefile('/@handler.lua', 'return {}')

    local fs = assert(new_fs(TESTDIR))
    local ok, err = fs:build()
    assert.is_nil(ok)
    assert.re_match(err, 'must return non-empty method table')
end

function testcase.build_error_non_callable()
    -- test that a non-callable method handler causes build() to fail
    writefile('/@handler.lua', 'return { get = 1 }')

    local fs = assert(new_fs(TESTDIR))
    local ok, err = fs:build()
    assert.is_nil(ok)
    assert.re_match(err, 'method handler must be callable object')
end

function testcase.build_error_static_lua()
    -- test that a content handler in a staticdir causes build() to fail
    writefile('/static/@handler.lua', 'return { get = function() end }')

    local fs = assert(new_fs(TESTDIR, {
        staticdirs = {
            '/static',
        },
    }))
    local ok, err = fs:build()
    assert.is_nil(ok)
    assert.re_match(err, 'treated as a static file')
end

function testcase.build_ignores_dotfiles()
    -- test that files starting with '.' are ignored by default
    writefile('/.hidden.html', '')
    writefile('/visible.html', '')

    local fs = assert(new_fs(TESTDIR))
    assert(fs:build())

    assert.is_nil(fs:lookup('/.hidden'))
    assert.not_nil(fs:lookup('/visible'))
end

function testcase.build_ignores_dot_dirs()
    -- test that directories starting with '.' are not traversed
    writefile('/.git/config', '')
    writefile('/public/index.html', '')

    local fs = assert(new_fs(TESTDIR))
    assert(fs:build())

    assert.is_nil(fs:lookup('/.git/config'))
    assert.not_nil(fs:lookup('/public'))
end

function testcase.build_with_staticdir_file()
    -- test that a file in a staticdir is registered as a static file
    -- (evalfile: is_static=true, type='file' → return stat)
    writefile('/page.html', '<html></html>')

    local fs = assert(new_fs(TESTDIR, {
        staticdirs = {
            '/',
        },
    }))
    assert(fs:build())

    local route = fs:lookup('/page')
    assert.not_nil(route)
    assert.not_nil(route.finfo)
    assert.equal(route.finfo.pathname, '/page.html')
end

function testcase.build_with_wildcard_file()
    -- test that a wildcard file (*name.ext, non-.lua) is registered as a static file
    -- (evalfile: is_static=false, type='wildcard', ext != '.lua' → return stat)
    writefile('/*all.html', '')

    local fs = assert(new_fs(TESTDIR))
    assert(fs:build())

    assert.not_nil(fs:lookup('/*all.html'))
end

function testcase.build_error_non_lua_handler()
    -- test that a content/filter handler with a non-.lua extension causes an error
    -- (evalfile: is_static=false, ext != '.lua', type='content' → return errorf)
    writefile('/@handler.html', '')

    local fs = assert(new_fs(TESTDIR))
    local ok, err = fs:build()
    assert.is_nil(ok)
    assert.re_match(err, 'extension.*must be.*[.]lua')
end

function testcase.build_ignores_invalid_filename()
    -- test that files with invalid names (parse_pathname returns nil) are silently skipped
    -- (#0 does not match the filter pattern, parse returns nil)
    writefile('/#0.lua', '')
    writefile('/valid.html', '')

    local fs = assert(new_fs(TESTDIR))
    assert(fs:build())

    assert.is_nil(fs:lookup('/#0'))
    assert.not_nil(fs:lookup('/valid'))
end

function testcase.build_error_duplicate_filter_name()
    -- test that registering two filter files with the same filter name causes build() to fail
    -- (register_filter_handler returns false when filter name is already registered)
    writefile('/dir1/#1.cors.lua', 'return { ["@all"] = function() end }')
    writefile('/dir2/#1.cors.lua', 'return { ["@all"] = function() end }')

    local fs = assert(new_fs(TESTDIR))
    local ok, err = fs:build()
    assert.is_nil(ok)
    assert.re_match(err, 'already registered')
end

function testcase.build_error_unreadable_dir()
    -- test that a directory that cannot be read causes build() to fail
    -- (readdir returns nil, err → errorf 'failed to read directory')
    writefile('/secret/file.html', '')
    os.execute('chmod 000 ' .. TESTDIR .. '/secret')

    local fs = assert(new_fs(TESTDIR))
    local ok, err = fs:build()
    os.execute('chmod 755 ' .. TESTDIR .. '/secret')
    assert.is_nil(ok)
    assert.re_match(err, 'failed to read directory')
end

function testcase.build_error_stat_failure()
    -- test that a file whose stat fails causes build() to fail
    -- (chmod 444 on parent dir: readdir lists entries but stat fails with EACCES)
    writefile('/restricted/file.html', '')
    os.execute('chmod 444 ' .. TESTDIR .. '/restricted')

    local fs = assert(new_fs(TESTDIR))
    local ok, err = fs:build()
    os.execute('chmod 755 ' .. TESTDIR .. '/restricted')
    assert.is_nil(ok)
    assert.re_match(err, 'failed to stat')
end

function testcase.build_atomic_on_error()
    -- test that a failed build() does not replace the existing router
    writefile('/index.html', '')
    local fs = assert(new_fs(TESTDIR))
    assert(fs:build())
    local route_before = fs:lookup('/')
    assert.not_nil(route_before)

    -- add a file that will cause a build error
    writefile('/@bad.lua', 'invalid{{{')
    local ok, err = fs:build()
    assert.is_nil(ok)
    assert.not_nil(err)

    -- old router is still active
    local route_after = fs:lookup('/')
    assert.not_nil(route_after)
end

function testcase.lookup()
    -- test that lookup returns registered routes and nil for unknown ones
    writefile('/index.html', '')
    writefile('/about.html', '')

    local fs = assert(new_fs(TESTDIR))
    assert(fs:build())

    assert.not_nil(fs:lookup('/'))
    assert.not_nil(fs:lookup('/about'))
    assert.is_nil(fs:lookup('/nonexistent'))

    -- test that rebuild updates the routing table
    writefile('/new.html', '')
    assert(fs:build())
    assert.not_nil(fs:lookup('/new'))
end
