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

--
-- Word under cursor
--

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

--
-- Scratch buffers/windows
--

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

function strip_cursor_motion(s)
  -- CSI n G  (Horizontal Absolute)   e.g. ESC[19G
  s = s:gsub("\27%[[0-9]+G", "")
  -- CSI n H / CSI r;c H (Cursor Position)  ESC[H or ESC[12;34H
  s = s:gsub("\27%[[0-9;]*H", "")
  -- CSI n f (same as H)
  s = s:gsub("\27%[[0-9;]*f", "")
  -- CSI n A/B/C/D (cursor up/down/right/left)
  s = s:gsub("\27%[[0-9]*[ABCD]", "")
  return s
end

local function buf_append_text(buf, text)
  if not text or text == "" then return end
  text = strip_cursor_motion(text)
  vim.bo[buf].modifiable = true
  local lines = vim.split(text, "\n", { plain = true })
  -- Avoid inserting a final empty line if text ends with "\n"
  if #lines > 0 and lines[#lines] == "" then table.remove(lines, #lines) end

  local last = vim.api.nvim_buf_line_count(buf)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, last, last, true, lines)
end

local function buf_set_text(buf, text)
  test = strip_cursor_motion(text)
  vim.bo[buf].modifiable = true
  local lines = vim.split(text or "", "\n", { plain = true })
  if #lines > 0 and lines[#lines] == "" then table.remove(lines, #lines) end
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)

  vim.bo[buf].modifiable = true
  baleia.automatically(out_buf, 0, 999999)
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

-- Live OUT terminal (renders ANSI cursor motion like WezTerm)
-- Globals you keep (one OUT terminal)
local out_chan, out_term_buf, out_term_win

local function out_term_visible_in_current_tab()
  if not out_term_buf or not vim.api.nvim_buf_is_valid(out_term_buf) then return false end
  local tab = vim.api.nvim_get_current_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.api.nvim_win_get_buf(win) == out_term_buf then
      return true
    end
  end
  return false
end

local function moor_open_out_live()
  -- If OUT terminal already exists and window is valid, do nothing
  if out_term_win and vim.api.nvim_win_is_valid(out_term_win)
     and out_term_buf and vim.api.nvim_buf_is_valid(out_term_buf) then
    return
  end

  local src_win = vim.api.nvim_get_current_win()

  -- Create a NEW bottom split for OUT and move into it
  vim.cmd("botright split")
  vim.cmd("resize 15")
  out_term_win = vim.api.nvim_get_current_win()

  -- Start terminal job in THIS window only
  out_term_buf = vim.api.nvim_get_current_buf()
  out_chan = vim.b.terminal_job_id

  -- Make it panel-like
  vim.bo[out_term_buf].buflisted = false
  vim.wo[out_term_win].number = false
  vim.wo[out_term_win].relativenumber = false
  vim.wo[out_term_win].signcolumn = "no"

  -- Go back to source window
  vim.api.nvim_set_current_win(src_win)
  vim.cmd("wincmd r")

end

local function ensure_out_terminal_here()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()

  -- If this window is not already a terminal, replace its buffer with a fresh one
  -- BEFORE termopen, otherwise you convert the source buffer into a terminal buffer.
  if vim.bo[buf].buftype ~= "terminal" then
    vim.cmd("enew")  -- critical: break buffer sharing created by :split
  end

  -- Now ensure we have a terminal job
  buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "terminal" then
    -- vim.fn.termopen({ "cat" })
    vim.fn.termopen({ "sh", "-lc", "stty -echo -icanon min 1 time 0; cat"  })
  end

  out_term_win = win
  out_term_buf = vim.api.nvim_get_current_buf()
  out_chan = vim.b.terminal_job_id

  -- panel cosmetics
  vim.bo[out_term_buf].buflisted = false
  vim.wo[out_term_win].number = false
  vim.wo[out_term_win].relativenumber = false
  vim.wo[out_term_win].signcolumn = "no"
end

local function out_send(s)
  if not s or s == "" then return end
  if not out_chan then moor_open_out_live() end
  if out_chan then
    vim.api.nvim_chan_send(out_chan, s)
  end
end

local function out_clear()
  if out_chan then
    -- clear screen + home cursor
    vim.api.nvim_chan_send(out_chan, "\27[2J\27[H")
  end
end

local function out_term_visible_in_current_tab()
  if not out_term_buf or not vim.api.nvim_buf_is_valid(out_term_buf) then return false end
  local tab = vim.api.nvim_get_current_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.api.nvim_win_get_buf(win) == out_term_buf then
      return true
    end
  end
  return false
end

function moor_open_panels()
  -- If OUT terminal already exists in this tab, do nothing
  if out_term_visible_in_current_tab() then
    return
  end

  -- Create stack buffer once
  if not stack_buf then
    stack_buf = ensure_scratch_buf("MOOR-STACK")
  end

  -- Capture source window/buffer explicitly
  local src_win = vim.api.nvim_get_current_win()
  local src_buf = vim.api.nvim_win_get_buf(src_win)

  -- 1) Create OUT row (bottom split)
  vim.cmd("split")
  vim.cmd("wincmd w")
  local out_win = vim.api.nvim_get_current_win()

  -- Critical: detach OUT window from source buffer by putting a new empty buffer into OUT win
  local tmpbuf = vim.api.nvim_create_buf(false, true) -- scratch
  vim.api.nvim_win_set_buf(out_win, tmpbuf)
  vim.bo[tmpbuf].buftype = "nofile"
  vim.bo[tmpbuf].bufhidden = "wipe"
  vim.bo[tmpbuf].swapfile = false

  -- Turn THAT buffer into a terminal by running termopen in OUT window
  vim.api.nvim_set_current_win(out_win)

  -- Create OUT terminal buffer (no job/PTY)
  out_term_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(out_win, out_term_buf)
  vim.bo[out_term_buf].bufhidden = "hide"
  vim.bo[out_term_buf].swapfile = false
  vim.bo[out_term_buf].modifiable = false

  out_chan = vim.api.nvim_open_term(out_term_buf, {})
  out_term_win = out_win

  -- Panel cosmetics
  vim.bo[out_term_buf].buflisted = false
  vim.wo[out_term_win].number = false
  vim.wo[out_term_win].relativenumber = false
  vim.wo[out_term_win].signcolumn = "no"

  -- Set OUT height
  vim.api.nvim_win_set_height(out_term_win, 20)

  -- 2) Create STACK column on the right inside the OUT row
  vim.cmd("vsplit")
  vim.cmd("wincmd w")
  
  local sw = vim.api.nvim_get_current_win()
  stack_win = sw
  -- vim.api.nvim_win_set_buf(stack_win, stack_buf)
  vim.api.nvim_win_set_width(stack_win, 20)

  -- Optional cosmetics for stack pane
  vim.wo[stack_win].number = false
  vim.wo[stack_win].relativenumber = false
  vim.wo[stack_win].signcolumn = "no"

  -- 3) Restore focus to source window + buffer (belt and suspenders)
  if vim.api.nvim_win_is_valid(src_win) then
    vim.api.nvim_set_current_win(src_win)
    -- Ensure source buffer is still the source buffer
    if vim.api.nvim_win_get_buf(src_win) ~= src_buf and vim.api.nvim_buf_is_valid(src_buf) then
      vim.api.nvim_win_set_buf(src_win, src_buf)
    end
  end

  vim.cmd("b MOOR-STACK")
  vim.cmd("wincmd w")
end


local sink = "out"          -- "out" or "stack"
local pending_out = ""
local pending_stack = {}
local flush_scheduled = false

local function schedule_flush()
  if flush_scheduled then return end
  flush_scheduled = true
  vim.schedule(function()
    flush_scheduled = false

    if out_chan and #pending_out > 0 then
      out_send(pending_out)
      pending_out = ""
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
    pending_out = pending_out .. c
  end
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
  vim.cmd("wa")

  local word = forth_word_under_cursor()
  print(word)
  word = word .. " vim "

  moor_open_panels()

  out_clear()
  moor.vim_exec(word)
  schedule_flush()
end,
{ noremap=true, silent=true, desc = "Go to Moor definition" })

vim.keymap.set('n', 'md', 
function()
  vim.cmd("wa")

  local word = forth_word_under_cursor()
  print(word)
  word = "cr ' " .. word .. " decompile vim "

  moor_open_panels()

  out_clear()
  moor.vim_exec(word)
  schedule_flush()
end,
{ noremap=true, silent=true, desc = "Decompile Moor definition" })

vim.keymap.set('n', 'mD', 
function()
  vim.cmd("wa")

  local word = forth_word_under_cursor()
  local adr = tonumber(word, 16)
  if adr == nil then return end
  print(word)

  word = word .. " decompile vim "

  out_clear()
  moor.vim_exec(word)
  schedule_flush()
end,
{ noremap=true, silent=true, desc = "Decompile at address" })

vim.keymap.set('n', 'mm', 
function()
  vim.cmd("wa")

  vim.fn.inputsave()
  local expr = vim.fn.input("Input Moor: ")
  vim.fn.inputrestore()
  if expr == "" then return end

  expr = expr .. " cr .S cr vim"
  print(expr)

  moor_open_panels()

  out_clear()
  moor.vim_exec(expr)
  schedule_flush()

end,
{ noremap=true, silent=true, desc = "Execure Moor string" })

vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], { noremap = true })

vim.keymap.set("n", "LL", function()
  vim.cmd("wqa")
end)

hex = require'hex'

--
-- MOOR API
--

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


