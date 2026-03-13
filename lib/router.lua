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
local next = next
local pairs = pairs
local ipairs = ipairs
local lower = string.lower
local sub = string.sub
local concat = table.concat
local sort = table.sort
local fatalf = require('error').fatalf
local errorf = require('error').format
local is_str = require('lauxhlib.is').str
local is_callable = require('lauxhlib.is').callable
local check = require('lauxhlib.check')
local checkopt = require('lauxhlib.checkopt')
local natcmp_lt = require('string.natcmp').lt
local new_regex = require('regex').new

--- @alias regex userdata

--- regex_verify_pattern
---@param s string
---@return boolean ok
---@return any err
local function regex_verify_pattern(s)
    if not is_str(s) then
        return false, errorf('regular expression pattern must be string')
    end

    -- evalulate
    local _, err = new_regex(s, 'i')
    if err then
        return false, errorf('failed to compile regular expression pattern %q',
                             s, err)
    end
    return true
end

--- regex_compile_patterns
---@param patterns string[]
---@return regex re
---@return any err
---@return string? pat
---@return integer? idx
local function regex_compile_patterns(patterns)
    local list = {}
    for i, p in ipairs(patterns) do
        local ok, err = regex_verify_pattern(p)
        if not ok then
            return nil, err, p, i
        end
        list[#list + 1] = p
    end

    -- compile patterns
    local pat = '(?:' .. concat(list, '|') .. ')'
    local re, err = new_regex(pat, 'i')
    if err then
        return nil, errorf('failed to compile regular expression pattern %q',
                           pat, err)
    end
    return re
end

--- @class net.http.router.options
--- @field trim_extentions string[]
--- @field mimetypes string
--- @field staticdirs string[]
--- @field ignore string[]
--- @field no_ignore string[]

local new_mime = require('mime').new
local new_plut = require('plut').new

--- @alias plut userdata

--- @class net.http.router
--- @field mime mime
--- @field trim_extentions table<string, boolean>
--- @field staticdirs table<string, boolean>
--- @field re_ignore regex
--- @field re_no_ignore regex
--- @field plut plut routing table
--- @field dirty boolean true if the routing table is dirty
--- @field filternames table<string, string> prevent dupulicate filter name
local Router = {}

--- init
--- @param opts net.http.router.options?
--- @return net.http.router
function Router:init(opts)
    -- check opts
    opts = checkopt.table(opts, {}, 'opts')

    -- create MIME type detecter
    local mime = new_mime()
    if opts.mimetypes ~= nil then
        local mimetypes = check.str(opts.mimetypes, 'opts.mimetypes')
        local invalid_lines = mime:read(mimetypes)
        if next(invalid_lines) then
            error('found invalid lines in opts.mimetypes: \n' ..
                      concat(invalid_lines, '\n'), 2)
        end
    end
    self.mime = mime

    -- create trim_extentions lookup table
    -- the trim_extentions is used to remove the extension from the filename
    -- when registring the handler.
    local trim_extentions = {}
    for i, ext in ipairs(checkopt.table(opts.trim_extensions, {
        -- default trim_extentions
        '.html',
        '.htm',
    }, 'opts.trim_extensions')) do
        if not is_str(ext) then
            fatalf(2, 'opts.trim_extensions#%d is not a string', i)
        end
        trim_extentions[ext] = true
    end
    self.trim_extentions = trim_extentions

    -- create static route table
    local staticdirs = {}
    for i, v in ipairs(checkopt.table(opts.staticdirs, {}, 'opts.staticdirs')) do
        if not is_str(v) then
            fatalf(2, 'opts.staticdirs#%d is not a string', i)
        end
        staticdirs[v] = true
    end
    self.staticdirs = staticdirs

    -- create regex that is used for the following purposes:
    -- the ignore and no_ignore patterns are used to ignore the path-segments
    -- and filename when registering the handler.
    -- these patterns are used as in 'ignore <ignore> except <no_ignore>'.
    local ignore = checkopt.table(opts.ignore, nil, 'opts.ignore')
    ignore = ignore and #ignore > 0 and ignore or {
        -- default ignore patterns
        -- path-segments and filename that starts with '.'
        '^\\.',
    }
    local no_ignore = checkopt.table(opts.no_ignore, nil, 'opts.no_ignore')
    no_ignore = no_ignore and #no_ignore > 0 and no_ignore or {
        -- default allow patterns
        '^[^.].*\\.(?:gif|png|jpe?g|webp)$',
        '^[^.].*\\.(?:lua|js|css|txt|htm?l)$',
    }
    for k, patterns in pairs({
        no_ignore = no_ignore,
        ignore = ignore,
    }) do
        local re, err, pat, idx = regex_compile_patterns(patterns)
        if not re then
            if idx then
                fatalf(2, 'opts.%s#%d %s', k, idx, err)
            end
            fatalf(2, 'opts.%s: %q: %s', k, pat, err)
        elseif k == 'ignore' then
            self.re_ignore = re
        else
            self.re_no_ignore = re
        end
    end

    -- create router that is used for managing routes
    self.plut = new_plut()
    self.dirty = true
    -- create filter name lookup table
    self.filternames = {}

    return self
end

--- @alias method string

--- @class net.http.router.filter
--- @field pathname string filter pathname
--- @field name string filter name
--- @field handler function filter handler

--- @class net.http.router.filters
--- @field orders table<integer, string> filter order
--- @field handlers table<method, table<integer, net.http.router.filter>|table<string, boolean>> filter handlers

--- @class net.http.router.routeinfo
--- @field route string route pathname
--- @field filename string filename part of the route pathname
--- @field name string name part of the filename
--- @field ext string extension part of the filename
--- @field mime string? MIME type
--- @field static boolean? true if the route is static
--- @field finfo table? fileinfo
--- @field handlers table<string, table> method handlers
--- @field filters net.http.router.filters filter registry

--- get_or_create_routeinfo gets or creates a route for the specified pathinfo
--- @param r net.http.router
--- @param pathinfo net.http.router.parse.pathinfo
--- @return table routeinfo
--- @return boolean? is_new_route true if the route is newly created
local function get_or_create_routeinfo(r, pathinfo)
    local routeinfo, err = r:get(pathinfo.route)
    assert(not err, err)
    return routeinfo or {
        route = pathinfo.route,
        static = pathinfo.is_static,
    }, routeinfo == nil
end

--- register_routeinfo registers the routeinfo to the router
--- @private
--- @param routeinfo net.http.router.routeinfo
--- @return boolean ok
--- @return any err
function Router:register_routeinfo(routeinfo)
    local ok, err = self.plut:set(routeinfo.route, routeinfo)
    if ok then
        -- set the route as dirty
        self.dirty = true
        return true
    end
    return false, errorf('failed to register route %q', routeinfo.route, err)
end

--- register_content_handler registers the content handler
--- @private
--- @param pathinfo net.http.router.parse.pathinfo
--- @param methods table<string, function>
--- @return boolean ok
--- @return any err
function Router:register_content_handler(pathinfo, methods)
    -- check the method table
    if methods['@all'] then
        return false,
               errorf('method "@all" is not allowed for the content handler')
    end

    -- get routeinfo
    local routeinfo, is_new_route = get_or_create_routeinfo(self, pathinfo)
    -- register the handler for each method
    local handlers = routeinfo.handlers or {}
    for method, fn in pairs(methods) do
        if handlers[method] ~= nil then
            return false,
                   errorf('%q handler for %q is already registered with %q',
                          method, routeinfo.route, handlers[method].pathname)
        end

        -- add method handler
        local handler = {
            type = 'content',
            method = method,
            pathname = pathinfo.pathname,
            handler = fn,
        }
        handlers[method] = handler
    end
    routeinfo.handlers = handlers
    routeinfo.filename = routeinfo.filename or pathinfo.filename
    routeinfo.name = routeinfo.name or pathinfo.name
    routeinfo.ext = routeinfo.ext or pathinfo.ext
    routeinfo.mime = routeinfo.mime or pathinfo.mime
    -- set the route as dirty
    self.dirty = true

    if not is_new_route then
        return true
    end
    -- register a new route
    return self:register_routeinfo(routeinfo)
end

--- register_file registers the file
--- @private
--- @param pathinfo net.http.router.parse.pathinfo
--- @param fileinfo table
--- @return boolean ok
--- @return any err
function Router:register_file(pathinfo, fileinfo)
    -- get routeinfo
    local routeinfo, is_new_route = get_or_create_routeinfo(self, pathinfo)
    routeinfo.filename = routeinfo.filename or pathinfo.filename
    routeinfo.name = routeinfo.name or pathinfo.name
    routeinfo.ext = routeinfo.ext or pathinfo.ext
    routeinfo.mime = routeinfo.mime or pathinfo.mime
    -- update the file stat
    routeinfo.finfo = {
        pathname = pathinfo.pathname,
        uid = fileinfo.uid,
        gid = fileinfo.gid,
        ctime = fileinfo.ctime,
        mtime = fileinfo.mtime,
        atime = fileinfo.atime,
        perm = fileinfo.perm,
        size = fileinfo.size,
        blksize = fileinfo.blksize,
        blocks = fileinfo.blocks,
    }
    -- set the route as dirty
    self.dirty = true

    if not is_new_route then
        return true
    end
    -- register a new route
    return self:register_routeinfo(routeinfo)
end

--- register_filter_handler
--- @private
--- @param pathinfo net.http.router.parse.pathinfo
--- @param methods table<string, function>
--- @return boolean ok
--- @return any err
function Router:register_filter_handler(pathinfo, methods)
    local filtername = self.filternames[pathinfo.name]
    if filtername and filtername ~= pathinfo.pathname then
        -- filter name must be unique in the router
        return false, errorf(
                   'filter %q is already registered with %q: filter name must be unique in the router',
                   pathinfo.name, filtername)
    end

    -- get exsisting route
    local routeinfo, is_new_route = get_or_create_routeinfo(self, pathinfo)
    local filters = routeinfo.filters or {
        orders = {},
        handlers = {},
    }
    local orders = filters.orders
    local handlers = filters.handlers
    -- add the method handlers to the filter table
    for method, handler in pairs(methods) do
        if orders[pathinfo.order] and orders[pathinfo.order] ~=
            pathinfo.pathname then
            return false,
                   errorf('filter order %d is already registered with %q',
                          pathinfo.order, orders[pathinfo.order])
        end

        local list = handlers[method] or {}
        if list[pathinfo.name] then
            return false, errorf(
                       'filter %q for method %q is already registered',
                       pathinfo.name, method)
        end
        orders[pathinfo.order] = pathinfo.pathname
        list[pathinfo.name] = true
        list[#list + 1] = {
            type = 'filter',
            method = method,
            pathname = pathinfo.pathname,
            name = pathinfo.name,
            handler = handler,
        }
        sort(list, function(a, b)
            return natcmp_lt(a.pathname, b.pathname)
        end)
        handlers[method] = list
    end

    -- add the filter name to the lookup table
    self.filternames[pathinfo.name] = pathinfo.pathname
    routeinfo.filters = filters
    -- set the route as dirty
    self.dirty = true

    if not is_new_route then
        return true
    end
    -- register a new route
    return self:register_routeinfo(routeinfo)
end

--- disable_filter_handler disable the filter handler
--- @private
--- @param pathinfo net.http.router.parse.pathinfo
--- @param methods table<string, boolean>?
--- @return boolean ok
--- @return any err
function Router:disable_filter_handler(pathinfo, methods)
    -- get exsisting route
    local routeinfo, is_new_route = get_or_create_routeinfo(self, pathinfo)
    local disabled_filters = routeinfo.disabled_filters or {}
    for _, method in ipairs(methods) do
        local filters = disabled_filters[method]
        if not filters then
            -- create new list of disabled filters
            filters = {}
            disabled_filters[method] = filters
        end
        -- add the method to the list of disabled filters
        filters[pathinfo.name] = pathinfo.pathname
    end
    routeinfo.disabled_filters = disabled_filters
    -- set the route as dirty
    self.dirty = true

    if not is_new_route then
        return true
    end
    -- register a new route
    return self:register_routeinfo(routeinfo)
end

local RE_METHODNAME_PAT = '^@?[a-z](_*[a-z]+)*$'
local RE_METHODNAME = assert(new_regex(RE_METHODNAME_PAT, 'i'))

--- is_valid_methodname checks if the method name is valid or not
--- @param method string
--- @return boolean
--- @return any err
local function is_valid_methodname(method)
    if not is_str(method) or #method == 0 then
        return false, errorf('method must be non-empty string')
    elseif sub(method, 1, 1) == '@' and method ~= '@all' and method ~= '@any' then
        -- '@' prefix is allowed only for '@all' and '@any' methods
        return false, errorf(
                   'method %q is not allowed: @ prefix is allowed only for @all and @any methods',
                   method)
    elseif not RE_METHODNAME:test(method) then
        return false, errorf('method must be string matching the pattern %q',
                             '/' .. RE_METHODNAME_PAT .. '/i')
    end
    return true
end

--- validate_method_handler validates the method name and handler type
--- @param method string
--- @param handler function
--- @return boolean ok
--- @return any err
local function validate_method_handler(method, handler)
    -- method and handler must be specified together
    local ok, err = is_valid_methodname(method)
    if not ok then
        return false, err
    elseif not is_callable(handler) then
        return false,
               errorf('%q method handler must be callable object', method)
    end
    return true
end

local parse_pathname = require('net.http.router.parse')

--- register
--- @param pathname string
--- @param method string?
--- @param handler function?
function Router:register(pathname, method, handler)
    if not is_str(pathname) or #pathname == 0 then
        fatalf(2, 'pathname must be non-empty string')
    end

    local pathinfo, err = parse_pathname(pathname, self.staticdirs,
                                         self.re_ignore, self.re_no_ignore,
                                         self.mime, self.trim_extentions)
    if not pathinfo then
        fatalf(2, 'failed to parse pathname %q', pathname, err)
    end

    if pathinfo.order == '-' then
        -- disable the filter handler
        if handler ~= nil then
            -- filter disable specifier must not have method handler
            fatalf(2,
                   'filter disable specifier %q must not have method handler',
                   pathname)
        elseif method ~= nil then
            method = lower(method)
            local ok
            ok, err = is_valid_methodname(method)
            if not ok then
                fatalf(2, err)
            end
        end

        local ok
        ok, err = self:disable_filter_handler(pathinfo, {
            method or '@all',
        })
        if not ok then
            fatalf(2, 'failed to disable filter handler', err)
        end
        return
    end

    -- method and handler must be specified together
    local ok
    ok, err = validate_method_handler(method, handler)
    if not ok then
        fatalf(2, 'failed to validate method handler: %s', err)
    end
    method = lower(method)
    local methods = {
        [method] = handler,
    }

    if pathinfo.type == 'filter' then
        ok, err = self:register_filter_handler(pathinfo, methods)
    else
        ok, err = self:register_content_handler(pathinfo, methods)
    end

    if not ok then
        fatalf(2, 'failed to register %s handler for %q', pathinfo.type,
               pathname, err)
    end
end

--- get a registered route for the specified pathname
--- @param pathname string
--- @return table route
--- @return any err
function Router:get(pathname)
    return self.plut:get(pathname)
end

--- dump a registered routes
--- @private
--- @return table[] routes
function Router:dump()
    local routes = {}
    for k, routeinfo in pairs(self.plut:dump()) do
        routes[#routes + 1] = {
            route = k,
            routeinfo = routeinfo,
        }
    end

    -- sort the list by route by natural order
    sort(routes, function(a, b)
        return natcmp_lt(a.route, b.route)
    end)

    return routes
end

--- build builds the dispatch table from the routing table
--- @private
--- @return boolean built
function Router:build()
    if not self.dirty then
        -- the routing table is not dirty
        return false
    end

    local table_copy = function(dst, src)
        dst = dst or {}
        for k, v in pairs(src) do
            dst[k] = v
        end
        return dst
    end

    -- build the dispatch tables
    local stack = {}
    local routes = self:dump()
    for _, v in ipairs(routes) do
        -- remove the parent context if it does not match the route prefix
        for i = #stack, 1, -1 do
            local proute = stack[i].route
            if #proute > #v.route or proute ~= sub(v.route, 1, #proute) then
                stack[i] = nil
            end
        end

        -- copy the disabled_filters
        local disabled_filters = {}
        for method, names in pairs(v.routeinfo.disabled_filters or {}) do
            disabled_filters[method] = table_copy({}, names)
        end

        -- determine the specified name of filter is disabled
        local is_disabled = function(method, name)
            local dict = disabled_filters['@all']
            if dict and dict[name] then
                return true
            end
            dict = disabled_filters[method]
            if dict and dict[name] then
                return true
            end
            return false
        end

        -- copy the filter handlers into the specified list
        local filter_copy = function(list, method, handlers)
            for _, handler in ipairs(handlers or {}) do
                if handler.type == 'filter' and
                    not is_disabled(method, handler.name) then
                    list[#list + 1] = handler
                end
            end
        end

        -- add the parent filter handlers to the dispatch table
        local parent_filters = {}
        local pctx = stack[#stack]
        if pctx then
            -- add the parent disabled filters
            for method, names in pairs(pctx.disabled_filters) do
                disabled_filters[method] =
                    table_copy(disabled_filters[method], names)
            end

            -- copy parent filters
            for method, handlers in pairs(pctx.filters) do
                local list = {}
                filter_copy(list, method, handlers)
                parent_filters[method] = list
            end
        end

        if v.routeinfo.filters then
            -- add the method filters to the dispatch table
            local filters = v.routeinfo.filters.handlers
            for method, handlers in pairs(filters) do
                local list = parent_filters[method] or {}
                filter_copy(list, method, handlers)
                parent_filters[method] = list
            end
        end

        -- copy the content handlers to the dispatch table
        local parent_filters_all = parent_filters['@all'] or {}
        local copy_parent_filters = function(list, method)
            -- add filter handlers
            for _, filter_handlers in ipairs({
                parent_filters_all,
                parent_filters[method] or {},
            }) do
                for _, filter_handler in ipairs(filter_handlers) do
                    if not is_disabled(method, filter_handler.name) then
                        list[#list + 1] = filter_handler
                    end
                end
            end
            sort(list, function(a, b)
                return natcmp_lt(a.pathname, b.pathname)
            end)
            return list
        end

        -- remove old dispatch table
        v.routeinfo.dispatch = nil

        -- create dispatch table
        local dispatch = {}
        local route_handlers = v.routeinfo.handlers
        if route_handlers then
            for method, handler in pairs(v.routeinfo.handlers or {}) do
                local list = copy_parent_filters(dispatch[method] or {}, method)
                -- copy the content handler to the dispatch table
                list[#list + 1] = handler
                dispatch[method] = list
            end
            v.routeinfo.dispatch = dispatch
        end

        -- add the dispatch table to the routeinfo
        if v.routeinfo.finfo and not dispatch.get and not dispatch['@any'] then
            local list = copy_parent_filters(dispatch.get or {}, 'get')
            -- copy the content handler to the dispatch table
            dispatch.get = list
            v.routeinfo.dispatch = dispatch
        end

        -- keep the context of the parent context for the child routes
        stack[#stack + 1] = {
            route = v.route,
            filters = parent_filters,
            disabled_filters = disabled_filters,
        }
    end

    self.dirty = false
    return true
end

--- lookup
--- @param pathname string
--- @return net.http.router.routeinfo? routeinfo
--- @return table? glob
function Router:lookup(pathname)
    if self.dirty then
        -- build dispatch table if the routing table is dirty
        self:build()
    end
    local routeinfo, _, glob = self.plut:lookup(pathname)
    return routeinfo, glob
end

return require('metamodule').new(Router)
