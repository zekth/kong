local bit = require "bit"
local FLAG_SAMPLED = 0x01
local FLAG_RECORDING = 0x02

local both = bit.bor(FLAG_RECORDING, FLAG_SAMPLED)

print(both)
print(bit.band(both, FLAG_RECORDING) == FLAG_RECORDING)
