package.cpath = '/home/john/moor/?.so;' .. package.cpath

local ffi = require("ffi")
ffi.cdef[[
  long long mur_add(long long a, long long b);


  void vim_init();

  typedef void (* emit_func_t)(int c); 
  void vim_set_emit(emit_func_t ef);

  void vim_launch();
  void vim_exec(const char *source);

]]
local moor = ffi.load("moorst.so");

-- print(tostring(tonumber(moor.mur_add(40, 2))))


moor.vim_init()

MOOR_OUT = "This is Forth output: "
moor.vim_set_emit(
  function (c) 
    MOOR_OUT = MOOR_OUT .. string.char(c); 
    -- print(string.char(c))
  end)

moor.vim_launch()

--print("Moor!" .. MOOR_OUT)
MOOR_OUT = ""
moor.vim_exec('words vim')

print("Moor!" .. MOOR_OUT)
