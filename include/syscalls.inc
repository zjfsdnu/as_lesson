; ===========================================================================
; syscalls.inc —— x86-64 Linux 系统调用号与常用常量
;
; 用法：  %include "syscalls.inc"
;   （Makefile 里已经加了 -I ../include，所以直接写文件名即可）
;
; 说明：
;   系统调用号查表：/usr/include/x86_64-linux-gnu/asm/unistd_64.h
;   也可以在终端执行：ausyscall --dump | head -30   （装了 auditd 的话）
;
;   x86-64 syscall 调用约定（与 C 函数调用不同！）
;     rax = 系统调用号
;     rdi, rsi, rdx, r10, r8, r9 = 第 1..6 个参数（注意第 4 个是 r10，不是 rcx）
;     syscall 指令进入内核；返回值放在 rax
;     内核会破坏 rcx 和 r11 两个寄存器（它们保存 rip/rflags），别指望它们还在
; ===========================================================================

%ifndef SYSCALLS_INC
%define SYSCALLS_INC

; ---- 文件与 I/O -----------------------------------------------------------
%define SYS_read            0
%define SYS_write           1
%define SYS_open            2
%define SYS_close           3
%define SYS_stat            4
%define SYS_fstat           5
%define SYS_lstat           6
%define SYS_poll            7
%define SYS_lseek           8
%define SYS_mmap            9
%define SYS_mprotect       10
%define SYS_munmap         11
%define SYS_brk            12
%define SYS_ioctl          16
%define SYS_pread64        17
%define SYS_pwrite64       18
%define SYS_readv          19
%define SYS_writev         20
%define SYS_access         21
%define SYS_pipe           22
%define SYS_dup            32
%define SYS_dup2           33
%define SYS_nanosleep      35
%define SYS_getpid         39
%define SYS_sendfile       40
%define SYS_socket         41
%define SYS_connect        42
%define SYS_accept         43
%define SYS_sendto         44
%define SYS_recvfrom       45
%define SYS_fcntl          72
%define SYS_fsync          74
%define SYS_getcwd         79
%define SYS_chdir          80
%define SYS_mkdir          83
%define SYS_unlink         87
%define SYS_readlink       89
%define SYS_chmod          90
%define SYS_gettimeofday   96
%define SYS_getuid        102
%define SYS_getgid        104
%define SYS_setuid        105
%define SYS_geteuid       107
%define SYS_getegid       108
%define SYS_arch_prctl    158
%define SYS_gettid        186
%define SYS_futex         202
%define SYS_getdents64    217
%define SYS_set_tid_address 218
%define SYS_clock_gettime 228
%define SYS_exit_group    231
%define SYS_openat        257
%define SYS_newfstatat    262
%define SYS_unlinkat      263
%define SYS_readlinkat    267
%define SYS_utimensat     280
%define SYS_getrandom     318
%define SYS_execve        59
%define SYS_fork          57
%define SYS_wait4         61
%define SYS_kill          62
%define SYS_exit          60

; ---- 标准文件描述符 -------------------------------------------------------
%define STDIN               0
%define STDOUT              1
%define STDERR              2

; ---- open(2) 的 flags（O_RDONLY 是 0，所以要用 0q 或直接 0） -------------
%define O_RDONLY         0o0
%define O_WRONLY         0o1
%define O_RDWR           0o2
%define O_CREAT        0o100
%define O_EXCL         0o200
%define O_TRUNC       0o1000
%define O_APPEND      0o2000

; ---- lseek(2) 的 whence ---------------------------------------------------
%define SEEK_SET            0
%define SEEK_CUR            1
%define SEEK_END            2

; ---- 常用 ASCII -----------------------------------------------------------
%define LF                 10    ; '\n'
%define TAB                 9    ; '\t'
%define SPACE              32    ; ' '
%define NUL                 0

; ---- 退出状态码 -----------------------------------------------------------
%define EXIT_SUCCESS        0
%define EXIT_FAILURE        1

%endif ; SYSCALLS_INC
