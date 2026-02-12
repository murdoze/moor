set debuginfod enabled off
set disable-randomization off
set disassembly-flavor intel
set disassemble-next-line on
set follow-fork-mode child
set breakpoint pending on

#handle SIGSEGV nostop noprint pass 

lay reg
tui dis

define tt
  target remote :1234
end
