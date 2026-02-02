	/* Linux x86-64 syscalls */
	.equ SYS_read,   0
	.equ SYS_poll,   7
	.equ SYS_ioctl, 16

	.equ STDIN_FD, 0

	/* ioctl request codes (x86-64 Linux) */
	.equ TCGETS, 0x5401
	.equ TCSETS, 0x5402

	/* poll flags */
	.equ POLLIN, 0x0001

	/* termios layout (x86-64 Linux): struct termios is 60 bytes.
	   Offsets:
	     c_lflag at 12 (4 bytes)
	     c_cc starts at 17 (bytes)
	   c_cc indices:
	     VTIME = 5
	     VMIN  = 6
	*/
	.equ TERMIOS_SIZE, 60
	.equ OFF_c_lflag,  12
	.equ OFF_c_cc,     17
	.equ IDX_VTIME,    5
	.equ IDX_VMIN,     6

	/* lflag bits */
	.equ ICANON, 0x00000002
	.equ ECHO,   0x00000008
	/* Leave ISIG enabled by default (Ctrl-C still works). */

.align 16
kbd_orig_termios:
	.zero TERMIOS_SIZE
kbd_raw_termios:
kbd_new_termios:
	.zero TERMIOS_SIZE
kbd_is_raw:
	.long 0

/* Internal helper:
   r8b = desired VMIN (0 nonblocking, 1 blocking)
   Returns 0 or -errno
*/
kbd__enter_raw_common:
    /* if already raw, return 0 */
    #mov eax, dword ptr [rip + kbd_is_raw]
    #test eax, eax
    #jne	7f

    /* ioctl(STDIN, TCGETS, &orig) */
    mov eax, SYS_ioctl
    mov edi, STDIN_FD
    mov esi, TCGETS
    lea rdx, [rip + kbd_orig_termios]
    syscall
    test rax, rax
    js	8f

    /* copy orig -> new */
    lea rsi, [rip + kbd_orig_termios]
    lea rdi, [rip + kbd_new_termios]
    mov ecx, TERMIOS_SIZE
    cld
    rep movsb

    /* new.c_lflag &= ~(ICANON | ECHO) */
    mov eax, dword ptr [rip + kbd_new_termios + OFF_c_lflag]
    and eax, ~(ICANON | ECHO)
    mov dword ptr [rip + kbd_new_termios + OFF_c_lflag], eax

    /* new.c_cc[VTIME]=0; new.c_cc[VMIN]=r8b */
    //mov byte ptr [rip + kbd_new_termios + OFF_c_cc + IDX_VTIME], 0
    //mov byte ptr [rip + kbd_new_termios + OFF_c_cc + IDX_VMIN],  r8b

    /* ioctl(STDIN, TCSETS, &new) */
    mov eax, SYS_ioctl
    mov edi, STDIN_FD
    mov esi, TCSETS
    lea rdx, [rip + kbd_new_termios]
    syscall
	test	rax, rax
	js	8f

    mov dword ptr [rip + kbd_is_raw], 1
	7:
    xor eax, eax
	8:
    ret

/* int64_t kbd_enter_raw_nb(void) */
kbd_enter_raw_nb:
    mov r8b, 0          /* VMIN=0 => nonblocking */
    jmp kbd__enter_raw_common

/* int64_t kbd_enter_raw_blocking(void) */
kbd_enter_raw_blocking:
    mov r8b, 1          /* VMIN=1 => block for 1 byte */
    jmp kbd__enter_raw_common


/* int64_t kbd_leave_raw(void)
   Returns 0 on success, or -errno on failure.
*/
kbd_leave_raw:
	#mov eax, dword ptr [rip + kbd_is_raw]
	#test eax, eax
	#je	7f

	/* ioctl(STDIN, TCSETS, &kbd_orig_termios) */
	mov eax, SYS_ioctl
	mov edi, STDIN_FD
	mov esi, TCSETS
	lea rdx, [rip + kbd_orig_termios]
	syscall
	test rax, rax
	js	8f

	mov dword ptr [rip + kbd_is_raw], 0

	7:
	xor eax, eax
	8:
	ret

/* int kbd_kbhit(void)
   Nonblocking: returns 1 if stdin has data available, else 0.
   Uses poll(fd=0, events=POLLIN, timeout=0).
*/
kbd_kbhit:
	sub rsp, 16           /* space for struct pollfd (8) + padding */

	/* struct pollfd { int fd; short events; short revents; } */
	mov dword ptr [rsp + 0], STDIN_FD
	mov word  ptr [rsp + 4], POLLIN
	mov word  ptr [rsp + 6], 0

	/* poll(&pfd, 1, 0) */
	mov eax, SYS_poll
	lea rdi, [rsp]
	mov esi, 1
	xor edx, edx          /* timeout = 0 */
	syscall
	test rax, rax
	jle	8f               /* 0 = none, <0 = error => treat as no */

	/* check revents & POLLIN */
	movzx eax, word ptr [rsp + 6]
	and eax, POLLIN
	cmp eax, 0
	jne	9f

	8:
	xor eax, eax
	add rsp, 16
	ret

	9:
	mov eax, 1
	add rsp, 16
	ret


/* int kbd_getch_nb(void)
   Nonblocking: attempts to read 1 byte from stdin.
   Return:
     EAX = 1 and AL = byte, if a byte was read
     EAX = 0 if no byte available (or EOF)
     EAX = -errno if read failed with an error other than "no data" semantics
   Requires kbd_enter_raw() so VMIN/VTIME make read return immediately.
*/
kbd_getch_nb:
	sub	rsp, 8
	/* read(STDIN, rsp, 1) */
	mov	eax, SYS_read
	mov	edi, STDIN_FD
	lea	rsi, [rsp]
	mov	edx, 1
	syscall
	test	rax, rax
	js	6f             /* -errno */

	cmp	rax, 1
	jne	5f	           /* 0 => no data available (with VMIN=0) or EOF */

	movzx	ecx, byte ptr [rsp]
	mov	eax, 1
	add	rsp, 8
	ret

	5:
	xor	eax, eax
	add	rsp, 8
	ret

	6:
	/* RAX already -errno */
	add	rsp, 8
	ret

/* int kbd_getch_blocking(void)
   Blocking: requires enter_raw_blocking (VMIN=1).
   Returns: EAX=1, AL=byte; EAX=0 EOF; EAX=-errno on error.
*/
kbd_getch_blocking:
    sub rsp, 8
    mov eax, SYS_read
    mov edi, STDIN_FD
    lea rsi, [rsp]
    mov edx, 1
    syscall
    test rax, rax
    js 8f
    cmp rax, 1
    jne 6f
    movzx ecx, byte ptr [rsp]
    mov eax, 1
    add rsp, 8
    ret
	6:
    xor eax, eax
    add rsp, 8
    ret
	8:
    add rsp, 8
    ret

