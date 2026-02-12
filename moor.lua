package.cpath = '/home/john/moor/?.so;' .. package.cpath

local ffi = require("ffi")
ffi.cdef[[
  typedef int (* moor_callback_func_t)(int what, int iparam, const char *sparam); 
  void vim_set_callback(moor_callback_func_t f);

  void vim_init();
  void vim_launch();
  void vim_exec(const char *source);

]]
moor = ffi.load("moorst.so");

--
-- MOOR API
--

MOOR_OUT = "This is Forth output: "

local function moor_emit(c)
  MOOR_OUT = MOOR_OUT .. c
end

local function moor_sourcefile(filename)
  MOOR_OUT = MOOR_OUT .. "SOURCEFILE [" .. filename .. "]\n"
end

local MOOR_EMIT = 1
local MOOR_SOURCEFILE = 2

moor.vim_init()

moor.vim_set_callback(
  function(what, iparam, sparam)
    if what == MOOR_EMIT then moor_emit(string.char(iparam)) end
    if what == MOOR_SOURCEFILE then moor_sourcefile(ffi.string(sparam)) end
    if what ~= 0 then print(what) end
    
    return 0
  end)

moor.vim_launch()

print("Moor!" .. MOOR_OUT)
MOOR_OUT = ""
moor.vim_exec('30 emit ')

print("Moor!" .. MOOR_OUT)
