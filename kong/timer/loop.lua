local utils = require("kong.timer.utils")
local ngx_timer_at = ngx.timer.at
local table_unpack = table.unpack

local setmetatable = setmetatable
local error = error

local assert = utils.assert


local _M = {
    ACTION_CONTINUE = 1,
    ACTION_ERROR = 2,
    ACTION_EXIT = 3,
}

local meta_table = {
    __index = _M,
}


local function callback_wrapper(check_worker_exiting, callback, ...)
    local action, err_or_nil = callback(...)

    if action == _M.ACTION_CONTINUE or
       action == _M.ACTION_EXIT
    then
        if check_worker_exiting and ngx.worker.exiting() then
            return _M.ACTION_EXIT
        end

        return action
    end

    if action == _M.ACTION_ERROR then
        assert(err_or_nil ~= nil)

        return _M.ACTION_ERROR, err_or_nil
    end

    error("unexpected error")
end


local function nop()
    return _M.ACTION_CONTINUE
end


local function loop_wrapper(premature, self)
    if premature then
        return
    end

    self.init()

    local before = self.before
    local loop_body = self.loop_body
    local after = self.after

    while not ngx.worker.exiting() and not self._kill do
        before()

        if ngx.worker.exiting() then
            break
        end

        loop_body()

        if ngx.worker.exiting() then
            break
        end

        after()
    end

    self.finally()
end


function _M:spawn()
    ngx_timer_at(0, loop_wrapper, self)
end


function _M:kill()
    self._kill = true
end


function _M.new(options)
    local self = {
        _kill = false,
        init = nop,
        before = nop,
        loop_body = nop,
        after = nop,
        finally = nop,
    }

    local check_worker_exiting = true
    local do_not_check_worker_exiting = false

    if options.init then
        local callback = options.init.callback
        local argc = options.init.argc
        local argv = options.init.argv
        self.init = function ()
            return callback_wrapper(do_not_check_worker_exiting, callback, table_unpack(argv, 1, argc))
        end
    end

    if options.before then
        local callback = options.before.callback
        local argc = options.before.argc
        local argv = options.before.argv
        self.before = function ()
            return callback_wrapper(check_worker_exiting, callback, table_unpack(argv, 1, argc))
        end
    end

    if options.loop_body then
        local callback = options.loop_body.callback
        local argc = options.loop_body.argc
        local argv = options.loop_body.argv
        self.loop_body = function ()
            return callback_wrapper(check_worker_exiting, callback, table_unpack(argv, 1, argc))
        end
    end

    if options.after then
        local callback = options.after.callback
        local argc = options.after.argc
        local argv = options.after.argv
        self.after = function ()
            return callback_wrapper(do_not_check_worker_exiting, callback, table_unpack(argv, 1, argc))
        end
    end

    if options.finally then
        local callback = options.finally.callback
        local argc = options.finally.argc
        local argv = options.finally.argv
        self.finally = function ()
            return callback_wrapper(do_not_check_worker_exiting, callback, table_unpack(argv, 1, argc))
        end
    end

    return setmetatable(self, meta_table)
end


return _M