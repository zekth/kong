local semaphore = require("ngx.semaphore")
local loop = require("kong.timer.thread.loop")
local utils = require("kong.timer.utils")
local constants = require("kong.timer.constants")

-- luacheck: push ignore
local ngx_log = ngx.log
local ngx_STDERR = ngx.STDERR
local ngx_ALERT = ngx.ALERT
local ngx_CRIT = ngx.CRIT
local ngx_ERR = ngx.ERR
local ngx_WARN = ngx.WARN
local ngx_NOTICE = ngx.NOTICE
local ngx_INFO = ngx.INFO
local ngx_DEBUG = ngx.DEBUG
-- luacheck: pop

-- luacheck: push ignore
local assert = utils.assert
-- luacheck: pop

local ngx_worker_exiting = ngx.worker.exiting

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
    local jobs = timer_sys.jobs

    while not utils.table_is_empty(wheels.pending_jobs) and
          not ngx_worker_exiting()
    do
        local _, job = next(wheels.pending_jobs)

        wheels.pending_jobs[job.name] = nil

        if not job:is_runnable() then
            goto continue
        end

        job:execute()

        if job:is_oneshot() then
            jobs[job.name] = nil
            goto continue
        end

        if job:is_runnable() then
            wheels:sync_time()
            job:re_cal_next_pointer(wheels)
            wheels:insert_job(job)
            self.wake_up_super_thread()
        end

        ::continue::
    end

    if not utils.table_is_empty(wheels.ready_jobs) then
        self.wake_up_mover_thread()
    end

    return loop.ACTION_CONTINUE
end


function _M:set_wake_up_mover_thread_callback(callback)
    self.wake_up_mover_thread = callback
end


function _M:set_wake_up_super_thread_callback(callback)
    self.wake_up_super_thread = callback
end


function _M:kill()
    local threads = self.threads
    for i = 1, #threads do
        threads[i]:kill()
    end
end


function _M:wake_up()
    local wake_up_semaphore = self.wake_up_semaphore
    wake_up_semaphore:post(#self.threads)
end


function _M:spawn()
    local threads = self.threads
    for i = 1, #threads do
        threads[i]:spawn()
    end
end


function _M.new(timer_sys, threads)
    local self = {
        timer_sys = timer_sys,
        wake_up_semaphore = semaphore.new(0),
        threads = {},
    }

    for i = 1, threads do
        self.threads[i] = loop.new({
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
    end

    return setmetatable(self, meta_table)
end


return _M