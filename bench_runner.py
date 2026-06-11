#!/usr/bin/env python3
"""
bench_runner.py — Run all 16 .dna bench programs via the DNAOS simulator.
Usage: python3 bench_runner.py
"""
import subprocess, os, sys, re, time

SIM = "/workspace/dnaos_review/simulator"
os.chdir(SIM)

# ── Step 1: patch dnasm_exec.c to support st[N] registers and @label syntax ──

with open("dnasm_exec.c") as f: src = f.read()

# Replace register parsing to accept both rN and st[N] formats
old_parse = '''    if (op == OP_NUM || op == OP_LOAD || op == OP_STORE || op == OP_READ) {
        if (nt > 1) out->ra = (tok[1][0]=='r'||tok[1][0]=='R') ? atoi(tok[1]+1) : -1;
        if (nt > 2) out->rb = (tok[2][0]=='r'||tok[2][0]=='R') ? atoi(tok[2]+1) : -1;'''

new_parse = '''    if (op == OP_NUM || op == OP_LOAD || op == OP_STORE || op == OP_READ) {
        if (nt > 1) {
            char *t1 = tok[1];
            if (t1[0]=='s' && t1[1]=='t' && t1[2]=='[') {
                out->ra = atoi(t1+3); /* st[N] → reg N */
            } else if (t1[0]=='r'||t1[0]=='R') {
                out->ra = atoi(t1+1);
            } else {
                out->imm = atoll(t1);
            }
        }
        if (nt > 2) {
            char *t2 = tok[2];
            if (t2[0]=='s' && t2[1]=='t' && t2[2]=='[') {
                out->rb = atoi(t2+3);
            } else if (t2[0]=='r'||t2[0]=='R') {
                out->rb = atoi(t2+1);
            } else {
                out->imm = atoll(t2);
            }
        }'''

if old_parse not in src:
    print("WARNING: old_parse pattern not found")
else:
    src = src.replace(old_parse, new_parse)

# Replace op_names lookup to also map ST/NUM etc.
# Add ST (stack register) as alias for NUM
if '"ST"' not in src:
    src = src.replace('#define MAX_PROG', '#define OP_ST 100  /* stack register alias */\n#define MAX_PROG')

if old_parse not in src:
    print("ERROR: parse replacement failed")
    sys.exit(1)

# Update register count to 128 for st[]
src = src.replace('#define REG_COUNT     16', '#define REG_COUNT     128')

# Handle @label syntax in LABEL
src = src.replace('if (nt > 1) strncpy(out->label, tok[1], 31);',
                  'if (nt > 1) { char *lbl = tok[1]; if (lbl[0] == \'@\') lbl++; strncpy(out->label, lbl, 31); }')

# Handle JMP @name syntax (strip @)
src = src.replace(
    'if (nt > 1) strncpy(out->label, tok[1], 31);',
    'if (nt > 1) { char *lbl = tok[1]; if (lbl[0]==\'@\') lbl++; strncpy(out->label, lbl, 31); }'
)

# Fix ; comment: lines starting with ; are comments
# (parser already handles # comments, add ; support by stripping inline ; comments)
# Update parse_line to strip ; comments
old_comment = '        if (!*p||*p==\'#\'||*p==\'\\n\') break;'
new_comment = '        if (!*p||*p==\'#\'||*p==\'\\n\') break;\n        /* strip inline ; comments */\n        char *sc = strchr(p, \';\'); if (sc) *sc = 0;'
if old_comment in src:
    src = src.replace(old_comment, new_comment)

# Add DIV, SQRT, POW, SIN, COS, LN implementations (already in switch but ensure they're present)
# Check what's already there
existing = re.findall(r'case OP_\w+:', src)
print(f"Existing op cases: {sorted(set(existing))[:20]}")

with open("dnasm_exec.c", "w") as f: f.write(src)
print("dnasm_exec.c patched OK")

# ── Step 2: add dnasm_exec_file() to transcript.c ──
with open("transcript/transcript.c") as f: tc = f.read()

exec_file_fn = '''
/* ── Execute a .dna file directly via DNAsm VM ── */
int dnasm_exec_file(const char *filepath, long long input, long long atp_budget, AVal *result) {
    FILE *fp = fopen(filepath, "r");
    if (!fp) { printf("[TRANSCRIBE] Cannot open: %s\\n", filepath); return -1; }
    char buf[8192]; size_t n = fread(buf, 1, sizeof(buf)-1, fp); buf[n] = 0; fclose(fp);
    /* Strip ; comments inline */
    char clean[8192]; int ci = 0;
    for (int i = 0; buf[i]; i++) {
        if (buf[i] == \';\') { while (buf[i] && buf[i] != \'\\n\' && buf[i] != \'\\r\') i++; i--; continue; }
        clean[ci++] = buf[i];
    }
    clean[ci] = 0;
    int rc = dnasm_exec(clean, input, atp_budget, result);
    return rc;
}
'''
if "dnasm_exec_file" not in tc:
    tc = tc.rstrip() + "\n" + exec_file_fn
    with open("transcript/transcript.c", "w") as f: f.write(tc)
    print("transcript.c patched OK")

# ── Step 3: rebuild ──
print("\\n=== Rebuilding ===")
srcs = [
    "genome/charter.c","genome/d1d4.c",
    "transcript/transcript.c","transcript/esv.c","transcript/atp.c",
    "protein/protein.c","protein/mersenne_ll.c","protein/sieve.c",
    "nsm_backend.c","av_math.c","dna_hal.c","dnasm_exec.c","boot.c"
]
for s in srcs:
    obj = s.replace(".c", ".o")
    r = subprocess.run(["gcc","-O3","-Wall","-g","-I..","-c",s,"-o",obj],
                      capture_output=True, text=True)
    if r.returncode != 0:
        print(f"ERR {s}: {r.stderr[-400:]}")
        sys.exit(1)
r = subprocess.run(["gcc","-O3"]+[s.replace(".c",".o") for s in srcs]
                  +["-lgmp","-lm","-o","dnaos2"], capture_output=True, text=True)
if r.returncode != 0:
    print(f"LINK ERR: {r.stderr[-300:]}")
    sys.exit(1)
print("Build OK")

# ── Step 4: run all bench programs ──
print("\\n=== Running Bench Programs ===")
bench_dir = "/workspace/dnaos_review/bench"
programs = sorted(os.listdir(bench_dir))

results = []
for prog in programs:
    if not prog.endswith(".dna"): continue
    path = os.path.join(bench_dir, prog)
    lines = sum(1 for _ in open(path))
    atp = 100000 if lines < 150 else 500000 if lines < 400 else 2000000

    print(f"\\n[{prog}] ({lines} lines, ATP={atp})")
    r = subprocess.run(["./dnaos2"], input=f"bench {prog}\n", capture_output=True,
                      text=True, timeout=30, cwd=SIM)
    output = r.stdout
    # Extract key lines
    key_lines = [l for l in output.split("\n")
                 if any(k in l for k in ["PRINT","RESULT","DNAVM","ERROR","ATP spent","BENCH"])]
    for l in key_lines[:8]:
        print(f"  {l}")
    results.append((prog, lines, "OK" if r.returncode == 0 else "FAIL"))
    time.sleep(0.1)

print("\\n=== Summary ===")
for prog, lines, status in results:
    mark = "✅" if status == "OK" else "❌"
    print(f"  {mark} {prog} ({lines} lines)")
print(f"\\nPassed: {sum(1 for _,_,s in results if s=='OK')}/{len(results)}")