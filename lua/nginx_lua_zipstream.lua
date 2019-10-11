local ZipWriter = require('ZipWriter')

-- Required arguments
local UPSTREAM = ngx.var.upstream;
local FILE_ROOT = ngx.var.file_root;

-- Optional arguments
local HEADER_NAME = ngx.var.header or 'X-Archive-Files'
local CHUNK_SIZE = ngx.var.chunk_size or 65535
local ZIPNAME = ngx.var.zipname or 'multi.zip'
local METHODS = ngx.var.methods or 'GET POST'

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Library functions
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local splitlines = function(str)
    lines = {}
    for s in str:gmatch("[^\r\n]+") do
        table.insert(lines, s)
    end
    return lines
end

local unescape = function(url)
    return url:gsub("%%(%x%x)", function(x)
        return string.char(tonumber(x, 16))
    end)
end

local make_reader = function(uri)
    local path = unescape(uri)
    local f = assert(io.open(FILE_ROOT .. path, 'rb'))

    -- TODO: additional attributes...
    -- http://moteus.github.io/ZipWriter/#FILE_DESCRIPTION
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

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Main routine.
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local method = ngx.req.get_method()
if not string.match(METHODS, method) then
    -- We are not to handle this method.
    return ngx.exec(UPSTREAM)
end

-- Do a subrequest to origin. This will proxy to upstream, but allow us to
-- ispect the response.
local r = ngx.location.capture(UPSTREAM)

-- Get magic header.
local archive = r.header[HEADER_NAME]

-- If header value is not "zip", forward response downstream. We may
-- support other archive formats in the future.
-- TODO: maybe return an error?
if archive ~= 'zip' then
    -- Copy headers and status from subrequest.
    ngx.headers = r.header
    ngx.status = r.status
    -- Proxy body and status code.
    ngx.print(r.body)
    ngx.exit(r.status)
end

-- Set headers for a zip file download.
ngx.header['Content-Type'] = 'application/zip'
ngx.header['Content-Disposition'] = 'attachment; filename="' .. ZIPNAME .. '"'

-- Set up zip output.
local ZipStream = ZipWriter.new()

-- The following creates a callback to write response incrementally.
ZipStream:open_writer(function(chunk)
    ngx.print(chunk)
    ngx.flush()
end)

-- Loop over requested files
for _, entry in pairs(splitlines(r.body)) do
    -- Format: crc32 size uri name
    local _, _, uri, name = string.match(entry, "(.-)%s(.-)%s(.-)%s(.*)")
    ZipStream:write(name, make_reader(uri))
end

ZipStream:close()
