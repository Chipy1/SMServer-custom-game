local modes={}
modes.k = class()
modes.k.__index = nil -- intentional: weak-table mode objects must not inherit
modes.k.__mode = "k"

modes.kv = class()
modes.kv.__index = nil -- intentional: weak-table mode objects must not inherit
modes.kv.__mode = "kv"

modes.v = class()
modes.v.__index = nil -- intentional: weak-table mode objects must not inherit
modes.v.__mode = "v"


std = std or {}
function std.weakTable(mode)
    return ( type(mode) == "string" and modes[mode:lower()] or error("mode must be one of 'k', 'kv', 'v'", 2) )()
end