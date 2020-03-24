local ZipWriter = require('ZipWriter')

-- Required arguments
local UPSTREAM = ngx.var.upstream;
local FILE_ROOT = ngx.var.file_root;

-- Optional arguments
local HEADER_NAME = ngx.var.header or 'X-Archive-Files'
local CHUNK_SIZE = ngx.var.chunk_size or 65535
local ZIPNAME = ngx.var.zipname or 'multi.zip'
local METHODS = ngx.var.methods or 'GET POST'

-- For conversion of method name to method constant.
local METHOD_MAP = {}
METHOD_MAP['POST'] = ngx.HTTP_POST
METHOD_MAP['GET'] = ngx.HTTP_GET
METHOD_MAP['HEAD'] = ngx.HTTP_HEAD
METHOD_MAP['PUT'] = ngx.HTTP_PUT

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Library functions
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local splitlines = function(str)
    local lines = {}
    for s in str:gmatch("[^\r\n]+") do
        table.insert(lines, s)
    end
    return lines
end

local make_reader = function(path)
    -- prepend file_root if specified.
    if (FILE_ROOT ~= nil) then
        path = FILE_ROOT .. path
    end

    local f = assert(io.open(path, 'rb'))

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
local method_name = ngx.req.get_method()
if not string.match(METHODS, method_name) then
    -- We are not to handle this method.
    return ngx.exec(UPSTREAM)
end

-- Convert method name returned by ngx.req.get_method() to the constant needed
-- by ngx.location.capture().
local method_id = METHOD_MAP[method_name]
if (method_id == nil) then
    ngx.log(ngx.ERR, 'Unsupported method ' .. method_name .. ', add to METHOD_MAP')
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

-- Prepare for subrequest, we must have read the body in order for the body to
-- be forwarded in the subrequest.
ngx.req.read_body()

-- Do a subrequest to origin. This will proxy to upstream, but allow us to
-- ispect the response. Ensure the method matches parent request, in which
-- case the body (if a POST or PUT) will be forwarded.
local r = ngx.location.capture(UPSTREAM, { method = method_id })

-- Get magic header.
local archive = r.header[HEADER_NAME]

-- If header value is not "zip", forward response downstream. We may
-- support other archive formats in the future.
-- TODO: maybe return an error?
if archive ~= 'zip' then
    ngx.log(ngx.WARN, 'Unsupported header ' .. HEADER_NAME .. ': ' .. archive)

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
    -- Parse each line, format: crc32 size uri name
    local _, _, uri, name = string.match(entry, "(.-)%s(.-)%s(.-)%s(.*)")
    local path = ngx.unescape_uri(uri)

    ZipStream:write(name, make_reader(path))
end

ZipStream:close()
