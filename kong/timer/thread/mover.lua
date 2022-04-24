local semaphore = require("ngx.semaphore")
local loop = require("kong.timer.loop")
local utils = require("kong.timer.utils")
local constants = require("kong.timer.constants")

local math_abs = math.abs

local setmetatable = setmetatable

local _M = {}

local meta_table = {
    __index = _M,
}


local function thread_before(self)
    local wake_up_semaphore = self.wake_up_semaphore
    wake_up_semaphore:wait(constants.TOLERANCE_OF_GRACEFUL_SHUTDOWN)
    return loop.ACTION_CONTINUE
end


local function thread_body(self)
    local timer_sys = self.timer_sys
    local wheels = timer_sys.wheels

    local is_no_pending_jobs =
        utils.table_is_empty(timer_sys.wheels.pending_jobs)

    local is_no_ready_jobs =
        utils.table_is_empty(timer_sys.wheels.ready_jobs)

    if not is_no_pending_jobs then
        self.wake_up_worker_thread()
        return loop.ACTION_CONTINUE
    end

    if not is_no_ready_jobs then
        -- just swap two lists
        -- `wheels.ready_jobs = {}` will bring work to GC
        local temp = wheels.pending_jobs
        wheels.pending_jobs = wheels.ready_jobs
        wheels.ready_jobs = temp
        self.wake_up_worker_thread()
    end

    return loop.ACTION_CONTINUE
end


function _M:set_wake_up_worker_thread_callback(callback)
    self.wake_up_worker_thread = callback
end


function _M:kill()
    self.thread:kill()
end


function _M:wake_up()
    local wake_up_semaphore = self.wake_up_semaphore
    local count = wake_up_semaphore:count()

    if count <= 0 then
        wake_up_semaphore:post(math_abs(count) + 1)
    end
end


function _M:spawn()
    self.thread:spawn()
end


function _M.new(timer_sys)
    local self = {
        timer_sys = timer_sys,
        wake_up_semaphore = semaphore.new(0),
    }

    self.thread = loop.new({
        before = {
            argc = 1,
            argv = {
                self,
            },
            callback = thread_before,
        },

        loop_body = {
            argc = 1,
            argv = {
                self,
            },
            callback = thread_body,
        },
    })

    return setmetatable(self, meta_table)
end


return _M