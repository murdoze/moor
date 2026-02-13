package.cpath = '/home/john/moor/?.so;' .. package.cpath

local ffi = require("ffi")
ffi.cdef[[
  typedef int (* moor_callback_func_t)(int what, int iparam, const char *sparam); 
  void vim_set_callback(moor_callback_func_t f);

  void vim_init();
  void vim_launch();
  void vim_exec(const char *source);

]]
is_moor, moor = pcall(ffi.load, "moorst.so")

if not is_moor then return end

local function forth_word_under_cursor()
  local row, col0 = unpack(vim.api.nvim_win_get_cursor(0)) -- row is 1-based, col is 0-based
  local line = vim.api.nvim_get_current_line()
  local len = #line
  local col = col0 + 1 -- make it 1-based for Lua string indexing

  if len == 0 then return nil end
  if col < 1 then col = 1 end
  if col > len + 1 then col = len + 1 end

  -- If cursor is on whitespace, try to move right to next non-space (optional behavior).
  -- If you prefer "no word on whitespace", remove this block.
  if col <= len and line:sub(col, col):match("%s") then
    local r = line:find("%S", col)
    if not r then return nil end
    col = r
  end

  -- Find word boundaries: maximal run of non-whitespace containing col
  local left = col
  while left > 1 and not line:sub(left - 1, left - 1):match("%s") do
    left = left - 1
  end

  local right = col
  while right <= len and not line:sub(right, right):match("%s") do
    right = right + 1
  end
  right = right - 1

  if right < left then return nil end
  return line:sub(left, right)
end

-- Scratch buffers/windows
local out_buf, stack_buf
local out_win, stack_win

local function ensure_scratch_buf(name)
  local b = vim.api.nvim_create_buf(false, true) -- listed=false, scratch=true
  vim.api.nvim_buf_set_name(b, name)
  vim.bo[b].buftype = "nofile"
  vim.bo[b].bufhidden = "hide"
  vim.bo[b].swapfile = false
  vim.bo[b].modifiable = false
  return b
end

local function buf_append_text(buf, text)
  if not text or text == "" then return end
  vim.bo[buf].modifiable = true
  local lines = vim.split(text, "\n", { plain = true })
  -- Avoid inserting a final empty line if text ends with "\n"
  if #lines > 0 and lines[#lines] == "" then table.remove(lines, #lines) end

  local last = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, last, last, true, lines)
  vim.bo[buf].modifiable = false
end

local function buf_set_text(buf, text)
  vim.bo[buf].modifiable = true
  local lines = vim.split(text or "", "\n", { plain = true })
  if #lines > 0 and lines[#lines] == "" then table.remove(lines, #lines) end
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  vim.bo[buf].modifiable = false
end

local function buf_visible_in_current_tab(buf)
  local tab = vim.api.nvim_get_current_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return true
    end
  end
  return false
end


function moor_open_panels()
  if buf_visible_in_current_tab(out_buf) then return end

  if not out_buf then out_buf = ensure_scratch_buf("MOOR-OUT") end
  if not stack_buf then stack_buf = ensure_scratch_buf("MOOR-STACK") end

  local src_win = vim.api.nvim_get_current_win()

  -- Create right column and get its win id deterministically
  vim.cmd("split")
  vim.cmd("wincmd w")
  local right_win = vim.api.nvim_get_current_win()

  -- Put OUT in right_win
  vim.api.nvim_win_set_buf(right_win, out_buf)

  -- Set right column width (adjust to taste)
  vim.api.nvim_win_set_height(right_win, 20)

  -- Split right column horizontally -> bottom pane
  vim.api.nvim_set_current_win(right_win)
  vim.cmd("vsplit")
  vim.cmd("wincmd w")
  local stack_win = vim.api.nvim_get_current_win()

  -- Put STACK in bottom-right
  vim.api.nvim_win_set_buf(stack_win, stack_buf)

  -- Set heights (top is OUT, bottom is STACK)
  vim.api.nvim_win_set_width(stack_win, 20)  -- stack height
  -- output pane gets remaining height automatically
  vim.cmd("wincmd r")

  -- Return focus to source
  vim.api.nvim_set_current_win(src_win)
  vim.cmd("wincmd w")
  vim.cmd("wincmd w")
end

local sink = "out"          -- "out" or "stack"
local pending_out = {}
local pending_stack = {}
local flush_scheduled = false

local function schedule_flush()
  if flush_scheduled then return end
  flush_scheduled = true
  vim.schedule(function()
    flush_scheduled = false
    if out_buf and #pending_out > 0 then
      buf_append_text(out_buf, table.concat(pending_out))
      pending_out = {}
    end
    if stack_buf and #pending_stack > 0 then
      buf_set_text(stack_buf, table.concat(pending_stack))
      pending_stack = {}
    end
  end)
end

local function sink_emit_char(c)
  if sink == "stack" then
    pending_stack[#pending_stack + 1] = c
  else
    pending_out[#pending_out + 1] = c
  end
  schedule_flush()
end

--
-- Key mappings
--

vim.keymap.set('n', '<c-\\>', 
function()
  local word = forth_word_under_cursor()
  local def = definitions[word]
  if def == nil then return end

  vim.cmd("edit " .. vim.fn.fnameescape(def.sourcefile))

  local lnum = tonumber(def.line) or 1
  local cnum = tonumber(def.col) or 1
  vim.api.nvim_win_set_cursor(0, { lnum, math.max(cnum - 1, 0) })
end,
{ noremap=true, silent=true, desc = "Go to Moor definition" })

vim.keymap.set('n', '<s-Enter>', 
function()
  moor_open_panels()

  local word = forth_word_under_cursor()
  print(word)
  word = word .. " "


  MOOR_OUT = ""
  moor.vim_exec(word)
  MOOR_OUT = MOOR_OUT .. "\n"
  buf_set_text(out_buf, MOOR_OUT)
end,
{ noremap=true, silent=true, desc = "Go to Moor definition" })

--
-- MOOR API
--

MOOR_OUT = ""

sourcefiles = {}
latest_sourcefile = ""
definitions = {}
defs = ""

local function moor_emit(c)
  sink_emit_char(c)
end

local function moor_sourcefile(filename)
  table.insert(sourcefiles, filename)
  latest_sourcefile = filename
end

local function moor_definition(word, col, line)
  definitions[word] = { sourcefile = latest_sourcefile, line = line, col = col }
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

-- 
-- Dirty tail
--


--moor.vim_exec('.S ')
--print("Moor!\n" .. MOOR_OUT)
--moor.vim_exec('30 emit ')

--print("Moor!" .. MOOR_OUT)
-- moor.vim_exec('.S ')

