--
-- Copyright (C) 2021 Masatoshi Fukunaga
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
local concat = table.concat
local format = string.format
local find = string.find
local sub = string.sub
local is_uint = require('isa').uint
local parse = require('net.http.parse')
local parse_header = parse.header
local parse_chunksize = parse.chunksize
--- constants
local CRLF = '\r\n'

--- @class net.http.content.chunked.Handler
local Handler = {}

--- read_chunk
--- @param s string
--- @param ext table<string, string>
--- @return string s
--- @return string? err
function Handler:read_chunk(s, ext)
    return s
end

--- read_last_chunk
--- @param ext table<string, string>
--- @return string? err
function Handler:read_last_chunk(ext)
end

--- read_trailer
--- @param trailer table
--- @return string? err
function Handler:read_trailer(trailer)
end

--- write_chunk
--- @param w net.http.writer
--- @param s string
--- @return integer n
--- @return string? err
function Handler:write_chunk(w, s)
    -- chunk = chunk-size [ chunk-ext ] CRLF
    --         chunk-data CRLF
    return w:write(concat({
        format('%x', #s),
        s,
        '',
    }, CRLF))
end

--- write_last_chunk
--- @param w net.http.writer
--- @return integer n
--- @return string? err
function Handler:write_last_chunk(w)
    -- last-chunk = 1*("0") [ chunk-ext ] CRLF
    return w:write('0\r\n')
end

--- write_trailer
--- @param w net.http.writer
--- @return integer n
--- @return string? err
function Handler:write_trailer(w)
    -- trailer-part = *( header-field CRLF ) CRLF
    return w:write('\r\n')
end

Handler = require('metamodule').new.Handler(Handler)

--- constants
local DEFAULT_CHUNKHANDLER = Handler()
local DEFAULT_CHUNKSIZE = 1024 * 8
local EAGAIN = parse.EAGAIN

--- @class net.http.content.chunked : net.http.content
--- @field reader net.http.reader
--- @field is_chunked boolean
--- @field is_consumed boolean
local ChunkedContent = {}

--- init
--- @param r net.http.reader
--- @return net.http.content.chunked content
function ChunkedContent:init(r)
    self.reader = r
    self.is_chunked = true
    self.is_consumed = false
    return self
end

--- copy
--- @param w net.http.writer
--- @param chunksize? integer
--- @param handler? net.http.content.chunked.Handler
--- @return integer len
--- @return string? err
function ChunkedContent:copy(w, chunksize, handler)
    if self.is_consumed then
        error('content is already consumed', 2)
    elseif chunksize == nil then
        chunksize = DEFAULT_CHUNKSIZE
    elseif not is_uint(chunksize) or chunksize == 0 then
        error('chunksize must be uint greater than 0', 2)
    end

    if handler == nil then
        -- use default handler
        handler = DEFAULT_CHUNKHANDLER
    end
    self.is_consumed = true

    -- read chunked-encoded string
    local r = self.reader
    local size = 0
    local str = ''
    local done = false
    while not done do
        local s, err = r:read(chunksize)
        if not s or #s == 0 or err then
            return nil, err
        end
        str = str .. s

        --
        -- 4.1.  Chunked Transfer Coding
        -- https://tools.ietf.org/html/rfc7230#section-4.1
        --
        -- chunked-body     = *chunk
        --                    last-chunk
        --                    trailer-part
        --                    CRLF
        --
        -- chunk            = chunk-size [ chunk-ext ] CRLF
        --                    chunk-data CRLF
        -- chunk-size       = 1*HEXDIG
        -- last-chunk       = 1*("0") [ chunk-ext ] CRLF
        --
        -- chunk-ext        = *( BWS ";" BWS chunk-ext-name [ BWS "=" BWS chunk-ext-val ] )
        -- chunk-ext-name   = token
        -- chunk-ext-val    = token / quoted-string
        -- BWS              = *( SP / HTAB )
        --                  ; Bad White Space for backward compatibility
        --
        -- read chunk-size
        repeat
            local ext = {}
            local csize, perr, cur = parse_chunksize(str, ext)
            if perr then
                if perr.type ~= EAGAIN then
                    -- invalid chunk-size format
                    return nil, perr
                end
            elseif csize == 0 then
                -- last-chunk
                done = true
                csize = nil
                -- add chunk-ext
                err = handler:read_last_chunk(ext)
                if err then
                    return nil, err
                end
                str = sub(str, cur + 1)
            else
                -- remove chunk-size [ chunk-ext ] CRLF
                str = sub(str, cur + 1)

                --
                -- chunk-data = 1*OCTET ; a sequence of chunk-size octets
                --
                -- read chunk-data (csize + CRLF)
                while #str < csize + 2 do
                    s, err = r:read(chunksize)
                    if not s then
                        return nil, err
                    end
                    str = str .. s
                end

                -- check end-of-line (CRLF) of chunk-data
                local head, tail = find(str, '^\r*\n', csize + 1)
                if not head then
                    -- invalid end-of-line terminator
                    return nil, parse.EEOL:new()
                end

                -- check chunk by handler
                s, err = handler:read_chunk(sub(str, 1, csize), ext)
                if err then
                    return nil, err
                elseif s then
                    -- write chunk
                    local nw
                    nw, err = w:write(s)
                    if not nw or err then
                        return nil, err
                    end
                    size = size + csize
                end

                -- parse again
                str = sub(str, tail + 1)
            end
        until not csize
        -- read again
    end

    --
    -- trailer-part = *( header-field CRLF ) CRLF
    --
    -- parse trailer-part
    while true do
        local trailer = {}
        local cur, err = parse_header(str, trailer)

        if cur then
            r:prepend(sub(str, cur + 1))

            err = handler:read_trailer(trailer)
            if err then
                return nil, err
            end
            return size
        elseif err.type ~= EAGAIN then
            return nil, err
        end

        -- read data
        local s
        s, err = r:read(chunksize)
        if not s or #s == 0 or err then
            return nil, err
        end
        str = str .. s
    end
end

--- write
--- @param w net.http.writer
--- @param chunksize? integer
--- @param handler? net.http.content.chunked.Handler
--- @return integer len
--- @return string? err
function ChunkedContent:write(w, chunksize, handler)
    if self.is_consumed then
        error('content is already consumed', 2)
    elseif chunksize == nil then
        chunksize = DEFAULT_CHUNKSIZE
    elseif not is_uint(chunksize) or chunksize == 0 then
        error('chunksize must be uint greater than 0', 2)
    end

    if handler == nil then
        -- use default handler
        handler = DEFAULT_CHUNKHANDLER
    end
    self.is_consumed = true

    -- read and write string
    local r = self.reader
    local size = 0
    while true do
        local s, err = r:read(chunksize)

        if not s then
            if err then
                return nil, err
            end
            break
        elseif #s == 0 then
            local n
            n, err = handler:write_last_chunk(w)
            if not n or err then
                return nil, err
            end
            break
        end

        local n
        n, err = handler:write_chunk(w, s)
        if not n or err then
            return nil, err
        end
        size = size + #s
    end

    local n, err = handler:write_trailer(w)
    if not n or err then
        return nil, err
    end
    return size
end

return {
    new = require('metamodule').new(ChunkedContent, 'net.http.content'),
}
