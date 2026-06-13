; ============================================================================
; DNAOS v3.5 M11 v22 — scheduler 照抄 xv6 swtch.S 极简
;
; v17-v21 撞穿真根因: 我用 pushad (8 GPR) + iret + jmp label = 错
; v22 修法 (照抄 xv6 swtch.S 11 行):
;   1. 只保存 4 callee-saved (EBP/EBX/ESI/EDI)
;   2. 不保存 EFLAGS (caller 已经 sti)
;   3. 不保存段寄存器 (同段)
;   4. ret 跳新任务 return 地址 (新任务栈预装好 return address)
;
; 设计:
;   task_A 栈预装好:
;     [0xA0EFC] = 0x00000000  (EDI 还原)
;     [0xA0EF0] = 0x00000000  (ESI)
;     [0xA0EE4] = 0x00000000  (EBX)
;     [0xA0EE0] = 0x00000000  (EBP)
;     [0xA0EDC] = TASK_A_PHYS  (return address = task_A 物理, swtch ret 跳)
;   初始 ESP = 0xA0EFC (push 4 dword 后 ESP=0xA0EEC, pop 后 ESP=0xA0EFC 顶, ret pop = 0xA0EDC)
;
;   swtch 切任务: push 4 regs + movl esp, [old] + movl [new], esp + pop 4 regs + ret
; ============================================================================

BITS 16

org 0x10000

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov dx, 0x3F8
    mov al, 'K'
    out dx, al

; 装 PGD[0] + 9 PTE (加 task_A 0xA 页 + task_B 0xB 页 + 0x9F kernel 栈)
    mov ax, 0x1100
    mov es, ax
    xor di, di
    mov cx, 0x800
    xor ax, ax
    rep stosw

    mov word [es:0], 0x2003
    mov word [es:2], 0x0001
    mov word [es:0x1040], 0x0003
    mov word [es:0x1042], 0x0001
    mov word [es:0x12E0], 0xB803
    mov word [es:0x12E2], 0x000B
    mov word [es:0x123C], 0xF003
    mov word [es:0x123E], 0x0008
    mov word [es:0x1240], 0x0003
    mov word [es:0x1242], 0x0009
    mov word [es:0x1244], 0x0003
    mov word [es:0x1246], 0x0009
    mov word [es:0x1280], 0x0003
    mov word [es:0x1282], 0x000A
    mov word [es:0x12C0], 0x0003
    mov word [es:0x12C2], 0x000B
    mov word [es:0x127C], 0x0003
    mov word [es:0x127E], 0x0009
    mov word [es:0xA000], 0x0003    ; PGT#1[0xA0] @ 0x11A000 = 0x000A0003 (task_A 物理页)
    mov word [es:0xA002], 0x000A
    mov word [es:0xA400], 0x0003    ; PGT#1[0xB0] @ 0x11A400 = 0x000B0003 (task_B 物理页)
    mov word [es:0xA402], 0x000B
    mov word [es:0x4], 0xA003       ; PGD[1] = 0x0001A003 (PGT#1 = 0x11A000)
    mov word [es:0x6], 0x0001

; 装 GDT 段
    mov ax, 0x1020
    mov ds, ax

    mov bx, gdt_start_offset
    mov dword [bx+8],  0x0000FFFF
    mov dword [bx+12], 0x00CF9A00
    mov dword [bx+16], 0x0000FFFF
    mov dword [bx+20], 0x00CF9200

    mov dx, 0x3F8
    mov al, 'G'
    out dx, al

%define GDT_START_PHYS (0x10200 + gdt_start_offset)

    mov bx, gdt_desc_offset
    mov word [bx+0], 0x0017
    mov word [bx+2], (GDT_START_PHYS & 0xFFFF)
    mov word [bx+4], (GDT_START_PHYS >> 16)

    lgdt [bx]

; 16→32 切
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    db 0x66, 0xEA
    dd pm_entry_phys
    dw 0x0008

; ============================================================================
; 32-bit PM 段
; ============================================================================
BITS 32

pm_entry_phys equ 0x10000 + (pm_entry - 0x10000)

pm_entry:
    mov dx, 0x3F8
    mov al, 'P'
    out dx, al

; 32-bit 段设
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000

    mov dx, 0x3F8
    mov al, 'X'
    out dx, al

; 分页开
    mov eax, 0x11000
    mov cr3, eax

    mov dx, 0x3F8
    mov al, '3'
    out dx, al

    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    mov dx, 0x3F8
    mov al, '!'
    out dx, al

; IDT 装 scheduler + PS2 handler
    mov edi, 0x10186

%define SCHED_PHYS (0x10000 + (scheduler - 0x10000))
%define PS2_PHYS   (0x10000 + (ps2_handler - 0x10000))

    mov eax, SCHED_PHYS
    mov word [edi + 0x100 + 0], ax
    mov word [edi + 0x100 + 2], 0x0008
    mov word [edi + 0x100 + 4], 0x8E00
    shr eax, 16
    mov word [edi + 0x100 + 6], ax

    mov eax, PS2_PHYS
    mov word [edi + 0x108 + 0], ax
    mov word [edi + 0x108 + 2], 0x0008
    mov word [edi + 0x108 + 4], 0x8E00
    shr eax, 16
    mov word [edi + 0x108 + 6], ax

    mov eax, 0x10186
    mov word [0x10986 + 2], ax
    shr eax, 16
    mov word [0x10986 + 4], ax
    mov word [0x10986 + 0], 0x07FF
    mov word [0x10986 + 6], 0

    lidt [0x10986]

    mov dx, 0x3F8
    mov al, 'I'
    out dx, al

; 8259 PIC 重映射
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    mov al, 0xFE
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al

    mov dx, 0x3F8
    mov al, 'A'
    out dx, al

; PIT 100Hz
    mov al, 0x36
    out 0x43, al
    mov al, 0x87
    out 0x40, al
    mov al, 0x2D
    out 0x40, al

; ----------------------------------------------------------------------------
; 初始化 2 任务栈 (照 xv6 swtch ret 跳)
; task_A 栈 (kernel virtual 0xA0000-0xAFFFF, PGT#1[0xA0]=0x000A0003, PGT#1[0xB0]=0x000B0003)
%define TASK_A_PHYS (0x10000 + (task_A - 0x10000))
%define TASK_B_PHYS (0x10000 + (task_B - 0x10000))

; task_A 栈布局 (从高到低):
;   0xA0F00: ESP 初始值 (scheduler 入口 ESP=0xA0F00, 跑前没 push 任何)
;   swtch 调用前 ESP=0xA0F00, CPU push return address, ESP=0xA0EFC
;   swtch 跑: push 4 regs (EBP/EBX/ESI/EDI = 16 字节), ESP=0xA0EEC
;            movl esp, [old], movl [new], esp
;            pop 4 regs, ESP=0xA0EFC
;            ret pop return address, ESP=0xA0F00, 跳 return address
;
; 新任务栈预装好: 4 callee-saved + return address (顺序反过来 push, swtch 跑 pop)
;   0xA0EDC = return address (TASK_A_PHYS, swtch ret 跳)
;   0xA0EE0 = EBP saved
;   0xA0EE4 = EBX saved
;   0xA0EE8 = ESI saved
;   0xA0EEC = EDI saved
;   ESP 初始 = 0xA0EFC (跑过 pop 4 regs 后 ESP=0xA0EFC, ret pop 0xA0EDC, ESP=0xA0F00)

; 装 task_A 栈 (从高到低 push)
;   高位 -> 0xA0F00 (ESP 初始, swtch 跑完 ESP=这里)
;   0xA0EFC -> 0x00000000 (EDI, 还原)
;   0xA0EF8 -> 0x00000000 (ESI)
;   0xA0EF4 -> 0x00000000 (EBX)
;   0xA0EF0 -> 0x00000000 (EBP)
;   0xA0EEC -> TASK_A_PHYS (return address, swtch ret 跳)
;   0xA0EE8 -> 0x00000000 (padding, 4 字节对齐, swtch 不会跑到)

    mov dword [0xA0EFC], 0x00000000  ; EDI
    mov dword [0xA0EF8], 0x00000000  ; ESI
    mov dword [0xA0EF4], 0x00000000  ; EBX
    mov dword [0xA0EF0], 0x00000000  ; EBP
    mov dword [0xA0EEC], TASK_A_PHYS ; return address

    mov dword [0xB0EFC], 0x00000000
    mov dword [0xB0EF8], 0x00000000
    mov dword [0xB0EF4], 0x00000000
    mov dword [0xB0EF0], 0x00000000
    mov dword [0xB0EEC], TASK_B_PHYS

; 任务 context 指针 (swtch old/new 参数)
    mov dword [0x90030], 0x000A0EFC  ; task_A context 指针 (4 dword 起始位置)
    mov dword [0x90040], 0x000B0EFC  ; task_B context 指针
    mov dword [0x90050], 0           ; tick_count
    mov byte [0x90060], 0            ; current_task (0=A, 1=B)

    sti

    mov dx, 0x3F8
    mov al, 'S'
    out dx, al

; 32-bit VGA 写
    mov word [0xB8000], 0x0F50

    mov dx, 0x3F8
    mov al, 'V'
    out dx, al

; 跳到 task_A (用 swtch 从"main 栈"切到 task_A)
; main 栈预装好: 4 callee-saved + return address (跟 task_A 一样)
;   0x90EFC -> 0x00000000 (EDI)
;   0x90EF8 -> 0x00000000 (ESI)
;   0x90EF4 -> 0x00000000 (EBX)
;   0x90EF0 -> 0x00000000 (EBP)
;   0x90EEC -> TASK_A_PHYS (return address, swtch ret 跳)
;   0x90F00 (ESP 初始, swtch 跑完 ESP=这里)
; 然后 swtch 跑: push 4 regs, movl esp, [0x90030], movl [0x90040], esp (task_A 栈 = 0xA0EFC)
;                pop 4 regs (从 task_A 栈), ret pop 0xA0EEC = TASK_A_PHYS, 跳 task_A
; 然后 swtch 跑第二次: push 4 regs, movl esp, [0x90030] (保存 main 栈 0x90EEC = swtch 跑过后的 ESP)
;                注意: [0x90030] 在 main 是 0x90EEC, 切回 main 时 ESP=0x90EEC, 跑过 pop 4 regs + ret
;                ret 跳 [0x90EEC] = TASK_A_PHYS (装的是 task_A return address, **错! 应装 swtch 调用 return address**)
;
; 等等, 我想错了 — **main 跳到 task_A 后, task_A 跑 jmp task_A 死循环, 不返回**
; main 跳 task_A 是"**第一次**调度", 之后 scheduler 切回 main 不会发生
; 简化: main 跳 task_A 直接 jmp task_A (不用 swtch), 然后 task_A 跑过 PIT 触发 scheduler
;       scheduler 切到 task_B, task_B 跑过 PIT 触发 scheduler, scheduler 切到 task_A
;       循环跑, main 不会回到

    jmp task_A

.wait:
    hlt
    jmp .wait

; ============================================================================
; swtch (照抄 xv6 swtch.S 11 行)
; void swtch(uint32_t *old, uint32_t new);
;   old: 4 dword 起始位置 (push 4 callee-saved 后 ESP 存到这里)
;   new: 新栈 4 dword 起始位置
; ============================================================================
swtch:
    mov eax, [esp+4]        ; 旧栈 4 dword 起始位置
    mov edx, [esp+8]        ; 新栈 4 dword 起始位置
    push ebp
    push ebx
    push esi
    push edi
    mov [eax], esp          ; 保存旧 ESP
    mov esp, edx            ; 装新 ESP
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret                     ; 跳新任务 return address

; ============================================================================
; scheduler (IRQ0, INT 0x20) — 用 swtch 切任务
;   入口: CPU push EIP+CS+EFLAGS (12 字节) 到 task 栈
;   跑: EOI + tick_count + 切任务标记
;   切任务: swtch(&old, new) — 切到新任务栈
;   不切任务: 还原 task 栈 (12 字节 pop 还原 EIP+CS+EFLAGS) + iret
; ============================================================================
scheduler:
    ; 还原 task 栈 (CPU push 12 字节到 task 栈)
    ; scheduler 入口 ESP = task_esp_initial - 12
    ; 简化: scheduler 入口**不**读 task 栈, 跑前**不**还原 ESP
    ;       跑过 EOI + tick_count + 切任务标记
    ;       切任务: swtch(&[0x90030], [0x90040]) — 切到新任务栈
    ;       不切任务: add esp, 12 + iret — 还原 task 栈

    ; 1. EOI
    mov al, 0x20
    out 0x20, al

    ; 2. tick_count++
    mov eax, [0x90050]
    inc eax
    mov [0x90050], eax

    ; 3. 串口 'C'
    mov dx, 0x3F8
    mov al, 'C'
    out dx, al

    ; 4. VGA tick 数字
    mov edx, eax
    and edx, 0xF
    add dl, '0'
    mov byte [0xB8004], dl
    mov byte [0xB8005], 0x07

    ; 5. 5 ticks 切任务
    mov eax, [0x90050]
    test eax, 0x04
    jz .sched_iret

    ; 切任务
    mov al, [0x90060]
    xor al, 1
    mov [0x90060], al

    ; 写 'A'/'B' marker
    test al, 1
    jz .mark_A
    mov al, 'B'
    jmp .mark
.mark_A:
    mov al, 'A'
.mark:
    mov byte [0xB8006], al
    mov byte [0xB8007], 0x0E

    ; swtch 切任务: swtch(&old, new)
    ; 简化: swtch 从 0x90030 (旧 task 栈 context 位置) 切到 0x90040 (新 task 栈 context 位置)
    ; 装 ESP 之前 scheduler 跑过, 跑过的栈是 task 栈 (ESP=task_esp-12)
    ; 等等, **不**对 — scheduler 跑时 ESP=task_esp-12 (CPU push 12 字节后), scheduler 跑过没还原
    ; swtch 装 ESP = new 栈 (task_B 栈 0xB0EFC), push 4 regs, 保存 ESP=[0x90040]? 不, swtch 参数是 [old, new] = [0x90030 或 0x90040, 0x90040 或 0x90030]
    ;
    ; 关键: swtch 入口 [esp+4]=old, [esp+8]=new, esp=scheduler 栈 (CPU push 后)
    ;       swtch 跑: push 4 regs (32 字节), mov [old]=esp, mov esp=new
    ;       swtch 跑后: ESP=new 栈, pop 4 regs, ret 跳 new 栈 return address

    ; swtch 装: scheduler push [old, new] (8 字节), call swtch (4 字节 = return address)
    ; 但我们用 jmp swtch (不 call), 自己装 [old, new] 到栈
    sub esp, 8
    mov eax, [0x90030]          ; old = 旧 task context 指针位置 (scheduler 装 ESP=旧 task)
    ; 等等, scheduler 跑过 ESP=task_esp-12 (CPU push 后), 装 old=0x90030 (task_A context 位置)
    ; swtch 跑: push 4 regs + mov [0x90030]=esp (= task_esp-12-32-12 = task_esp-56?)
    ;          mov esp=0x90040 (新 task context 指针)
    ;          pop 4 regs (从新 task 栈)
    ;          ret (跳新 task return address)
    ; 然后新 task 跑, PIT 触发 scheduler, scheduler 入口 ESP=新 task 栈
    ; scheduler 跑过, 切任务, swtch 装 old=新 task, new=旧 task
    ; swtch 跑: push 4 regs + mov [0x90030]=esp (= 新 task_esp-12-32-8 = 新 task_esp-52?)
    ;          mov esp=0x90030? 不, new=旧 task context 指针 = 0x90030 = 旧 task ESP
    ;          pop 4 regs + ret — **但** ESP=0x90030, 0x90030 是 task 栈 context 指针位置, 不是栈
    ;          pop 4 regs 会从 [0x90030], [0x90034], [0x90038], [0x9003C] pop
    ;          ret 从 [0x90040] pop? 不, pop 4 之后 ESP=0x90040
    ;          ret 从 [0x90040] pop? 0x90040 = task_B context 指针, = 0x000B0EFC (task_B ESP 数值)
    ;          **错! ret 应该跳 return address, 不是 ESP 数值**

    ; 等等, xv6 swtch ret 跳 return address — return address 是 swtch 调用前 push 的 (call swtch)
    ; xv6 main 跳到 swtch 是用 call, CPU push return address
    ; 我们 scheduler 跳到 swtch 用 jmp, **没** push return address
    ;
    ; **修法**: scheduler 调 swtch 用 **call swtch** (push return address 到栈)
    ; 但 scheduler 栈是 task 栈 (CPU push 12 字节后), call swtch push 4 字节 (return address)
    ; swtch 跑后, ret pop return address 跳回 scheduler, scheduler 跑完切任务标记
    ; 切任务 swtch 装: scheduler 栈装好 [old, new] (8 字节) + call swtch (4 字节)
    ; swtch 跑: push 4 regs + mov [old]=esp + mov esp=new + pop 4 regs + ret
    ; ret pop 4 字节 return address — **但**新任务栈**没**装 return address
    ; 等等, 新任务栈 0xB0EFC 装: 0xB0EFC=0, 0xB0F00=0, 0xB0F04=0, 0xB0F08=0, 0xB0F0C=TASK_B_PHYS
    ; 装顺序: 0xB0EFC (低) -> 0xB0F00 -> 0xB0F04 -> 0xB0F08 -> 0xB0F0C (TASK_B_PHYS, return)
    ; swtch 跑: push 4 regs, mov esp=0xB0EFC
    ;          pop edi (pop [0xB0EFC]=0), pop esi ([0xB0F00]=0), pop ebx ([0xB0F04]=0), pop ebp ([0xB0F08]=0)
    ;          ret pop [0xB0F0C]=TASK_B_PHYS, 跳 task_B
    ; 跑对!

    ; 简化 scheduler 切任务: 装 ESP=task_esp_current, 装 [old]=ESP, mov ESP=new, pop 4 regs, ret
    ; 不 call swtch, 直接 inline swtch

    ; 装 [old, new] 到 scheduler 栈
    mov eax, [0x90030]          ; old 位置 (保存 ESP 数值)
    mov edx, [0x90040]          ; new 位置 (新 ESP 数值)
    push edx                    ; push new
    push eax                    ; push old
    mov eax, [esp+4]            ; eax = old
    mov edx, [esp+8]            ; edx = new
    add esp, 8                  ; 还原栈 (pop [old, new] 用)

    ; swtch inline
    push ebp
    push ebx
    push esi
    push edi
    mov [eax], esp              ; 保存 ESP 到 [old] (scheduler 跑过 ESP = task_esp-12 - 8 - 16 = task_esp-36)
    mov esp, edx                ; 装新 ESP
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret

.sched_iret:
    ; 不切任务, 还原 task 栈 (CPU push 12 字节 = add esp, 12) + iret
    add esp, 12
    iret

; ============================================================================
; task_A
; ============================================================================
task_A:
    mov byte [0xB8008], 'a'
    mov byte [0xB8009], 0x0A
    jmp task_A

; ============================================================================
; task_B
; ============================================================================
task_B:
    mov byte [0xB800A], 'b'
    mov byte [0xB800B], 0x0C
    jmp task_B

; ============================================================================
; PS/2 键盘 handler
; ============================================================================
ps2_handler:
    in al, 0x60
    mov ah, al
    mov al, 0x20
    out 0x20, al
    mov dx, 0x3F8
    mov al, 'K'
    out dx, al
    mov al, ah
    shr al, 4
    cmp al, 10
    jb .ps2_hex1
    add al, 'a' - 10
    jmp .ps2_hex1_out
.ps2_hex1:
    add al, '0'
.ps2_hex1_out:
    mov dx, 0x3F8
    out dx, al
    mov al, ah
    and al, 0xF
    cmp al, 10
    jb .ps2_hex2
    add al, 'a' - 10
    jmp .ps2_hex2_out
.ps2_hex2:
    add al, '0'
.ps2_hex2_out:
    mov dx, 0x3F8
    out dx, al
    mov al, ' '
    out dx, al
    iret

; ============================================================================
; BSS
; ============================================================================
gdt_start:     times 24 db 0
gdt_desc:      times 8  db 0
idt_start:     times 2048 db 0
idt_desc:      times 8  db 0
pgt1:          times 4096 db 0

gdt_start_offset  equ gdt_start - $$
gdt_desc_offset   equ gdt_desc - $$
