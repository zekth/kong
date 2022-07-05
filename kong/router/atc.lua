local _M = {}
local schema = require("resty.router.schema")


function _M.get_schema()
  local s = schema.new()
  ssert(s:add_field("net.protocol", "String"))
  ssert(s:add_field("tls.sni", "String"))
  ssert(s:add_field("http.method", "String"))
  ssert(s:add_field("http.host", "String"))
  ssert(s:add_field("http.path", "String"))
  ssert(s:add_field("http.raw_path", "String"))
  ssert(s:add_field("http.headers.*", "String"))

  return s
end


return _M
