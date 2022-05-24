local ffi = require "ffi"
local C = ffi.C
local fmt = string.format

ffi.cdef [[
  typedef long time_t;
  typedef int clockid_t;

  typedef struct timespec {
          time_t   tv_sec;        /* seconds */
          long     tv_nsec;       /* nanoseconds */
  } nanotime;
  int clock_gettime(clockid_t clk_id, struct timespec *tp);
]]

local ffi_time_unix_nano
do
  local pnano = ffi.new("nanotime[1]")

  function ffi_time_unix_nano()
    -- CLOCK_REALTIME -> 0
    C.clock_gettime(0, pnano)
    local t = pnano[0]
    return tonumber(t.tv_sec) * 100000000 + tonumber(t.tv_nsec)
  end
end

print(fmt("%d", ffi_time_unix_nano()))
print(fmt("%d", ngx.now() * 100000000))
print(fmt("%d", ngx.now() * 1000 * 100000))
