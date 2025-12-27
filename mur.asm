.intel_syntax	noprefix


	.globl _start

.text	
	.equ	STATES, 16	/* Number of possible address interpreter states */
	.equ	INTERPRETING, 0
	.equ	COMPILING, -2
	.equ	DECOMPILING, -4

	.equ	CANARY, 0x610eb14d500dbeef

				/* Before changing register assignment check usage of low 8-bit parts of these registers: al, bl, cl, dl, rXl etc. */
				/* TODO: define low byte aliases for needed address interpreter regsters */
	.equ	rwork, rax	/* Points to XT in code words. Needs not be preserved */
	.equ	rtop, rcx
	.equ	rstate, rbx
	.equ	rtmp, rdx	/* Needs not be preserved */
	.equ	rpc, rsi	/* Do not change! LODSx instructions are used */
	.equ	rstack, rbp
	.equ	rhere, rdi	/* Do not change! STOSx instructions are used */
	.equ	rindex, r10	/* Loop end and index values */
				/* R11 is clobbered by syscalls ix x64 Linux ABI */
	.equ	rend, r12
	.equ	rnext, r13
	.equ	rstack0, r15

# Initialization

	.align	4096
_start:
	jmp	_start1

	# Baremetal API

	RUNMODE_LINUXUSR	= 0
	RUNMODE_BAREMETAL 	= 1

runmode:	.byte	0
__key:		.quad	0
__emitchar:	.quad	0
__setcolor:	.quad	0
__warm:		.quad	_warm0	# Threaded code address to start execution from after warm restart

_start1:	
	cmp	byte ptr [runmode], RUNMODE_LINUXUSR
	je	1f

	lea	rhere, [here0]
	jmp	_cold

	1:
	mov	rax, 12
	lea	rdi, [here0]
	syscall
	# TODO check for error here
	mov	[_mem_reserved], rax

	call	_setup_sigsegv_handler
	mov	rhere, [_mem_reserved]

_cold:
	lea	rwork, last
	mov	[forth_], rwork
	lea	rwork, [forth_]
	mov	[_current], rwork
	mov	[_context], rwork

_restart:
	mov	rpc, qword ptr [__warm]
	jmp	_abort2
_abort:
	lea	rpc, [_warm0]
_abort2:	
	mov	byte ptr [_trace], 0
	mov	byte ptr [_debug], 0
	xor	rtop, rtop
	xor	rstate, rstate
	mov	[_state], rstate
	lea	rnext, qword ptr [_next]
	/* TODO: In "hardened" version map stacks to separate pages, with gaps between them */
	lea	rstack0, [rsp - 0x1000]
	xor	rstack, rstack
	lea	rwork, [rsp - 0x2000]
	mov	qword ptr [_tib], rwork
	xor	rwork, rwork

	cmp	byte ptr [runmode], RUNMODE_LINUXUSR
	je	2f

	sti

	2:
	push	rpc

# Address Interpreter and Compiler

_exit:
	call	_qcsp
	pop	rpc
_next:
	lodsq
	# Canary does not save from GPF, so let's think...
	#movabs	r11, CANARY
	#cmp	qword ptr [rwork - STATES * 16 - 8], r11
	#jne	_canary_fail
_doxt:
.ifdef TRACE
	jmp	_do_trace
.endif
_notrace:
	jmp	[rwork + rstate * 8 - 16]
_code:
_call:
	push	rnext
	jmp	[rwork + rstate * 8 - 16 + 8]	
_run:
	mov	rstate, INTERPRETING
_forth:
_exec:
	push	rpc
	mov	rpc, [rwork + rstate * 8 - 16 + 8]
	jmp	rnext
_thread:
	push	rpc
	mov	rpc, rtop
	inc	rstack
	mov	rtop, [rstack0 + rstack * 8]
	jmp	rnext
_does:
	mov	qword ptr [rstack0 + rstack * 8], rtop
	dec	rstack
	mov	rtop, rwork
	push	rpc
	mov	rpc, [rwork + rstate * 8 - 16 + 8]
	jmp	rnext
_comp:
	mov	rwork, [rwork + rstate * 8 - 16 + 8]
	stosq
	jmp	rnext
_interp:
	lea	rnext, qword ptr [_next]
	mov	rstate, INTERPRETING
	mov	qword ptr [_state], INTERPRETING
	jmp	rnext

_do_trace:
	cmp	byte ptr [_trace], 0
	jz	99f

	lea	rtmp, [_quit]
	cmp	rpc, rtmp
	jb	3f
	lea	rtmp, [_quit$]
	cmp	rpc, rtmp
	jae	3f
	jmp	99f

	3:
	push	rwork
	call	_dup
	mov	rtop, rstack
	push	rtmp
	push	rwork
	inc	rtop
	neg	rtop
	call	_dot
	pop	rwork
	call	_dup
	mov	rtop, rstate
	push	rwork
	call	_dot
	pop	rwork

	lea	r9, [rsi - 8]

	call	_dup
	mov	rtop, rwork
	push	rwork
	call	_decomp_print
	pop	rwork

	cmp	byte ptr [runmode], RUNMODE_BAREMETAL
	jne	4f
	call	_dup
	mov	rtop, 0x9
	call	_emit
	jmp	5f


	4:
	call	_dup
	mov	rtop, 0x1b
	call	_emit
	call	_dup
	mov	rtop, 0x5b
	call	_emit
	call	_dup
	mov	rtop, 0x33
	call	_emit
	call	_dup
	mov	rtop, 0x39
	call	_emit
	call	_dup
	mov	rtop, 0x47
	call	_emit
	
	5:
	call	_drop
	push	rwork
	call	dot_s
	pop	rwork
	call	_dup
	mov	rtop, 0xa
	call	_emit

	cmp	byte ptr [_debug], 1
	jne	8f

	cmp	qword ptr [_brkpt], 0
	jz	7f
_trace_brkpt:
	cmp	qword ptr [_brkpt], r9
	jne	98f
	mov	qword ptr [_brkpt], 0

	7:
	call    _dup
	mov     rtop, '>'
  	call    _emit	
	push	rwork
	call	key
	pop	rwork
	mov	rtmp, rtop
	call	_drop
	cmp	rtmp, 0xa
	je	7b
	cmp	rtmp, 'c'
	jne	8f
	call	nodebug
	call	notrace
	8:
	cmp	rtmp, 'q'
	je	_abort
	cmp	rtmp, 'n'
	jne	9f

	mov	qword ptr [_brkpt], rsi

	9:

	98:
	pop	rtmp
	pop	rwork
	99:
	jmp	_notrace
	.p2align	3, 0x90
_state:
	.quad	INTERPRETING
_tib:
	.quad	0
_mem_reserved:
	.quad	0	# used to allocate more memory by brk() when ALLOT causes SIGSEGV
_current:
	.quad	0
_context:
	.quad	0
_brkpt:
	.quad	0
_trace:
	.byte	0
_debug:
	.byte	0

	#
	# Message display
	#

.macro	MESSAGE	name, msg, msg1, msg2
.L_\name\()_msg:
	.byte .L_\name\()_msg$ - .L_\name\()_msg - 1
	.ascii "\msg"
	.ascii "\msg1" 
	.ascii "\msg2"
.L_\name\()_msg$:
.endm

_canary_fail:
	# TODO: Nice error message
	lea	rtop, qword ptr [.L_canary_fail_errm1]
	call	_count
	call	_type

.ifdef	DEBUG
	call	_bye
.endif
	jmp	_abort

.L_canary_fail_errm1:
	.byte .L_canary_fail_errm1$ - .L_canary_fail_errm1 - 1
	.ascii	"\r\n\x1b[31mERROR! \x1b[0m\x1b[33m \x1b[1m\x1b[7m Canary DEAD \x1b[0m \r\n"
.L_canary_fail_errm1$:

_state_notimpl:
	push	rstate
	push	rwork

	call	_dup
	lea	rtop, qword ptr [.L_state_notimpl_errm1]
	call	_count
	call	_type
	
	pop	rwork
	
	call	_dup
	mov	rwork, [rwork - STATES * 16 - 24]	/* XT > NFA */
	mov	rtop, rwork
	call	_count
	call	_type

	call	_dup
	lea	rtop, qword ptr [.L_state_notimpl_errm2]
	call	_count
	call	_type

	pop	rstate

	call	_dup
	mov	rtop, rstate
	call	_dot

	call	_dup
	lea	rtop, qword ptr [.L_state_notimpl_errm3]
	call	_count
	call	_type

.ifdef	DEBUG
	call	_bye
.endif
	jmp	_abort

	9:
	ret
.L_state_notimpl_errm1:
	.byte .L_state_notimpl_errm1$ - .L_state_notimpl_errm1 - 1
	.ascii	"\r\n\x1b[31mERROR! \x1b[0m\x1b[33mWord \x1b[1m\x1b[7m "
.L_state_notimpl_errm1$:

.L_state_notimpl_errm2:
	.byte .L_state_notimpl_errm2$ - .L_state_notimpl_errm2 - 1
	.ascii	" \x1b[0m does not implement state \x1b[7m "
.L_state_notimpl_errm2$:

.L_state_notimpl_errm3:
	.byte .L_state_notimpl_errm3$ - .L_state_notimpl_errm3 - 1
	.ascii	"\x1b[0m\r\n"
.L_state_notimpl_errm3$:

#
# SIGSEGV signal handler
#
	.equ	SIGSEGV, 11
	
_sigaction:
	.quad	_sigsegv_handler
	.quad	0x0000000004000004
	.quad	_sigsegv_restorer,   0x0000000000000000
	.quad	0x0000000000000000, 0x0000000000000000
	.quad	0x0000000000000000, 0x0000000000000000
	.quad	0x0000000000000000, 0x0000000000000000
	.quad	0x0000000000000000, 0x0000000000000000
	.quad	0x0000000000000000, 0x0000000000000000
	.quad	0x0000000000000000, 0x0000000000000000
	.quad	0x0000000000000000, 0x0000000000000000
	.quad	0x0000000000000000, 0x0000000000000000

_setup_sigsegv_handler:
	# rax             rdi      rsi                          rdx                     r10
	# 13 rt_sigaction int sig, const struct sigaction *act, struct sigaction *oact, size_t sigsetsize

	lea	rax, [_sigsegv_handler]
	mov	[_sigaction], rax
	mov	rax, 13
	mov	rdi, SIGSEGV
	lea	rsi, [_sigaction]
	xor	rdx, rdx
	mov	r10, 8
	syscall

	ret

_sigsegv_handler:
	# rdi = sig, rsi = siginfo_t , rdx = ucontext_t

	mov	rax, qword ptr [rdx + 40 + 8 * 8]	# RDI, see <sys/ucontext.h>
	cmp	rax, [_mem_reserved]
	jb	5f					# cause of fault is not ALLOT

	#	mmap()
	# 	rdi = unsigned long addr, rsi = unsigned long len, rdx = unsigned long prot, r10 = unsigned long flags, r8 = unsigned long fd, r9 = unsigned long off

_sigsegv_handler_needalloc:
	mov	rdi, rax
	push	rdi
	push	rdx
	test	rdi, 0x0fff
	jz	1f
	and	rdi, 0xfffffffffffff000
	1:
	mov	rsi, rdi
	mov	rdi, [_mem_reserved]
	sub	rsi, rdi
	jnz	3f
	add	rsi, 0x2000
	3:
	mov	rdx, 7					# RWX
	mov	r10, 0x22				# MAP_PRIVATE | MAP_ANONYMOUS
	mov	r8, -1
	mov	r9, 0
	mov	rax, 9					# mmap()
	syscall
	mov	r9, rdi	
	cmp	rax, 0
	pop	rdx
	pop	rdi
	jle	4f					

	add	r9, rsi
	mov	[_mem_reserved], r9			# update reserved memory pointer

.if	0						# might be useful for debugging later, let is stay here for now
	push	rdx
	call	_dup
	lea	rtop, [.L_avail_mem_msg]
	call	_count
	call	_type
	call	_dup
	pop	rdx
	mov	rtop, qword ptr [rdx + 40 + 8 * 16]
	call	_dot
	call	_dup
	mov	rtop, rdi
	call	_dot
	call	_dup
	mov	rtop, [_mem_reserved]
	call	_dot
.endif

	jmp	9f

	4:
	call	_dup
	lea	rtop, qword ptr [.L_out_of_memory_errm1]
	call	_count
	call	_type
	jmp	_bye
	
	5:
	push	rax					# RDI
	mov	rax, qword ptr [rdx + 40 + 8 * 16]	# RIP
	push	rax

	lea	rax, [_cold]
	mov	qword ptr [rdx + 40 + 8 * 16], rax # continue execution from _cold

.if	0
	call	_dup
	lea	rtop, qword ptr [.L_sigsegv_errm1]
	call	_count
	call	_type
.endif

	pop	rtop

.if	0
	call	_dup
	call	_dot
	call	_dup
	pop	rtop
	call	_dot
	call	_dup
	mov	rtop, [_mem_reserved]
	call	_dot
.endif

	9:
	ret

	nop
	.align 16
	.type __rt_restorer, @function
__rt_restorer:	
_sigsegv_restorer:

.if	0
	lea	rtop, qword ptr [.L_sigsegv_errm2]
	call	_count
	call	_type
.endif
	mov	rax, 15	# rt_sigreturn
	syscall

.L_sigsegv_errm1:
	.byte .L_sigsegv_errm1$ - .L_sigsegv_errm1 - 1
	.ascii	"\r\n\x1b[41;30m\x1b[1m\x1b[7m SIGSEGV \x1b[0m\x1b[33m Handler  \x1b[34mIP/HERE/RESERVED = \x1b[0m"
.L_sigsegv_errm1$:
.L_sigsegv_errm2:
	.byte .L_sigsegv_errm2$ - .L_sigsegv_errm2 - 1
	.ascii	"\r\n\x1b[42;30m\x1b[1m\x1b[7m SIGSEGV \x1b[0m\x1b[33m Restorer \x1b[0m"
.L_sigsegv_errm2$:

.L_avail_mem_msg:
	.byte .L_avail_mem_msg$ - .L_avail_mem_msg - 1
	.ascii	"\r\n\x1b[41;30m\x1b[1m\x1b[7m Available \x1b[0m\x1b[33m memory \x1b[34mIP/HERE/RESERVED = \x1b[0m"
.L_avail_mem_msg$:

.L_alloc_mem_msg:
	.byte .L_alloc_mem_msg$ - .L_alloc_mem_msg - 1
	.ascii	"\r\n\x1b[41;30m\x1b[1m\x1b[7m Allocated \x1b[0m\x1b[33m memory \x1b[34mIP/HERE/RESERVED = \x1b[0m"
.L_alloc_mem_msg$:

.L_out_of_memory_errm1:
	.byte .L_out_of_memory_errm1$ - .L_out_of_memory_errm1 - 1
	.ascii	"\r\n\x1b[41;30m\x1b[1m\x1b[7m Out of memory \x1b[0m\x1b[33m Aborting \x1b[0m"
.L_out_of_memory_errm1$:
#
# Word definition
#
	latest_word	= 0

.macro	reserve_cfa does, reserve=(STATES - 3)
	# Execution semantics can be either code or Forth word

	# Compilation semantics inside Forth words is the same: compile adress of XT
	# Semantics for other states does nothing by default
	.rept \reserve
	.quad	_state_notimpl, 0
	.endr
.endm

.macro	word	name, fname, immediate, does=code, param, decomp, decomp_param, regalloc, regalloc_param
	.endfunc
	.align	16
.L\name\()_str0:
	.byte	.L\name\()_strend - .L\name\()_str
.L\name\()_str:
.ifc "\fname",""
	.ascii	"\name"
.else
	.ascii	"\fname"
.endif
.L\name\()_strend:
	.p2align	4, 0x00
	.quad	.L\name\()_str0	/* NFA */
	.quad	latest_word	/* LFA */
	.quad	CANARY	


	reserve_cfa

	# DECOMPILING
.ifc "\decomp", ""
	.ifc "\does", "forth"
		.quad	_decomp
		.quad	0
	.else
		.quad	_decomp_code
		.quad	0
	.endif
.else
	.quad	\decomp
	.quad	\decomp_param
.endif

	# COMPILING
.ifc	"\immediate", "immediate"
	.ifc "\does", "forth"
		.quad	_run
	.else
		.quad	_\does
	.endif
	.ifc	"\param",""
		.quad	\name
	.else
		.quad	\param
	.endif
.else
	.quad	_comp
	.ifc	"\param",""
		.quad	\name
	.else
		.quad	\param
	.endif
.endif

	# INTERPRETING
	.quad	_\does
.ifc	"\param",""
	.quad	\name
.else
	.quad	\param
.endif
	# TODO: Add a "canary"/hash to make sure an XT is actually an XT
.func	name
\name\():
	latest_word = .
	latest_name = _\name
.endm

# Words
.p2align	4, 0x90

.func	words

# FORTH
# The root vocabulary
word	forth_, "forth", immediate, code, _forth_
	.quad	last
_forth_:
	mov	[_context], rwork
	ret

# DUMMY
# For breakpoints
word	dummy
_dummy:
	ret

# CURRENT ( -- v )
# Returns current vocabulary
word	current
	call	_dup
	lea	rtop, [_current]
	ret

# CONTEXT ( -- v )
# Returns context vocabulary
word	context
	call	_dup
	lea	rtop, [_context]
	ret

# LATEST ( -- xt )
# Returns XT of the latest defined word in current vocabulary
word	latest
	call	current
	mov	rtop, [rtop]
	mov	rtop, [rtop]
	ret

# TRACE
# Turn tracing on
word	trace
	mov	byte ptr [_trace], 1
	ret

# NOTRACE
word	notrace
	mov	byte ptr [_trace], 0
	ret

# DEBUG
# Turn debugging on. Works when TRACE ON
word	debug
	mov	byte ptr [_debug], 1
	ret

# BRKPT ( pc -- )
# Set breakpoint in threaded code for debugging
word	brkpt
	mov	qword ptr [_brkpt], rtop
	call	_drop
	ret

# NODEBUG
word	nodebug
	mov	byte ptr [_debug], 0
	mov	qword ptr [_brkpt], 0
	ret

# EXECUTE ( xt -- )
# Executes word, specified by XT
word	execute
	mov	rwork, rtop
	call	_drop
	pop	rtmp	# Skip return address (=NEXT)

	mov	rstate, [_state]

	jmp	_doxt

# THREAD ( pc -- )
# Executes Forth word thread, specified by thread address. EXIT returns
word	thread,,, thread, thread
	jmp	_thread


# EXIT
# Exit current Forth word and return the the caller
word	exit,,, exit, exit, _decomp_exit, 0, _exit_regalloc, 0
_exit_regalloc:
	jmp	_exit

# SUMMON
# Summons Forth word from assembly
word	summon
_summon:
	push	rpc
	lea	rpc, qword ptr [forsake]
	jmp	_doxt

# RETREAT
# Retreats from Forth back into assembly
word	retreat
_retreat:
	pop	rtmp
	pop	rpc
	ret

# FORSAKE
# Forsakes Forth for assembly
word	forsake
	.quad	retreat
	.quad	exit

# DUP ( a -- a a )
word	dup
_dup:
	mov	[rstack0 + rstack * 8], rtop
	dec	rstack
	ret

# DROP ( a -- )
word	drop
_drop:
	inc	rstack
	mov	rtop, [rstack0 + rstack * 8]
	ret

# PICK ( # -- a )
word	pick
	add	rtop, rstack
	inc	rtop
	mov	rtop, [rstack0 + rtop * 8]
	ret

# LIT ( -- n )
# Pushes compiled literal onto data stack
word	lit,,,,, _lit_decomp, 0
_lit:
	call	_dup
	lodsq
	mov	rtop, rax
	ret
_lit_decomp:
	mov	rtop, rwork
	call	_decomp_print

	call	_dup
	mov	rtop, 0x9
	call	_emit

	lodsq
	call	_dup
	mov	rtop, rwork
	call	_dot

	call	_dup
	mov	rtop, 0xa
	call	_emit
	jmp	rnext

# LITERAL ( n -- ) IMMEDIATE
# Compiles a literal
word	literal,, immediate, forth
_literal:
	.quad	compile, lit
	.quad	comma
	.quad	exit

# BRANCH ( -- )
# Changes PC by compiled offset (in cells)
word	branch,,,,, _branch_decomp, 0
_branch:
	lodsq
	lea	rpc, [rpc + rwork * 8]
	ret
_branch_decomp:
	call	_dup
	mov	rtop, rwork
	call	_decomp_print
	call	_dup
	mov	rtop, 0x9
	call	_emit

	lodsq
	mov	rtmp, rpc
	sal	rwork, 3
	add	rtmp, rwork
	call	_dup
	mov	rtop, rtmp
	call	_dot
	mov	rtop, 0xa
	call	_emit
	jmp	rnext

# ?BRANCH ( f -- )
# Changes PC by compiled offset (in cells) if top element is zero
word	qbranch, "?branch",,,, _branch_decomp, 0
_qbranch:
	lodsq
	test	rtop, rtop
	jnz	9f

	lea	rpc, [rpc + rwork * 8]

	9:
	call	_drop
	ret

# -?BRANCH ( f -- )
# Changes PC by compiled offset (in cells) if top element is not zero
word	mqbranch, "-?branch",,,, _branch_decomp, 0
_mqbranch:
	lodsq
	test	rtop, rtop
	jz	9f

	lea	rpc, [rpc + rwork * 8]

	9:
	call	_drop
	ret

# COMPILE ( -- )
# Compiles the next address in the threaded code into current definition
word	compile
_compile:
	lodsq
	stosq
	ret

# ALIGN
# Aligns HERE to 16-byte boundary
word	align
_align:
	add	rhere, 0xf
	and	rhere, -16
	ret

# CMOVE ( as ad n -- )
# Move N bytes from as to ad
word	cmove
	push	rsi
	push	rdi
	mov	rtmp, rtop
	call	_drop
	mov	rdi, rtop
	call	_drop
	mov	rsi, rtop
	mov	rcx, rtmp
	rep	movsb

	call	_drop
	pop	rdi
	pop	rsi
	ret

# (") ( -- a )
# Returns address of a compiled string
word	_quot_, "(\")",,,, _quot__decomp, 0
	lodsb
	movzx	rax, al
	call	_dup
	mov	rtop, rpc
	dec	rtop
	add	rpc, rax
	add	rpc, 0xf
	and	rpc, -16
	ret	
_quot__decomp:

	mov	rtop, rwork
	call	_decomp_print

	
	call	_dup
	mov	rtop, 0x9
	call	_emit
	call	_dup
	mov	rtop, 0x9
	call	_emit
		
	call	_dup
	mov	rtop, rpc
	call	_count
	call	_type
	
	lodsb
	movzx	rax, al
	add	rpc, rax
	add	rpc, 0xf
	and	rpc, -16

	call	_dup
	mov	rtop, 0xa
	call	_emit

	jmp	rnext
	

# " ( "ccc" -- )
# Compiles a string
word	quot, "\"", immediate
	lea	rwork, qword ptr [_quot_]	/* compile (") */
	stosq

	call	_dup
	mov	rtop, 0x22
	call	_word
	call	_count
	mov	rtmp, rtop
	inc	rtmp
	push	rtmp
	call	_drop
	dec	rtop
	call	_dup
	mov	rtop, rhere
	call	_dup
	mov	rtop, rtmp
	call	cmove
	pop	rtmp
	add	rhere, rtmp
	call	_align
	ret

# EMIT ( c -- )
# Prints a character to stdout
word	emit
_emit:
	cmp	byte ptr [runmode], RUNMODE_BAREMETAL
	je	_emit_baremetal

	push	rtop
	push	rwork
	push	rdx
	push	rsi
	push	rdi
	
	mov	rwork, rtop
	push	rax
	mov	rdx, 0x1	# count
	mov	rsi, rsp	# buffer
	mov 	rdi, 0x1	# stdout
	mov	rax, 0x1	# sys_write
	syscall
	pop	rwork
	pop	rdi
	pop	rsi
	pop	rdx
	pop	rwork
	pop	rtop
	
	call	_drop

	ret

_emit_baremetal:
	push	rtop
	push	rwork
	push	rdx
	push	rsi
	push	rdi
	
	mov	rwork, rtop

	call	[__emitchar]
	
	pop	rdi
	pop	rsi
	pop	rdx
	pop	rwork
	pop	rtop
	
	call	_drop

	ret

# READ ( -- c )
# Reads a character from stdin

_source_completed:
	.byte	0
_source_in:
	.quad	_source

word	read
_read:
	call	_dup

	cmp	byte ptr [_source], 0
	jz	7f
	cmp	byte ptr [_source_completed], 0
	jnz	7f

	mov	rax, [_source_in]
	inc	qword ptr [_source_in]
	movzx	rtop, byte ptr [rax]
	
	or	rtop, rtop
	jnz	5f

	mov	byte ptr [_source_completed], 1
	jmp	7f

	5:
	ret

	7:
	cmp	byte ptr [runmode], RUNMODE_BAREMETAL
	je	_read_baremetal

_read_key:
	push	rsi
	push	rdi

	xor	rwork, rwork
	push	rwork
	mov	rdx, 0x1	# count
	mov	rsi, rsp	# buffer
	mov 	rdi, 0x0	# stdin
	mov	rax, 0x0	# sys_read
	syscall
	pop	rtop
	cmp	rtop, 0x0	# ^D
	jne	9f
	jmp	_bye

	9:
	pop	rdi
	pop	rsi
	ret

_read_baremetal:
	call	_key_baremetal
	#call	_dup
	#call	_emit
	ret

# KEY ( -- c )
# Reads one character from input
word	key
	call	_dup
	cmp	byte ptr [runmode], RUNMODE_BAREMETAL
	je	_key_baremetal

	call	_read_key
	ret

_key_baremetal:
	push	rbx
	push	rsi
	push	rdi

	call	[__key]
	mov	rtop, rax

	pop	rdi
	pop	rsi
	pop	rbx

	ret

# TYPE ( c-addr u -- )
# Print string to stdout
word	type
_type:
	cmp	byte ptr [runmode], RUNMODE_BAREMETAL
	je	_type_baremetal

	push	rsi
	push	rdi

	mov	rtmp, rtop	# count
	call	_drop
	mov	rsi, rtop
	mov	rax, 0x1
	mov	rdi, 0x1
	syscall

	pop	rdi
	pop	rsi
	
	call	_drop

	ret

_type_baremetal:
	push	rsi
	push	rdi

	mov	rtmp, rtop	# count
	call	_drop
	or	rtmp, rtmp
	jz 	8f
	mov	rsi, rtop
	
	1:
	lodsb
	call	_dup
	movzx	rtop, al
	call	_emit
	dec	rtmp
	jnz	1b
	

	pop	rdi
	pop	rsi
	
	8:
	call	_drop

	ret

# WORDS
# Prints all defined words to stdout
word	words
_words:
	call	context
	mov	rtop, [rtop]
	mov	rtop, [rtop]
	call	_words_

	call	current
	mov	rtop, [rtop]
	cmp	rtop, [_context]
	je	2f
	mov	rtop, [rtop]
	call	_dup
	mov	rtop, 0xa
	call	_emit
	call	_words_
	jmp	3f
	2:
	call	_drop
	3:
	call	_dup
	lea	rtop, [forth_]
	cmp	rtop, [_context]
	je	4f
	cmp	rtop, [_current]
	je	4f
	mov	rtop, [rtop]
	call	_dup
	mov	rtop, 0xa
	call	_emit
	call	_words_
	jmp	5f
	4:
	call	_drop
	5:
	ret

_words_:
	push	rtop
	push	rsi
	push	rdi

	mov	rtmp, rtop
	call	_drop

	7:
	test	rtmp, rtmp
	jz	9f

	push	rtmp					# current word

	mov	rwork, [rtmp - STATES * 16 - 24]	# NFA

	call	_dup
	mov	rtop, rwork

	call	_count
	call	_type

	/*
	mov	rdi, 1					# stdout
	mov	rax, 1					# sys_write
	syscall
	*/

	call	_dup
	mov	rtop, 0x20
	call	_emit

	pop	rtmp
	mov	rtmp, [rtmp - STATES * 16 - 16]		# LFA
	jmp	7b

	9:
	pop	rdi
	pop	rsi
	pop	rtop

	call	_dup
	mov	rtop, 0xa
	call	_emit
	ret

# STATE! ( state -- )
# Sets address interpreter state for the next word from the text interpreter
word	state_, "state!"
	mov	rwork, rtop
	call	_drop
	mov	qword ptr [_state], rwork
	ret

# STATE!! ( state -- )
# Sets address interpreter state for the next word from the address interpterer
word	state__, "state!!"
	mov	rwork, rtop
	call	_drop
	mov	rstate, rwork
	ret

# SEE ( -- )
# Sets STATE to DECOMPILING
word	see
_see:
	mov	qword ptr [_state], DECOMPILING
	ret

# DECOMP ( -- )
# Decompile XT being currently interpreted
_decomp_code:
	cmp	qword ptr [_decompiling], 1
	je	1f
	call	_dup
	mov	rtop, rwork
	call	_decomp_print
	mov	rtop, 0xa
	call	_emit
	call	_bracket_open
	call	_interpreting_
	jmp	rnext
_decomp:
	cmp	qword ptr [_decompiling], 1
	je	1f
_decomp1:
	push	rpc
	mov	rpc, rwork
	mov	qword ptr [_decompiling], 1
	jmp	7f
	1:
	call	_dup
	mov	rtop, rwork
	call	_decomp_print
	call	_dup
	mov	rtop, 0xa
	call	_emit
	7:
	call	_drop
	jmp	rnext
_decomp_exit:
	mov	qword ptr [_decompiling], 0
	call	_bracket_open
	call	_interpreting_
	call	_dup
	mov	rtop, rwork
	call	_decomp_print
	call	_dup
	mov	rtop, 0xa
	call	_emit
	pop	rpc
	jmp	rnext
_decomp_print:
	call	_dup
	mov	rtop, rpc
	sub	rtop, 8
	call	_dot
	call	_dup
	call	_dot
	call	_dup
	mov	rcx, 0x9
	call	_emit
	call	_dup
	mov	rtop, [rtop - STATES * 16 - 24]	# NFA
	call	_count
	call	_type
	ret
_decompiling:	.quad	0

# BL ( -- c )
# Returns blank character code
word	bl_, "bl"
_bl_:
	call	_dup
	mov	rtop, 0x20
	ret

# ALLOT ( n -- )
# Reserves n bytes in data space
word	allot
	add	rhere, rtop
	call	_drop
	ret

# @ ( a -- n )
# FETCH
word	fetch, "@"
	mov	rtop, [rtop]
	ret

# ! ( n a -- )
# STORE
word	store, "\!"
	mov	rtmp, rtop
	call	_drop
	mov	[rtmp], rtop
	call	_drop
	ret

# , ( v -- )
# Reserve space for one cell in the data space and store value in the pace
word	comma, ","
_comma:
	mov	rax, rtop
	stosq
	call	_drop
	ret

# 4, ( v -- )
# Reserve space for 4 bytes in the data space and store value in the pace
word	four_comma, "4,"
_four_comma:
	mov	rax, rtop
	stosd
	call	_drop
	ret

# 2, ( v -- )
# Reserve space for 2 bytes in the data space and store value in the pace
word	two_comma, "2,"
_two_comma:
	mov	rax, rtop
	stosw
	call	_drop
	ret

# C, ( c -- )
# Reserve space for one character in the data space and store char in the space
word	c_comma, "c,"
_c_comma:
	mov	rax, rtop
	stosb
	call	_drop
	ret

# COUNT ( c-addr -- c-addr' u )
# Converts address to byte-counted string into string address and count
word	count
_count:
	mov	rwork, rtop
	inc	rtop
	call	_dup
	movzx	rtop, byte ptr [rwork]
	ret

# WORD ( c "<chars>ccc<char>" -- c-addr )
# Reads char-separated word from stdin, places it as a byte-counted string at TIB
# TODO: BUG: If \ is the last character on the line (just before 0a), the next line is skipped (?)
word	word,,, code, _word
_word:
	mov	rtmp, qword ptr [_tib]
	push	rbx

	mov	rbx, rtop
	call	_drop

	push	rdi
	mov	rdi, rtmp
	mov	rtmp, 0
	xor	al, al
	stosb

	call	_dup
	1:
	call	_drop
	push	rtmp
	call	_read
.ifdef	DEBUG
	call	_dup
	call	_emit
.endif
	pop	rtmp
	cmp	rtop, rbx
	je	1b
	cmp	rtop, 0xd
	je	1b
	cmp	rtop, 0xa
	je	7f
	cmp	rtop, 0x9
	je	2f
	cmp	rtop, 127
	je	1b
	jmp	5f
	

	2:
	cmp	rbx, 0x20
	je	1b
	jmp	5f

	3:
	push	rtmp
	call	_read
.ifdef	DEBUG
	cmp	rcx, 127
	je	31f
	call	_dup
	call	_emit
	31:
.endif
	pop	rtmp
	cmp	rtop, rbx
	je	7f
	cmp	rtop, 0xd
	je	6f
	cmp	rtop, 0xa
	je	7f
	cmp	rtop, 0x9
	je	4f
	cmp	rtop, 127
	jne	5f
	or	rtmp, rtmp
	jz	6f
	dec	rdi
	dec	rtmp
	jmp	6f

	4:
	cmp	rbx, 0x20
	je	7f

	5:
	mov	rax, rtop
	stosb
	inc	rtmp
	6:
	call	_drop
	jmp	3b

	7:
_backspace:	
	mov	rcx, rdi
	and	rcx, 0x7	# zero fill rest of tib till mod 8
	jz	9f
	sub	rcx, 8
	neg	rcx
	xor	al, al
	8:
	stosb
	dec	rcx
	jnz	8b

	9:
	pop	rdi

	mov	al, dl
	mov	rtmp, qword ptr [_tib]
	push	rtmp
	mov	byte ptr [rtmp], al

	pop	rtop

	pop	rbx
	ret

# CFA-ALLOT ( -- )
# Creates a default multi-CFA section at HERE
word	cfa_allot, "cfa-allot"
_cfa_allot:
	mov	rcx, 16
	lea	rtmp, qword ptr [_state_notimpl]
	mov	rwork, 0

	1:
	mov	qword ptr [rhere], rtmp
	add	rhere, 8
	mov	qword ptr [rhere], rwork
	add	rhere, 8
	dec	rcx
	jnz	1b

	ret

# HEADER ( "<name>" -- ) : ( -- )
# Reads word name from input stream and creates a default header for the new word. The new word does nothing
word	header
_header:
	call	_bl_		# ( bl )
	call	_word		# ( tib ) 
	call	_dup		# ( tib tib )
	call	_count		# ( tib tib+1 count ) 
	test	rtop, rtop
	jz	6f

	push	rsi
	mov	rtmp, rtop	# count
	inc	rtmp
	mov	rsi, qword ptr [_tib]

	call	_drop
	call	_drop
	mov	rcx, rtmp
	call	_align
	mov	rwork, rhere
	rep	movsb		# copy name from TIB to HERE

	pop	rsi

	add	rhere, rtmp
	call	_align

	call	latest
	mov	rtmp, rtop
	call	_drop

	mov	qword ptr [rhere], rwork	# NFA
	add	rhere, 8
	mov	qword ptr [rhere], rtmp		# LFA
	add	rhere, 8
	movabs	rtmp, CANARY
	mov	qword ptr [rhere], rtmp		# canary
	add	rhere, 8

	call	_cfa_allot
	call	_drop

	call	current
	mov	rtop, [rtop]
	mov	[rtop], rhere	# XT
	call	_drop

	jmp	9f

	6:
	lea	rtop, qword ptr [.L_header_errm]
	call	_count
	call	_type
.ifdef	DEBUG
	call	_bye
.endif
	jmp	_abort

	call	_drop
	call	_drop

	9:
	ret

.L_header_errm:
	.byte .L_header_errm$ - .L_header_errm - 1
	.ascii	"\r\n\x1b[31mERROR! \x1b[0m\x1b[7m\x1b[1m\x1b[33m Refusing to create word header with empty name \x1b[0m\r\n"
.L_header_errm$:

# HERE ( -- a )
# Returns address of the first available byte of the code space
word	here
_here:
	call	_dup
	mov	rtop, rhere
	ret

# [ ( -- ) IMMEDIATE
# Switches text interpreter STATE to INTERPRETING
word	bracket_open, "[", immediate
_bracket_open:
	mov	qword ptr [_state], INTERPRETING
	ret

# ] ( -- )
# Switches text interpterer STATE to COMPILING
word	bracket_close, "]"
_bracket_close:
	mov	qword ptr [_state], COMPILING
	ret

# (INTERPRETING) IMMEDIATE
# Switches address interpreter state to INTERPRETING
word	interpreting_, "(interpreting)", immediate,,,,, _code, _interpreting_
_interpreting_:
	mov	rstate, INTERPRETING
	ret

# INTERPRETING!
# Switches address interpreter state to INTERPRETING
word	interpreting__, "interpreting!",,,,,, _code, _interpreting__
_interpreting__:
	mov	rstate, INTERPRETING
	ret

# DOES ( param code state xt -- )
# Sets semantics for a word defined by XT for given state to a given code:param pair
word	does
_does1:
	mov	rwork, rtop
	call	_drop
	mov	rtmp, rtop
	call	_drop

	mov	qword ptr [rwork + rtmp * 8 - 16], rtop
	call	_drop
	mov	qword ptr [rwork + rtmp * 8 - 16 + 8], rtop
	call	_drop

	ret

# IMMEDIATE ( -- )
# Sets latest word's compilation semantics to execution semantics
word	immediate
_immediate:
	call	latest
	mov	rwork, rtop
	call	_drop

	lea	rtmp, _run
	mov	[rwork + COMPILING * 8 - 16], rtmp
	mov	rtmp, [rwork + INTERPRETING * 8 - 16 + 8]
	mov	[rwork + COMPILING * 8 - 16 + 8], rtmp
	ret

# CODEWORD ( xt -- )
# Specifies execution semantics for a word specified by XT as a code word
word	codeword, "code",, forth
_codeword:
	.quad	here
	.quad	lit, _code
	.quad	lit, INTERPRETING
	.quad	latest
	.quad	does

	.quad	here
	.quad	lit, _comp
	.quad	lit, COMPILING
	.quad	latest
	.quad	does

	.quad	lit, 0
	.quad	lit, _decomp_code
	.quad	lit, DECOMPILING
	.quad	latest
	.quad	does

	.quad	exit

# FORTHWORD ( xt -- )
# Specifies execution semantics for a word specified by XT as a forth word with threaded code following at HERE
word	forthword, "fun",, forth
_forthword:
	.quad	here
	.quad	lit, _exec
	.quad	lit, INTERPRETING
	.quad	latest
	.quad	does

	.quad	here
	.quad	lit, _comp
	.quad	lit, COMPILING
	.quad	latest
	.quad	does

	.quad	lit, 0
	.quad	lit, _decomp
	.quad	lit, DECOMPILING
	.quad	latest
	.quad	does

	.quad	exit

# (CREATE) ( -- xt )
# Pushes XT of the word being executed into stack
word	_create_, "(create)"
__create_:
	call	_dup
	mov	rtop, rwork
	jmp	rnext

# CREATE ( "<name> -- ) ( -- xt )
# Creates a new definition, which pushes XT in the stack
word	create,,, forth
_create:
	.quad	header

	.quad	here
	.quad	lit, __create_
	.quad	lit, INTERPRETING
	.quad	latest
	.quad	does

	.quad	here
	.quad	lit, _comp
	.quad	lit, COMPILING
	.quad	latest
	.quad	does

	.quad	lit, 0
	.quad	lit, _decomp
	.quad	lit, DECOMPILING
	.quad	latest
	.quad	does

	.quad	exit

# :: ( "<name>" -- )
# Synonym for CREATE
word	coloncolon, "::",, forth
_coloncolon:
	.quad	create
	.quad	exit

# (DOES>XT)
# Internal word that fixes HERE address, depends on DOES> implementation
word	_does_xt_, "(does>xt)"
__does_xt_:
	add	rtop, 3 * 8
	ret

# (DOES) ( -- _does )
# Returns address of the _does primitive entry point
word	_does_, "(does)",, forth
	.quad	lit, _does
	.quad	exit

# (EXEC) ( -- _exec )
# Returns address of the _exec primitive entry point
word	_exec_, "(exec)",, forth
	.quad	lit, _exec
	.quad	exit

# (RESTART) ( -- _restart ) 
# Returns address of the _restart primitive entry point
word	_restart_, "(restart)",, forth
	.quad	lit, _restart
	.quad	exit

# (ABORT) ( -- _abort ) 
# Returns address of the _abort primitive entry point
word	_abort_, "(abort)",, forth
	.quad	lit, _abort
	.quad	exit

# (DOES>) ( xt -- )
# Defines execution and compilation semantics for the latest word
word	_does__, "(does>)",, forth
__does_:
	.quad	_does_xt_

	.quad	_does_
	.quad	lit, INTERPRETING
	.quad	latest
	.quad	does

	.quad	latest
	.quad	lit, _comp
	.quad	lit, COMPILING
	.quad	latest
	.quad	does

	.quad	exit

# DOES> ( -- ) IMMEDIATE
# Defines defining word
word	does_, "does>", immediate, forth
_does1_:
	.quad	compile, lit
	.quad	here, comma
	.quad	compile, _does__
	.quad	compile, exit
	.quad	exit

# : ( "<name>" -- )
# Creates a Forth word
word	colon, ":",, forth
_colon:
	.quad	header
	.quad	forthword
	.quad	bracket_close
	.quad	exit

# ; ( -- ) IMMEDIATE
# Finished Forth definition
word	semicolon, "\x3b", immediate, forth
_semicolon:
	.quad	compile, exit
	.quad	bracket_open
	.quad	exit

# FIND ( -- xt | 0 )
# Searches for word name, placed at TIB, in the vocabularies CONTEXT, CURRENT and FORTH
word	find
_find:
	call	_dup
	mov	rtop, [_context]
	call	_find_
	test	rtop, rtop
	jnz	3f

	mov	rtop, [_current]
	cmp	rtop, [_context]
	je	1f
	call	_find_
	test	rtop, rtop
	jnz	3f

	1:
	lea	rtop, [forth_]
	cmp	rtop, [_current]
	je	2f
	cmp	rtop, [_context]
	je	2f
	call	_find_
	test	rtop, rtop
	jnz	3f

	2:
	xor	rtop, rtop

	3:
	ret

_find_:
	push	rsi
	push	rdi
	push	rbx

	mov	rtmp, [rtop]

	mov	rbx, qword ptr [_tib]

	5:
	test	rtmp, rtmp
	jz	6f

	mov	rsi, rbx

	mov	rwork, [rtmp - STATES * 16 - 24]	# NFA
	movzx	rcx, byte ptr [rwork]
	inc	rcx
	mov	rdi, rwork
	rep	cmpsb
	mov	rtop, rtmp
	je	9f

	mov	rtmp, [rtmp - STATES * 16 - 16]		# LFA
	
	jmp	5b

	6:
	mov	rtop, 0

	9:
	pop	rbx
	pop	rdi
	pop	rsi
	ret

# TODO: BUG: Input -?branch causes stack underflow
# TODO: BUG: Minus can be at the end of a number, or in the middle of a number, and it is ok
# NUMBER ( c-addr -- n -1 | 0 )
# Parses string as a number (in HEX base)
word	number
_number:
	push	rsi
	push	rdi
	push	rbx
	xor	rbx, rbx	# Positive number, hex
	mov	rsi, rtop
	movzx	rcx, byte ptr [rtop]
	test	rcx, rcx
	jz	8f

	xor	rtmp, rtmp
	xor	rwork, rwork
	inc	rsi
	1:
	lodsb
	cmp	bl, 1
	je	2f
	cmp	al, '-'
	jne	2f
	test	rtmp, rtmp
	jnz	8f	# cannot be in the middle
	or	bl, 1
	jmp	5f
	2:
	cmp	al, '_'
	je	5f
	cmp	al, '\''
	je	5f
	cmp	al, '#'
	jne	21f
	test	rtmp, rtmp
	jnz	8f	# cannot be in the middle
	or	bl, 2	# decimal number
	jmp	5f
	21:
	cmp	al, 0x30
	jb	8f
	cmp	al, 0x39
	jbe	3f
	test	bl, 2
	jnz	8f
	or	al, 0x20
	cmp	al, 0x61
	jb	8f
	cmp	al, 0x66
	ja	8f
	sub	al, 0x61 - 10
	jmp	4f
	3:
	sub	al, 0x30
	4:
	test	bl, 2
	jz	416f
	410:
	mov	rdi, rtmp
	add	rdi, rdi	# *2
	add	rdi, rdi	# *4
	add	rdi, rtmp 	# *5
	add	rdi, rdi	# *10
	add	rdi, rwork
	mov	rtmp, rdi
	jmp	5f
	416:
	shl	rtmp, 4
	add	rtmp, rwork
	5:
	dec	rcx
	jnz	1b

	mov	rtop, rtmp
	test	bl, 1
	jz	7f
	or	rtop, rtop	# Single "-", "-0", "-0[0...]" is considered an errorneous input
	jz	8f
	neg	rtop
	7:
	call	_dup
	mov	rtop, -1
	jmp	9f

	8:
	mov	rtop, 0
	jmp	9f

	9:
	pop	rbx
	pop	rdi
	pop	rsi
	ret

# . ( n -- )
# Print number on the top of the stack (hexadecimal)
word	dot, "."
_dot:
	mov	rtmp, 16

	cmp	rtop, 0
	jge	1f
	cmp	rtop, -127
	jl	1f

	neg	rtop
	call	_dup
	mov	rtop, 0x2d
	call	_emit

	1:
	rol	rtop, 4
	test	rtop, 0xf
	jnz	3f
	dec	rtmp
	jnz	1b

	mov	rtop, 0x30
	call	_emit
	jmp	9f

	3:
	mov	al, cl
	and	al, 0xf
	cmp	al, 0x9
	jbe	4f
	add	al, 0x61 - 0x30 - 0xa
	4:
	add	al, 0x30
	push	rtop
	push	rwork
	call	_dup
	movzx	rtop, al
	call	_emit
	pop	rwork
	pop	rtop
	rol	rtop, 4
	dec	rtmp
	jnz	3b
	call	_drop

	9:
	call	_bl_
	call	_emit
	ret

# .0 ( n -- )
# Prints number with a leading '0', if it's < 10h (for dump)
word	dot0, ".0"
	cmp	rtop, 0x10
	jnb	3f
	
	call	_dup
	mov	rtop, 0x30
	call	_emit

	3:
	call	_dot
	ret

# .S ( -- )
# Prints stacks
word	dot_s, ".S"
	call	_qcsp

	call	_dup
	mov	rtop, 0x53
	call	emit
	call	_dup
	mov	rtop, 0x3a
	call	emit
	call	_dup
	mov	rtop, 0x20
	call	emit

	test	rstack, rstack
	jz	5f
	mov	rwork, 0
	1:
	dec	rwork
	cmp	rwork, rstack
	je	3f
	call	_dup
	mov	rtop, [rstack0 + rwork * 8]
	push	rwork
	call	dot
	pop	rwork
	jmp	1b
	3:
	test	rstack, rstack
	jz	5f
	call	_dup
	call	dot

	5:
	ret

# (QUIT) ( -- )
# Read one word from input stream and interpret it
word	quit_, "(quit)"
_quit_:
	call	_bl_
	call	_word
	call	_count
	or	rtop, rtop
	jz	7f
	call	_drop
	call	_drop

	call	_find
	test	rtop, rtop
	jz	2f

	mov	rwork, rtop
	call	_drop

	mov	rstate, qword ptr [_state]

	pop	rtmp
	jmp	_doxt

	2:
	mov	rtop, qword ptr [_tib]
__number:
	call	_number
	test	rtop, rtop
	jz	6f

	call	_drop
	# TODO: Explicit STATE check in NUMBER, move to compilation CFA
	cmp	qword ptr [_state], COMPILING
	jne	9f

	lea	rax, qword ptr [lit]
	stosq
	mov	rax, rcx
	stosq
	call	_drop

	jmp	9f

	6:
	lea	rtop, qword ptr [.L_quiterr1_msg]
	call	_count
	call	_type
	call	_dup
	mov	rtop, qword ptr [_tib]
	call	_count
	call	_type
	call	_dup
	lea	rtop, qword ptr [.L_quiterr2_msg]
	call	_count
	call	_type
.ifdef	DEBUG
	call	_bye
.endif
	jmp	_abort

	7:
	call	_drop
	call	_drop

	9:
	ret
.ifndef BAREMETAL
	MESSAGE	quiterr1, "\r\n\x1b[31mERROR! \x1b[0m\x1b[33mWord \x1b[1m\x1b[7m "
	MESSAGE	quiterr2, " \x1b[27m\x1b[22m not found, or invalid number\x1b[0m\r\n"
.else
	MESSAGE	quiterr1, "\nERROR! Word ["
	MESSAGE	quiterr2, "] not found, or invalid number\n"
.endif

# QUIT
# Interpret loop
word	quit,,, forth
_quit:
	.quad	quit_
	.quad	interpreting_
	.quad	qcsp
	.quad	branch, -5
	.quad	exit	# Needed here only for decompilation
_quit$:

# ?CSP ( -- )
# Aborts on stack underflow
word	qcsp, "?csp"
_qcsp:
	cmp	rstack, 0
	jnle	6f
	jmp	9f

	6:
	lea	rtop, qword ptr [.L_qcsperr_msg]
	call	_count
	call	_type
.ifdef	DEBUG
	call	_bye
.endif
_qcsp_abort:
	jmp	_abort

	9:
	ret
.ifndef	BAREMETAL
MESSAGE	qcsperr, "\r\n\r\n\x1b[31mERROR! \x1b[33m\x1b[7m Stack underflow \x1b[0m\r\n"
.else
MESSAGE qcsperr, "\nERROR! \x01\x20 Stack underflow \x01\x02"
.endif
.L_qcsp_errm:
	.byte .L_qcsp_errm$ - .L_qcsp_errm - 1
	.ascii	"\r\n\r\n\x1b[31mERROR! \x1b[33m\x1b[7m Stack underflow \x1b[0m\r\n"
.L_qcsp_errm$:

# .\ ( "ccc<EOL>" -- )
# Prints string till the end of line
word	dot_comment, ".\\"
_dot_comment:
	call	_dup
	mov	rtop, 0
	call	_word
	call	_count
	call	type
	ret

# DUMP ( a u -- )
# Prints hexadecimal bytes at address
word	dump
_dump:
	mov	rtmp, rtop	# count
	call	_drop
	mov	rwork, rtop	# address

	1:
	test	rtmp, rtmp
	jz	9f

	call	_dup
	movzx	rtop, byte ptr [rwork]
	push	rwork
	push	rtmp
	call	dot0
	pop	rtmp
	pop	rwork
	dec	rtmp
	inc	rwork
	jmp	1b

	9:
	call	_drop
	ret

# BYE
# Returns to OS
word	bye
_bye:

	cmp	byte ptr [runmode], RUNMODE_BAREMETAL
	je	_bye_baremetal
	
	mov	rdi, rtop
	mov	rax, 60
	syscall

_bye_baremetal:
	mov	byte ptr [_source_completed], 1

	lea	rax, [_source]
	mov	[_source_in], rax

	jmp	_abort

# ABORT
# Reinitializes the system, or quits to OS in debug build
word	abort
_abort1:
.ifdef	DEBUG
	jmp	bye
.else
	jmp	_abort
.endif

# DARK LORD
# Dark Lord to be summoned
word	darklord,,, forth
	.quad	lit, 42
	.quad	dup
	.quad	emit, emit
	.quad	exit

# SUMMONER
# Dark Lord, I summon Thee!
word	summoner
_summoner:
	lea	rwork, qword ptr [darklord]
	call	summon
	call	_dup
	mov	rtop, 43
	call	_emit
	ret

# COLD
# Cold start
word	cold
	jmp	_abort

# WARM ( xt -- )
# Sets restart point to XT
word	warm
	mov	[__warm], rtop
	call	_drop
	ret

# WARM0
# Warm start
word	warm0,,, forth
_warm0:
	.quad	lit, .L_hello_msg
	.quad	count
	.quad	type


	.quad	quit
	.quad	bye
	.quad	exit # Not needed here, for decompiler only for now

.ifndef	BAREMETAL
MESSAGE	hello, "\r\n\x1b[1;32mLinux \x1b[42m\x1b[1;30m \x1b[1;30m MOOR Forth System v 0.0  \x1b[0m\n\n" 
.else
MESSAGE hello, "\nBaremetal \x01\x20 MOOR Forth System \x01\x02                                             \x01\x82v 0.0"
.endif

# ( -- ?) BAREMETAL
word	baremetalq, "baremetal?" 
	call	_dup

	xor	rtop, rtop
	cmp	byte ptr [runmode], RUNMODE_BAREMETAL 	
	jne	1f
	inc	rtop
	1:
	ret

#
# Baremetal words
#

.ifdef	BAREMETAL

# ( c -- ) COLOR
# Sets current VGA color
word	color
	
	call	[__setcolor]

	call	_drop

	ret

# ( -- ) SOURCE
# Marks embedded source as not loaded
# Needed after warm restart
word	source

	lea	rax, [_source]
	mov	[_source_in], rax

	mov	byte ptr [_source_completed], 0

	ret	

.endif



# LATEST
	.endfunc
	.equ	last, latest_word

	.align	4096

_source:

.ifdef BOOT_SOURCE
	.incbin "core.moor"
	.ifdef	BAREMETAL
		.incbin	"ympx.moor"
	.endif
.else
	.byte	0
.endif

	.byte	0
	.byte	0
here0:

	.align	4096

