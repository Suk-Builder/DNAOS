#!/usr/bin/env python3
"""
================================================================================
DNAsm Compiler - DNA Assembly Language → x86_64 NASM
================================================================================

DNAsm is the native language of DNAOS. It compiles to x86_64 machine code
via NASM, but the source is pure ATCG-native assembly.

Features:
  - DNA-named registers (rA=rax, rT=rcx, rC=rdx, rG=rbx, rS=rsi, rP=rdi, rB=rbp, rK=rsp)
  - Quaternary instructions (qand, qor, qnot, qadd) → kernel function calls
  - ATCG data literals (atcg "ATCGATCG" → raw bytes)
  - Full x86_64 instruction set via 1:1 mapping
  - Macro system
  - Include files
  - ELF64 output via NASM

Usage:
  python3 dasm.py kernel.dna -o kernel.o
  python3 dasm.py kernel.dna -o kernel.nasm  # Just emit NASM

================================================================================
"""

import sys
import os
import re
import argparse
from pathlib import Path

# ============================================================================
# Register Mapping: DNAsm → x86_64 NASM
# ============================================================================
REG_MAP_64 = {
    'rA': 'rax', 'rT': 'rcx', 'rC': 'rdx', 'rG': 'rbx',
    'rS': 'rsi', 'rP': 'rdi', 'rB': 'rbp', 'rK': 'rsp',
    'r0': 'r8',  'r1': 'r9',  'r2': 'r10', 'r3': 'r11',
    'r4': 'r12', 'r5': 'r13', 'r6': 'r14', 'r7': 'r15',
}
REG_MAP_32 = {
    'rA.w': 'eax', 'rT.w': 'ecx', 'rC.w': 'edx', 'rG.w': 'ebx',
    'rS.w': 'esi', 'rP.w': 'edi', 'rB.w': 'ebp', 'rK.w': 'esp',
    'r0.w': 'r8d', 'r1.w': 'r9d', 'r2.w': 'r10d','r3.w': 'r11d',
    'r4.w': 'r12d','r5.w': 'r13d','r6.w': 'r14d','r7.w': 'r15d',
}
REG_MAP_16 = {
    'rA.d': 'ax',  'rT.d': 'cx',  'rC.d': 'dx',  'rG.d': 'bx',
    'rS.d': 'si',  'rP.d': 'di',  'rB.d': 'bp',  'rK.d': 'sp',
}
REG_MAP_8 = {
    'rA.b': 'al',  'rT.b': 'cl',  'rC.b': 'dl',  'rG.b': 'bl',
    'rA.h': 'ah',  'rT.h': 'ch',  'rC.h': 'dh',  'rG.h': 'bh',
    'r0.b': 'r8b', 'r1.b': 'r9b', 'r2.b': 'r10b','r3.b': 'r11b',
    'r4.b': 'r12b','r5.b': 'r13b','r6.b': 'r14b','r7.b': 'r15b',
}

REG_MAP = {}
REG_MAP.update(REG_MAP_64)
REG_MAP.update(REG_MAP_32)
REG_MAP.update(REG_MAP_16)
REG_MAP.update(REG_MAP_8)

# Sort by length descending so longer names match first (rA.w before rA)
REG_SORTED = sorted(REG_MAP.keys(), key=len, reverse=True)

# ATCG encoding
ATCG_MAP = {'A': 0, 'T': 1, 'C': 2, 'G': 3}

def encode_atcg_byte(s):
    """Encode 4 ATCG characters to 1 byte: A=00, T=01, C=10, G=11"""
    s = s.upper()
    while len(s) % 4 != 0:
        s += 'A'
    result = []
    for i in range(0, len(s), 4):
        b = 0
        for j in range(4):
            c = s[i+j]
            if c not in ATCG_MAP:
                raise ValueError(f"Invalid ATCG char '{c}' in '{s[i:i+4]}'")
            b |= ATCG_MAP[c] << (6 - j*2)
        result.append(b)
    return result

def decode_number(s):
    """Parse number: decimal, hex 0x, binary 0b, char 'A'"""
    s = s.strip()
    if not s:
        return None
    # Character literal
    if len(s) == 3 and s[0] == "'" and s[2] == "'":
        return ord(s[1])
    # Hex
    if s.startswith('0x') or s.startswith('0X') or s.startswith('$'):
        return int(s.lstrip('$'), 16)
    # Binary
    if s.startswith('0b') or s.startswith('0B'):
        return int(s, 2)
    # Negative
    if s.startswith('-'):
        v = decode_number(s[1:])
        return -v if v is not None else None
    # Decimal
    try:
        return int(s)
    except ValueError:
        return None

def split_operands(s):
    """Split operands by comma, respecting brackets and quotes"""
    parts = []
    depth = 0
    in_quote = False
    current = []
    for c in s:
        if c == '"':
            in_quote = not in_quote
            current.append(c)
        elif in_quote:
            current.append(c)
        elif c == '[':
            depth += 1
            current.append(c)
        elif c == ']':
            depth -= 1
            current.append(c)
        elif c == ',' and depth == 0:
            parts.append(''.join(current).strip())
            current = []
        else:
            current.append(c)
    if current:
        parts.append(''.join(current).strip())
    return [p for p in parts if p]

def translate_reg(token):
    """Translate a single register name"""
    token = token.strip()
    if token in REG_MAP:
        return REG_MAP[token]
    return token

def translate_operand(op):
    """Translate one operand (register, memory, immediate, label)"""
    op = op.strip()
    if not op:
        return op

    # Size-prefixed memory: byte/word/dword/qword [xxx]
    size_prefixes = ['byte', 'word', 'dword', 'qword']
    for sp in size_prefixes:
        if op.startswith(sp + ' '):
            rest = op[len(sp)+1:]
            return f"{sp} {translate_operand(rest)}"

    # Memory operand: [base+offset] or [base+index*scale+offset]
    if op.startswith('[') and op.endswith(']'):
        inner = op[1:-1]
        # Replace register names (longest first)
        for dna in REG_SORTED:
            x86 = REG_MAP[dna]
            # Use word boundary matching
            inner = re.sub(r'\b' + re.escape(dna) + r'\b', x86, inner)
        return f'[{inner}]'

    # Register
    if op in REG_MAP:
        return REG_MAP[op]

    # Number
    num = decode_number(op)
    if num is not None:
        if num < 0:
            return str(num)
        return f'0x{num:x}' if num > 9 else str(num)

    # Label or symbol - pass through
    return op

def translate_operands(operands_str):
    """Translate all operands in an instruction"""
    ops = split_operands(operands_str)
    return ', '.join(translate_operand(op) for op in ops)

# ============================================================================
# DNAsm Compiler
# ============================================================================
class DNAsmCompiler:
    def __init__(self):
        self.output = []
        self.includes_done = set()
        self.macros = {}
        self.macro_name = None
        self.macro_params = []
        self.macro_body = []
        self.in_macro = False
        self.label_counter = 0
        self.source_file = ""
        self.source_dir = "."

    def error(self, msg, line=""):
        print(f"\033[31mDNAsm Error:\033[0m {msg}", file=sys.stderr)
        if line:
            print(f"  Line: {line}", file=sys.stderr)
        sys.exit(1)

    def unique_label(self, prefix):
        """Generate a unique local label"""
        self.label_counter += 1
        return f".{prefix}_{self.label_counter}"

    def compile_file(self, filename):
        """Compile a .dna file"""
        path = Path(filename)
        if not path.exists():
            self.error(f"File not found: {filename}")
        self.source_file = str(path)
        self.source_dir = str(path.parent)
        with open(path, 'r') as f:
            lines = f.readlines()
        for i, line in enumerate(lines, 1):
            try:
                self.compile_line(line.rstrip('\n'), i)
            except Exception as e:
                self.error(f"{e} (line {i}: {line.strip()})")

    def process_include(self, fname):
        """Handle include directive"""
        # Try relative to source dir first
        candidates = [
            os.path.join(self.source_dir, fname),
            fname,
        ]
        for c in candidates:
            if os.path.exists(c):
                abs_path = os.path.abspath(c)
                if abs_path in self.includes_done:
                    return
                self.includes_done.add(abs_path)
                self.compile_file(c)
                return
        self.error(f"Include file not found: {fname}")

    def compile_line(self, line, lineno=0):
        """Compile one line of DNAsm"""
        # Strip comments (; to end of line, but not inside strings)
        in_quote = False
        comment_pos = -1
        for i, c in enumerate(line):
            if c == '"':
                in_quote = not in_quote
            elif c == ';' and not in_quote:
                comment_pos = i
                break
        if comment_pos >= 0:
            line = line[:comment_pos]
        line = line.rstrip()
        if not line.strip():
            return

        stripped = line.strip()

        # Inside macro definition?
        if self.in_macro:
            if stripped == 'endm':
                self.macros[self.macro_name] = (self.macro_params, self.macro_body)
                self.in_macro = False
                self.macro_body = []
                return
            self.macro_body.append(stripped)
            return

        # ---- Directives ----

        # Section
        if stripped in ('.code', '.text'):
            self.output.append('section .text')
            return
        if stripped == '.data':
            self.output.append('section .data')
            return
        if stripped == '.bss':
            self.output.append('section .bss')
            return
        if stripped == '.rodata':
            self.output.append('section .rodata')
            return
        if stripped.startswith('.section '):
            self.output.append(f'section {stripped[9:]}')
            return

        # Align
        if stripped.startswith('.align '):
            self.output.append(f'align {stripped[7:]}')
            return

        # Global/Extern
        if stripped.startswith(('.global ', '.globl ')):
            self.output.append(f'global {stripped.split(None, 1)[1]}')
            return
        if stripped.startswith('.extern '):
            self.output.append(f'extern {stripped.split(None, 1)[1]}')
            return

        # Include
        if stripped.startswith(('.include ', 'include ')):
            fname = stripped.split(None, 1)[1].strip('"\'')
            self.process_include(fname)
            return

        # Label
        if stripped.endswith(':') and not stripped.startswith(('db ','dw ','dd ','dq ')):
            label = stripped[:-1].strip()
            self.output.append(f'{label}:')
            return

        # ---- Data definitions ----
        if stripped.startswith('db '):
            self.compile_db(stripped[3:])
            return
        if stripped.startswith('dw '):
            self.output.append(f'dw {translate_operands(stripped[3:])}')
            return
        if stripped.startswith('dd '):
            self.output.append(f'dd {translate_operands(stripped[3:])}')
            return
        if stripped.startswith('dq '):
            self.output.append(f'dq {translate_operands(stripped[3:])}')
            return

        # ATCG data
        if stripped.startswith('atcg '):
            self.compile_atcg(stripped[5:])
            return

        # Times
        if stripped.startswith('times '):
            self.output.append(f'times {translate_operands(stripped[6:])}')
            return

        # Reservations
        for r in ('resb', 'resw', 'resd', 'resq'):
            if stripped.startswith(r + ' '):
                self.output.append(f'{r} {stripped[len(r)+1:]}')
                return

        # ---- Quaternary instructions ----
        if stripped.startswith('qand '):
            self.compile_qand(stripped[5:])
            return
        if stripped.startswith('qor '):
            self.compile_qor(stripped[4:])
            return
        if stripped.startswith('qnot '):
            self.compile_qnot(stripped[5:])
            return
        if stripped.startswith('qadd '):
            self.compile_qadd(stripped[5:])
            return

        # ---- Macro ----
        if stripped.startswith('macro '):
            parts = stripped[6:].split()
            self.macro_name = parts[0]
            self.macro_params = parts[1:] if len(parts) > 1 else []
            self.macro_body = []
            self.in_macro = True
            return
        if stripped == 'endm':
            return

        # ---- Macro invocation ----
        first_word = stripped.split()[0] if stripped.split() else ''
        if first_word in self.macros:
            self.expand_macro(first_word, stripped[len(first_word):].strip())
            return

        # ---- Regular instruction ----
        self.compile_instruction(stripped)

    def compile_db(self, data_str):
        """Compile db directive with ATCG string support"""
        items = split_operands(data_str)
        translated = []
        for item in items:
            item = item.strip()
            if item.startswith('"') and item.endswith('"'):
                # Check if it's an ATCG string: atcg"..."
                if item.startswith('"AT') or item.startswith('"at') or item.startswith('"ATCG') or item.startswith('"atcg'):
                    # Could be ATCG data
                    inner = item[1:-1].upper()
                    if all(c in ATCG_MAP for c in inner):
                        bytes_list = encode_atcg_byte(inner)
                        for b in bytes_list:
                            translated.append(f'0x{b:02x}')
                        continue
                # Regular string
                translated.append(item)
            else:
                num = decode_number(item)
                if num is not None:
                    translated.append(f'0x{num & 0xFF:02x}' if num > 9 or num < 0 else str(num))
                else:
                    translated.append(translate_operand(item))
        self.output.append(f'db {", ".join(translated)}')

    def compile_atcg(self, data_str):
        """Compile ATCG data literal"""
        data_str = data_str.strip()
        if data_str.startswith('"') and data_str.endswith('"'):
            atcg_str = data_str[1:-1].upper()
        else:
            atcg_str = data_str.upper()

        if not all(c in ATCG_MAP for c in atcg_str):
            self.error(f"Invalid ATCG data: {data_str}")

        bytes_list = encode_atcg_byte(atcg_str)
        hex_vals = [f'0x{b:02x}' for b in bytes_list]
        self.output.append(f'db {", ".join(hex_vals)}  ; ATCG: {atcg_str}')

    # ========================================================================
    # Quaternary Instructions → x86_64 inline implementation
    # ========================================================================
    def compile_qand(self, operands):
        """qand dst, src — Quaternary AND (min per quat pair)
        
        Processes 4 quats (8 bits) at a time.
        For each 2-bit pair: result = min(a, b)
        """
        ops = [o.strip() for o in operands.split(',')]
        if len(ops) != 2:
            self.error(f"qand requires 2 operands, got: {operands}")

        dst = translate_operand(ops[0])
        src = translate_operand(ops[1])
        lbl = self.unique_label('qand')

        self.output.append(f'    ; qand {ops[0]}, {ops[1]}')
        self.output.append(f'    push {src}')
        self.output.append(f'    push {dst}')
        self.output.append(f'    push r8')
        self.output.append(f'    push r9')
        self.output.append(f'    push r10')
        self.output.append(f'    push r11')
        self.output.append(f'    xor r8d, r8d          ; result accumulator')
        self.output.append(f'    mov r9d, 4            ; quat counter')
        self.output.append(f'{lbl}_loop:')
        self.output.append(f'    mov r10d, 3')
        self.output.append(f'    and r10d, {dst}       ; a_q = dst & 3')
        self.output.append(f'    mov r11d, 3')
        self.output.append(f'    and r11d, {src}       ; b_q = src & 3')
        self.output.append(f'    cmp r10d, r11d')
        self.output.append(f'    cmova r10d, r11d      ; r10 = min(a_q, b_q)')
        self.output.append(f'    mov ecx, r9d')
        self.output.append(f'    dec ecx')
        self.output.append(f'    shl ecx, 1')
        self.output.append(f'    shl r10d, cl          ; shift into position')
        self.output.append(f'    or r8d, r10d          ; accumulate')
        self.output.append(f'    shr {dst}, 2          ; next quat')
        self.output.append(f'    shr {src}, 2')
        self.output.append(f'    dec r9d')
        self.output.append(f'    jnz {lbl}_loop')
        self.output.append(f'    mov {dst}, r8         ; store result')
        self.output.append(f'    pop r11')
        self.output.append(f'    pop r10')
        self.output.append(f'    pop r9')
        self.output.append(f'    pop r8')
        self.output.append(f'    pop {dst}')
        self.output.append(f'    pop {src}')

    def compile_qor(self, operands):
        """qor dst, src — Quaternary OR (max per quat pair)"""
        ops = [o.strip() for o in operands.split(',')]
        if len(ops) != 2:
            self.error(f"qor requires 2 operands, got: {operands}")

        dst = translate_operand(ops[0])
        src = translate_operand(ops[1])
        lbl = self.unique_label('qor')

        self.output.append(f'    ; qor {ops[0]}, {ops[1]}')
        self.output.append(f'    push {src}')
        self.output.append(f'    push {dst}')
        self.output.append(f'    push r8')
        self.output.append(f'    push r9')
        self.output.append(f'    push r10')
        self.output.append(f'    push r11')
        self.output.append(f'    xor r8d, r8d')
        self.output.append(f'    mov r9d, 4')
        self.output.append(f'{lbl}_loop:')
        self.output.append(f'    mov r10d, 3')
        self.output.append(f'    and r10d, {dst}')
        self.output.append(f'    mov r11d, 3')
        self.output.append(f'    and r11d, {src}')
        self.output.append(f'    cmp r10d, r11d')
        self.output.append(f'    cmovb r10d, r11d      ; r10 = max(a_q, b_q)')
        self.output.append(f'    mov ecx, r9d')
        self.output.append(f'    dec ecx')
        self.output.append(f'    shl ecx, 1')
        self.output.append(f'    shl r10d, cl')
        self.output.append(f'    or r8d, r10d')
        self.output.append(f'    shr {dst}, 2')
        self.output.append(f'    shr {src}, 2')
        self.output.append(f'    dec r9d')
        self.output.append(f'    jnz {lbl}_loop')
        self.output.append(f'    mov {dst}, r8')
        self.output.append(f'    pop r11')
        self.output.append(f'    pop r10')
        self.output.append(f'    pop r9')
        self.output.append(f'    pop r8')
        self.output.append(f'    pop {dst}')
        self.output.append(f'    pop {src}')

    def compile_qnot(self, operands):
        """qnot dst — Quaternary NOT (3 - x per quat)"""
        op = operands.strip()
        dst = translate_operand(op)
        lbl = self.unique_label('qnot')

        self.output.append(f'    ; qnot {op}')
        self.output.append(f'    push {dst}')
        self.output.append(f'    push r8')
        self.output.append(f'    push r9')
        self.output.append(f'    push r10')
        self.output.append(f'    xor r8d, r8d')
        self.output.append(f'    mov r9d, 4')
        self.output.append(f'{lbl}_loop:')
        self.output.append(f'    mov r10d, 3')
        self.output.append(f'    and r10d, {dst}       ; q = dst & 3')
        self.output.append(f'    mov r11d, 3')
        self.output.append(f'    sub r11d, r10d        ; 3 - q')
        self.output.append(f'    mov ecx, r9d')
        self.output.append(f'    dec ecx')
        self.output.append(f'    shl ecx, 1')
        self.output.append(f'    shl r11d, cl')
        self.output.append(f'    or r8d, r11d')
        self.output.append(f'    shr {dst}, 2')
        self.output.append(f'    dec r9d')
        self.output.append(f'    jnz {lbl}_loop')
        self.output.append(f'    mov {dst}, r8')
        self.output.append(f'    pop r10')
        self.output.append(f'    pop r9')
        self.output.append(f'    pop r8')
        self.output.append(f'    pop {dst}')

    def compile_qadd(self, operands):
        """qadd dst, src — Quaternary ADD with carry propagation
        
        Each quat position: sum = (a+b+carry) % 4, carry = (a+b+carry) / 4
        """
        ops = [o.strip() for o in operands.split(',')]
        if len(ops) != 2:
            self.error(f"qadd requires 2 operands, got: {operands}")

        dst = translate_operand(ops[0])
        src = translate_operand(ops[1])
        lbl = self.unique_label('qadd')

        self.output.append(f'    ; qadd {ops[0]}, {ops[1]}')
        self.output.append(f'    push {src}')
        self.output.append(f'    push {dst}')
        self.output.append(f'    push r8')
        self.output.append(f'    push r9')
        self.output.append(f'    push r10')
        self.output.append(f'    push r11')
        self.output.append(f'    push r12')
        self.output.append(f'    xor r8d, r8d          ; result')
        self.output.append(f'    xor r12d, r12d        ; carry')
        self.output.append(f'    mov r9d, 4            ; counter')
        self.output.append(f'{lbl}_loop:')
        self.output.append(f'    mov r10d, 3')
        self.output.append(f'    and r10d, {dst}       ; a_q')
        self.output.append(f'    mov r11d, 3')
        self.output.append(f'    and r11d, {src}       ; b_q')
        self.output.append(f'    add r10d, r11d')
        self.output.append(f'    add r10d, r12d        ; a + b + carry')
        self.output.append(f'    xor r12d, r12d')
        self.output.append(f'    cmp r10d, 4')
        self.output.append(f'    setge r12b            ; carry = 1 if sum >= 4')
        self.output.append(f'    and r10d, 3           ; sum % 4')
        self.output.append(f'    mov ecx, r9d')
        self.output.append(f'    dec ecx')
        self.output.append(f'    shl ecx, 1')
        self.output.append(f'    shl r10d, cl')
        self.output.append(f'    or r8d, r10d')
        self.output.append(f'    shr {dst}, 2')
        self.output.append(f'    shr {src}, 2')
        self.output.append(f'    dec r9d')
        self.output.append(f'    jnz {lbl}_loop')
        self.output.append(f'    mov {dst}, r8')
        self.output.append(f'    pop r12')
        self.output.append(f'    pop r11')
        self.output.append(f'    pop r10')
        self.output.append(f'    pop r9')
        self.output.append(f'    pop r8')
        self.output.append(f'    pop {dst}')
        self.output.append(f'    pop {src}')

    # ========================================================================
    # Macro System
    # ========================================================================
    def expand_macro(self, name, args_str):
        """Expand a macro invocation"""
        params, body = self.macros[name]
        args = split_operands(args_str) if args_str else []
        if len(args) != len(params):
            self.error(f"Macro {name}: expected {len(params)} args, got {len(args)}")
        for line in body:
            expanded = line
            for param, arg in zip(params, args):
                expanded = expanded.replace(param, arg)
            self.compile_line(expanded)

    # ========================================================================
    # Regular Instructions → NASM
    # ========================================================================
    def compile_instruction(self, line):
        """Compile a regular x86_64 instruction"""
        # Split into mnemonic and operands
        parts = line.split(None, 1)
        mnemonic = parts[0]
        operands_str = parts[1] if len(parts) > 1 else ''

        # Instructions with no operands
        no_ops = {'nop', 'ret', 'hlt', 'cli', 'sti', 'cld', 'std',
                  'syscall', 'sysret', 'iretq', 'iret', 'swapgs',
                  'cpuid', 'rdmsr', 'wrmsr', 'pause', 'lfence',
                  'sfence', 'mfence', 'cbw', 'cwde', 'cdqe',
                  'cwd', 'cdq', 'cqo', 'pushf', 'popf', 'sahf', 'lahf',
                  'leave', 'int3', 'ud2', 'xlat', 'rdtsc', 'rdtscp',
                  'clts', 'invd', 'wbinvd'}
        if mnemonic in no_ops:
            self.output.append(f'    {mnemonic}')
            return

        # INT instruction
        if mnemonic == 'int':
            self.output.append(f'    int {translate_operand(operands_str)}')
            return

        # Instructions with operands - translate
        translated_ops = translate_operands(operands_str)

        # Special instruction handling
        special_two = {
            'push', 'pop', 'inc', 'dec', 'neg', 'not',
            'mul', 'div', 'imul', 'idiv',
            'jmp', 'call', 'jo', 'jno', 'jb', 'jnae', 'jc',
            'jnb', 'jae', 'jnc', 'jz', 'je', 'jnz', 'jne',
            'ja', 'jnbe', 'jna', 'jbe', 'js', 'jns',
            'jp', 'jpe', 'jnp', 'jpo', 'jl', 'jnge',
            'jnl', 'jge', 'jle', 'jng', 'jnle', 'jg',
            'loop', 'loope', 'loopne', 'jcxz', 'jecxz', 'jrcxz',
            'setz', 'setnz', 'sete', 'setne', 'setl', 'setge',
            'setle', 'setg', 'setb', 'seta', 'setbe', 'setae',
            'bswap', 'bzhi', 'pext', 'pdep',
        }
        special_three = {
            'mov', 'movzx', 'movsx', 'movsxd',
            'add', 'adc', 'sub', 'sbb', 'and', 'or', 'xor',
            'cmp', 'test', 'xchg', 'xadd', 'cmpxchg',
            'shl', 'shr', 'sal', 'sar', 'rol', 'ror', 'rcl', 'rcr',
            'shld', 'shrd',
            'lea', 'movabs',
            'cmovz', 'cmovnz', 'cmove', 'cmovne',
            'cmovl', 'cmovge', 'cmovle', 'cmovg',
            'cmovb', 'cmova', 'cmovbe', 'cmovae',
            'imul',  # 3-operand form
            'shlx', 'shrx', 'sarx',
        }
        special_mem = {
            'lgdt', 'lidt', 'lldt', 'ltr', 'invlpg',
            'prefetch', 'prefetchw', 'prefetchwt1',
            'fxsave', 'fxrstor',
        }
        io_ops = {'in', 'out'}

        if mnemonic in special_two:
            self.output.append(f'    {mnemonic} {translated_ops}')
        elif mnemonic in special_three:
            self.output.append(f'    {mnemonic} {translated_ops}')
        elif mnemonic in special_mem:
            self.output.append(f'    {mnemonic} {translated_ops}')
        elif mnemonic in io_ops:
            self.output.append(f'    {mnemonic} {translated_ops}')
        elif mnemonic == 'rep' or mnemonic == 'repz' or mnemonic == 'repnz' or mnemonic == 'lock':
            self.output.append(f'    {mnemonic} {translated_ops}')
        else:
            # Unknown instruction - pass through as-is (might be NASM-specific)
            self.output.append(f'    {mnemonic} {translated_ops}')

    def get_output(self):
        """Get the compiled NASM output"""
        return '\n'.join(self.output) + '\n'

    def compile(self, input_file, output_file=None, emit_nasm=False):
        """Main compile entry point"""
        self.compile_file(input_file)
        nasm_code = self.get_output()

        if emit_nasm or output_file is None:
            # Just output NASM
            if output_file:
                with open(output_file, 'w') as f:
                    f.write(nasm_code)
            else:
                print(nasm_code, end='')
            return

        # Write NASM, then assemble with NASM
        nasm_file = output_file.rsplit('.', 1)[0] + '.nasm'
        with open(nasm_file, 'w') as f:
            f.write(nasm_code)

        # Run NASM
        import subprocess
        result = subprocess.run(
            ['nasm', '-f', 'elf64', '-o', output_file, nasm_file],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"\033[31mNASM Error:\033[0m", file=sys.stderr)
            print(result.stderr, file=sys.stderr)
            sys.exit(1)

        print(f"\033[32mCompiled:\033[0m {input_file} → {output_file}")

# ============================================================================
# Main
# ============================================================================
def main():
    parser = argparse.ArgumentParser(description='DNAsm Compiler - DNA Assembly Language → x86_64')
    parser.add_argument('input', help='Input .dna file')
    parser.add_argument('-o', '--output', help='Output file (.o for ELF64, .nasm for NASM source)')
    parser.add_argument('-n', '--nasm', action='store_true', help='Emit NASM source instead of assembling')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output')

    args = parser.parse_args()

    compiler = DNAsmCompiler()
    if args.nasm or (args.output and args.output.endswith('.nasm')):
        compiler.compile(args.input, args.output, emit_nasm=True)
    elif args.output:
        compiler.compile(args.input, args.output)
    else:
        compiler.compile(args.input, emit_nasm=True)

if __name__ == '__main__':
    main()
