local _M = {}
local schema = require("resty.router.schema")


function _M.get_schema()
  local s = schema.new()
  s:add_field("net.protocol", "String")
  s:add_field("tls.sni", "String")
  s:add_field("http.method", "String")
  s:add_field("http.host", "String")
  s:add_field("http.path", "String")
  s:add_field("http.raw_path", "String")
  s:add_field("http.headers.*", "String")

  return s
end


return _M
