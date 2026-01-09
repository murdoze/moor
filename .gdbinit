set debuginfod enabled off
set disable-randomization off
set disassembly-flavor intel
set disassemble-next-line on

handle SIGSEGV nostop noprint pass 

define tt
  target remote :1234
end
