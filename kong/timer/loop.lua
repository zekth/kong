local ngx_timer_at = ngx.timer.at


local setmetatable = setmetatable


local _M = {}

local meta_table = {
    __index = _M,
}


local function loop_wrapper(premature, self)
    if premature then
        return
    end

    if self.init then
        local init = self.init
        init.callback(table.unpack(init.argv, 1, init.argc))
    end

    local loop_body = self.loop_body
    local loop_body_callback = loop_body.callback
    local loop_body_argc = loop_body.argc
    local loop_body_argv = loop_body.argv

    while not ngx.worker.exiting() and not self._kill do
        loop_body_callback(table.unpack(loop_body_argv, 1, loop_body_argc))
    end
end


function _M:spawn()
    ngx_timer_at(0, loop_wrapper, self)
end


function _M:kill()
    self._kill = true
end


function _M.new(options)
    local self = {
        _kill = false
    }

    if options.init then
        self.init = {
            callback = options.init.callback,
            argc = options.init.argc,
            argv = options.init.argv,
        }
    end

    if options.loop_body then
        self.loop_body = {
            callback = options.loop_body.callback,
            argc = options.loop_body.argc,
            argv = options.loop_body.argv
        }
    end

    return setmetatable(self, meta_table)
end


return _M