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

MOOR_OUT = ""

sourcefiles = {}
latest_sourcefile = ""
definitions = {}
defs = ""

local function moor_emit(c)
  MOOR_OUT = MOOR_OUT .. c
end

local function moor_sourcefile(filename)
  table.insert(sourcefiles, filename)
  latest_sourcefile = filename
end

local function moor_definition(word, col, line)
  definitions[word] = { sourcefile = latest_sourcefile, line = line, col = col }
  defs = defs .. word .. " "
end

local MOOR_EMIT		= 1
local MOOR_SOURCEFILE	= 11
local MOOR_DEF_SOURCE	= 21
local MOOR_DEF_XT	= 22

moor.vim_init()

moor.vim_set_callback(
  function(what, iparam, sparam)
    if what == MOOR_EMIT then moor_emit(string.char(iparam)) end
    if what == MOOR_SOURCEFILE then moor_sourcefile(ffi.string(sparam)) end
    if what == MOOR_DEF_SOURCE then moor_definition(ffi.string(sparam), bit.band(iparam, 0xffff), bit.arshift(iparam, 16)) end
    
    return 0
  end)

moor.vim_launch()

-- moor.vim_exec('.S ')
print("Moor!\n" .. MOOR_OUT)
moor.vim_exec('30 emit ')

print("Moor!" .. MOOR_OUT)
-- moor.vim_exec('.S ')
