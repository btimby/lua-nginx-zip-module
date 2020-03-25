local ZipWriter = require('ZipWriter')
local http = require('resty.http')
local resty_url = require('resty.url');

-- Required arguments
local UPSTREAM = ngx.var.upstream;
local FILE_URL = ngx.var.file_url;
local FILE_URL_PARTS = resty_url.parse(FILE_URL)

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
local res = ngx.location.capture(UPSTREAM, { method = method_id })

-- Get magic header.
local archive = res.header[HEADER_NAME]

-- If header value is not "zip", forward response downstream. We may
-- support other archive formats in the future.
-- TODO: maybe return an error?
if (archive ~= 'zip') then
    if (archive == nil) then
        ngx.log(ngx.WARN, 'Missing header ' .. HEADER_NAME)
    else
        ngx.log(ngx.WARN, 'Unsupported header ' .. HEADER_NAME .. ': ' .. archive)
    end

    -- Copy headers and status from subrequest.
    ngx.header = res.header
    ngx.status = res.status
    -- Proxy body and status code.
    ngx.print(res.body)
    ngx.exit(res.status)
end
ngx.header[HEADER_NAME] = nil

-- Set headers for a zip file download.
ngx.header['Content-Type'] = 'application/zip'
ngx.header['Content-Disposition'] = 'attachment; filename="' .. ZIPNAME .. '"'

-- This function generates a zipfile and streams it to ngx.print().
local stream_zip = function(file_list)

    -- This seems a bit backwards, but file I/O will block nginx's event loop.
    -- When the event loop is blocked, no other requests can be handled. One
    -- can add more workers, but if you have multiple requests for zip files
    -- you end up blocking multiple workers. To get around this we read the
    -- file using an HTTP request to localhost, nginx is configured to serve
    -- us the raw file which we can read chunk by chunk and flush out to nginx.
    --
    -- Thinking about this I feel it is an elegant solution. The data is read
    -- by nginx and never leaves nginx. We are leveraging it's file I/O capability
    -- even though nginx-lua/openresty does not expose an API for such. Lucky
    -- for us, it DOES expose a cosocket API that makes this possible.
    local make_reader = function(path)
        -- Set up our HTTP client.
        local httpc = http.new()

        httpc:connect(FILE_URL_PARTS.host, FILE_URL_PARTS.port)
        local file, httpErr = httpc:request({
            -- TODO: encode path parts
            path = FILE_URL_PARTS.path .. path,
        })

        -- Handle connection error.
        if not file then
            ngx.log(ngx.ERR, 'Error while requesting file: ' .. httpErr);
            ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        end

        -- The file description for use by ZipWriter.
        local desc = {
            istext = true,
            isfile = true,
        }

        -- Get a reader so we can incrementally read the file.
        local reader = file.body_reader

        -- Finally return the file information and a function that will
        -- return the file body chunk by chunk.
        return desc, desc.isfile and function()
            local chunk, readErr = reader(CHUNK_SIZE)
            if readErr then
                ngx.log(ngx.ERR, 'Failure reading file: ' .. readErr)
                ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end
            if chunk then
                return chunk
            end
        end
    end

    -- Set up zip output, use fastest method.
    local ZipStream = ZipWriter.new({ level = ZipWriter.COMPRESSION_LEVEL.SPEED })

    -- NOTE: it is critically important that the callback does not yield. It is called
    -- by a C function, and yielding across a C boundary is not permitted in lua. Any
    -- I/O operation that would possibly be put to sleep is not permitted. For example
    -- passing true to flush below causes this to fail because true waits for the flush
    -- to complete (I/O sleep). If this becomes a problem, the code could be refactored
    -- to write to a queue with a separate coroutine writing / flushing.
    --
    -- I ran this 100 times with flush(true) and it failed 3 times. I ran it 1000 times
    -- with flush() and it failed 0 times.
    --
    -- The error is:
    --
    --2020/03/25 03:36:23 [error] 6#6: *10 lua user thread aborted: runtime error: attempt to yield across C-call
    --  boundary
    --stack traceback:
    --coroutine 0:
    --	[C]: in function 'write'
    --	/usr/local/openresty/luajit/share/lua/5.1/ZipWriter.lua:562: in function 'write'
    --	/usr/local/openresty/luajit/share/lua/5.1/ZipWriter.lua:952: in function 'write'
    --	/usr/local/openresty/lualib/nginx_lua_zipstream.lua:148: in function
    --    </usr/local/openresty/lualib/nginx_lua_zipstream.lua:86>
    -- while sending to client, client: 172.17.0.1, server: localhost, request: "GET /zipstream/foobar HTTP/1.1",
    --   host: "localhost:8080"
    --
    -- The [C] call above is zlib which invokes our callback with a chunk of compressed
    -- data.
    ZipStream:open_writer(function(chunk)
        ngx.print(chunk)
        ngx.flush()
    end)

    -- TODO: We should enforce a limit on total file size. We can loop over this
    -- list that upstream sent us and sum the size and conditionally throw an error.
    -- Loop over requested files
    for _, entry in pairs(splitlines(file_list)) do
        -- Parse each line, format: crc32 size uri name
        local _, _, uri, name = string.match(entry, "(.-)%s(.-)%s(.-)%s(.*)")
        local path = ngx.unescape_uri(uri)

        ZipStream:write(name, make_reader(path))
    end

    ZipStream:close()
end

-- Do the heavy lifting in a coroutine. No need to wait, our entry thread / request
-- will not terminate until all light threads are done. If you need to spawn additional
-- coroutines, you can do so here.
ngx.thread.spawn(stream_zip, res.body)
