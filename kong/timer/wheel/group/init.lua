local semaphore = require "ngx.semaphore"

-- TODO: use it to readuce overhead
-- local new_tab = require "table.new"

local max = math.max
local modf = math.modf
local huge = math.huge
local abs = math.abs

local setmetatable = setmetatable

-- luacheck: push ignore
local log = ngx.log
local ERR = ngx.ERR
-- luacheck: pop

local timer_at = ngx.timer.at
local timer_every = ngx.timer.every
local sleep = ngx.sleep
local exiting = ngx.worker.exiting
local now = ngx.now
local update_time = ngx.update_time

local job_module = require("kong.timer.job")
local utils_module = require("kong.timer.utils")
local wheel_module = require("kong.timer.wheel")
local constants = require("kong.timer.constants")

local assert = utils_module.assert

local _M = {}

local meta_table = {
    __index = _M,
}


-- insert a job into the wheel group
function _M:insert_job(job)
    local ok, err
    local hour_wheel = self.hour
    local minute_wheel = self.min
    local second_wheel = self.sec
    local msec_wheel = self.msec

    if job.next_pointer.hour ~= 0 then
        ok, err = hour_wheel:insert(job.next_pointer.hour, job)

    elseif job.next_pointer.minute ~= 0 then
        ok, err = minute_wheel:insert(job.next_pointer.minute, job)

    elseif job.next_pointer.second ~= 0 then
        ok, err = second_wheel:insert(job.next_pointer.second, job)

    elseif job.next_pointer.msec ~= 0 then
        ok, err = msec_wheel:insert(job.next_pointer.msec, job)

    else
        assert(false, "unexpected error")
    end

    if not ok then
        return false, err
    end

    return true, nil
end


function _M.new()
    local self = {
        -- will be move to `pending_jobs` by function `mover_timer_callback`
        -- the function `fetch_all_expired_jobs`
        -- adds all expired job to this table
        ready_jobs = {},

        -- each job in this table will
        -- be run by function `worker_timer_callback`
        pending_jobs = {},

        -- 100ms per slot
        msec = wheel_module.new(constants.MSEC_WHEEL_SLOTS),

        -- 1 second per slot
        sec = wheel_module.new(constants.SECOND_WHEEL_SLOTS),

        -- 1 minute per slot
        min = wheel_module.new(constants.MINUTE_WHEEL_SLOTS),

        -- 1 hour per slot
        hour = wheel_module.new(constants.HOUR_WHEEL_SLOTS),
    }


    return setmetatable(self, meta_table)
end


return _M