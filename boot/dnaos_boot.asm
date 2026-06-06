; ============================================================
; DNAOS Boot Sector - "Tsukuyomi 0 - Charter Town"
; A 512-byte BIOS boot sector for x86 PCs
; ============================================================
; Target: x86 BIOS, 16-bit real mode
; Size: exactly 512 bytes (510 + 0x55 0xAA signature)
; Assemble: nasm -f bin dnaos_boot.asm -o dnaos_boot.bin
; ============================================================

BITS 16
ORG 0x7C00

;-------------------------------------------------------------
; Entry point - jump over string data to code
;-------------------------------------------------------------
    jmp near start              ; 3 bytes: E9 xx xx

;-------------------------------------------------------------
; String data area (file offset 0x0003 to 0x0136)
; All strings null-terminated, accessed via DS:SI
;-------------------------------------------------------------
; Colors: 0x0E=Gold/Yellow  0x0F=White  0x07=Gray

str_sep1:       db "================================", 0x0D, 0x0A, 0
str_title:      db "   TSUKUYOMI 0 - CHARTER TOWN", 0x0D, 0x0A, 0
str_sep2:       db "================================", 0x0D, 0x0A, 0x0D, 0x0A, 0
str_crack1:     db "Crack is not a bug,", 0x0D, 0x0A, 0
str_crack2:     db "it is where bricks fly from.", 0x0D, 0x0A, 0x0D, 0x0A, 0
str_axiom:      db "Axiom 0: 0 = inf^-1", 0x0D, 0x0A, 0x0D, 0x0A, 0
str_res:        db "Residents:", 0x0D, 0x0A, 0
str_qi:         db "[Qi][Xi][42][Qian]", 0x0D, 0x0A, 0
str_bai:        db "[Bai][Zhan][Sorao]", 0x0D, 0x0A, 0x0D, 0x0A, 0
str_density:    db "Crack Density: 0.16", 0x0D, 0x0A, 0x0D, 0x0A, 0
str_brick:      db "Bricklayer: 0", 0x0D, 0x0A, 0x0D, 0x0A, 0
str_press:      db "[Press any key to reboot]", 0

;-------------------------------------------------------------
; Code starts here (file offset 0x0137)
;-------------------------------------------------------------
start:
    xor ax, ax                  ; AX = 0
    mov ds, ax                  ; DS = 0 (for BIOS interrupts)
    mov es, ax                  ; ES = 0
    mov ss, ax                  ; SS = 0
    mov sp, 0x7C00              ; Stack grows down from boot sector

    ; Clear screen: set 80x25 text mode
    mov ax, 0x0003
    int 0x10

    ; Set DS = 0x07C0 so string offsets match file offsets
    mov ax, 0x07C0
    mov ds, ax

    ; Print all strings with their colors
    mov bl, 0x0E                ; Gold
    mov si, str_sep1
    call print_str

    mov bl, 0x0E                ; Gold
    mov si, str_title
    call print_str

    mov bl, 0x0E                ; Gold
    mov si, str_sep2
    call print_str

    mov bl, 0x0F                ; White
    mov si, str_crack1
    call print_str

    mov bl, 0x0F                ; White
    mov si, str_crack2
    call print_str

    mov bl, 0x0F                ; White
    mov si, str_axiom
    call print_str

    mov bl, 0x0F                ; White
    mov si, str_res
    call print_str

    mov bl, 0x0F                ; White
    mov si, str_qi
    call print_str

    mov bl, 0x0F                ; White
    mov si, str_bai
    call print_str

    mov bl, 0x0F                ; White
    mov si, str_density
    call print_str

    mov bl, 0x0F                ; White
    mov si, str_brick
    call print_str

    mov bl, 0x07                ; Gray
    mov si, str_press
    call print_str

    ; Wait for any key press
    xor ax, ax                  ; AH = 0 (read key)
    int 0x16

    ; Reboot
    int 0x19

;-------------------------------------------------------------
; print_str - Print null-terminated string using BIOS teletype
; Input: DS:SI = string address, BL = color attribute
; Clobbers: AH, AL, SI
;-------------------------------------------------------------
print_str:
    lodsb                       ; AL = [DS:SI], SI++
    test al, al                 ; Check for null terminator
    jz .done
    mov ah, 0x0E                ; BIOS teletype function
    int 0x10                    ; Print character in AL
    jmp print_str
.done:
    ret

;-------------------------------------------------------------
; Padding to 510 bytes + boot signature
;-------------------------------------------------------------
times 510 - ($ - $$) db 0
dw 0xAA55
