require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local new_regex = require('regex').new
local parse = require('net.http.router.parse')

-- Default regex patterns matching router.lua defaults
local RE_IGNORE = assert(new_regex('^\\.', 'i'))
local RE_NOT_IGNORE = assert(new_regex(
                                 '^[^.].*[.](gif|png|jpe?g|webp)$|^[^.].*[.](lua|js|css|txt|html?)$',
                                 'i'))
local RE_NOT_IGNORE_NONE = assert(new_regex('(?!)', 'i')) -- never matches

local EMPTY_STATIC = {}

-- ============================================================
-- parse()
-- ============================================================

function testcase.parse_root_path()
    -- test that root path returns file type with no static
    local info = assert(parse('/', EMPTY_STATIC, RE_IGNORE, RE_NOT_IGNORE))
    assert.equal(info.type, 'file')
    assert.equal(info.pathname, '/')
    assert.equal(info.is_static, nil)
end

function testcase.parse_root_path_with_static()
    -- test that root path with static returns is_static=true
    local info = assert(parse('/', {
        ['/'] = true,
    }, RE_IGNORE, RE_NOT_IGNORE))
    assert.equal(info.is_static, true)
end

function testcase.parse_pathname_no_leading_slash()
    -- test that pathname without leading slash returns error
    local _, err = parse('foo', EMPTY_STATIC, RE_IGNORE, RE_NOT_IGNORE)
    assert.re_match(err, 'pathname must be started with "/"')
end

function testcase.parse_pathname_trailing_slash()
    -- test that pathname with trailing slash returns error
    local _, err = parse('/foo/', EMPTY_STATIC, RE_IGNORE, RE_NOT_IGNORE)
    assert.re_match(err, 'pathname must be started with "/"')
end

-- ============================================================
-- verify_file_pathinfo (plain filename, no prefix)
-- ============================================================

function testcase.parse_file_with_extension()
    -- test that file with extension returns correct pathinfo
    local info = assert(parse('/index.html', EMPTY_STATIC, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.type, 'file')
    assert.equal(info.pathname, '/index.html')
    assert.equal(info.filename, 'index.html')
    assert.equal(info.name, 'index')
    assert.equal(info.ext, '.html')
    assert.equal(info.is_static, nil)
end

function testcase.parse_file_without_extension()
    -- test that file without extension returns correct pathinfo
    local info =
        assert(parse('/robots', EMPTY_STATIC, RE_IGNORE, RE_NOT_IGNORE))
    assert.equal(info.type, 'file')
    assert.equal(info.filename, 'robots')
    assert.equal(info.name, 'robots')
    assert.equal(info.ext, nil)
end

function testcase.parse_file_multi_extension()
    -- test that file with multiple extensions uses last one for ext
    local info = assert(parse('/archive.tar.gz', EMPTY_STATIC, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.type, 'file')
    assert.equal(info.filename, 'archive.tar.gz')
    assert.equal(info.name, 'archive')
    assert.equal(info.ext, '.tar.gz')
end

function testcase.parse_file_in_nested_path()
    -- test that nested path resolves file correctly
    local info = assert(parse('/foo/bar/baz.html', EMPTY_STATIC, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.type, 'file')
    assert.equal(info.pathname, '/foo/bar/baz.html')
    assert.equal(info.filename, 'baz.html')
    assert.equal(info.name, 'baz')
end

function testcase.parse_file_ignored()
    -- test that hidden file (matches re_ignore, not re_not_ignore) returns error
    local _, err = parse('/.hidden', EMPTY_STATIC, RE_IGNORE, RE_NOT_IGNORE)
    assert.re_match(err, 'ignored by configuration')
end

function testcase.parse_file_ignored_by_segment()
    -- test that hidden segment (matches re_ignore) returns error
    local _, err = parse('/.hidden/foo.html', EMPTY_STATIC, RE_IGNORE,
                         RE_NOT_IGNORE)
    assert.re_match(err, 'ignored by configuration')
end

function testcase.parse_file_invalid_filename()
    -- test that invalid filename returns error
    local _, err = parse('/%invalid', EMPTY_STATIC, RE_IGNORE, RE_NOT_IGNORE)
    assert.re_match(err, 'must be matching the pattern')
end

function testcase.parse_file_in_static_dir()
    -- test that file in a configured static dir returns is_static=true
    local staticdirs = {
        ['/static'] = true,
    }
    local info = assert(parse('/static/foo.png', staticdirs, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.is_static, true)
end

function testcase.parse_file_in_nested_static_dir()
    -- test that static detection propagates once set by parent dir
    local staticdirs = {
        ['/static'] = true,
    }
    local info = assert(parse('/static/img/logo.png', staticdirs, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.is_static, true)
end

function testcase.parse_file_not_in_static_dir()
    -- test that file outside static dirs returns is_static=false
    local staticdirs = {
        ['/static'] = true,
    }
    local info = assert(parse('/api/handler.lua', staticdirs, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.is_static, nil)
end

-- ============================================================
-- verify_content_pathinfo ('@' prefix)
-- ============================================================

function testcase.parse_content_handler()
    -- test that '@'-prefixed filename returns content type
    local info = assert(parse('/foo/@index', EMPTY_STATIC, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.type, 'content')
    assert.equal(info.pathname, '/foo/@index')
    assert.equal(info.filename, '@index')
    assert.equal(info.name, 'index')
    assert.equal(info.ext, nil)
    assert.equal(info.is_static, nil)
end

function testcase.parse_content_handler_with_extension()
    -- test that '@'-prefixed filename with extension returns correct ext
    local info = assert(parse('/foo/@handler.lua', EMPTY_STATIC, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.type, 'content')
    assert.equal(info.name, 'handler')
    assert.equal(info.ext, '.lua')
end

function testcase.parse_content_handler_invalid_name()
    -- test that '@' prefix followed by invalid name returns error
    local _, err = parse('/foo/@', EMPTY_STATIC, RE_IGNORE, RE_NOT_IGNORE)
    assert.re_match(err, 'must be matching the pattern')
end

-- ============================================================
-- verify_param_pathinfo (':' prefix, last segment)
-- ============================================================

function testcase.parse_param_segment()
    -- test that ':'-prefixed last segment returns param type
    local info = assert(parse('/foo/:bar', EMPTY_STATIC, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.type, 'param')
    assert.equal(info.pathname, '/foo/:bar')
    assert.equal(info.filename, ':bar')
    assert.equal(info.name, 'bar')
    assert.equal(info.ext, nil)
end

function testcase.parse_param_segment_with_extension()
    -- test that ':'-prefixed segment with extension returns correct ext
    local info = assert(parse('/foo/:bar.html', EMPTY_STATIC, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.type, 'param')
    assert.equal(info.name, 'bar')
    assert.equal(info.ext, '.html')
end

function testcase.parse_param_segment_invalid_name()
    -- test that ':' prefix followed by invalid name returns error
    local _, err = parse('/foo/:invalid-name', EMPTY_STATIC, RE_IGNORE,
                         RE_NOT_IGNORE)
    assert.re_match(err, 'must be matching the pattern')
end

-- ============================================================
-- verify_filter_pathinfo ('#' prefix)
-- ============================================================

function testcase.parse_filter_handler()
    -- test that '#order.name' returns filter type
    local info = assert(parse('/foo/#1.myfilter', EMPTY_STATIC, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.type, 'filter')
    assert.equal(info.pathname, '/foo/#1.myfilter')
    assert.equal(info.filename, '#1.myfilter')
    assert.equal(info.name, 'myfilter')
    assert.equal(info.ext, nil)
    assert.equal(info.order, 1)
end

function testcase.parse_filter_handler_with_extension()
    -- test that filter name includes extension (e.g. 'myfilter.lua')
    local info = assert(parse('/foo/#5.myfilter.lua', EMPTY_STATIC, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.type, 'filter')
    assert.equal(info.name, 'myfilter.lua')
    assert.equal(info.ext, '.lua')
    assert.equal(info.order, 5)
end

function testcase.parse_filter_disable()
    -- test that '#-.name' returns filter type with order='-'
    local info = assert(parse('/foo/#-.myfilter', EMPTY_STATIC, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.type, 'filter')
    assert.equal(info.name, 'myfilter')
    assert.equal(info.order, '-')
end

function testcase.parse_filter_handler_invalid_order()
    -- test that order '0' is invalid (must start with [1-9])
    local _, err = parse('/foo/#0.myfilter', EMPTY_STATIC, RE_IGNORE,
                         RE_NOT_IGNORE)
    assert.re_match(err, 'must be matching the pattern')
end

function testcase.parse_filter_handler_invalid_name()
    -- test that missing name after '#order.' returns error
    local _, err = parse('/foo/#1.', EMPTY_STATIC, RE_IGNORE, RE_NOT_IGNORE)
    assert.re_match(err, 'must be matching the pattern')
end

-- ============================================================
-- verify_wildcard_pathinfo ('*' prefix)
-- ============================================================

function testcase.parse_wildcard_segment()
    -- test that '*'-prefixed last segment returns wildcard type
    local info = assert(parse('/foo/*path', EMPTY_STATIC, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.type, 'wildcard')
    assert.equal(info.pathname, '/foo/*path')
    assert.equal(info.filename, '*path')
    assert.equal(info.name, 'path')
    assert.equal(info.ext, nil)
end

function testcase.parse_wildcard_segment_invalid_name()
    -- test that '*' with invalid name (hyphen) returns error
    local _, err =
        parse('/foo/*my-path', EMPTY_STATIC, RE_IGNORE, RE_NOT_IGNORE)
    assert.re_match(err, 'must be matching the pattern')
end

-- ============================================================
-- Segment validation (middle segments)
-- ============================================================

function testcase.parse_param_middle_segment()
    -- test that ':' param in middle is validated by RE_PARAM_SEGMENT
    local info = assert(parse('/:bar/baz.html', EMPTY_STATIC, RE_IGNORE,
                              RE_NOT_IGNORE))
    assert.equal(info.type, 'file')
    assert.equal(info.pathname, '/:bar/baz.html')
end

function testcase.parse_param_middle_segment_invalid()
    -- test that invalid ':' segment in middle returns error
    local _, err = parse('/:invalid-name/baz.html', EMPTY_STATIC, RE_IGNORE,
                         RE_NOT_IGNORE)
    assert.re_match(err, 'parameter segment.*must be matching the pattern')
end

function testcase.parse_invalid_middle_segment()
    -- test that invalid regular segment (with invalid chars) returns error
    local _, err = parse('/foo%bar/baz.html', EMPTY_STATIC, RE_IGNORE,
                         RE_NOT_IGNORE)
    assert.re_match(err, 'segment.*must be matching the pattern')
end

function testcase.parse_middle_segment_ignored()
    -- test that ignored middle segment returns error
    local re_ignore_all = assert(new_regex('private', 'i'))
    local _, err = parse('/foo/private/index.html', EMPTY_STATIC, re_ignore_all,
                         RE_NOT_IGNORE_NONE)
    assert.re_match(err, 'ignored by configuration')
end
