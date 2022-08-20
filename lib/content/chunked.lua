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
--- @field bufsize integer
--- @field is_chunked boolean
--- @field is_read_chunk boolean
--- @field is_read_trailer boolean
--- @field chunk string
local ChunkedContent = {}

--- init
--- @param r net.http.reader
--- @return net.http.content.chunked content
function ChunkedContent:init(r)
    self.reader = r
    self.bufsize = 4096
    self.is_chunked = true
    self.is_read_chunk = false
    self.is_read_trailer = false
    self.chunk = ''
    return self
end

--- read_trailer
--- @param self net.http.content.chunked
--- @param handler net.http.content.chunked.Handler
--- @return any err
--- @return boolean|nil timeout
local function read_trailer(self, handler)
    -- read chunked-encoded string
    local r = self.reader
    local bufsize = self.bufsize
    local str = ''

    --
    -- trailer-part = *( header-field CRLF ) CRLF
    --
    -- parse trailer-part
    while true do
        -- read data
        local s, err, timeout = r:read(bufsize)
        if not s or err or timeout then
            return err, timeout
        end
        str = str .. s

        local trailer = {}
        local tail
        tail, err = parse_header(str, trailer)
        if tail then
            self.is_read_trailer = true
            r:prepend(sub(str, tail + 1))
            err = handler:read_trailer(trailer)
            return err
        elseif err.type ~= EAGAIN then
            return err
        end
    end
end

--- read_chunk
--- @param self net.http.content.chunked
--- @param chunksize integer
--- @param handler net.http.content.chunked.Handler
--- @return boolean ok
--- @return any err
--- @return boolean|nil timeout
local function read_chunk(self, chunksize, handler)
    -- read chunked-encoded string
    local r = self.reader
    local bufsize = self.bufsize
    local chunk = self.chunk
    local str = ''

    while true do
        local s, err, timeout = r:read(bufsize)
        if not s or err or timeout then
            return false, err, timeout
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
        repeat
            -- read chunk-size
            local ext = {}
            local csize, perr, cur = parse_chunksize(str, ext)
            if csize then
                -- remove chunk-size [ chunk-ext ] CRLF
                str = sub(str, cur + 1)

                -- last-chunk
                if csize == 0 then
                    self.is_read_chunk = true
                    -- add chunk-ext
                    err = handler:read_last_chunk(ext)
                    if err then
                        return false, err
                    end
                    r:prepend(str)
                    self.chunk = chunk
                    return true
                end

                --
                -- chunk-data = 1*OCTET ; a sequence of chunk-size octets
                --
                -- read chunk-data (csize + CRLF)
                while #str < csize + 2 do
                    s, err, timeout = r:read(bufsize)
                    if not s or err or timeout then
                        return false, err, timeout
                    end
                    str = str .. s
                end

                -- check end-of-line (CRLF) of chunk-data
                local head, tail = find(str, '^\r*\n', csize + 1)
                if not head then
                    -- invalid end-of-line terminator
                    return false, parse.EEOL:new()
                end

                -- check chunk by handler
                s, err = handler:read_chunk(sub(str, 1, csize), ext)
                str = sub(str, tail + 1)
                if err then
                    return false, err
                end
                chunk = chunk .. s

                -- stops reading when the specified chunk size is reached
                if chunksize and #chunk >= chunksize then
                    r:prepend(str)
                    self.chunk = chunk
                    return true
                end
            elseif perr and perr.type ~= EAGAIN then
                -- invalid chunk-size format
                return false, perr
            end
        until not csize
    end
end

--- read
--- @param self net.http.content.chunked
--- @param chunksize integer
--- @param handler net.http.content.chunked.Handler
--- @return string|nil str
--- @return any err
local function read(self, chunksize, handler)
    local chunk = self.chunk
    local n = #chunk
    if not self.is_read_chunk and n < chunksize then
        local ok, err = read_chunk(self, chunksize, handler)
        if not ok then
            return nil, err
        end
        chunk = self.chunk
        n = #chunk
    end

    if n > 0 then
        if n >= chunksize then
            self.chunk = sub(chunk, chunksize + 1)
            return sub(chunk, 1, chunksize)
        end
        self.chunk = ''
        return chunk
    elseif not self.is_read_trailer then
        return nil, read_trailer(self, handler)
    end
end

--- read
--- @param chunksize? integer
--- @param handler net.http.content.chunked.Handler|nil
--- @return string|nil s
--- @return any err
function ChunkedContent:read(chunksize, handler)
    if chunksize == nil then
        chunksize = DEFAULT_CHUNKSIZE
    elseif not is_uint(chunksize) or chunksize == 0 then
        error('chunksize must be uint greater than 0', 2)
    end

    if handler == nil then
        -- use default handler
        handler = DEFAULT_CHUNKHANDLER
    end

    return read(self, chunksize, handler)
end

--- readall
--- @param self net.http.content.chunked
--- @param handler net.http.content.chunked.Handler
--- @return string|nil str
--- @return any err
local function readall(self, handler)
    local chunk
    if not self.is_read_chunk then
        local ok, err = read_chunk(self, nil, handler)
        if not ok then
            return nil, err
        end
        chunk = self.chunk
        self.chunk = ''
    end

    if not self.is_read_trailer then
        local err, timeout = read_trailer(self, handler)
        if err or timeout then
            return nil, err
        end
    end

    return chunk
end

--- readall
--- @param handler? net.http.content.chunked.Handler
--- @return string|nil s
--- @return any err
function ChunkedContent:readall(handler)
    if handler == nil then
        -- use default handler
        handler = DEFAULT_CHUNKHANDLER
    end

    local s, err = readall(self, handler)
    if not s then
        return nil, err
    end
    return s
end

--- copy
--- @param w net.http.writer
--- @param chunksize? integer
--- @param handler? net.http.content.chunked.Handler
--- @return integer len
--- @return string? err
function ChunkedContent:copy(w, chunksize, handler)
    if chunksize == nil then
        chunksize = DEFAULT_CHUNKSIZE
    elseif not is_uint(chunksize) or chunksize == 0 then
        error('chunksize must be uint greater than 0', 2)
    end

    if handler == nil then
        -- use default handler
        handler = DEFAULT_CHUNKHANDLER
    end

    local nbyte = 0
    local s, err = read(self, chunksize, handler)
    while s do
        -- write chunk
        local n, werr = w:write(s)
        if not n or werr then
            return nil, werr
        end

        nbyte = nbyte + #s
        s, err = read(self, chunksize, handler)
    end

    if err then
        return nil, err
    end

    return nbyte
end

--- write
--- @param w net.http.writer
--- @param chunksize? integer
--- @param handler? net.http.content.chunked.Handler
--- @return integer|nil len
--- @return any err
--- @return boolean|nil timeout
function ChunkedContent:write(w, chunksize, handler)
    if chunksize == nil then
        chunksize = DEFAULT_CHUNKSIZE
    elseif not is_uint(chunksize) or chunksize == 0 then
        error('chunksize must be uint greater than 0', 2)
    end

    if handler == nil then
        -- use default handler
        handler = DEFAULT_CHUNKHANDLER
    end

    if self.is_consumed then
        -- content is already consumed
        return 0
    end
    self.is_consumed = true

    -- read and write string
    local r = self.reader
    local size = 0
    local s, err, timeout = r:read(chunksize)
    while s do
        local n, werr = handler:write_chunk(w, s)
        if not n or werr then
            return nil, werr
        end
        size = size + #s

        s, err, timeout = r:read(chunksize)
    end

    if err or timeout then
        return nil, err, timeout
    end

    local n, werr = handler:write_last_chunk(w)
    if not n or werr then
        return nil, werr
    end

    n, werr = handler:write_trailer(w)
    if not n or werr then
        return nil, werr
    end
    return size
end

return {
    new = require('metamodule').new(ChunkedContent, 'net.http.content'),
}
