local utils = require("kong.timer.utils")

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

local ngx_timer_at = ngx.timer.at
local ngx_worker_exiting = ngx.worker.exiting

local table_unpack = table.unpack

local setmetatable = setmetatable
local error = error


local _M = {
    ACTION_CONTINUE = 1,
    ACTION_ERROR = 2,
    ACTION_EXIT = 3,
}

local meta_table = {
    __index = _M,
}


local function callback_wrapper(self, check_worker_exiting, callback, ...)
    local action, err_or_nil = callback(...)

    if action == _M.ACTION_CONTINUE or
       action == _M.ACTION_EXIT
    then
        if check_worker_exiting and ngx_worker_exiting() then
            return _M.ACTION_EXIT
        end

        if self._kill then
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

    while not ngx_worker_exiting() and not self._kill do
        before()

        loop_body()

        after()
    end

    self.finally()
end


local function wrap_callback(self, callback, argc, argv,
                             is_check_worker_exiting)
    return function ()
        return callback_wrapper(self,
                                is_check_worker_exiting,
                                callback,
                                table_unpack(argv, 1, argc))
    end
end


function _M:spawn()
    self._kill = false
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
        self.init = wrap_callback(self,
                                  options.init.callback,
                                  options.init.argc,
                                  options.init.argv,
                                  do_not_check_worker_exiting)
    end

    if options.before then
        self.before = wrap_callback(self,
                                    options.before.callback,
                                    options.before.argc,
                                    options.before.argv,
                                    check_worker_exiting)
    end

    if options.loop_body then
        self.loop_body = wrap_callback(self,
                                       options.loop_body.callback,
                                       options.loop_body.argc,
                                       options.loop_body.argv,
                                       check_worker_exiting)
    end

    if options.after then
        self.after = wrap_callback(self,
                                   options.after.callback,
                                   options.after.argc,
                                   options.after.argv,
                                   do_not_check_worker_exiting)
    end

    if options.finally then
        self.finally = wrap_callback(self,
                                    options.finally.callback,
                                    options.finally.argc,
                                    options.finally.argv,
                                    do_not_check_worker_exiting)
    end

    return setmetatable(self, meta_table)
end


return _M