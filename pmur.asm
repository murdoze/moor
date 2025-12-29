.intel_syntax	noprefix
	.globl _start0

.text	

##############################################################################################################################################################
#																			     #
#                        		THIS IS THE PROTECTED MODE HYPERVISOR PLAYGROUND.                                                                    #
#																			     #
##############################################################################################################################################################

# Initialization

.p2align	16, 0x90

	.org	ORG

_start0:
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
	.word	_boot_16 - _start0 + 0x7c00, 0x0000

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
#	di = print offset on screen
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

	mov	ah, 0x41
	mov	bx, 0x55AA
	int	0x13
	jc	.L_edd_error
	cmp	bx, 0xAA55
	jne	.L_edd_error

	call	.L_load_lba

_dap:
	.byte	0x10
	.byte	0
	.word	64
_dap_ofs:
	.word	0
_dap_seg:	
	.word	0x1000
	.quad	1

.L_load_lba:
	pop	si
	mov	cx, 512 / 64

	1:
	mov	ah, 0x42
	mov	bx, 0

	push	cx
	int	0x13
	pop	cx
	jc	.L_disk_error
	add	word ptr [si + 6], 0x800	# dap seg
	add	word ptr [si + 8], 64
	dec	cx
	jnz	1b

	jmp	.L_loaded

.L_disk_error:
	boot_status	0x39, 0x4f
	
	jmp	.

.L_edd_error:
	boot_status	0x38, 0x4f
	
	jmp	.


.L_loaded:
	boot_status	0x42, 0x5f

#
# Entering protected mode
#

	# Disable interrupts (NMI some day, TODO)
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
	shl	ecx, 8
	rep	movsd

	boot32_status	'R', 0xaf

	#jmp	ORG + 0x200
	push	ORG + 0x200
	ret

	#
	# Partition table, without it the disk is not recognized as bootable
	#

	.org	ORG + 0x1be
	/*
	.byte	0x80			# bootable	TODO sizes are wrong
	.byte	0x00, 0x02, 0x00	# start CHS address
	.byte	0x0b			# partition type
	.byte	0x01, 0x12, 0x4f	# end CHS address
	.byte	0x01, 0x00, 0x00, 0x00	# LBA
	.byte	0x3f, 0x0b, 0x00, 0x00	# number of sectors
	*/
	.byte   0x80                    # bootable      TODO sizes are wrong
	.byte   0x01, 0x01, 0x00        # start CHS address
	.byte   0x0b                    # partition type
	.byte   0xfe, 0xff, 0xff        # end CHS address
	.byte   0x3f, 0x00, 0x00, 0x00  # LBA
	.byte   0xc1, 0x9f, 0xfb, 0x00  # number of sectors

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

_setcolor:
	mov	byte ptr fs:[_pcolor], al
	ret


	# al = char
_p32emit:
	mov	[edi], al
	inc	edi
	mov	al, fs:[_pcolor]
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

	# al = row, ah = col
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
	mov	al, 0x48
	call	_p32emit

	mov	eax, 0x020a
	call	_cursor


	jmp	_setup_paging

	#
	# Setup 4-level initial paging
	#

	X86_CR4_PAE = (1 << 5)
	
	BOOT_PGTABLE_ADDR = 0x80000

	MSR_EFER = 0xc0000080
	EFER_LME = 8

_setup_paging:
	# Stolen from Linux 6.19 arch/x86/compressed/head_64.S

	mov	eax, cr4
	or	eax, X86_CR4_PAE
	mov	cr4, eax

	xor	edx, edx

	boot32_status	'B', 0x5f

	mov	ebp, BOOT_PGTABLE_ADDR

	# Build Level 4
	lea	edi, [ebp + 0]
	lea	eax, [edi + 0x1007]
	mov	[edi + 0], eax
	add	[edi + 4], edx		# ??? edx = 0

	# Build Level 3
	lea	edi, [ebp + 0x1000]
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
	lea	edi, [ebp + 0x2000]
	mov	eax, 0x00000183
	mov	ecx, 2048
1:	mov	[edi + 0], eax
	add	[edi + 4], edx		# ??? edx = 0
	add	eax, 0x00200000
	add	edi, 8
	dec	ecx
	jnz	1b


	boot32_status	'C', 0x5f
	mov	cr3, ebp
	boot32_status	'd', 0x5f

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
	# 64-bit screen output
	#

.code64

_itrace:
	pushf
	pop	rax
	or	rax, 0x100
	push	rax
	popf
	ret

_noitrace:
	pushf
	pop	rax
	and	rax, ~0x100
	push	rax
	popf
	ret

_p64emit:
	mov	[rdi], al
	inc	rdi
	mov	al, fs:[_pcolor]
	mov	[rdi], al
	inc	rdi
	ret
	
	# eax = hex number
_p64printq:
	push	rax
	shr	rax, 32
	call	_p64printd
	pop	rax
_p64printd:
	push	rax
	shr	rax, 16
	call	_p64printw
	pop	rax
_p64printw:
	xchg	al, ah
	call	_p64printb
	xchg	al, ah
_p64printb:
	push	cx
	mov	cl, al
	shr	al, 4
	call	_p64print1
	mov	al, cl
	pop	cx
_p64print1:
	and	al, 0x0f
	cmp	al, 0xa
	jb	1f
	add	al, 0x61 - 0x39 - 1
	1:
	add	al, 0x30
	call	_p64emit
	ret


_emitq:
	push	rax
	shr	rax, 32
	call	_emitd
	pop	rax
_emitd:
	push	rax
	shr	rax, 16
	call	_emitw
	pop	rax
_emitw:
	xchg	al, ah
	call	_emitb
	xchg	al, ah
_emitb:
	push	cx
	mov	cl, al
	shr	al, 4
	call	_emit1
	mov	al, cl
	pop	cx
_emit1:
	and	al, 0x0f
	cmp	al, 0xa
	jb	1f
	add	al, 0x61 - 0x39 - 1
	1:
	add	al, 0x30
	push	rax
	push	rcx
	call	_emitchar
	pop	rcx
	pop	rax
	ret


	#
	# IDT and GDT 64-bit
	#

	IDT64_TRAP_COUNT =  32
	IDT64_INTERRUPT_COUNT = 16
	IDT64_COUNT = IDT64_TRAP_COUNT + IDT64_INTERRUPT_COUNT

	GATE_TRAP	= 0x0f00
	GATE_INTERRUPT	= 0x0e00

	TRAP_DE		= 0
	TRAP_DB 	= 1
	TRAP_NMI	= 2
	TRAP_BP		= 3
	TRAP_OF		= 4
	TRAP_BR		= 5
	TRAP_UD		= 6
	TRAP_DF		= 8
	TRAP_TS		= 10
	TRAP_NP		= 11
	TRAP_SS		= 12
	TRAP_GP		= 13
	TRAP_PF		= 14
	TRAP_AC		= 17
	TRAP_MC		= 18
	TRAP_XM		= 19
	TRAP_VE		= 20
	TRAP_CP		= 21

	INTERRUPT_TIMER		= 0x20
	INTERRUPT_KEYBOARD	= 0x21

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

	.equ	CS_64, 0x10
	.equ	DS_64, 0x18
	.equ	TSS_64, 0x20

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
	.quad	0x00008900100000ff	# 20 TS descriptor
	.quad   0x0000000000000000	#
_gdt_64$:	

 	# Write an IDT entry to idt_32
 	# eax =	handler
 	# esi =	vector #
	# edi =	IDT address
	# ebx = gate type (0x0e00 for interrupt, 0x0f00 for trap)
_set_idt64_entry:
	lea	ecx, [esi * 8]
	add	ecx, ecx

	lea	ecx, [edi + ecx]

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

	#
	# Print helper functions
	#

_clear_screen:
	mov	rdi, SCREEN
	mov	rcx, 1 * 80
	mov	ax, 0x082e
	rep	stosw
	mov	rcx, 24 * 80
	mov	ax, 0x0f00
	rep	stosw
	ret

_print_interrupt_masks:
	inb	al, 0x21
	add	al, 0x30

	mov	rdi, SCREEN + 3 * (2 * 80) - 8
	mov	byte ptr fs:[_pcolor], 0x20
	call	_p64printb
	
	inb	al, 0xa1
	add	al, 0x30

	mov	rdi, SCREEN + 3 * (2 * 80) - 4
	mov	byte ptr fs:[_pcolor], 0x20
	call	_p64printb

	ret

	# Print stack and instruction pointers
_print_sp_ip:
	mov	rdi, SCREEN + 3 * (2 * 80) + 80
	mov	byte ptr fs:[_pcolor], 0x20
	mov	al, 'S'
	call	_p64emit
	mov	al, 'P'
	call	_p64emit
	mov	al, ' '
	call	_p64emit
	mov	al, ' '
	call	_p64emit
	mov	byte ptr fs:[_pcolor], 0x2f
	mov	rax, rsp
	call	_p64printq

	mov	rdi, SCREEN + 4 * (2 * 80) + 80
	mov	byte ptr fs:[_pcolor], 0x20
	mov	al, 'I'
	call	_p64emit
	mov	al, 'P'
	call	_p64emit
	mov	al, ' '
	call	_p64emit
	mov	al, ' '
	call	_p64emit
	mov	byte ptr fs:[_pcolor], 0x2f
	mov	rax, [_trap_rip]
	call	_p64printq
	ret

# RSI = start
_print_dump:
	push	rcx
	push	rdx
	push	rdi

	mov	rdi, SCREEN + 7 * (2 * 80)
	mov	byte ptr fs:[_pcolor], 0x0f
	mov	rcx, 0x100

	0:
	mov	rdx, 16
	mov	rax, rsi
	call	_p64printq
	mov	al, ':'
	call	_p64emit
	mov	al, ' '
	call	_p64emit
	1:
	lodsb
	call	_p64printb
	mov	al, ' '
	call	_p64emit
	dec	rdx
	jnz	2f
	add	rdi, 2 *80 - 2 * (16 * 3) - 2 * 18
	dec	rcx
	jnz	0b
	jmp	9f
	2:
	dec	rcx
	jnz	1b
	9:
	pop	rdi
	pop	rdx
	pop	rcx

	ret

_print_instructions_dump:
	push	rcx
	push	rdx
	push	rsi
	push	rdi

	mov	rdi, SCREEN + 7 * (2 * 80) + 80
	mov	byte ptr fs:[_pcolor], 0x0f
	mov	rcx, 0x30

	mov	rsi, [_trap_rip]
	0:
	mov	rdx, 8
	1:
	lodsb
	call	_p64printb
	mov	al, ' '
	call	_p64emit
	dec	rdx
	jnz	2f
	mov	rdx, 8
	add	rdi, 2 *80 - 2 * (8 * 3)
	2:
	dec	rcx
	jnz	1b

	pop	rdi
	pop	rsi
	pop	rdx
	pop	rcx

	ret

_print_error_code:
	mov	rdi, SCREEN + 2 * (2 * 80) + 80
	mov	byte ptr fs:[_pcolor], 0x40
	mov	al, 'E'
	call	_p64emit
	mov	al, 'C'
	call	_p64emit
	mov	al, ' '
	call	_p64emit
	mov	al, ' '
	call	_p64emit
	mov	byte ptr fs:[_pcolor], 0x0e
	mov	rax, fs:[_trap_error_code]
	call	_p64printq
	ret

_print_cr2:
	mov	rdi, SCREEN + 5 * (2 * 80) + 80
	mov	byte ptr fs:[_pcolor], 0x20
	mov	al, 'C'
	call	_p64emit
	mov	al, 'R'
	call	_p64emit
	mov	al, '2'
	call	_p64emit
	mov	al, ' '
	call	_p64emit
	mov	byte ptr fs:[_pcolor], 0x04f
	mov	rax, cr2
	call	_p64printq
	ret

_print_trap_counter:
	mov	rdi, SCREEN + 2 * (80 - 16)
	#mov	byte ptr fs:[_pcolor], 0x5f
	inc	qword ptr [_trap_counter]
	mov	rax, qword ptr [_trap_counter]
	call	_p64printq
	ret

_print_interrupt_number:
	mov	rdi, SCREEN + 2
	mov	byte ptr fs:[_pcolor], 0x1f
	mov	al, byte ptr [_interrupt_number]
	call	_p64printb
	ret

_print_key_pressed:
	mov	word ptr [SCREEN + 18], 0x5f4b

	mov	rdi, SCREEN + 22
	mov	byte ptr fs:[_pcolor], 0x0b
	push	rax
	call	_p64printb
	mov	al, ' '
	call	_p64emit
	pop	rax
	mov	ah, 0x1f
	call	_p64emit
	ret

.macro	pushr
	push	rax
	push	rbx
	push	rcx
	push	rdx
	push	rsi
	push	rdi
.endm

.macro	popr
	pop	rdi
	pop	rsi
	pop	rdx
	pop	rcx
	pop	rbx
	pop	rax
.endm

_trap_counter:		 .quad	0
_trap_number:		.byte	0
_trap_wo_error_code:	.byte	0
_trap_error_code:	.quad	0
_trap_rip:		.quad	0
_trap_temp:		.quad	0


	# Handlers for traps w/o error code

_trap_ud_handler:
	mov	byte ptr fs:[_trap_number], TRAP_UD

	mov	dword ptr [SCREEN + 4], 0xcf44cf55
	
	jmp	_trap_handler64


	# Handlers for traps with error code 


_trap_df_handler:
	mov	byte ptr fs:[_trap_number], TRAP_DF
	jmp	_trap_error_handler

_trap_ts_handler:
	mov	byte ptr fs:[_trap_number], TRAP_TS
	jmp	_trap_error_handler

_trap_np_handler:
	mov	byte ptr fs:[_trap_number], TRAP_NP
	jmp	_trap_error_handler

_trap_ss_handler:
	mov	byte ptr fs:[_trap_number], TRAP_SS
	jmp	_trap_error_handler

_trap_gp_handler:
	mov	byte ptr fs:[_trap_number], TRAP_GP

	mov	dword ptr [SCREEN + 4], 0x4f474f50
	
	jmp	_trap_error_handler

_trap_pf_handler:
	mov	byte ptr fs:[_trap_number], TRAP_PF

	mov	dword ptr [SCREEN + 4], 0x4f464f50
	
	jmp	_trap_error_handler

_trap_ac_handler:
	mov	byte ptr fs:[_trap_number], TRAP_AC
	jmp	_trap_error_handler

_trap_cp_handler:
	mov	byte ptr fs:[_trap_number], TRAP_CP
	jmp	_trap_error_handler

	# Handler for traps with error code

_trap_handler64:
	mov	word ptr [SCREEN + 2], 0xcf23
	
	pushr

	mov	qword ptr fs:[_trap_temp], rax
	mov	rax, [rsp + 0 + 8 * 6]
	mov	qword ptr fs:[_trap_rip], rax
	mov	rax, qword ptr fs:[_trap_temp]

	call	_print_sp_ip
	call	_print_instructions_dump

	mov	rdi, SCREEN + 10
	mov	al, byte ptr [_trap_number]
	mov	byte ptr fs:[_pcolor], 0x8e
	call	_p64printb

	popr

	sti

	jmp	.

	iretq

_trap_error_handler:
	pushr

	mov	qword ptr fs:[_trap_temp], rax
	mov	rax, [rsp + 0 + 8 * 6]			# must currespond to number of registers pushed by pushr
	mov	qword ptr fs:[_trap_error_code], rax
	mov	rax, [rsp + 8 + 8 * 6]
	mov	qword ptr fs:[_trap_rip], rax
	mov	rax, qword ptr fs:[_trap_temp]

	mov	word ptr [SCREEN + 8], 0x4f45

	call	_print_error_code
	call	_print_sp_ip
	call	_print_cr2
	call	_print_instructions_dump

	mov	rdi, SCREEN + 12
	mov	al, byte ptr [_trap_number]
	mov	byte ptr fs:[_pcolor], 0x8e
	call	_p64printb

	jmp	.

	popr
	add	rsp, 8
	iretq

_interrupt_number:	.byte	0

_interrupt_handler64:
	pushr

	boot32_status	'I', 0x5f

	call	_print_interrupt_number

	jmp	.

	popr
	iretq

_interrupt_20_handler:
	mov	byte ptr fs:[_interrupt_number], 0x20
	jmp	_interrupt_handler64

_interrupt_21_handler:
	mov	byte ptr fs:[_interrupt_number], 0x21
	jmp	_interrupt_handler64

_interrupt_22_handler:
	mov	byte ptr fs:[_interrupt_number], 0x22
	jmp	_interrupt_handler64

_interrupt_23_handler:
	mov	byte ptr fs:[_interrupt_number], 0x23
	jmp	_interrupt_handler64

_interrupt_24_handler:
	mov	byte ptr fs:[_interrupt_number], 0x24
	jmp	_interrupt_handler64

_interrupt_25_handler:
	mov	byte ptr fs:[_interrupt_number], 0x25
	jmp	_interrupt_handler64

_interrupt_26_handler:
	mov	byte ptr fs:[_interrupt_number], 0x26
	jmp	_interrupt_handler64

_interrupt_27_handler:
	pushr

	#boot32_status	's', 0x5f

	call	_pic_send_eoi

	popr
	iretq


_interrupt_trace_handler:
	pushr

	mov	qword ptr fs:[_trap_temp], rax
	mov	rax, [rsp + 0 + 8 * 6]
	mov	qword ptr fs:[_trap_rip], rax
	mov	rax, qword ptr fs:[_trap_temp]

	call	_print_sp_ip
	add	qword ptr [_trap_counter], 0x10000000
	call	_print_trap_counter

	mov	al, 10
	call	_emitchar
	mov	al, 0x10
	call	_emitchar
	mov	rax, [_trap_rip]
	mov	rsi, [rax]
	call	_emitq
	mov	al, ' '
	call	_emitchar
	mov	rax, rsi
	call	_emitq

	sti
	call	_waitkey

	popr
	iretq

_interrupt_timer_handler:
	pushr

	inc	qword ptr [_trap_counter]
	call	_print_trap_counter

	call	_pic_send_eoi

	popr
	iretq

	#
	# Keyboard input
	#

_keyboard_task:	.quad	0
_keyboard_temp:	.quad	0
_keyboard_wait:	.byte	0
_key_code:	.byte	0

_interrupt_keyboard_handler:
	pushr

	in	al, 0x60
	mov	byte ptr [_key_code], al

	call	_print_key_pressed

	call	_pic_send_eoi

	# ESC to restart
	cmp	byte ptr [_key_code], 0x01	#KEYCODE_ESC
	jne	1f

	mov	qword ptr fs:[_trap_temp], rax
	mov	rax, [rsp + 0 + 8 * 6]
	mov	qword ptr fs:[_trap_rip], rax
	mov	rax, qword ptr fs:[_trap_temp]

	call	_print_sp_ip
	call	_print_instructions_dump

	popr	

	lea	rax, [_warm_64]
	mov	[rsp], rax
	iretq

	# Run task
	1:
	cmp	qword ptr [_keyboard_task], 0
	jz	7f
	cmp	byte ptr [_keyboard_wait], 0
	jz	7f

	popr

	xor	al, al
	xchg	al, byte ptr [_key_code]
	movzx	rax, al

	mov	byte ptr [_keyboard_wait], 0
	pop	qword ptr [_keyboard_temp]	# discard return address
	push	qword ptr [_keyboard_task]	# run the waiting keyboard task

	jmp	9f

	7:
	popr

	9:
	iretq

_inkey:
	movzx	rax, byte ptr [_key_code]
	ret

_waitkey:
	xor	al, al
	xchg	al, byte ptr [_key_code]
	movzx	rax, al
	jnz	_key_exit

	lea	rax, [_key_wait]
	mov	qword ptr [_keyboard_task], rax
	mov	byte ptr [_keyboard_wait], 1
	1:
	sti
	hlt
	jmp	1b
_key_wait:

_key_exit:
	ret

	PRESSED_ALT	= 0x1
	PRESSED_CTRL	= 0x2
	PRESSED_SHIFT	= 0x4

	KEYMASK_RELEASE	= 0x80
	KEYCODE_ALT	= 0x38
	KEYCODE_CTRL	= 0x1d
	KEYCODE_LSHIFT	= 0x2a
	KEYCODE_RSHIFT	= 0x36
	KEYCODE_CAPS	= 0x3a

	.set	KEYCODE_ESC,	0x01

	KEYCODE_COUNT	= 0x3b

	#	00	01	02	03	04	05	06	07	08	09	0a	0b	0c	0d	0e	0f
_keycode_to_ascii:
_keycode_to_ascii_noshift:
	.byte	0,	27,	'1',	'2',	'3',	'4',	'5',	'6',	'7',	'8',	'9',	'0',	'-',	'=',	127,	9
	.byte	'q',	'w',	'e',	'r',	't',	'y',	'u',	'i',	'o',	'p', 	'[',	']',	10,	0,	'a', 	's'
	.byte	'd',	'f',	'g',	'h',	'j',	'k',	'l',	';',	'\'',	'`',	0,	'\\',	'z',	'x',	'c',	'v'
	.byte	'b',	'n',	'm',	',',	'.',	'/',	0,	2,	0,	' ',	1
_keycode_to_ascii_shift:
	.byte	0,	27,	'!',	'@',	'#',	'$',	'%',	'^',	'&',	'*',	'(',	')',	'_',	'+',	127,	9
	.byte	'Q',	'W',	'E',	'R',	'T',	'Y',	'U',	'I',	'O',	'P', 	'{',	'}',	28,	0,	'A', 	'S'
	.byte	'D',	'F',	'G',	'H',	'J',	'K',	'L',	':',	'"',	'~',	0,	'|',	'Z',	'X',	'C',	'V'
	.byte	'B',	'N',	'M',	'<',	'>',	'?',	0,	0,	0,	' ',	1

_key_modifiers:
	.byte	0

_key:
	0:
	call	_waitkey

	cmp	al, KEYCODE_ALT
	je	0b
	cmp	al, KEYCODE_CTRL
	je	0b
	cmp	al, KEYCODE_LSHIFT
	jne	3f
	2:
	or	byte ptr [_key_modifiers], PRESSED_SHIFT
	jmp	0b
	3:
	cmp	al, KEYCODE_RSHIFT
	je	2b
	cmp	al, KEYCODE_LSHIFT | KEYMASK_RELEASE
	jne	5f
	4:
	and	byte ptr [_key_modifiers], ~PRESSED_SHIFT
	jmp	0b
	5:
	cmp	al, KEYCODE_RSHIFT | KEYMASK_RELEASE
	je	4b

	test	al, KEYMASK_RELEASE
	jnz	0b

	cmp	al, KEYCODE_COUNT
	ja	0b

	lea	rbx, [_keycode_to_ascii]
	test	byte ptr [_key_modifiers], PRESSED_SHIFT
	jz	7f
	add	rbx, KEYCODE_COUNT
	7:
	mov	al, byte ptr [rbx + rax]

	or	al, al
	jz	0b

	push	rax
	mov	ah, 0x5f
	mov	word ptr [SCREEN + 20], ax
	pop	rax

	ret

_keychar:
	jmp	1f
	0:	
	mov	byte ptr fs:[_pcolor], 0x02

	mov	al, 0x10
	call	_emitchar

	mov	byte ptr fs:[_pcolor], 0x05

	1:
	call	_key

	cmp	al, 1
	jne	2f
	call	_clrscr
	jmp	0b
	2:
	cmp	al, 127
	jne	7f
	call	_cursor_backward
	mov	al, ' '
	call	_emitchar
	call	_cursor_backward
	call	_cursor_show
	mov	rax, 127
	7:
	ret

	# Display output 

	START_ROW	= 1
	START_COL	= 0
	END_ROW		= 25
	END_COL		= 80

_cursor_row:	.byte	START_ROW
_cursor_col:	.byte	START_COL

_cursor_show:
	mov	al, byte ptr [_cursor_row]
	mov	ah, byte ptr [_cursor_col]
	call	_cursor
	ret

_screen_scrollup:
	push	rcx
	push	rsi
	push	rdi

	mov	rdi, SCREEN + 2 * 80 * START_ROW
	lea	rsi, [rdi + 2 * 80]
	mov	rcx, 2 * 80 / 8 * (END_ROW - START_ROW)

	rep	movsq

	pop	rdi
	pop	rsi
	pop	rcx
	ret


_cursor_backward:
	mov	al, byte ptr [_cursor_col]
	cmp	al, 0
	jz	4f
	dec	byte ptr [_cursor_col]
	jmp	9f

	4:
	cmp	byte ptr [_cursor_row], START_ROW
	je	9f
	mov	byte ptr [_cursor_col], END_COL - 1
	dec	byte ptr [_cursor_row]

	9:
	ret

_cursor_forward:
	inc	byte ptr [_cursor_col]
	call	_cursor_limit
	ret

_cursor_newline:
	add	byte ptr [_cursor_row], 1
	mov	byte ptr [_cursor_col], 0
	call	_cursor_limit
	ret

_cursor_tab:
	add	byte ptr [_cursor_col], 8
	and	byte ptr [_cursor_col], 0xf8
	call	_cursor_limit
	ret

_cursor_limit:
	mov	al, byte ptr [_cursor_col]
	cmp	al, END_COL
	jb	1f
	mov	byte ptr [_cursor_col], START_COL
	inc	byte ptr [_cursor_row]
	1:
	mov	al, byte ptr [_cursor_row]
	cmp	al, END_ROW
	jb	3f

	call	_screen_scrollup
	dec	byte ptr [_cursor_row]

	3:
	ret

_clrscr:
	call	_clear_screen

	mov	byte ptr [_cursor_col], START_COL
	mov	byte ptr [_cursor_row], START_ROW
	
	call	_cursor_show

	ret

	EMIT_COLOR	= 0x01
_emitting_color:
	.byte	0

_emitchar:
	#out	0xe9, al

	cmp	byte ptr [_emitting_color], 0
	jz	1f
	mov	byte ptr fs:[_pcolor], al
	mov	byte ptr [_emitting_color], 0
	ret

	1:
	cmp	al, EMIT_COLOR
	jne	3f
	mov	byte ptr [_emitting_color], 1
	ret

	3:
	cmp	al, 10
	jne	4f
	call	_cursor_newline	
	mov	byte ptr fs:[_pcolor], 0x02

	mov	al, 0x10
	call	_emitchar
	ret
	
	4:
	cmp	al, 9
	jne	5f
	call	_cursor_tab
	ret

	5:
	push	rdi

	movzx	rax, al
	push	rax

	mov	al, byte ptr [_cursor_row]
	mov	dl, 2 * 80
	mul	dl
	movzx	rax, ax
	movzx	rdx, byte ptr [_cursor_col]
	add	rax, rdx
	add	rax, rdx
	mov	rdi, SCREEN
	add	rdi, rax

	pop	rax

	call	_p64emit

	call	_cursor_forward

	call	_cursor_show

	pop	rdi

	ret

	READLINE_SIZE = 1024


	#
	# PIC programming
	#

_pic_remap:
	in	al, 0x21
	mov	bl, al
	in	al, 0xa1
	mov	bh, al

	mov	al, 0x11
	out	0x20, al
	out	0xa0, al

	mov	al, 0x20
	out	0x21, al
	out	0xa1, al

	mov	al, 0x04
	out	0x21, al
	out	0xa1, al

	mov	al, 0x01
	out	0x21, al
	out	0xa1, al

	mov	al, bl
	out	0x21, al
	mov	al, bh
	out	0xa1, al

	ret

_pic_send_eoi:
	mov	al, 0x20
	out	0x20, al

	ret

	#
	# 64-bit entrypoint with paging enabled
	#

_boot_64_entry:

	boot32_status	'E', 0x5f

_setup_idt64:
	# Setup generic handlers
	lea	edi, [_idt_64]
	xor	esi, esi

	lea	eax, [_trap_handler64]
	mov	ebx, GATE_TRAP
	1:
	call	_set_idt64_entry
	inc	esi
	cmp	esi, IDT64_TRAP_COUNT
	jne	1b

	2:
	lea	eax, [_interrupt_handler64]
	mov	ebx, GATE_INTERRUPT
	call	_set_idt64_entry
	inc	esi
	cmp	esi, IDT64_COUNT
	jne	2b

	# Setup specific trap handlers
_setup_idt64_traps:
	mov	ebx, GATE_TRAP

	lea	eax, _trap_pf_handler
	mov	esi, TRAP_PF
	call	_set_idt64_entry

	lea	eax, _trap_gp_handler
	mov	esi, TRAP_GP
	call	_set_idt64_entry

	push	rsi

	lea	eax, _trap_ud_handler
	mov	esi, TRAP_UD
	call	_set_idt64_entry
	lea	eax, _trap_df_handler
	mov	esi, TRAP_DF
	call	_set_idt64_entry
	lea	eax, _trap_np_handler
	mov	esi, TRAP_NP
	call	_set_idt64_entry
	lea	eax, _trap_ss_handler
	mov	esi, TRAP_SS
	call	_set_idt64_entry
	lea	eax, _trap_gp_handler
	mov	esi, TRAP_GP
	call	_set_idt64_entry
	lea	eax, _trap_pf_handler
	mov	esi, TRAP_PF
	call	_set_idt64_entry
	lea	eax, _trap_ac_handler
	mov	esi, TRAP_AC
	call	_set_idt64_entry
	lea	eax, _trap_cp_handler
	mov	esi, TRAP_CP
	call	_set_idt64_entry

	pop	rsi

	# Setup specific interrupt handlers
_setup_idt64_interrupts:
	mov	ebx, GATE_INTERRUPT

	lea	eax, _interrupt_trace_handler
	mov	esi, 0x01
	call	_set_idt64_entry

	lea	eax, _interrupt_timer_handler
	mov	esi, INTERRUPT_TIMER
	call	_set_idt64_entry

	lea	eax, _interrupt_keyboard_handler
	mov	esi, INTERRUPT_KEYBOARD
	call	_set_idt64_entry

	lea	eax, _interrupt_22_handler
	mov	esi, 0x22
	call	_set_idt64_entry

	lea	eax, _interrupt_23_handler
	mov	esi, 0x23
	call	_set_idt64_entry

	lea	eax, _interrupt_24_handler
	mov	esi, 0x24
	call	_set_idt64_entry

	lea	eax, _interrupt_25_handler
	mov	esi, 0x25
	call	_set_idt64_entry

	lea	eax, _interrupt_26_handler
	mov	esi, 0x26
	call	_set_idt64_entry

	lea	eax, _interrupt_27_handler
	mov	esi, 0x27
	call	_set_idt64_entry

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

	mov	eax, TSS_64
	ltr	ax

	boot32_status	'W', 0xcf

	push	CS_64
	lea	eax, [_boot_64]
	push	rax
	retfq

	#
	# 64-bit mode with PAE paging and interrupts, fully functional
	#

_boot_64:
	boot32_status	'X', 0xaf

	call	_pic_remap

	#call	_clrscr

	boot32_status	'Y', 0x4f

	BOOT_STACK_ADDR = 0x300000 + 0x4000
_warm_64:
	lea	esp, [BOOT_STACK_ADDR - 8]

	RUNMODE_LINUXUSR	= 0
	RUNMODE_BAREMETAL 	= 1
	mov	byte ptr [runmode], RUNMODE_BAREMETAL

	sti


	boot32_status	'Y', 0xaf

	#jmp	_vmx_on

	mov	byte ptr fs:[_pcolor], 0x0e

	mov	al, 0x10
	call	_emitchar



	1:
	mov	byte ptr fs:[_pcolor], 0x05

	call	_keychar

	cmp     al, 28 # 28 - SHift+Enter
	jmp     9f
	cmp	al, 127
	je	1b

	call	_emitchar

	jmp	1b


	9:
	call	_clrscr
	#call	_itrace


__start_entry:
	and	byte ptr [_key_modifiers], ~PRESSED_SHIFT

	lea	rax, [_keychar]
	mov	qword ptr [__key], rax

	lea	rax, [_emitchar]
	mov	qword ptr [__emitchar], rax

	lea	rax, [_setcolor]
	mov	qword ptr [__setcolor], rax

	jmp	__start

	#
	# VMX root operation
	#

.equ	IA32_VMX_BASIC, 0x480
.equ	IA32_VMX_CR0_FIXED0, 0x486
.equ	IA32_VMX_CR0_FIXED1, 0x487
.equ	IA32_VMX_CR4_FIXED0, 0x488
.equ	IA32_VMX_CR4_FIXED1, 0x489
.equ	IA32_VMX_PROCBASED_CTLS2, 0x48b

_vmx_on:
	mov	rax, cr4
	or	rax, 0x2000
	mov	cr4, rax

	mov	r8, cr0
	mov	ecx, IA32_VMX_CR0_FIXED0
	rdmsr
	shl	rdx, 32
	or	rax, rdx
	or	r8, rax
	mov	ecx, IA32_VMX_CR0_FIXED1
	rdmsr
	shl	rdx, 32
	or	rax, rdx
	and	r8, rax
	mov	cr0, r8
	
	mov	r8, cr4
	mov	ecx, IA32_VMX_CR4_FIXED0
	rdmsr
	shl	rdx, 32
	or	rax, rdx
	or	r8, rax
	mov	ecx, IA32_VMX_CR4_FIXED1
	rdmsr
	shl	rdx, 32
	or	rax, rdx
	and	r8, rax
	mov	cr4, r8

	
	mov	ecx, IA32_VMX_BASIC
	rdmsr
	mov	dword ptr [_vmcs], eax
	
	boot32_status	'9', 0x4f

	lea	ecx, [pvmxon]
	vmxon	[ecx]
	jc	1f

	boot32_status	'+', 0x3f
	jmp	.
	1:
	boot32_status	'-', 0x4f
	jmp	.

	mov	word ptr [0xb8000], cx


pvmxon:	.quad	_vmcs

	.align	4096
_vmcs:
	.fill	4096, 1, 0
	
__start:


	#
	# 64-bit code	
	#

.include "mur.asm"

