--
-- Copyright (C) 2026 Masatoshi Fukunaga
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
local lower = string.lower
local find = string.find
local pairs = pairs
local ipairs = ipairs
local type = type
local next = next
local metamodule = require('metamodule')
local new_basedir = require('basedir').new
local new_router = require('net.http.router')
local parse_pathname = require('net.http.router.parse')
local DEFAULT_LOADFENV = require('net.http.router.loadfenv')
local DEFAULT_COMPILER = require('net.http.router.compiler')
local checkopt = require('lauxhlib.checkopt')
local check = require('lauxhlib.check')
local errorf = require('error').format
local is_callable = require('lauxhlib.is').callable

--- @class net.http.router.fs
--- @field router net.http.router
--- @field basedir basedir
--- @field opts table
--- @field loadfenv function
--- @field compiler function
--- @field precheck function?

--- evalfile evaluates the specified file and returns fileinfo and method handlers.
--- @param r net.http.router.fs
--- @param pathinfo net.http.router.parse.pathinfo
--- @param stat table
--- @return table? fileinfo
--- @return any err
--- @return table? methods
local function evalfile(r, pathinfo, stat)
    if pathinfo.is_static then
        if pathinfo.type == 'file' or pathinfo.type == 'param' then
            return stat
        end
        return nil, errorf(
                   'attempted to register the %s handler from file %q, but it is treated as a static file according to the configuration',
                   pathinfo.type, pathinfo.pathname)
    end

    if pathinfo.ext and find(pathinfo.ext, '%.lua$') then
        local tbl, err = r.compiler(stat.pathname, r.loadfenv())
        if err then
            return nil, errorf('failed to load handler from %q',
                               pathinfo.pathname, err)
        elseif type(tbl) ~= 'table' or not next(tbl) then
            return nil, errorf('%q must return non-empty method table',
                               pathinfo.pathname)
        end

        local methods = {}
        for method, handler in pairs(tbl) do
            if not is_callable(handler) then
                return nil, errorf('%q method handler must be callable object',
                                   method)
            end
            methods[lower(method)] = handler
        end
        return stat, nil, methods
    elseif pathinfo.type == 'file' or pathinfo.type == 'param' or pathinfo.type ==
        'wildcard' then
        return stat
    end

    return nil, errorf(
               'the extension of the "content" and "filter" handler files must be %q: %q',
               '.lua', pathinfo.pathname)
end

--- process_file parses, precheks, evaluates, and registers a single file entry.
--- @param r net.http.router.fs
--- @param router net.http.router
--- @param rpath string
--- @param stat table
--- @return boolean? ok
--- @return any err
local function process_file(r, router, rpath, stat)
    local pathinfo, err = parse_pathname(rpath, router.staticdirs,
                                         router.re_ignore, router.re_no_ignore,
                                         router.mime, router.trim_extentions)
    if not pathinfo then
        -- ignored or invalid filename: silently skip
        return true
    end

    if r.precheck then
        local ok
        ok, err = r.precheck(pathinfo, stat)
        if ok == false then
            if err then
                return nil, err
            end
            return true
        end
    end

    local fileinfo, eval_err, methods = evalfile(r, pathinfo, stat)
    if not fileinfo then
        return nil, eval_err
    end

    local ok, reg_err
    if methods then
        if pathinfo.type == 'filter' then
            ok, reg_err = router:register_filter_handler(pathinfo, methods)
        else
            ok, reg_err = router:register_content_handler(pathinfo, methods)
        end
    else
        ok, reg_err = router:register_file(pathinfo, fileinfo)
    end
    if not ok then
        return nil, reg_err
    end

    return true
end

--- traverse recursively walks dirname and registers all matching files.
--- @param r net.http.router.fs
--- @param router net.http.router
--- @param dirname string
--- @return boolean? ok
--- @return any err
local function traverse(r, router, dirname)
    local entries, err = r.basedir:readdir(dirname)
    if not entries then
        if err then
            return nil, errorf('failed to read directory %q', dirname, err)
        end
        return true
    end

    local subdirs = {}
    for _, entry in ipairs(entries) do
        if not (router.re_ignore:test(entry) and
            not router.re_no_ignore:test(entry)) then
            local rpath = dirname == '/' and '/' .. entry or dirname .. '/' ..
                              entry

            local stat
            stat, err = r.basedir:stat(rpath)
            if not stat then
                if err then
                    return nil, errorf('failed to stat %q', rpath, err)
                end
            elseif stat.type == 'directory' then
                subdirs[#subdirs + 1] = rpath
            elseif stat.type == 'file' then
                local ok
                ok, err = process_file(r, router, rpath, stat)
                if not ok then
                    return nil, err
                end
            end
        end
    end

    for _, subdir in ipairs(subdirs) do
        local ok
        ok, err = traverse(r, router, subdir)
        if not ok then
            return nil, err
        end
    end

    return true
end

local FS = {}

--- init
--- @param rootdir string
--- @param opts table?
--- @return net.http.router.fs
function FS:init(rootdir, opts)
    check.str(rootdir, 'rootdir')
    opts = checkopt.table(opts, {}, 'opts')

    local follow_symlink = checkopt.bool(opts.follow_symlink, false,
                                         'opts.follow_symlink')
    local loadfenv_fn = checkopt.callable(opts.loadfenv, DEFAULT_LOADFENV,
                                          'opts.loadfenv')
    local compiler_fn = checkopt.callable(opts.compiler, DEFAULT_COMPILER,
                                          'opts.compiler')
    local precheck_fn = checkopt.callable(opts.precheck, nil, 'opts.precheck')

    local bd = new_basedir(rootdir, follow_symlink)
    local router = new_router(opts)

    self.router = router
    self.basedir = bd
    self.opts = opts
    self.loadfenv = loadfenv_fn
    self.compiler = compiler_fn
    self.precheck = precheck_fn
    return self
end

--- build traverses the filesystem and atomically rebuilds the routing table.
--- @return boolean? ok
--- @return any err
function FS:build()
    local router = new_router(self.opts)

    local ok, err = traverse(self, router, '/')
    if not ok then
        return nil, err
    end

    router:build()
    self.router = router
    return true
end

--- lookup returns the routeinfo for the given pathname.
--- @param pathname string
--- @return table? routeinfo
--- @return any err
function FS:lookup(pathname)
    return self.router:get(pathname)
end

return metamodule.new(FS)
