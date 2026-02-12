package.cpath = '/home/john/moor/?.so;' .. package.cpath

local ffi = require("ffi")
ffi.cdef[[
  long long mur_add(long long a, long long b);


  void vim_init();

  typedef int (* moor_callback_func_t)(int what, int param); 
  void vim_set_callback(moor_callback_func_t ef);

  void vim_launch();
  void vim_exec(const char *source);

]]
moor = ffi.load("moorst.so");

-- print(tostring(tonumber(moor.mur_add(40, 2))))


moor.vim_init()

MOOR_OUT = "This is Forth output: "
moor.vim_set_callback(
  function (what, param) 
    MOOR_OUT = MOOR_OUT .. string.char(param) 
    -- print(string.char(c))
    return 0
  end)

moor.vim_launch()

--print("Moor!" .. MOOR_OUT)
MOOR_OUT = ""
moor.vim_exec('30 emit ')

print("Moor!" .. MOOR_OUT)
