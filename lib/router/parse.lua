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
local concat = table.concat
local gmatch = string.gmatch
local match = string.match
local sub = string.sub
local tonumber = tonumber
local errorf = require('error').format
local new_regex = require('regex').new

-- extension pattern which repeats the following pattern:
--  - must start with a dot and followed by [a-z0-9],
--  - may continue with (?:[a-z0-9_-]*[a-z0-9])*
local RE_EXTNAME_PAT = '(?:[.][a-z0-9](?:[a-z0-9_-]*[a-z0-9])*)*'

-- filename pattern
local RE_FILENAME_PAT = concat({
    -- optional dot prefix (for hidden file)
    '[.]?',
    -- name part follows this pattern:
    --  - must start and end with [a-z0-9_]
    --  - can contain [a-z0-9_-] in between
    '([a-z0-9_](?:[a-z0-9_-]*[a-z0-9_])*)',
    -- optional extension part (last one will be captured)
    '(',
    RE_EXTNAME_PAT,
    ')$',
})
local RE_FILENAME = assert(new_regex('^' .. RE_FILENAME_PAT, 'i'))

--- @class net.http.router.parse.pathinfo
--- @field type string
--- @field pathname string pathname
--- @field filename string last-segment of the pathname
--- @field name string name part of the filename
--- @field ext string extension part of the filename
--- @field order integer filter order (only for filter type)
--- @field is_static boolean whether the pathname should treated as static file
--- @field route string route pathname
--- @field mime string? MIME type of the file

--- get_mimetype returns the MIME type for the given extension string.
--- @param mime mime? MIME type detector
--- @param ext string? extension string (e.g. '.html' or '.html.gz')
--- @return string? mimetype
local function get_mimetype(mime, ext)
    if not mime or not ext or ext == '' then
        return nil
    end
    local last = match(ext, '[^.]+$')
    return last and mime:getmime(last) or nil
end

--- trim_filename removes trimmable extensions from the end of a filename.
--- @param filename string filename (e.g. 'index.html' or 'page.html.gz')
--- @param ext string? full extension string already extracted (e.g. '.html.gz')
--- @param trim_extentions table<string, boolean>? extensions to remove
--- @return string filename trimmed filename
local function trim_filename(filename, ext, trim_extentions)
    if not ext or ext == '' or not trim_extentions then
        return filename
    end
    local v = match(ext, '%.[^.]+$')
    while v and trim_extentions[v] do
        filename = sub(filename, 1, #filename - #v)
        ext = sub(ext, 1, #ext - #v)
        v = match(ext, '%.[^.]+$')
    end
    return filename
end

--- create_filecontent_pathinfo builds a file or content pathinfo table.
--- The caller is responsible for validation; this function only constructs the result.
--- @param ptype string 'file' or 'content'
--- @param segments string[] pathname segments
--- @param filename string original filename (e.g. 'index.html' or '@index.html')
--- @param basename string filename with any prefix stripped, used for route computation
--- @param name string name part of the filename captured by regex (e.g. 'index')
--- @param ext string extension part of the filename captured by regex (e.g. '.html')
--- @param is_static boolean
--- @param mime mime? MIME type detector
--- @param trim_extentions table<string, boolean>? extensions to remove from route
--- @return net.http.router.parse.pathinfo info
local function create_filecontent_pathinfo(ptype, segments, filename, basename,
                                           name, ext, is_static, mime,
                                           trim_extentions)
    local dirname = '/' .. concat(segments, '/', 1, #segments - 1)
    local mimetype = get_mimetype(mime, ext)
    local fname = trim_filename(basename, ext, trim_extentions)
    local route
    if fname == 'index' then
        route = dirname
    elseif dirname == '/' then
        route = '/' .. fname
    else
        route = dirname .. '/' .. fname
    end
    return {
        type = ptype,
        pathname = '/' .. concat(segments, '/'),
        filename = filename,
        name = name,
        ext = #ext > 0 and ext or nil,
        is_static = is_static,
        route = route,
        mime = mimetype,
    }
end

--- verify_file_pathinfo checks the pathname is the file pathinfo
--- @param segments string[] pathname segments
--- @param is_static boolean
--- @param re_ignore regex
--- @param re_not_ignore regex
--- @param mime mime? MIME type detector
--- @param trim_extentions table<string, boolean>? extensions to remove from route
--- @return net.http.router.parse.pathinfo? info
--- @return any err
local function verify_file_pathinfo(segments, is_static, re_ignore,
                                    re_not_ignore, mime, trim_extentions)
    local filename = segments[#segments]
    local res = RE_FILENAME:match(filename)
    if not res then
        return nil,
               errorf('filename %q must be matching the pattern %q', filename,
                      '/^' .. RE_FILENAME_PAT .. '/i')
    elseif re_ignore:test(filename) and not re_not_ignore:test(filename) then
        return nil, errorf('filename %q is ignored by configuration', filename)
    end
    return create_filecontent_pathinfo('file', segments, filename, filename,
                                       res[2], res[3], is_static, mime,
                                       trim_extentions)
end

--- verify_content_pathinfo checks the pathname is the content pathinfo
--- @param segments string[] pathname segments
--- @param is_static boolean
--- @param mime mime? MIME type detector
--- @param trim_extentions table<string, boolean>? extensions to remove from route
--- @return net.http.router.parse.pathinfo? info
--- @return any err
local function verify_content_pathinfo(segments, is_static, mime,
                                       trim_extentions)
    local filename = segments[#segments]
    local res = RE_FILENAME:match(sub(filename, 2))
    if not res then
        return nil,
               errorf(
                   'content handler filename %q must be matching the pattern %q',
                   filename, '/^@' .. RE_FILENAME_PAT .. '/i')
    end
    return create_filecontent_pathinfo('content', segments, filename,
                                       sub(filename, 2), res[2], res[3],
                                       is_static, mime, trim_extentions)
end

-- filename pattern
local RE_PARAM_FILENAME_PAT = concat({
    -- must start with ':'
    '^:',
    -- name part must start and end with [a-z0-9_]
    '([a-z0-9_]+)',
    -- optional extension part (last one will be captured)
    '(',
    RE_EXTNAME_PAT,
    ')$',
})
local RE_PARAM_FILENAME = assert(new_regex('^' .. RE_PARAM_FILENAME_PAT, 'i'))

--- verify_param_pathinfo checks the pathname is the parameter pathinfo
--- @param segments string[] pathname segments
--- @param is_static boolean
--- @return net.http.router.parse.pathinfo? info
--- @return any err
local function verify_param_pathinfo(segments, is_static)
    local filename = segments[#segments]
    local res = RE_PARAM_FILENAME:match(filename)
    if not res then
        return nil,
               errorf(
                   'parameter handler filename %q must be matching the pattern %q',
                   filename, '/' .. RE_PARAM_FILENAME_PAT .. '/i')
    end

    local ext = res[3]
    local pathname = '/' .. concat(segments, '/')
    return {
        type = 'param',
        pathname = pathname,
        filename = filename,
        name = res[2],
        ext = ext and #ext > 0 and ext or nil,
        is_static = is_static,
        route = pathname,
    }
end

-- filter handler segment pattern based on the name pattern
local RE_FILTER_NAME_PAT = concat({
    -- must start with '#' and dot
    '^#',
    -- order part follows this pattern: (it will be captured)
    --  - must start with [1-9]
    --  - may continue with [0-9]*
    --  - or must be '-' (for disabled filter)
    '([1-9][0-9]*|-)',
    -- dot separator
    '[.]',
    -- name part is the same as the filename pattern (it will be captured)
    '(',
    RE_FILENAME_PAT,
    ')',
})
local RE_FILTER_NAME = assert(new_regex(RE_FILTER_NAME_PAT, 'i'))

--- verify_filter_pathinfo checks the pathname is the filter pathinfo
--- @param segments string[] pathname segments
--- @param is_static boolean
--- @return net.http.router.parse.pathinfo? info
--- @return any err
local function verify_filter_pathinfo(segments, is_static)
    local filename = segments[#segments]
    local res = RE_FILTER_NAME:match(filename)
    if not res then
        return nil,
               errorf(
                   'filter handler filename %q must be matching the pattern %q',
                   filename, '/' .. RE_FILTER_NAME_PAT .. '/i')
    end

    -- filter route is its parent directory (with trailing slash for non-root)
    local dirname = '/' .. concat(segments, '/', 1, #segments - 1)
    local route = dirname == '/' and dirname or dirname .. '/'
    return {
        type = 'filter',
        pathname = '/' .. concat(segments, '/'),
        filename = filename,
        name = res[3],
        ext = res[5] and #res[5] > 0 and res[5] or nil,
        order = res[2] == '-' and '-' or tonumber(res[2]),
        is_static = is_static,
        route = route,
    }
end

-- wildcard/catch-all segment pattern (last segment only)
local RE_WILDCARD_FILENAME_PAT = concat({
    '^[*]',
    -- name part must start and end with [a-z0-9_]
    '([a-z0-9_]+)',
    -- optional extension part (last one will be captured)
    '(',
    RE_EXTNAME_PAT,
    ')$',
})
local RE_WILDCARD_FILENAME = assert(new_regex(RE_WILDCARD_FILENAME_PAT, 'i'))

--- verify_wildcard_pathinfo checks the pathname is the wildcard pathinfo
--- @param segments string[] pathname segments
--- @param is_static boolean
--- @return net.http.router.parse.pathinfo? info
--- @return any err
local function verify_wildcard_pathinfo(segments, is_static)
    local filename = segments[#segments]
    local res = RE_WILDCARD_FILENAME:match(filename)
    if not res then
        return nil,
               errorf('wildcard segment %q must be matching the pattern %q',
                      filename, '/' .. RE_WILDCARD_FILENAME_PAT .. '/i')
    end

    local ext = res[3]
    local pathname = '/' .. concat(segments, '/')
    return {
        type = 'wildcard',
        pathname = pathname,
        filename = filename,
        name = res[2],
        ext = ext and #ext > 0 and ext or nil,
        is_static = is_static,
        route = pathname,
    }
end

-- parameter-segment pattern
local RE_PARAM_SEGMENT_PAT = concat({
    -- must start with ':'
    '^:',
    -- name part must start and end with [a-z0-9_]
    '[a-z0-9_]+$',
})
local RE_PARAM_SEGMENT = assert(new_regex(RE_PARAM_SEGMENT_PAT, 'i'))

-- path-segment pattern except the last-segment
local RE_SEGMENT_PAT = concat({
    -- optional dot prefix (for hidden directory)
    '^[.]?',
    -- name part follows this pattern:
    --  - must start and end with [a-z0-9_-]
    '[a-z0-9_-]+$',
})
local RE_SEGMENT = assert(new_regex(RE_SEGMENT_PAT, 'i'))

--- parse parses the pathname and returns the pathinfo
--- @param pathname string
--- @param staticdirs table<string,boolean>
--- @param re_ignore regex
--- @param re_not_ignore regex
--- @param mime mime? MIME type detector
--- @param trim_extentions table<string, boolean>? extensions to remove from route
--- @return net.http.router.parse.pathinfo? info
--- @return any? err
local function parse(pathname, staticdirs, re_ignore, re_not_ignore, mime,
                     trim_extentions)
    -- check the pathname is the root
    if pathname == '/' then
        return {
            type = 'file',
            pathname = pathname,
            is_static = staticdirs['/'],
            route = '/',
        }
    end

    -- pathname must start with '/'
    -- pathname must not be end with '/'
    if sub(pathname, 1, 1) ~= '/' or sub(pathname, -1) == '/' then
        return nil, errorf(
                   'pathname must be started with "/"' ..
                       ' and must not be ended with "/"')
    end

    -- splitting pathname with '/'
    local parts = {}
    for part in gmatch(pathname, '[^/]+') do
        parts[#parts + 1] = part
    end

    -- the path-segment must be matching the RE_SEGMENT_PAT pattern
    local is_static = staticdirs['/']
    local dirname = ''
    for i = 1, #parts - 1 do
        local part = parts[i]
        -- check the files in the static directories
        if not is_static then
            dirname = dirname .. '/' .. part
            is_static = staticdirs[dirname]
        end

        -- check the segment name is valid or not
        if sub(part, 1, 1) == ':' then
            -- parameter segment
            if not RE_PARAM_SEGMENT:test(part) then
                return nil,
                       errorf(
                           'parameter segment %q must be matching the pattern %q',
                           part, '/' .. RE_PARAM_SEGMENT_PAT .. '/i')
            end
        elseif not RE_SEGMENT:test(part) then
            return nil,
                   errorf('segment %q must be matching the pattern %q', part,
                          '/' .. RE_SEGMENT_PAT .. '/i')
        elseif re_ignore:test(part) and not re_not_ignore:test(part) then
            return nil, errorf('segment %q is ignored by configuration', part)
        end
    end

    local prefix = sub(parts[#parts], 1, 1)
    if prefix == '#' then
        -- filter handler segment
        return verify_filter_pathinfo(parts, is_static)
    elseif prefix == '@' then
        -- contents handler segment
        return verify_content_pathinfo(parts, is_static, mime, trim_extentions)
    elseif prefix == ':' then
        -- parameter segment
        return verify_param_pathinfo(parts, is_static)
    elseif prefix == '*' then
        -- wildcard/catch-all segment (last segment only)
        return verify_wildcard_pathinfo(parts, is_static)
    end
    return verify_file_pathinfo(parts, is_static, re_ignore, re_not_ignore,
                                mime, trim_extentions)
end

return parse
