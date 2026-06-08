#!/usr/bin/env python3
"""
DNAsm → C Compiler (v2) — for DNAOS 2D games
Usage: python3 dasm_c.py game.dna -o game_gen.c
"""

import sys, re, argparse

class Compiler:
    def __init__(self):
        self.consts = {}
        self.globals = {}
        self.functions = {}
        self.out = []

    def resolve(self, s):
        """Replace const names with values."""
        for k in sorted(self.consts, key=len, reverse=True):
            s = re.sub(r'\b' + k + r'\b', str(self.consts[k]), s)
        return s

    def expr(self, s):
        """Convert DNAsm expression to C."""
        s = self.resolve(s.strip())
        # Fix integer division: DNAsm uses / for integer div, same as C for ints
        # But we replaced / with // in resolve, undo that
        s = s.replace('//', '/')
        return s

    def call_to_c(self, s):
        """Convert 'call func(args)' to 'func(args)'."""
        s = s.strip()
        if s.startswith('call '):
            return s[5:]
        return s

    def cond_to_c(self, s):
        """Convert DNAsm condition to C condition."""
        s = s.strip()
        # Handle "call func()" in conditions
        s = re.sub(r'call\s+', '', s)
        # Handle "!call func()" → "!func()"
        # Handle negation
        s = s.replace('!call ', '!')
        return s

    def parse(self, src):
        lines = src.split('\n')
        i = 0
        while i < len(lines):
            raw = lines[i].strip()
            i += 1
            # Strip comments
            line = raw.split(';')[0].split('#')[0].strip()
            if not line:
                continue

            # const
            m = re.match(r'const\s+(\w+)\s*=\s*(.+)', line)
            if m:
                self.consts[m.group(1)] = m.group(2).strip()
                continue

            # var (global)
            m = re.match(r'var\s+(\w+)\s*=\s*(.+)', line)
            if m:
                self.globals[m.group(1)] = m.group(2).strip()
                continue

            # func
            m = re.match(r'func\s+(\w+)\s*\((.*?)\)\s*\{', line)
            if m:
                fname, params = m.group(1), m.group(2).strip()
                body, depth = [], 1
                while i < len(lines) and depth > 0:
                    l = lines[i].strip().split(';')[0].split('#')[0].strip()
                    i += 1
                    if not l:
                        continue
                    depth += l.count('{') - l.count('}')
                    if depth <= 0:
                        l = l.rstrip('}').strip()
                    if l:
                        body.append(l)
                self.functions[fname] = (params, body)
                continue

    def compile_body(self, body, indent=1):
        """Compile function body lines to C."""
        pfx = "    " * indent
        for line in body:
            line = line.strip()
            if not line:
                continue

            # label
            m = re.match(r'label\s+(\w+)', line)
            if m:
                self.out.append(f"{m.group(1)}:")
                continue

            # var (local)
            m = re.match(r'var\s+(\w+)\s*=\s*(.+)', line)
            if m:
                self.out.append(f"{pfx}int {m.group(1)} = {self.expr(m.group(2))};")
                continue

            # set
            m = re.match(r'set\s+(\w+)\s*=\s*(.+)', line)
            if m:
                self.out.append(f"{pfx}{m.group(1)} = {self.expr(m.group(2))};")
                continue

            # if ... goto
            m = re.match(r'if\s+(.+?)\s+goto\s+(\w+)', line)
            if m:
                self.out.append(f"{pfx}if ({self.cond_to_c(m.group(1))}) goto {m.group(2)};")
                continue

            # if ... {  (block if)
            m = re.match(r'if\s+(.+?)\s*\{$', line)
            if m:
                self.out.append(f"{pfx}if ({self.cond_to_c(m.group(1))}) {{")
                continue

            # if cond call func() {  → if (cond) { func(); }
            m = re.match(r'if\s+(.+?)\s+call\s+(.+?)\s*\{$', line)
            if m:
                self.out.append(f"{pfx}if ({self.cond_to_c(m.group(1))}) {{")
                self.out.append(f"{pfx}    {self.call_to_c('call ' + m.group(2))};")
                continue

            # if cond set var = val  → if (cond) { var = val; }
            m = re.match(r'if\s+(.+?)\s+set\s+(\w+)\s*=\s*(.+)', line)
            if m:
                self.out.append(f"{pfx}if ({self.cond_to_c(m.group(1))}) {{")
                self.out.append(f"{pfx}    {m.group(2)} = {self.expr(m.group(3))};")
                self.out.append(f"{pfx}}}")
                continue

            # if cond call func()  → if (cond) func();
            m = re.match(r'if\s+(.+?)\s+call\s+(.+)', line)
            if m:
                self.out.append(f"{pfx}if ({self.cond_to_c(m.group(1))}) {self.call_to_c('call ' + m.group(2))};")
                continue

            # Simple if (no block, next line is body) — handled by block parsing

            # return
            m = re.match(r'return\s+(.+)', line)
            if m:
                self.out.append(f"{pfx}return {self.expr(m.group(1))};")
                continue
            if line == 'return':
                self.out.append(f"{pfx}return 0;")
                continue

            # call
            m = re.match(r'call\s+(.+)', line)
            if m:
                self.out.append(f"{pfx}{self.call_to_c(line)};")
                continue

            # goto
            m = re.match(r'goto\s+(\w+)', line)
            if m:
                self.out.append(f"{pfx}goto {m.group(1)};")
                continue

            # closing brace
            if line == '}':
                self.out.append(f"{pfx[:-4]}}}")
                continue

            # assignment: name = expr
            m = re.match(r'(\w+)\s*=\s*(.+)', line)
            if m:
                self.out.append(f"{pfx}{m.group(1)} = {self.expr(m.group(2))};")
                continue

            # fallback: emit as-is
            self.out.append(f"{pfx}{line};")

    def compile_all(self):
        self.out.append("/* Generated by DNAsm → C compiler v2 */")
        self.out.append('#include "game_rt.h"')
        self.out.append("")

        # Constants
        for k, v in self.consts.items():
            self.out.append(f"#define {k} ({self.resolve(v)})")
        if self.consts:
            self.out.append("")

        # Globals
        for k, v in self.globals.items():
            self.out.append(f"static int {k} = {self.expr(v)};")
        if self.globals:
            self.out.append("")

        # Forward declarations
        for fname, (params, _) in self.functions.items():
            if fname == 'main':
                continue
            if params:
                pnames = [p.strip() for p in params.split(',') if p.strip()]
                pstr = ', '.join(f'int {p}' for p in pnames)
            else:
                pstr = 'void'
            self.out.append(f"int {fname}({pstr});")
        self.out.append("")

        # Functions
        for fname, (params, body) in self.functions.items():
            if fname == 'main':
                self.out.append("int main(int argc, char *argv[]) {")
            else:
                if params:
                    pnames = [p.strip() for p in params.split(',') if p.strip()]
                    pstr = ', '.join(f'int {p}' for p in pnames)
                else:
                    pstr = 'void'
                self.out.append(f"int {fname}({pstr}) {{")
            self.compile_body(body)
            if fname == 'main':
                self.out.append("    return 0;")
            self.out.append("}")
            self.out.append("")

    def get_output(self):
        return '\n'.join(self.out)


def main():
    p = argparse.ArgumentParser(description='DNAsm → C Compiler v2')
    p.add_argument('input', help='Input .dna file')
    p.add_argument('-o', '--output', help='Output .c file')
    args = p.parse_args()

    with open(args.input) as f:
        src = f.read()

    c = Compiler()
    c.parse(src)
    c.compile_all()
    out = c.get_output()

    if args.output:
        with open(args.output, 'w') as f:
            f.write(out)
        print(f"OK: {args.input} → {args.output}")
    else:
        print(out)

if __name__ == '__main__':
    main()
