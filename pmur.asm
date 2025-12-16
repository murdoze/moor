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

##############################################################################################################################################################
#																			     #
#		THIS IS THE PROTECTED MODE PLAYGROUND.                        DO NOT MAKE CHANGES TO CORE FUNCTIONALITY HERE OR FACE MERGES                  #
#																			     #
##############################################################################################################################################################

# Initialization

.p2align	16, 0x90

	.org	ORG

_start:
	# Check if we're in 16/32/64-bit mode
	jmp	_mode_16

.macro	boot_status value, color
	mov	word ptr gs:[0], (\color << 8) | \value
.endm

	.align	8
	# 32-bit fault handler is located at 0x7c00
_fault_handler32:
	mov	word ptr [0xb8002], 0xcf7e

	jmp	.


.code16

_mode_16:
	xor	ax, ax
	mov	ds, ax

	# 16-bit mode, bootloader at 0x7c00
	.byte	0xea			# jmp far 0:0x7c00+x
	.word	_boot_16 - _start + 0x7c00, 0x0000

	#
	# IDT and GDT for 32-bit protected mode
	#

	.equ	CS_32_10, 0x10	# to turn on PAE paging we need one more code segment (???)
	.equ	DS_32, 0x28
	.equ	CS_32, 0x20

	# Empty IDT, will be changed later, because a real one does not fit the bootsector
	.align	16
_idtr_32:
	.word	32 * 8 - 1
	.long	0x7000

.align	16
_gdtr_32:
	.word	_gdt_32$ - _gdt_32 - 1
	.long	_gdt_32 - ORG + 0x7c00
	.word	0			# Stolen from Linux
_gdt_32:
	.quad	0			# 00
	.quad	0x00cf9a000000ffff	# 08
	.quad	0x00af9a000000ffff	# 10
	.quad	0x00cf92000000ffff	# 18: present, code, executable, granulatity=4K base=0, limit=0xfffff000
	# ?? The following have to be removed, they work but are not as Linux boots
	# Linux 32-entry has CS = 0x08 and DS = 0x18
	.quad	0x00cf9b000000ffff	# 20: present, data, writable,   granulatity=4K base=0, limit=0xfffff000
	.quad	0x00cf93000000ffff	# 28: as in Linux, don't ask
_gdt_32$:

	#
	# Screen output 16-bit
	#

#	ax = value
#	di = print location n screen
_printd:
	push	eax
	shr	eax, 16
	call	_printw
	pop	eax
_printw:
	xchg	al, ah
	call	_printb
	xchg	al, ah
_printb:
	push	cx
	mov	cl, al
	shr	al, 4
	call	_print1
	mov	al, cl
	pop	cx
_print1:
	and	al, 0x0f
	cmp	al, 0xa
	jb	1f
	add	al, 0x61 - 0x39 - 1
	1:
	add	al, 0x30
	mov	byte ptr gs:[di], al
	inc	di
	inc	di
	ret

_boot_16:
	mov	ax, 0xb800
	mov	gs, ax

	#boot_status	0x42, 0x4f

	.equ	RELOC32_SEG, 0x1000
	.equ	SECTORS, 512
					# DL contains disk number (normally 0x80)
	mov	bx, 0x1000		# load sector to memory address 0x10000
	mov	es, bx                 
	mov	bx, 0x0			# ES:BX = 0x1000:0x0
	mov	si, SECTORS	

	mov	dh, 0x0			# head 0
	mov	ch, 0x0			# cylinder 0
	mov	cl, 0x2			# starting sector to read from disk

	mov	di, 2			# debug print

	jmp	.L_load1

.L_next_sector:
	mov	byte ptr gs:[di], 0x2e
	inc	di
	inc	di

	inc	cl
	dec	si
	jz	.L_loaded

	add	bh, 0x2
	jnz	.L_load1

	mov	ax, es
	add	ax, 0x1000		# next 64K
	mov	es, ax

.L_load1:
	mov	ax, 0x0201
	int	0x13                    # BIOS interrupts for disk functions
	jc	.L_disk_error

	cmp	cl, 63
	jne	.L_next_sector
	inc	dh
	cmp	dh, 0xf			# Number of heads
	jna	.L_forward
	xor	dh, dh
	inc	ch
	jnz	.L_forward
	add	cl, 0x40
.L_forward:
	and	cl, 0xc0

	mov	byte ptr gs:[di], 0x2b
	inc	di
	inc	di

	jmp	.L_next_sector

.L_disk_error:
	#boot_status	0x39, 0x4f
	
	jmp	.


.L_loaded:
	#boot_status	0x42, 0xaf

#
# Entering protected mode
#

	# Disable interrupts and NMI
	cli


	# A20 check was here
	#boot_status	0x32, 0x4f
	#jmp	.

	#boot_status	0x33, 0xaf

_load_idt32_gdt32:
	mov	di, 0x7000	# IDT_32 will be places at 0x7000
	mov	ax, 0x8e00	# present, 32-bit interrupt gate
	mov	bx, 0x7c08	# fault handler
	xor	dx, dx
	mov	si, CS_32
	mov	cx, 32
	1:
	mov	[di], bx	# offset low
	mov	[di + 2], si	# segment selector = CS_32
	mov	[di + 4], ax	# flags
	mov	[di + 6], dx	# offset hight = 0	
	add	di, 8
	loop	1b

	# LIDT load null IDT
	.byte	0x0f, 0x01, 0x1e		# to avoid reference truncated warning
	.word	_idtr_32 - ORG + 0x7c00

	#boot_status	0x43, 0xaf

	# LGDT for 32-bit mode
	.byte	0x0f, 0x01, 0x16		# to avoid reference truncated warning
	.word	_gdtr_32 - ORG + 0x7c00

	#boot_status	0x44, 0xaf

	#
	# Switch to protected mode
	#

	mov	cx, DS_32

	.equ	CR0_PE, 1
	mov	edx, cr0
	or	dl, CR0_PE
	mov	cr0, edx

	#boot_status	0x41, 0x4f

	.byte	0xea
	.word	_pm_32 - ORG + 0x7c00
	.word	CS_32

	#
	# 32-bit protected mode
	#

.code32

_pm_32:

.macro	boot32_status value, color
	mov	word ptr [0xb8000], (\color << 8) | \value
.endm
	mov	ds, cx
	mov	es, cx
	mov	fs, cx
	mov	gs, cx
	mov	ss, cx
	
	boot32_status	'P', 0xaf

	mov	esi, 0x10000
	mov	edi, ORG + 0x200
	mov	ecx, SECTORS
	shl	ecx, 6
	rep	movsd

	boot32_status	'R', 0xaf

	#jmp	ORG + 0x200
	push	ORG + 0x200
	ret

	#
	# Partition table, without it the disk is not recognized as bootable
	#

	.org	ORG + 0x1be
	.byte	0x80			# bootable	TODO sizes are wrong
	.byte	0x01, 0x01, 0x00	# start CHS address
	.byte	0x0b			# partition type
	.byte	0xfe, 0xff, 0xe5	# end CHS address
	.byte	0x00, 0x00, 0x00, 0x00	# LBA
	.byte	0xc1, 0xaf, 0xf4, 0x00	# number of sectors


	# Boot signature
	.org	ORG + 0x1fe
	.byte	0x55, 0xaa

	#
	# 0x200 is second sector
	#

	# 0x200 is a 64-bit bootloader kernel entry, but we'll take care of this later

	.org	ORG + 0x200

_boot_32_entry:
	.equ	SCREEN, 0xb8000

	boot32_status	'S', 0x4f

	jmp	_boot_32

	#
	# Screen output functions
	#

_pcolor:	
	.byte	0x2f

	# al = char
_p32emit:
	mov	[edi], al
	inc	edi
	mov	al, [_pcolor]
	mov	[edi], al
	inc	edi
	ret
	
	# eax = hex number
_p32printd:
	push	eax
	shr	eax, 16
	call	_p32printw
	pop	eax
_p32printw:
	xchg	al, ah
	call	_p32printb
	xchg	al, ah
_p32printb:
	push	cx
	mov	cl, al
	shr	al, 4
	call	_p32print1
	mov	al, cl
	pop	cx
_p32print1:
	and	al, 0x0f
	cmp	al, 0xa
	jb	1f
	add	al, 0x61 - 0x39 - 1
	1:
	add	al, 0x30
	call	_p32emit
	ret

	# ah = row, ah = col
_cursor:
	push	edx
	push	ecx

	push	eax
	and	eax, 0xff
	mov	dl, 80 
	mul	dl
	pop	edx
	shr	edx, 8
	add	eax, edx

	mov	ecx, eax
	mov	al, 0x0f
	mov	dx, 0x3d4
	outb	dx, al
	mov	dx, 0x3d5
	mov	al, cl
	outb	dx, al
	
	mov	al, 0x0e
	mov	dx, 0x3d4
	outb	dx, al
	mov	dx, 0x3d5
	mov	al, ch
	outb	dx, al

	pop	ecx
	pop	edx
	ret

_boot_32:

	mov	edi, SCREEN
	mov	al, 0x41
	call	_p32emit

	mov	edi, SCREEN + 6 * (80 * 2)
	movzx	eax, byte ptr [_pcolor - 2]
	lea	eax, [_pcolor - 2]
	call	_p32printd
	mov	al, 0x20
	call	_p32emit
	call	1f
	1:
	pop	eax
	call	_p32printd
	mov	al, 0x20
	call	_p32emit
	mov	byte ptr [_pcolor], 0x5f
	mov	eax, [0x100210]
	call	_p32printd

	mov	eax, 0x020a
	call	_cursor


	jmp	_setup_paging

	#
	# Setup 4-level initial paging
	#

	X86_CR4_PAE = (1 << 5)
	
	BOOT_PGTABLE_SIZE = (32 * 4096)

	MSR_EFER = 0xc0000080
	EFER_LME = 8

_setup_paging:
	# Stolen from Linux 6.19 arch/x86/compressed/head_64.S

	mov	eax, cr4
	or	eax, X86_CR4_PAE
	mov	cr4, eax

	xor	edx, edx

	# Build Level 4
	lea	edi, [_pgtable + 0]
	lea	eax, [edi + 0x1007]
	mov	[edi + 0], eax
	add	[edi + 4], edx		# ??? edx = 0

	# Build Level 3
	lea	edi, [_pgtable + 0x1000]
	lea	eax, [edi + 0x1007]
	mov	ecx, 4
	1:
	mov	[edi + 0], eax
	add	[edi + 4], edx		# ??? edx = 0
	add	eax, 0x00001000
	add	edi, 8
	dec	ecx
	jnz	1b

	# Build Level 2
	lea	edi, [_pgtable + 0x2000]
	mov	eax, 0x00000183
	mov	ecx, 2048
1:	mov	[edi + 0], eax
	add	[edi + 4], edx		# ??? edx = 0
	add	eax, 0x00200000
	add	edi, 8
	dec	ecx
	jnz	1b


	lea	eax, [_pgtable]
	mov	cr3, eax

	mov	ecx, MSR_EFER
	rdmsr
	bts	eax, EFER_LME
	wrmsr

_setup_pae:
	lea	eax, [_boot_64_entry]

	push	CS_32_10	
	push	eax

	mov	eax, 0x80050033		# PE MP ET NE WP AM PG
	mov	cr0, eax

	retf

	#
	# IDT and GDT 64-bit
	#

	IDT64_TRAP_COUNT =  32
	IDT64_INTERRUPT_COUNT = 8
	IDT64_COUNT = IDT64_TRAP_COUNT + IDT64_INTERRUPT_COUNT

	.align	4
_idtr_64:
	.word	_idt_64$ - _idt_64 - 1
	.quad	_idt_64

	.align	8
_idt_64:
	.rept	IDT64_COUNT
	.quad	0
	.quad	0
	.endr
	.rept	IDT64_INTERRUPT_COUNT
	.quad	0
	.quad	0
	.endr
_idt_64$:

	.equ	DS_64, 0x18
	.equ	CS_64, 0x10

	.align	16
_gdtr_64:
	.word	_gdt_64$ - _gdt_64 - 1
	.long	_gdt_64
	.word	0			# Stolen from Linux
_gdt_64:
	.quad	0x0000000000000000	# 00
	.quad	0x00cf9a000000ffff	# 08 __KERNEL32_CS
	.quad	0x00af9a000000ffff	# 10 __KERNEL_CS
	.quad	0x00cf92000000ffff	# 18 __KERNEL_DS
	.quad	0x0080890000000000	# 20 TS descriptor
	.quad   0x0000000000000000	# 28 TS continued
_gdt_64$:	

.code64
 	# Write an IDT entry to idt_32
 	# eax =	handler
 	# esi =	vector #
	# edi =	IDT address
	# ebx = gate type (0x0e00 for interrupt, 0x0f00 for trap)
_set_idt64_entry:
	lea	ecx, [edi + esi * 8]

	mov	edx, eax
	and	edx, 0xffff		# Target code segment offset [15:0]. Handler is in lower 4GB anyways
	or	edx, CS_64 << 16	# Target code segment selector

	mov	[ecx], edx

	mov	edx, eax
	and	edx, 0xffff0000		# Target code segment offset [31:16]
	or	edx, 0x00008000		# Present
	or	edx, ebx		# Gate type

	mov	[ecx + 4], edx
	ret

_trap_handler64:
	boot32_status	'@', 0x5f

	jmp	.

	iretq

_interrupt_handler64:
	boot32_status	'I', 0x5f

	jmp	.

	iretq

	#
	# 64-bit entrypoint with paging enabled
	#

_boot_64_entry:

	lea	edi, [_idt_64]
	xor	esi, esi

	lea	eax, [_trap_handler64]
	mov	ebx, 0x0f00
	1:
	call	_set_idt64_entry
	add	edi, 8
	inc	esi
	cmp	esi, IDT64_TRAP_COUNT
	jne	1b
	2:
	lea	eax, [_interrupt_handler64]
	mov	ebx, 0x0e00
	call	_set_idt64_entry
	add	edi, 8
	inc	esi
	cmp	esi, IDT64_COUNT
	jne	2b

_load_idt64:
	boot32_status	'T', 0x4f

	lidt	[_idtr_64]

	boot32_status	'U', 0x4f

_load_gdt64:

	lgdt	[_gdtr_64]

	boot32_status	'V', 0xaf

	mov	eax, DS_64
	mov	ds, ax
	mov	es, ax
	mov	fs, ax
	mov	gs, ax
	mov	ss, ax

	boot32_status	'W', 0xcf

	push	CS_64
	lea	eax, [_boot_64]
	push	rax
	retfq

_boot_64:

	boot32_status	'X', 0xaf

	int3

	jmp	.

	.align	4096
_pgtable:
	.fill	BOOT_PGTABLE_SIZE, 1, 0















	#
	# 64-bit code	
	#













.code64
_mode_64:    

	mov	rax, 12
	lea	rdi, [here0]
	syscall
	# TODO check for error here
	mov	[_mem_reserved], rax

	call	_setup_sigsegv_handler

_restart:

	lea	rwork, last
	mov	[forth_], rwork
	lea	rwork, [forth_]
	mov	[_current], rwork
	mov	[_context], rwork
	mov	rhere, [_mem_reserved]
_abort:
_cold:
	xor	rtop, rtop
	xor	rstate, rstate
	mov	[_state], rstate
	lea	rpc, qword ptr [_warm]
	lea	rnext, qword ptr [_next]
	/* TODO: In "hardened" version map stacks to separate pages, with gaps between them */
	lea	rstack0, [rsp - 0x1000]
	xor	rstack, rstack
	lea	rwork, [rsp - 0x2000]
	mov	qword ptr [_tib], rwork
	xor	rwork, rwork

	push	rpc

# Address Interpreter and Compiler

_exit:
	pop	rpc
_next:
	lodsq
	# Canary does not save from GPF, so let's think...
	#movabs	r11, CANARY
	#cmp	qword ptr [rwork - STATES * 16 - 8], r11
	#jne	_canary_fail
_doxt:
.ifdef DEBUG
.ifdef TRACE
	jmp	_do_trace
.endif
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
	cmp	qword ptr [_trace], 0
	jz	1f
	call	_dup
	mov	rtop, rstack
	push	rtmp
	push	rwork
	call	_dot
	pop	rwork
	call	_dup
	mov	rtop, rstate
	push	rwork
	call	_dot
	pop	rwork
	call	_dup
	mov	rtop, rwork
	push	rwork
	call	_decomp_print
	pop	rwork
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
	call	_drop
	push	rwork
	call	dot_s
	pop	rwork
	call	_dup
	mov	rtop, 0xa
	call	_emit
	pop	rtmp
	1:
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
_trace:
	.quad	0

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

	lea	rax, [_restart]
	mov	qword ptr [rdx + 40 + 8 * 16], rax # continue execution from _restart

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
	mov	qword ptr [_trace], 1
	ret

# NOTRACE
word	notrace
	mov	qword ptr [_trace], 0
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
	call	_dup
	mov	rtop, rwork
	call	_decomp_print
	call	_dup
	mov	rtop, 0x9
	call	_emit

	lodsq
	call	_dup
	mov	rtop, rwork
	call	_dot
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
word	_quot_, "(\")"
	lodsb
	movzx	rax, al
	call	_dup
	mov	rtop, rpc
	dec	rtop
	add	rpc, rax
	add	rpc, 0xf
	and	rpc, -16
	ret	

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

# READ ( -- c )
# Reads a character from stdin
word	read
_read:
	call	_dup

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

# TYPE ( c-addr u -- )
# Print string to stdout
word	type
_type:
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
	movzx	rtmp, byte ptr [rwork]			# count
	lea	rsi, [rwork + 1]			# buffer
	mov	rdi, 1					# stdout
	mov	rax, 1					# sys_write
	syscall

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
	jmp	5f

	2:
	cmp	rbx, 0x20
	je	1b
	jmp	5f

	3:
	push	rtmp
	call	_read
.ifdef	DEBUG
	call	_dup
	call	_emit
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
	jmp	5f

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
	push	rbx
	xor	rbx, rbx	# Positive number
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
	cmp	al, 0x2d # "-"
	jne	2f
	inc	bl
	jmp	5f
	2:
	cmp	al, 0x30
	jb	8f
	cmp	al, 0x39
	jbe	3f
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
	shl	rtmp, 4
	add	rtmp, rwork
	5:
	dec	rcx
	jnz	1b

	mov	rtop, rtmp
	cmp	bl, 1
	jne	7f
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
	pop	rsi
	ret

# . ( n -- )
# Print number on the top of the stack (hexadecimal)
word	dot, "."
_dot:
	mov	rtmp, 16

	cmp	rtop, 0
	jge	1f

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
	lea	rtop, qword ptr [.L_quit_errm1]
	call	_count
	call	_type
	call	_dup
	mov	rtop, qword ptr [_tib]
	call	_count
	call	_type
	call	_dup
	lea	rtop, qword ptr [.L_quit_errm2]
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
.L_quit_errm1:
	.byte .L_quit_errm1$ - .L_quit_errm1 - 1
	.ascii	"\r\n\x1b[31mERROR! \x1b[0m\x1b[33mWord \x1b[1m\x1b[7m "
.L_quit_errm1$:
.L_quit_errm2:
	.byte .L_quit_errm2$ - .L_quit_errm2 - 1
	.ascii	" \x1b[27m\x1b[22m not found, or invalid hex number\x1b[0m\r\n"
.L_quit_errm2$:

# QUIT
# Interpret loop
word	quit,,, forth
	.quad	quit_
	.quad	interpreting_
	.quad	qcsp
	.quad	branch, -5
	.quad	exit	# Needed here only for decompilation

# ?CSP ( -- )
# Aborts on stack underflow
word	qcsp, "?csp"
_qcsp:
	cmp	rstack, 0
	jnle	6f
	jmp	9f

	6:
	lea	rtop, qword ptr [.L_qcsp_errm]
	call	_count
	call	_type
.ifdef	DEBUG
	call	_bye
.endif
	jmp	_abort

	9:
	ret
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
	mov	rdi, rtop
	mov	rax, 60
	syscall

# ABORT
# Reinitializes the system, or quits to OS in debug build
word	abort
_abort1:
.ifdef	DEBUG
	jmp	_bye
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

# WARM
# Warm start
word	warm,,, forth
_warm:
	.quad	lit, .L_hello_msg
	.quad	count
	.quad	type


	.quad	quit
	.quad	bye
	.quad	exit # Not needed here, for decompiler only for now

.L_hello_msg:
	.byte .L_hello_msg$ - .L_hello_msg - 1
	.ascii	"\r\n\x1b[31mHello \x1b[0m\x1b[42;37m\x1b[1m MOOR \x1b[0m\n\n"
.L_hello_msg$:
	
# LATEST
	.endfunc
	.equ	last, latest_word


	.align	4096
	.equ	BOOT_STACK_SIZE, 0x1000
_boot_stack:
	.fill	BOOT_STACK_SIZE, 1, 0
_boot_stack$:

	.align	4096

here0:
