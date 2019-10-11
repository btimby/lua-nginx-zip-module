local _M = { _VERSION = "0.1"}
local mt = { __index = _M }

local ZipWriter = require('ZipWriter')

local HEADER_NAME = 'X-Archive-Files'
local CHUNK_SIZE = 65535

local splitlines = function(str)
    lines = {}
    for s in str:gmatch("[^\r\n]+") do
        table.insert(lines, s)
    end
    return lines
end

local hex_to_char = function(x)
    return string.char(tonumber(x, 16))
end
  
local unescape = function(url)
    return url:gsub("%%(%x%x)", hex_to_char)
end

function _M.new(self, o)
    local o = o or {}

    -- Set defaults
    o["origin"] = o["origin"] or "/origin"
    -- TODO: I would rather URI in file list refer to nginx "location", but
    -- would need to learn how to stream subrequest responses (cosocket).
    o["file_root"] = o["file_root"] or "/files"
    
    return setmetatable(o, mt)
end

function _M.send(self, r)
    -- Copy headers from subrequest.
    ngx.headers = r.header
    ngx.status = r.status
    -- Proxy body and status code.
    ngx.print(r.body)
    ngx.exit(r.status)
end

function _M.make_reader(self, uri)
    local path = unescape(uri)
    local f = assert(io.open(self.file_root .. path, 'rb'))
    local desc = {
        istext = true,
        isfile = true
    }

    return desc, desc.isfile and function()
        local chunk = f:read(CHUNK_SIZE)
        if chunk then return chunk end
        f:close()
    end
end

function _M.stream_files(self, r)
    ngx.header['Content-Type'] = 'application/zip'
    ngx.header['Content-Disposition'] = 'attachment; filename="multi.zip"'

    -- Set up zip output.
    local ZipStream = ZipWriter.new()

    ZipStream:open_writer(function(chunk)
        ngx.print(chunk)
        ngx.flush()
    end)

    -- Loop over requested files
    for _, entry in pairs(splitlines(r.body)) do
        local _, _, uri, name = string.match(entry, "(.-)%s(.-)%s(.-)%s(.*)")
        ZipStream:write(name, self:make_reader(uri))
    end

    ZipStream:close()
end

function _M.subrequest(self)
    -- Do a subrequest to origin. This will proxy to upstream, but allow us to
    -- ispect the response.
    local r = ngx.location.capture(self.origin)

    -- Get magic header.
    local archive = r.header[HEADER_NAME]

    -- If header value is not "zip", forward response downstream. We may
    -- support other archive formats in the future.
    if archive ~= 'zip' then
        return self:send(r)
    end

    self:stream_files(r)
end

function _M.pass()
    -- NOOP, we pass the request upstream.
    ngx.exec(self.origin)
end

function _M.process(self)
    -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    -- Main method. This processes a request.
    -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    local method = ngx.req.get_method()
    if method ~= "GET" then
        -- We operate only on GET requests
        return self:pass()
    end

    self:subrequest()

end

return _M