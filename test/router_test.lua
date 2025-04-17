require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local mkdtemp = require('mkdtemp')
local mkdir = require('mkdir')
local rmdir = require('rmdir')
local new_router = require('net.http.router').new

local TESTDIR
function testcase.before_each()
    TESTDIR = assert(mkdtemp('./router_test_XXXXXX'))
end

function testcase.after_each()
    if TESTDIR and not TESTDIR:find('^/') then
        assert(rmdir(TESTDIR, true))
        TESTDIR = nil
    end
end

local function createfile(pathname)
    -- pathname must not be contains '/./' or '/../'
    assert(not pathname:find('/%.%.?/'),
           'pathname must not be contains "/./" or "/../"')

    -- prepend the directory path to pathname, and remove double slashes
    pathname = TESTDIR .. '/' .. pathname
    pathname = pathname:gsub('/+', '/')

    -- create a directory
    local dirname = pathname:match('^(.+)/[^/]+$')
    assert(mkdir(dirname, nil, true, false))

    -- create a file
    return assert(io.open(pathname, 'w'))
end

function testcase.new()
    -- test that create a new router instance
    local r = new_router()
    assert.re_match(r, '^net[.]http[.]router: ')

    -- test that opts must be table
    local err = assert.throws(new_router, 'options')
    assert.re_match(err, "bad argument 'opts' .+table expected,")
end

function testcase.new_with_mime_option()
    -- test that create a new router instance with mimetypes option
    assert.not_throws(new_router, {
        mimetypes = [[
            text/html html;
            text/css css;
            text/javascript js;
            application/json json;
        ]],
    })

    -- test that must be string
    local err = assert.throws(new_router, {
        mimetypes = 1,
    })
    assert.re_match(err, "bad argument 'opts.mimetypes' .+string expected,")

    -- test that contains invalid value
    err = assert.throws(new_router, {
        mimetypes = 'extension/is-not-declared',
    })
    assert.re_match(err, "found invalid lines in opts.mimetypes")
end

function testcase.new_with_trim_extension_option()
    -- test that create a new router instance with trim_extensions option
    assert.not_throws(new_router, {
        trim_extensions = {
            '.html',
            '.htm',
        },
    })

    -- test that must be string array
    local err = assert.throws(new_router, {
        trim_extensions = 'html',
    })
    assert.re_match(err, "bad argument 'opts.trim_extensions' .+table expected,")

    -- test that contains invalid value
    err = assert.throws(new_router, {
        trim_extensions = {
            '.html',
            1,
        },
    })
    assert.re_match(err, "opts.trim_extensions#2 is not a string")
end

function testcase.new_with_staticdirs_option()
    -- test that create a new router instance with staticdirs option
    assert.not_throws(new_router, {
        staticdirs = {
            '/static',
            '/public',
        },
    })

    -- test that must be string array
    local err = assert.throws(new_router, {
        staticdirs = '/static',
    })
    assert.re_match(err, "bad argument 'opts.staticdirs' .+table expected,")

    -- test that contains invalid value
    err = assert.throws(new_router, {
        staticdirs = {
            '/static',
            1,
        },
    })
    assert.re_match(err, "opts.staticdirs#2 is not a string")
end

function testcase.new_with_ignore_option()
    -- test that create a new router instance with ignore option
    assert.not_throws(new_router, {
        ignore = {
            -- regexp patterns to ignore
            '^[.]git',
            '^[.]svn',
        },
    })

    -- test that must be string array
    local err = assert.throws(new_router, {
        ignore = '^[.]git',
    })
    assert.re_match(err, "bad argument 'opts.ignore' .+table expected,")

    -- test that contains invalid value
    err = assert.throws(new_router, {
        ignore = {
            '^[.]git',
            1,
        },
    })
    assert.re_match(err, "opts.ignore#2 .+ pattern must be string")

    -- test that contains invalid pattern
    err = assert.throws(new_router, {
        ignore = {
            '^[.]git',
            '^[.svn',
        },
    })
    assert.re_match(err, "opts.ignore#2 .+ failed to compile")
end

function testcase.new_with_no_ignore_option()
    -- test that create a new router instance with no ignore option
    assert.not_throws(new_router, {
        no_ignore = {
            -- regexp patterns to ignore
            '^[.]git',
            '^[.]svn',
        },
    })

    -- test that must be string array
    local err = assert.throws(new_router, {
        no_ignore = '^[.]git',
    })
    assert.re_match(err, "bad argument 'opts.no_ignore' .+table expected,")

    -- test that contains invalid value
    err = assert.throws(new_router, {
        no_ignore = {
            '^[.]git',
            1,
        },
    })
    assert.re_match(err, "opts.no_ignore#2 .+ pattern must be string")

    -- test that contains invalid pattern
    err = assert.throws(new_router, {
        no_ignore = {
            '^[.]git',
            '^[.svn',
        },
    })
    assert.re_match(err, "opts.no_ignore#2 .+ failed to compile")
end

function testcase.new_with_rootdir_option()
    -- test that create a new router instance with rootdir option
    assert.not_throws(new_router, {
        rootdir = TESTDIR,
    })

    -- test that must be string
    local err = assert.throws(new_router, {
        rootdir = 1,
    })
    assert.re_match(err, "bad argument 'opts.rootdir' .+string expected,")

    -- test that must be a directory
    err = assert.throws(new_router, {
        rootdir = TESTDIR .. '/not-found',
    })
    assert.match(err, 'ENOENT')
end

function testcase.new_with_follow_symlink_option()
    -- NOTE: the rootdir option is required for the following tests

    -- test that create a new router instance with follow_symlink option
    assert.not_throws(new_router, {
        rootdir = TESTDIR,
        follow_symlink = true,
    })

    -- test that must be boolean
    local err = assert.throws(new_router, {
        rootdir = TESTDIR,
        follow_symlink = 1,
    })
    assert.re_match(err,
                    "bad argument 'opts.follow_symlink' .+boolean expected,")
end

function testcase.new_with_loadfenv_option()
    -- NOTE: the rootdir option is required for the following tests

    -- test that create a new router instance with loadfenv option
    assert.not_throws(new_router, {
        rootdir = TESTDIR,
        loadfenv = function()
        end,
    })

    -- test that must be function
    local err = assert.throws(new_router, {
        rootdir = TESTDIR,
        loadfenv = 1,
    })
    assert.re_match(err,
                    "bad argument 'opts.loadfenv' .+callable object expected,")
end

function testcase.new_with_compiler_option()
    -- NOTE: the rootdir option is required for the following tests

    -- test that create a new router instance with compiler option
    assert.not_throws(new_router, {
        rootdir = TESTDIR,
        compiler = function()
        end,
    })

    -- test that must be function
    local err = assert.throws(new_router, {
        rootdir = TESTDIR,
        compiler = 1,
    })
    assert.re_match(err,
                    "bad argument 'opts.compiler' .+callable object expected,")
end

function testcase.new_with_precheck_option()
    -- test that create a new router instance with precheck option
    assert.not_throws(new_router, {
        precheck = function()
        end,
    })

    -- test that must be function
    -- NOTE: the rootdir option is required for the following tests
    local err = assert.throws(new_router, {
        rootdir = TESTDIR,
        precheck = 1,
    })
    assert.re_match(err,
                    "bad argument 'opts.precheck' .+callable object expected,")
end

function testcase.register_content_handler()
    local r = assert(new_router())
    local handler = function()
    end

    -- test that register a method handler for pathname
    assert.not_throws(function()
        r:register('/foo', 'get', handler)
    end)
    -- confirm that the pathname is registered
    local route = r:get('/foo')
    assert.equal(route, {
        route = '/foo',
        filename = 'foo',
        name = 'foo',
        handlers = {
            get = {
                type = 'content',
                method = 'get',
                handler = handler,
                pathname = '/foo',
            },
        },
    })

    -- test that register a method handler for root '/'
    assert.not_throws(function()
        r:register('/', 'get', handler)
    end)
    -- confirm that the pathname is registered
    route = r:get('/')
    assert.equal(route, {
        route = '/',
        handlers = {
            get = {
                type = 'content',
                method = 'get',
                handler = handler,
                pathname = '/',
            },
        },
    })

    -- test that index is a special filename that routing to the directory
    assert.not_throws(function()
        r:register('/index.html', 'post', handler)
    end)
    -- confirm that the pathname is registered
    route = r:get('/')
    assert.equal(route, {
        route = '/',
        filename = 'index.html',
        name = 'index',
        ext = '.html',
        handlers = {
            get = {
                type = 'content',
                method = 'get',
                handler = handler,
                pathname = '/',
            },
            post = {
                type = 'content',
                method = 'post',
                handler = handler,
                pathname = '/index.html',
            },
        },
    })
end

function testcase.register_invalid_content_handler()
    local r = assert(new_router())
    local handler = function()
    end

    -- test that cannot register handler for the same method
    local err = assert.throws(function()
        r:register('/index.html', 'post', handler)
        r:register('/', 'post', handler)
    end)
    assert.match(err, 'already registered with "/index.html"')

    -- test that pathname must be non-empty string
    err = assert.throws(function()
        r:register('', 'get', handler)
    end)
    assert.match(err, 'pathname must be non-empty string')

    -- test that pathname must be started with '/'
    err = assert.throws(function()
        r:register('foo', 'get', handler)
    end)
    assert.match(err, 'pathname must be started with "/"' ..
                     ' and must not be ended with "/"')

    -- test that pathname must not be end with '/'
    err = assert.throws(function()
        r:register('/foo/', 'get', handler)
    end)
    assert.match(err, 'pathname must be started with "/"' ..
                     ' and must not be ended with "/"')

    -- test that path-segments must be string matching the pattern
    err = assert.throws(function()
        r:register('/foo/b ar/baz', 'get', handler)
    end)
    assert.match(err,
                 '"b ar" must be matching the pattern "/^[.]?[a-z0-9_-]+$/i"')

    -- test that file-segment must be string matching the pattern
    err = assert.throws(function()
        r:register('/foo/bar/baz-', 'get', handler)
    end)
    assert.match(err,
                 '"baz-" must be matching the pattern "/^[.]?([a-z0-9_](?:[a-z0-9_-]*[a-z0-9_])*)((?:[.][a-z0-9](?:[a-z0-9_-]*[a-z0-9])*)*)$/i"')

    -- test that pathname contains ignore segments
    err = assert.throws(function()
        r:register('/.hidden/foo', 'get', handler)
    end)
    assert.match(err, 'segment ".hidden" is ignored by configuration')

    -- test that last-segment is ignored by configuration
    err = assert.throws(function()
        r:register('/foo/.git', 'get', handler)
    end)
    assert.match(err, 'filename ".git" is ignored by configuration')

    -- test that method must be non-empty string
    err = assert.throws(function()
        r:register('/foo', '', handler)
    end)
    assert.match(err, 'method must be non-empty string')

    -- test that method must be string matching the pattern
    err = assert.throws(function()
        r:register('/foo', 'g et', handler)
    end)
    assert.match(err,
                 'method must be string matching the pattern "/^@?[a-z](_*[a-z]+)*$/i"')

    -- test that 'all' method cannot be registered
    err = assert.throws(function()
        r:register('/foo', '@all', handler)
    end)
    assert.match(err, 'method "@all" is not allowed for the content handler')

    -- test that '@' prefix is not allowed except '@all' and '@any'
    err = assert.throws(function()
        r:register('/foo', '@hello', handler)
    end)
    assert.match(err, '@ prefix is allowed only for @all and @any methods')

    -- test that handler must be callable object
    err = assert.throws(function()
        r:register('/foo', 'get', 1)
    end)
    assert.match(err, 'handler must be callable object')
end

function testcase.register_content_handler_with_parameter_segment()
    local r = assert(new_router())
    local handler = function()
    end

    -- test that register with parameter segment
    assert.not_throws(function()
        r:register('/:foo/bar/:baz.html', 'get', handler)
    end)
    -- confirm that the pathname is registered
    local route = r:get('/:foo/bar/:baz.html')
    assert.equal(route, {
        -- extension part is removed when registering the handler
        route = '/:foo/bar/:baz.html',
        filename = ':baz.html',
        name = 'baz',
        ext = '.html',
        handlers = {
            get = {
                type = 'content',
                method = 'get',
                handler = handler,
                pathname = '/:foo/bar/:baz.html',
            },
        },
    })
    -- confirm that the parameters are extracted
    local _, glob = r:lookup('/foo-param/bar/baz-param.html')
    assert.equal(glob, {
        foo = 'foo-param',
        ['baz.html'] = 'baz-param.html',
    })
end

function testcase.register_content_handler_with_invalid_parameter_segment()
    local r = assert(new_router())
    local handler = function()
    end

    -- test that cannot register with invalid parameter segment
    local err = assert.throws(function()
        r:register('/foo/:ba-r/baz', 'get', handler)
    end)
    assert.match(err, 'matching the pattern "/^:[a-z0-9_]+$/i"')

    -- test that cannot register with invalid parameter last-segment
    err = assert.throws(function()
        r:register('/foo/bar/:ba-z.html', 'get', handler)
    end)
    assert.match(err,
                 '":ba-z.html" must be matching the pattern "/^:([a-z0-9_]+)((?:[.][a-z0-9](?:[a-z0-9_-]*[a-z0-9])*)*)$/i"')
end

function testcase.register_handler_with_content_segment()
    local r = assert(new_router())
    local handler = function()
    end

    -- test that register with content segment
    assert.not_throws(function()
        r:register('/foo/@baz.html', 'get', handler)
    end)
    -- confirm that the pathname is registered
    local route = r:get('/foo/baz')
    assert.equal(route, {
        -- extension part is removed when registering the handler
        route = '/foo/baz',
        filename = '@baz.html',
        name = 'baz',
        ext = '.html',
        handlers = {
            get = {
                type = 'content',
                method = 'get',
                handler = handler,
                pathname = '/foo/@baz.html',
            },
        },
    })

    -- test that index is a special filename that routing to the directory
    assert.not_throws(function()
        r:register('/foo/@index.html', 'get', handler)
    end)
    -- confirm that the pathname is registered
    route = r:get('/foo')
    assert.equal(route, {
        route = '/foo',
        filename = '@index.html',
        name = 'index',
        ext = '.html',
        handlers = {
            get = {
                type = 'content',
                method = 'get',
                handler = handler,
                pathname = '/foo/@index.html',
            },
        },
    })
end

function testcase.register_handler_with_invalid_content_segment()
    local r = assert(new_router())
    local handler = function()
    end

    -- test that cannot register with invalid content segment
    local err = assert.throws(function()
        r:register('/quu/@quux-.html', 'get', handler)
    end)
    assert.match(err,
                 '"@quux-.html" must be matching the pattern "/^@[.]?([a-z0-9_](?:[a-z0-9_-]*[a-z0-9_])*)((?:[.][a-z0-9](?:[a-z0-9_-]*[a-z0-9])*)*)$/i"')
end

function testcase.register_handler_with_filter_segment()
    local r = assert(new_router())
    local handler = function()
    end

    -- test that register with filter segment
    assert.not_throws(function()
        r:register('/', 'get', handler)
        r:register('/#5.foo', 'get', handler)
        r:register('/#6.bar', '@all', handler)
    end)
    -- confirm that the filter is registered
    local route = r:get('/')
    assert.equal(route, {
        route = '/',
        handlers = {
            get = {
                handler = handler,
                type = 'content',
                method = 'get',
                pathname = '/',
            },
        },
        filters = {
            orders = {
                [5] = '/#5.foo',
                [6] = '/#6.bar',
            },
            handlers = {
                ['@all'] = {
                    {
                        type = 'filter',
                        method = '@all',
                        pathname = '/#6.bar',
                        name = 'bar',
                        handler = handler,
                    },
                    bar = true,
                },
                get = {
                    {
                        type = 'filter',
                        method = 'get',
                        pathname = '/#5.foo',
                        name = 'foo',
                        handler = handler,
                    },
                    foo = true,
                },
            },
        },
    })

    -- test that the order of filters is determined by the order specifier
    assert.not_throws(function()
        r:register('/#2.qux', 'get', handler)
    end)
    -- confirm that the filter is registered
    route = r:get('/')
    assert.equal(route.filters, {
        orders = {
            [2] = '/#2.qux',
            [5] = '/#5.foo',
            [6] = '/#6.bar',
        },
        handlers = {
            ['@all'] = {
                {
                    type = 'filter',
                    method = '@all',
                    pathname = '/#6.bar',
                    name = 'bar',
                    handler = handler,
                },
                bar = true,
            },
            get = {
                {
                    type = 'filter',
                    method = 'get',
                    pathname = '/#2.qux',
                    name = 'qux',
                    handler = handler,
                },
                {
                    type = 'filter',
                    method = 'get',
                    pathname = '/#5.foo',
                    name = 'foo',
                    handler = handler,
                },
                foo = true,
                qux = true,
            },
        },
    })
end

function testcase.register_handler_with_invalid_filter_segment()
    local r = assert(new_router())
    local handler = function()
    end

    -- test that cannot register a filter for the same method
    r:register('/#2.qux', 'get', handler)
    local err = assert.throws(function()
        r:register('/#2.qux', 'get', handler)
    end)
    assert.match(err, 'filter "qux" for method "get" is already registered')

    -- test that cannot register same order filter
    err = assert.throws(function()
        r:register('/#2.hello', 'get', handler)
    end)
    assert.match(err, 'filter order 2 is already registered with "/#2.qux"')

    -- test that cannot register same filter name
    err = assert.throws(function()
        r:register('/foo/bar/#3.qux', 'get', handler)
    end)
    assert.match(err,
                 'filter "qux" is already registered with "/#2.qux": filter name must be unique in the router')

    -- test that cannot register with invalid filter segment
    err = assert.throws(function()
        r:register('/#quux', 'get', handler)
    end)
    assert.match(err,
                 'matching the pattern "/^#([1-9][0-9]*|-)[.]([.]?([a-z0-9_](?:[a-z0-9_-]*[a-z0-9_])*)((?:[.][a-z0-9](?:[a-z0-9_-]*[a-z0-9])*)*)$)/i"')
end

function testcase.register_handler_with_filter_disable_segment()
    local r = assert(new_router())
    local handler = function()
    end

    -- test that disable the filter if the order specifier is negative
    assert.not_throws(function()
        r:register('/#-.foo')
    end)
    -- confirm that the filter is registered
    local route = r:get('/')
    assert.equal(route.disabled_filters, {
        ['@all'] = {
            foo = '/#-.foo',
        },
    })

    -- test that the order of filters is determined by the order specifier
    local err = assert.throws(function()
        r:register('/#-.qux', 'get', handler)
    end)
    assert.match(err, 'must not have method handler')
end

function testcase.register_static_file()
    local f = createfile('/static.html')
    f:write('hello world!')
    f:close()
    local r = assert(new_router({
        rootdir = TESTDIR,
        staticdirs = {
            '/foo/static',
        },
    }))

    -- test that register a static file
    assert.not_throws(function()
        r:register('/static.html')
    end)
    -- confirm that the pathname is registered
    local route = r:get('/static')
    assert.contains(route, {
        route = '/static',
        filename = 'static.html',
        name = 'static',
        ext = '.html',
        finfo = {
            pathname = '/static.html',
        },
    })
    assert.is_table(route.finfo)
    assert.equal(route.finfo.pathname, '/static.html')
    assert.is_int(route.finfo.uid)
    assert.is_int(route.finfo.gid)
    assert.is_int(route.finfo.ctime)
    assert.is_int(route.finfo.mtime)
    assert.is_int(route.finfo.atime)
    assert.is_int(route.finfo.size)
    assert.is_int(route.finfo.blksize)
    assert.is_int(route.finfo.blocks)
    assert.is_string(route.finfo.perm)

    -- test that register a static file even it is a script file if it is in staticdirs
    f = createfile('/foo/static/bar.lua')
    f:write([[
            local function get()
            end
            return {
                get = get,
            }
        ]])
    f:close()
    assert.not_throws(function()
        r:register('/foo/static/bar.lua')
    end)
    -- confirm that the pathname is registered as a static file
    route = r:get('/foo/static/bar.lua')
    assert.contains(route, {
        route = '/foo/static/bar.lua',
        filename = 'bar.lua',
        name = 'bar',
        ext = '.lua',
        finfo = {
            pathname = '/foo/static/bar.lua',
        },
        static = true,
    })
end

function testcase.register_invalid_static_file()
    local f = createfile('/foo/static/bar.html')
    f:write('hello world!')
    f:close()
    local r = assert(new_router({
        rootdir = TESTDIR,
        staticdirs = {
            '/foo/static',
        },
    }))

    -- test that cannot register if it is not a file
    local err = assert.throws(function()
        r:register('/foo/static')
    end)
    assert.match(err, 'pathname "/foo/static" is not a file')

    -- test that cannot register with invalid pathname
    err = assert.throws(function()
        r:register('/statics.html')
    end)
    assert.match(err, 'file not found')

    -- test that cannot register a static file if rootdir is not specified
    r = assert(new_router())
    err = assert.throws(function()
        r:register('/static.html')
    end)
    assert.match(err,
                 'cannot evaluate file specified by the pathname "/static.html": opts.rootdir is not specified')
end

function testcase.register_handler_with_script_file()
    local f = createfile('/static.html')
    f:write('hello world!')
    f:close()
    f = createfile('/@static.html.lua')
    f:write([[
        local function get()
        end
        local function post()
        end
        return {
            get = get,
            post = post,
        }
    ]])
    f:close()
    local r = assert(new_router({
        rootdir = TESTDIR,
        staticdirs = {
            '/foo/static',
        },
    }))

    -- test that register a handler with script file
    assert.not_throws(function()
        r:register('/@static.html.lua')
    end)
    -- confirm that the pathname is registered
    local route = r:get('/static')
    assert.contains(route, {
        route = '/static',
        filename = '@static.html.lua',
        name = 'static',
        ext = '.html.lua',
        handlers = {
            get = {
                pathname = '/@static.html.lua',
            },
            post = {
                pathname = '/@static.html.lua',
            },
        },
    })
    assert.is_func(route.handlers.get.handler)
end

function testcase.register_handler_with_invalid_script_file()
    local r = assert(new_router({
        rootdir = TESTDIR,
        staticdirs = {
            '/foo/static',
        },
    }))

    -- test that cannot register a handler if file not found
    local err = assert.throws(function()
        r:register('/@notfound.lua')
    end)
    assert.match(err, 'file not found')

    -- test that cannot register a handler with empty script file
    local f = createfile('/@empty.lua')
    f:close()
    err = assert.throws(function()
        r:register('/@empty.lua')
    end)
    assert.match(err, 'must return non-empty method table')

    -- test that cannot register a handler if script file returns invalid table
    f = createfile('/@invalid_method.lua')
    f:write([[
            return {
                get = 1,
            }
        ]])
    f:close()
    err = assert.throws(function()
        r:register('/@invalid_method.lua')
    end)
    assert.match(err, 'method handler must be callable object')

    -- test that cannot register a handler if script file is invalid
    f = createfile('/@invalid.lua')
    f:write([[
            {
        ]])
    f:close()
    err = assert.throws(function()
        r:register('/@invalid.lua')
    end)
    assert.match(err, 'failed to load handler from "/@invalid.lua"')

    -- test that cannot register a handler if script throws error
    f = createfile('/@error.lua')
    f:write([[
            foo = bar + 1
        ]])
    f:close()
    err = assert.throws(function()
        r:register('/@error.lua')
    end)
    assert.match(err, 'failed to pre-process()')

    -- test that cannot register if it is in staticdirs
    f = createfile('/foo/static/@baz.lua')
    f:write([[
            local function get()
            end
            return {
                get = get,
            }
        ]])
    f:close()
    err = assert.throws(function()
        r:register('/foo/static/@baz.lua')
    end)
    assert.match(err,
                 'it is treated as a static file according to the configuration')

    -- test that cannot register if it has no '.lua' extension
    f = createfile('/@no_extension')
    f:write([[
            local function get()
            end
            return {
                get = get,
            }
        ]])
    f:close()
    err = assert.throws(function()
        r:register('/@no_extension')
    end)
    assert.match(err,
                 'the extension of the "content" and "filter" handler files must be ".lua": "/@no_extension"')
end

function testcase.build()
    local r = assert(new_router())
    local handler = function()
    end

    -- test that build dispatch table
    assert.not_throws(function()
        -- SET FILTER @ALL /#1.foo
        r:register('/#1.foo', '@all', handler)
        -- GET /foo
        r:register('/foo', 'get', handler)
        -- SET FILTER GET /foo/bar/#2.bar
        r:register('/foo/bar/#2.bar', 'get', handler)
        -- POST /foo/bar/baz
        r:register('/foo/bar/baz', 'post', handler)
        -- SET FILTER @ALL /foo/bar/baz/#1.baz
        r:register('/foo/bar/baz/#1.baz', '@all', handler)
        -- UNSET FILTER GET /foo/bar/baz/#1.baz
        r:register('/foo/bar/baz/#-.baz', 'get')
        -- GET /foo/bar/baz/qux
        r:register('/foo/bar/baz/qux', 'get', handler)
        -- POST /foo/bar/baz/qux
        r:register('/foo/bar/baz/qux', 'post', handler)
        -- UNSET FILTER @ALL /foo/bar/baz/qux/#1.baz
        r:register('/foo/bar/baz/qux/#-.baz', '@all')
        -- GET /foo/bar/baz/qux/corge
        r:register('/foo/bar/baz/qux/corge', 'get', handler)
        -- GET /grault
        r:register('/grault', 'get', handler)
        -- SET FILTER @ANY /grault/#1.garply
        r:register('/grault/#1.garply', '@any', handler)
        -- @ANY /grault/garply/waldo
        r:register('/grault/garply/waldo', '@any', handler)
    end)
    assert.is_true(r:build())
    -- confirm that the dispatch table has been built
    --  - filter handlers are sorted by the pathnames
    --  - content handler is placed at the end of the dispatch table
    for route, except in pairs({
        ['/foo'] = {
            get = {
                {
                    type = 'filter',
                    method = '@all',
                    pathname = '/#1.foo',
                    name = 'foo',
                    handler = handler,
                },
                {
                    type = 'content',
                    method = 'get',
                    pathname = '/foo',
                    handler = handler,
                },
            },
        },
        ['/foo/bar/baz'] = {
            post = {
                {
                    type = 'filter',
                    method = '@all',
                    pathname = '/#1.foo',
                    name = 'foo',
                    handler = handler,
                },
                {
                    type = 'content',
                    method = 'post',
                    pathname = '/foo/bar/baz',
                    handler = handler,
                },
            },
        },
        ['/foo/bar/baz/qux'] = {
            get = {
                {
                    type = 'filter',
                    method = '@all',
                    pathname = '/#1.foo',
                    name = 'foo',
                    handler = handler,
                },
                {
                    type = 'filter',
                    method = 'get',
                    pathname = '/foo/bar/#2.bar',
                    name = 'bar',
                    handler = handler,
                },
                {
                    type = 'content',
                    method = 'get',
                    pathname = '/foo/bar/baz/qux',
                    handler = handler,
                },
            },
            post = {
                {
                    type = 'filter',
                    method = '@all',
                    pathname = '/#1.foo',
                    name = 'foo',
                    handler = handler,
                },
                {
                    type = 'filter',
                    method = '@all',
                    pathname = '/foo/bar/baz/#1.baz',
                    name = 'baz',
                    handler = handler,
                },
                {
                    type = 'content',
                    method = 'post',
                    pathname = '/foo/bar/baz/qux',
                    handler = handler,
                },
            },
        },
        ['/foo/bar/baz/qux/corge'] = {
            get = {
                {
                    type = 'filter',
                    method = '@all',
                    pathname = '/#1.foo',
                    name = 'foo',
                    handler = handler,
                },
                {
                    type = 'filter',
                    method = 'get',
                    pathname = '/foo/bar/#2.bar',
                    name = 'bar',
                    handler = handler,
                },
                {
                    type = 'content',
                    method = 'get',
                    pathname = '/foo/bar/baz/qux/corge',
                    handler = handler,
                },
            },
        },
        ['/grault'] = {
            get = {
                {
                    type = 'filter',
                    method = '@all',
                    pathname = '/#1.foo',
                    name = 'foo',
                    handler = handler,
                },
                {
                    type = 'content',
                    method = 'get',
                    pathname = '/grault',
                    handler = handler,
                },
            },
        },
        ['/grault/garply/waldo'] = {
            ['@any'] = {
                {
                    type = 'filter',
                    method = '@all',
                    pathname = '/#1.foo',
                    name = 'foo',
                    handler = handler,
                },
                {
                    type = 'filter',
                    method = '@any',
                    pathname = '/grault/#1.garply',
                    name = 'garply',
                    handler = handler,
                },
                {
                    type = 'content',
                    method = '@any',
                    pathname = '/grault/garply/waldo',
                    handler = handler,
                },
            },
        },
    }) do
        local routeinfo = r:get(route)
        assert.equal(routeinfo.dispatch, except)
    end

    -- test that it returns false if the dispatch table is already built
    assert.is_false(r:build())

end

