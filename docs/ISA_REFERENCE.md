# DNAsm v3.3 ISA Reference for libbsem_math Development

## System
- NTUBES: 64 (st[0] ~ st[63])
- Data type: 64-bit signed integer
- SUB clamps to 0 (no negative numbers)
- All tube indices must be compile-time constants (no indirect addressing)
- Main program MUST be at the top of the file, subroutines after HALT

## Full Control Flow (v3.3, 9 opcodes)
- JMP @label  -- unconditional
- JZ @label   -- jump if st[a] == 0 (after CMP)
- JNZ @label  -- jump if st[a] != 0
- JE @label   -- jump if equal (after CMP)
- JNE @label  -- jump if not equal
- JL @label   -- jump if less (CMP: a < b)
- JLE @label  -- jump if less or equal
- JG @label   -- jump if greater (CMP: a > b)
- JGE @label  -- jump if greater or equal
- CALL @label -- call subroutine (stack depth 64)
- RET         -- return
- LABEL @name -- define label

## Arithmetic (13 opcodes)
- NUM st[k] N     -- load immediate N into st[k]
- ADD st[dst] st[src]  -- dst += src
- SUB st[dst] st[src]  -- dst -= src (clamps to 0)
- MUL st[dst] st[src]  -- dst *= src
- DIV st[dst] st[src]  -- dst /= src (integer, dst=0 if src=0)
- POW st[dst] N   -- dst = dst^N (N is immediate)
- SQRT st[k]      -- st[k] = floor(sqrt(st[k]))
- GCD st[a] st[b] -- st[a] = gcd(st[a], st[b])
- FIB st[k] N     -- st[k] = Fibonacci(N) (N immediate)
- FACT st[k] N    -- st[k] = N! (N immediate)
- SIN st[dst] st[src] -- dst = sin(src*0.001)*1000
- COS st[dst] st[src] -- dst = cos(src*0.001)*1000

## GPU/Vector (11 opcodes)
- PARA st[start] N OP -- mark st[start..start+N-1] as parallel region
- REDUCE_SUM st[dst] st[start] N -- sum st[start..start+N-1] into dst
- REDUCE_MAX st[dst] st[start] N -- max of range into dst
- DOT st[dst] st[a] st[b] N -- dot product of N elements
- MAD st[dst] st[a] st[b]  -- dst = dst + a*b
- LERP st[dst] st[a] st[b] t -- dst = (a*(1000-t) + b*t) / 1000
- CLAMP st[k] min max  -- clamp st[k] to [min, max]
- FMA st[dst] st[a] st[b] -- fused multiply-add (same as MAD)
- SYNC -- no-op

## I/O
- PRINT st[k]  -- print st[k] value
- HALT         -- stop execution

## CRITICAL RULES
1. SUB clamps to 0 -- no negative numbers!
2. No indirect addressing -- st[k] where k is always a literal number
3. No immediate SUB/MUL/DIV -- must NUM to a temp tube first
4. COPY is molecular operation, NOT numerical copy -- use NUM 0; ADD
5. Labels need @ prefix: LABEL @name / JMP @name
6. Tube index >= 64 = segfault
7. Comments start with # or ;

## TUBE MAP (Global Reservation)
st[0-6]:   Number A (7 digits, BASE=10^6)
st[7-13]:  Number B
st[14-20]: Number C (result/square)
st[21-27]: Number M (modulus)
st[28-34]: Number T (temp)
st[35]:    carry/borrow flag
st[36-39]: general temp (single digit)
st[40]:    CONST 0
st[41]:    CONST 1
st[42]:    CONST 2
st[43]:    CONST 999999
st[44]:    CONST 1000000 (BASE)
st[45]:    CONST 7 (N_DIGITS)
st[46]:    input parameter
st[47-48]: loop counters
st[49]:    return value
st[50-63]: MODULE-SPECIFIC workspace
            (vectors, matrices, neural network weights/activations)
