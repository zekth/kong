local ffi = require "ffi"
local C = ffi.C

ffi.cdef[[
    typedef long time_t;
    typedef int clockid_t;

    typedef struct timespec {
            time_t   tv_sec;        /* seconds */
            long     tv_nsec;       /* nanoseconds */
    } nanotime;
    int clock_gettime(clockid_t clk_id, struct timespec *tp);
]]

local function clock_gettime()
    local pnano = assert(ffi.new("nanotime[?]", 1))

    -- CLOCK_REALTIME -> 0
    C.clock_gettime(0, pnano)
    return pnano[0]
end


local function timestamp_ns()
    local t = clock_gettime()
    return tonumber(t.tv_sec) * 100000000 + tonumber(t.tv_nsec)
end

local function ngx_time_unix_nano()
    ngx.update_time()
    return ngx.now() * 1000000
end

local a = ngx.now()

local N = 1e7
for i = 1, N do
    timestamp_ns()
end

ngx.update_time()
print("ffi: ", ngx.now() - a)

ngx.update_time()

a = ngx.now()

for i = 1, N do
    ngx_time_unix_nano()
end

ngx.update_time()
print("ngx: ", ngx.now() - a)