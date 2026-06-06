; ========================================================================
; DNAOS v3.3 - DNAsm Core (x86-64 Assembly)
; ========================================================================
; 递砖机认知操作系统 · 分子计算核心
; NASM语法 · Linux x86-64 · System V AMD64 ABI
;
; 架构说明:
;   - 64个试管(tubes): 32位有符号整数数组,索引0-63
;   - 特殊寄存器: t0=tubes[0](累加器), t1=tubes[1](计数器/操作数)
;                t2=tubes[2](状态), t3=tubes[3](I/O缓冲)
;   - 程序计数器: r12 (64位,指向当前操作码)
;   - 调用栈: 64层,用于CALL/RET
;
; 操作码定义 (每个1字节,部分带1字节参数):
;   0x00-0x3F : LOAD tube    -> t0 = tubes[tube]
;   0x40-0x7F : STORE tube   -> tubes[tube] = t0
;   0x80      : A (Add)      -> t0 = t0 + t1
;   0x81      : T (Subtract) -> t0 = t0 - t1
;   0x82      : C (Multiply) -> t0 = t0 * t1
;   0x83      : G (Divide)   -> t0 = t0 / t1
;   0x84      : LOOP addr    -> t1--; if(t1>0) PC=addr
;   0x85      : TEST         -> if(t0==0) skip next 2-byte instruction
;   0x86      : JMP addr     -> PC = addr
;   0x87      : CALL addr    -> push PC; PC = addr
;   0x88      : RET          -> pop PC
;   0x89      : IN           -> t0 = read number from stdin
;   0x8A      : OUT          -> print t0 to stdout
;   0x8B      : NOP          -> no operation
;   0xFF      : HALT         -> stop execution
; ========================================================================

; =========================================================================
; 数据段
; =========================================================================
section .data
    align 4

    ; -----------------------------------------------------------------
    ; 64个试管 (每个4字节,共256字节)
    ; 初始值: tube[0]=0(t0/累加器), tube[1]=0(t1/计数器)
    ;         tube[2]=5(n/乘数), tube[3]=5(counter/循环计数)
    ;         tube[4]=1(const), tube[5]=5(n_init)
    ;         tube[6]=5(counter_init), tube[7]=0(result存储)
    ; -----------------------------------------------------------------
    tubes:      dd 0, 0, 5, 5, 1, 5, 5, 0
                times 56 dd 0

    ; -----------------------------------------------------------------
    ; 预加载程序: 计算 5! = 120 (阶乘)
    ;
    ; 设计说明:
    ;   tube[7] 用作result存储 (因为t0=tube[0]每次LOAD都会被覆盖)
    ;   tube[2] = n (乘数)
    ;   tube[3] = counter (循环计数器)
    ;   tube[4] = 1 (常数1,用于递减)
    ;
    ; 程序源码 (DNAsm汇编):
    ;   LOAD 4          ; t0 = 1
    ;   STORE 7         ; result = 1 (保存到tube[7],避免被LOAD覆盖)
    ;   LOAD 5          ; t0 = 5
    ;   STORE 2         ; n = 5
    ;   LOAD 6          ; t0 = 5
    ;   STORE 3         ; counter = 5
    ; loop_test:
    ;   LOAD 3          ; t0 = counter
    ;   TEST            ; if counter==0, skip JMP body
    ;   JMP body        ; if counter!=0, goto body
    ;   JMP end         ; if counter==0, goto end
    ; body:
    ;   LOAD 2          ; t0 = n
    ;   STORE 1         ; t1 = n (set C operand)
    ;   LOAD 7          ; t0 = result
    ;   C               ; result *= n
    ;   STORE 7         ; save result
    ;   LOAD 4          ; t0 = 1
    ;   STORE 1         ; t1 = 1
    ;   LOAD 2          ; t0 = n
    ;   T               ; n = n - 1
    ;   STORE 2         ; save n
    ;   LOAD 4          ; t0 = 1
    ;   STORE 1         ; t1 = 1
    ;   LOAD 3          ; t0 = counter
    ;   T               ; counter = counter - 1
    ;   STORE 3         ; save counter
    ;   JMP loop_test   ; goto loop_test
    ;   NOP x5          ; padding (alignment)
    ; end:
    ;   LOAD 7          ; t0 = result
    ;   OUT             ; print result
    ;   HALT            ; stop
    ;
    ; 机器码 (37字节):
    ; -----------------------------------------------------------------
    program:    db 0x04, 0x47                      ; 0x00: LOAD 4, STORE 7 (result=1)
                db 0x05, 0x42                      ; 0x02: LOAD 5, STORE 2 (n=5)
                db 0x06, 0x43                      ; 0x04: LOAD 6, STORE 3 (counter=5)
                db 0x03, 0x85                      ; 0x06: LOAD 3, TEST
                db 0x86, 0x0C                      ; 0x08: JMP body(0x0C)
                db 0x86, 0x22                      ; 0x0A: JMP end(0x22)
                db 0x02, 0x41                      ; 0x0C: LOAD 2, STORE 1 (t1=n)
                db 0x07, 0x82                      ; 0x0E: LOAD 7, C (result*=n)
                db 0x47                            ; 0x10: STORE 7 (save result)
                db 0x04, 0x41, 0x02, 0x81, 0x42   ; 0x11: n--
                db 0x04, 0x41, 0x03, 0x81, 0x43   ; 0x16: counter--
                db 0x86, 0x06                      ; 0x1B: JMP loop_test(0x06)
                db 0x8B, 0x8B, 0x8B, 0x8B, 0x8B   ; 0x1D: NOP padding x5
                db 0x07, 0x8A, 0xFF                ; 0x22: end: LOAD 7, OUT, HALT
    prog_len:   equ $ - program

    ; -----------------------------------------------------------------
    ; 字符串常量
    ; -----------------------------------------------------------------
    welcome:    db "========================================", 10
                db "  DNAOS v3.3 Core", 10
                db "  Bricklayer continues. 0.", 10
                db "========================================", 10
                db "Running preloaded program: factorial 5!", 10
                db "----------------------------------------", 10, 0
    welcome_len: equ $ - welcome - 1      ; -1 to exclude trailing null

    result_msg: db "Result: ", 0
    result_msg_len: equ $ - result_msg - 1

    end_msg:    db "----------------------------------------", 10
                db "[Program End - DNAOS v3.3]", 10, 0
    end_msg_len: equ $ - end_msg - 1

    newline:    db 10

; =========================================================================
; BSS段 (未初始化数据)
; =========================================================================
section .bss
    align 8

    call_stack: resq 64             ; 调用栈: 64个返回地址
    call_sp:    resq 1              ; 调用栈指针 (0-64)
    input_buf:  resb 64             ; 输入缓冲区
    number_buf: resb 32             ; 数字打印缓冲区

; =========================================================================
; 代码段
; =========================================================================
section .text
global _start

; ========================================================================
; 入口点 _start
; ========================================================================
_start:
    ; 初始化调用栈指针为0
    mov     qword [call_sp], 0

    ; 打印欢迎信息
    mov     rsi, welcome
    call    print_string

    ; 初始化程序计数器 PC = 0
    xor     r12, r12

    ; 进入取指-译码-执行循环
    jmp     fetch

; ========================================================================
; 取指-译码-执行 (Fetch-Decode-Execute)
; ========================================================================
fetch:
    ; 检查PC是否越界
    cmp     r12, prog_len
    jae     prog_done

    ; ---- 取指 (Fetch) ----
    ; 从program[PC]读取1字节操作码
    movzx   eax, byte [program + r12]   ; eax = opcode (零扩展)
    inc     r12                         ; PC++ (指向下一个位置)

    ; ---- 译码 (Decode) ----
    ; 根据操作码范围分发到对应处理器

    ; 范围1: 0x00-0x3F -> LOAD
    cmp     al, 0x3F
    jbe     op_load

    ; 范围2: 0x40-0x7F -> STORE
    cmp     al, 0x7F
    jbe     op_store

    ; 范围3: 0x80-0x88 -> A/T/C/G/LOOP/TEST/JMP/CALL/RET
    cmp     al, 0x88
    jbe     .dispatch_special

    ; 范围4: 0x89-0x8B -> IN/OUT/NOP
    cmp     al, 0x8B
    jbe     .dispatch_io

    ; 0xFF -> HALT
    cmp     al, 0xFF
    je      op_halt

    ; 其他: 未知操作码 -> NOP
    jmp     op_nop

; ------------------------------------------------------------------------
; 特殊操作码分发 (0x80-0x88)
; 使用跳转表实现O(1)分发
; ------------------------------------------------------------------------
.dispatch_special:
    ; al = 0x80..0x88, 计算跳转表索引
    push    rbx
    movzx   ebx, al
    sub     ebx, 0x80                   ; ebx = 0..8
    shl     ebx, 3                      ; ebx *= 8 (每个表项8字节)
    pop     rax                         ; 恢复rax (操作码已在ebx计算中使用)
    ; 注意: 我们需要保持操作码相关信息
    ; 重新加载操作码到al
    movzx   eax, byte [program + r12 - 1] ; 重新取操作码
    sub     al, 0x80
    movzx   rax, al
    jmp     [rel jump_table + rax * 8]

; ------------------------------------------------------------------------
; I/O操作码分发 (0x89-0x8B)
; ------------------------------------------------------------------------
.dispatch_io:
    sub     al, 0x89                    ; al = 0(IN), 1(OUT), 2(NOP)
    jz      op_in
    dec     al
    jz      op_out
    jmp     op_nop

; ========================================================================
; 跳转表 (用于0x80-0x88操作码的O(1)分发)
; ========================================================================
section .data
    align 8
jump_table:
    dq op_a         ; 0x80: A (Add)
    dq op_t         ; 0x81: T (Subtract)
    dq op_c         ; 0x82: C (Multiply)
    dq op_g         ; 0x83: G (Divide)
    dq op_loop      ; 0x84: LOOP
    dq op_test      ; 0x85: TEST
    dq op_jmp       ; 0x86: JMP
    dq op_call      ; 0x87: CALL
    dq op_ret       ; 0x88: RET

section .text

; ========================================================================
; 操作码处理器: LOAD (0x00-0x3F)
; 功能: t0 = tubes[tube_index]
; 编码: opcode = tube_index (0-63)
; ========================================================================
op_load:
    and     eax, 0x3F                   ; tube_index = opcode & 0x3F
    mov     ebx, [tubes + rax * 4]      ; ebx = tubes[tube_index]
    mov     [tubes], ebx                ; t0 = ebx
    jmp     fetch

; ========================================================================
; 操作码处理器: STORE (0x40-0x7F)
; 功能: tubes[tube_index] = t0
; 编码: opcode = 0x40 | tube_index
; ========================================================================
op_store:
    and     eax, 0x3F                   ; tube_index = opcode & 0x3F
    mov     ebx, [tubes]                ; ebx = t0
    mov     [tubes + rax * 4], ebx      ; tubes[tube_index] = t0
    jmp     fetch

; ========================================================================
; 操作码处理器: A - 碱基加法 (0x80)
; 功能: t0 = t0 + t1
; 说明: A代表腺嘌呤(Adenine),执行加法运算
; ========================================================================
op_a:
    mov     eax, [tubes]                ; eax = t0
    add     eax, [tubes + 4]            ; eax += t1
    mov     [tubes], eax                ; t0 = eax
    jmp     fetch

; ========================================================================
; 操作码处理器: T - 碱基减法 (0x81)
; 功能: t0 = t0 - t1
; 说明: T代表胸腺嘧啶(Thymine),执行减法运算
; ========================================================================
op_t:
    mov     eax, [tubes]                ; eax = t0
    sub     eax, [tubes + 4]            ; eax -= t1
    mov     [tubes], eax                ; t0 = eax
    jmp     fetch

; ========================================================================
; 操作码处理器: C - 碱基乘法 (0x82)
; 功能: t0 = t0 * t1
; 说明: C代表胞嘧啶(Cytosine),执行乘法运算
; ========================================================================
op_c:
    mov     eax, [tubes]                ; eax = t0
    imul    eax, dword [tubes + 4]      ; eax *= t1 (有符号乘法)
    mov     [tubes], eax                ; t0 = eax
    jmp     fetch

; ========================================================================
; 操作码处理器: G - 碱基除法 (0x83)
; 功能: t0 = t0 / t1
; 说明: G代表鸟嘌呤(Guanine),执行除法运算
; ========================================================================
op_g:
    mov     ebx, [tubes + 4]            ; ebx = t1 (除数)
    test    ebx, ebx
    jz      .div_zero                   ; 除零检查
    mov     eax, [tubes]                ; eax = t0 (被除数)
    cdq                                 ; 符号扩展 edx:eax
    idiv    ebx                         ; eax = edx:eax / ebx
    mov     [tubes], eax                ; t0 = 商
    jmp     fetch
.div_zero:
    ; 除零错误: 设置t0 = 0,继续执行
    mov     dword [tubes], 0
    jmp     fetch

; ========================================================================
; 操作码处理器: LOOP (0x84)
; 功能: t1--; if (t1 > 0, signed) PC = addr
; 参数: 下1字节为绝对跳转地址
; ========================================================================
op_loop:
    ; 读取地址参数
    movzx   ebx, byte [program + r12]   ; ebx = addr
    inc     r12                         ; consume parameter

    ; t1-- (有符号递减)
    dec     dword [tubes + 4]           ; t1--

    ; 检查t1 > 0 (有符号比较)
    mov     eax, [tubes + 4]
    cmp     eax, 0
    jg      .loop_jump                  ; t1 > 0, 跳转
    jmp     fetch                       ; t1 <= 0, 继续

.loop_jump:
    mov     r12, rbx                    ; PC = addr
    jmp     fetch

; ========================================================================
; 操作码处理器: TEST (0x85)
; 功能: if (t0 == 0) 跳过下一条2字节指令
; 说明: 用于构造条件跳转。典型用法:
;         TEST       ; if t0==0, skip JMP body
;         JMP body   ; if t0!=0, goto body
;         JMP end    ; if t0==0, goto end
; ========================================================================
op_test:
    mov     eax, [tubes]                ; eax = t0
    test    eax, eax
    jnz     fetch                       ; t0 != 0, 正常执行下一条

    ; t0 == 0, 跳过下一条2字节指令
    add     r12, 2                      ; PC += 2 (跳过操作码+参数)
    jmp     fetch

; ========================================================================
; 操作码处理器: JMP (0x86)
; 功能: PC = addr (无条件跳转)
; 参数: 下1字节为绝对跳转地址
; ========================================================================
op_jmp:
    movzx   r12, byte [program + r12]   ; PC = addr
    jmp     fetch

; ========================================================================
; 操作码处理器: CALL (0x87)
; 功能: 调用子程序 - push PC, PC = addr
; 参数: 下1字节为绝对跳转地址
; ========================================================================
op_call:
    ; 读取目标地址
    movzx   rbx, byte [program + r12]   ; rbx = addr
    inc     r12                         ; consume parameter, r12 = return addr

    ; 保存返回地址到调用栈
    mov     rcx, [call_sp]
    mov     [call_stack + rcx * 8], r12 ; call_stack[sp] = return address
    inc     qword [call_sp]             ; sp++

    ; 跳转
    mov     r12, rbx
    jmp     fetch

; ========================================================================
; 操作码处理器: RET (0x88)
; 功能: 从子程序返回 - pop PC
; ========================================================================
op_ret:
    dec     qword [call_sp]             ; sp--
    mov     rcx, [call_sp]
    mov     r12, [call_stack + rcx * 8] ; PC = return address
    jmp     fetch

; ========================================================================
; 操作码处理器: IN (0x89)
; 功能: 从标准输入读取32位有符号整数到t0
; ========================================================================
op_in:
    call    read_number
    mov     [tubes], eax                ; t0 = 读取的数字
    jmp     fetch

; ========================================================================
; 操作码处理器: OUT (0x8A)
; 功能: 输出t0到标准输出 (打印整数+换行)
; ========================================================================
op_out:
    mov     eax, [tubes]                ; eax = t0
    call    print_number
    call    print_newline
    jmp     fetch

; ========================================================================
; 操作码处理器: NOP (0x8B)
; 功能: 空操作 (No Operation)
; ========================================================================
op_nop:
    jmp     fetch

; ========================================================================
; 操作码处理器: HALT (0xFF)
; 功能: 停止执行,转移到程序结束处理
; ========================================================================
op_halt:
    jmp     prog_done

; ========================================================================
; 程序结束处理
; ========================================================================
prog_done:
    ; 打印 "Result: "
    mov     rsi, result_msg
    call    print_string

    ; 打印最终结果 (t0)
    mov     eax, [tubes]
    call    print_number
    call    print_newline

    ; 打印结束消息
    mov     rsi, end_msg
    call    print_string

    ; 退出程序 (sys_exit)
    mov     rax, 60                     ; syscall: exit
    xor     rdi, rdi                    ; status = 0
    syscall


; =========================================================================
; 辅助函数
; =========================================================================

; ========================================================================
; 函数: print_string
; 功能: 打印以null结尾的字符串到stdout
; 参数: RSI = 字符串地址 (C风格,以0结尾)
; 破坏: RAX, RDX, RDI
; ========================================================================
print_string:
    push    rax
    push    rdx
    push    rdi
    push    rsi

    ; 计算字符串长度 (找到null终止符)
    mov     rdx, rsi                    ; rdx = 起始地址
    mov     rdi, rsi
.count_loop:
    cmp     byte [rdi], 0
    je      .got_length
    inc     rdi
    jmp     .count_loop
.got_length:
    sub     rdi, rdx                    ; rdi = 长度
    test    rdi, rdi
    jz      .done                       ; 空字符串,不打印

    ; sys_write(stdout, rsi, length)
    mov     rax, 1                      ; syscall: write
    mov     rdx, rdi                    ; length
    mov     rdi, 1                      ; fd = stdout
    ; rsi already points to string
    syscall

.done:
    pop     rsi
    pop     rdi
    pop     rdx
    pop     rax
    ret

; ========================================================================
; 函数: print_newline
; 功能: 打印换行符
; ========================================================================
print_newline:
    push    rax
    push    rdx
    push    rsi
    push    rdi

    mov     rax, 1                      ; syscall: write
    mov     rdi, 1                      ; stdout
    mov     rsi, newline                ; "\n"
    mov     rdx, 1                      ; length = 1
    syscall

    pop     rdi
    pop     rsi
    pop     rdx
    pop     rax
    ret

; ========================================================================
; 函数: print_number
; 功能: 打印32位有符号整数到stdout
; 参数: EAX = 要打印的数字
; ========================================================================
print_number:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    rax

    mov     ebx, eax                    ; ebx = number
    mov     rsi, number_buf + 31        ; rsi = buffer end
    mov     byte [rsi], 0               ; null terminate
    mov     ecx, 10                     ; divisor = 10

    ; ---- 处理0 ----
    test    ebx, ebx
    jnz     .check_negative
    dec     rsi
    mov     byte [rsi], '0'
    mov     rdx, 1
    jmp     .do_print

.check_negative:
    ; ---- 处理负数 ----
    test    ebx, ebx
    jns     .convert                    ; 正数,直接转换

    ; 负数: 先打印负号
    neg     ebx                         ; ebx = -ebx (转为正数)
    push    rbx
    mov     byte [rsp-1], '-'           ; 在栈上构造 '-' 字符
    mov     rax, 1                      ; sys_write
    mov     rdi, 1                      ; stdout
    lea     rsi, [rsp-1]                ; 负号地址
    mov     rdx, 1                      ; length = 1
    syscall
    pop     rbx
    mov     rsi, number_buf + 31        ; 重置缓冲区指针

.convert:
    ; ---- 数字转字符串 (从末尾向前填充) ----
.convert_loop:
    test    ebx, ebx
    jz      .calc_length
    mov     eax, ebx
    xor     edx, edx
    div     ecx                         ; eax = ebx / 10, edx = ebx % 10
    add     dl, '0'                     ; 转为ASCII
    dec     rsi
    mov     [rsi], dl                   ; 存入缓冲区
    mov     ebx, eax
    jmp     .convert_loop

.calc_length:
    ; 计算字符串长度
    lea     rdx, [number_buf + 31]
    sub     rdx, rsi                    ; rdx = length

.do_print:
    ; ---- 打印数字字符串 ----
    mov     rax, 1                      ; sys_write
    mov     rdi, 1                      ; stdout
    syscall

    pop     rax
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ========================================================================
; 函数: read_number
; 功能: 从标准输入读取32位有符号整数
; 返回: EAX = 读取的数字
; 说明: 读取一行,解析开头的整数,支持负号
; ========================================================================
read_number:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    ; ---- 从stdin读取一行 ----
    mov     rax, 0                      ; syscall: read
    mov     rdi, 0                      ; stdin
    mov     rsi, input_buf
    mov     rdx, 63                     ; 最多读63字节
    syscall

    ; ---- 解析整数 ----
    mov     rsi, input_buf              ; rsi = 缓冲区指针
    xor     ebx, ebx                    ; result = 0
    xor     ecx, ecx                    ; ecx = sign flag (0=正,1=负)

    ; 跳过前导空白字符
.skip_space:
    mov     al, [rsi]
    cmp     al, ' '
    je      .next_char
    cmp     al, 9                       ; tab
    je      .next_char
    cmp     al, 10                      ; newline
    je      .next_char
    cmp     al, 13                      ; carriage return
    je      .next_char
    jmp     .check_sign
.next_char:
    inc     rsi
    jmp     .skip_space

.check_sign:
    ; 检查负号
    mov     al, [rsi]
    cmp     al, '-'
    jne     .parse_digits
    mov     ecx, 1                      ; sign = 1 (negative)
    inc     rsi

.parse_digits:
    xor     edx, edx                    ; digit count = 0
.digit_loop:
    mov     al, [rsi]
    cmp     al, '0'
    jb      .done_parsing
    cmp     al, '9'
    ja      .done_parsing

    sub     al, '0'                     ; al = digit value (0-9)
    imul    ebx, 10                     ; result *= 10
    add     ebx, eax                    ; result += digit
    inc     edx                         ; digit count++
    inc     rsi
    jmp     .digit_loop

.done_parsing:
    ; 如果没有读到任何数字,返回0
    test    edx, edx
    jnz     .apply_sign
    xor     ebx, ebx

.apply_sign:
    mov     eax, ebx
    test    ecx, ecx                    ; 检查sign flag
    jz      .positive
    neg     eax                         ; 应用负号
.positive:

    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ========================================================================
; 文件结束
; ========================================================================
