local _M = {}
local schema = require("resty.router.schema")


function _M.get_schema()
  local s = schema.new()
  assert(s:add_field("net.protocol", "String"))
  assert(s:add_field("tls.sni", "String"))
  assert(s:add_field("http.method", "String"))
  assert(s:add_field("http.host", "String"))
  assert(s:add_field("http.path", "String"))
  assert(s:add_field("http.raw_path", "String"))
  assert(s:add_field("http.headers.*", "String"))

  return s
end


return _M
