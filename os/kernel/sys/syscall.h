/*
 * ============================================================================
 * DNAOS - System Call Interface
 * ============================================================================
 * 
 * Syscall convention (similar to Linux):
 *   rax = syscall number
 *   rdi = arg1
 *   rsi = arg2
 *   rdx = arg3
 *   r10 = arg4
 *   r8  = arg5
 *   r9  = arg6
 *   Return: rax = result (negative = error)
 *
 * Syscall numbers:
 *   0x00  read(fd, buf, count)
 *   0x01  write(fd, buf, count)
 *   0x02  open(path, flags)
 *   0x03  close(fd)
 *   0x04  seek(fd, offset, whence)
 *   0x05  mkdir(path)
 *   0x06  ls(path, buf, size)
 *   0x07  exec(path, argv)
 *   0x08  fork()
 *   0x09  exit(code)
 *   0x0A  getpid()
 *   0x0B  atp_query()
 *   0x0C  atp_consume(amount)
 *   0x0D  quat_and(a, b)
 *   0x0E  quat_or(a, b)
 *   0x0F  quat_not(a)
 *   0x10  quat_add(a, b)
 *   0x11  encode_atcg(buf, len)
 *   0x12  decode_atcg(buf, len)
 *   0x13  fb_draw(x, y, color)
 *   0x14  fb_print(x, y, str, color)
 *   0x15  kbd_read()
 *   0x16  proc_list(buf, size)
 *   0x17  mem_info(buf, size)
 *   0x18  yield()
 *   0x19  sleep(ms)
 *   0x1A  time()
 * ============================================================================
 */

#ifndef SYSCALL_H
#define SYSCALL_H

#include <stdint.h>

/* Syscall numbers */
#define SYS_READ        0x00
#define SYS_WRITE       0x01
#define SYS_OPEN        0x02
#define SYS_CLOSE       0x03
#define SYS_SEEK        0x04
#define SYS_MKDIR       0x05
#define SYS_LS          0x06
#define SYS_EXEC        0x07
#define SYS_FORK        0x08
#define SYS_EXIT        0x09
#define SYS_GETPID      0x0A
#define SYS_ATP_QUERY   0x0B
#define SYS_ATP_CONSUME 0x0C
#define SYS_QUAT_AND    0x0D
#define SYS_QUAT_OR     0x0E
#define SYS_QUAT_NOT    0x0F
#define SYS_QUAT_ADD    0x10
#define SYS_ENCODE_ATCG 0x11
#define SYS_DECODE_ATCG 0x12
#define SYS_FB_DRAW     0x13
#define SYS_FB_PRINT    0x14
#define SYS_KBD_READ    0x15
#define SYS_PROC_LIST   0x16
#define SYS_MEM_INFO    0x17
#define SYS_YIELD       0x18
#define SYS_SLEEP       0x19
#define SYS_TIME        0x1A

/* Error codes */
#define EPERM   -1   /* Operation not permitted */
#define ENOENT  -2   /* No such file or directory */
#define EIO     -3   /* I/O error */
#define ENOMEM  -4   /* Out of memory */
#define EACCES  -5   /* Permission denied */
#define EINVAL  -6   /* Invalid argument */
#define ENOSYS  -7   /* Not implemented */
#define EMFILE  -8   /* Too many open files */

/* Syscall handler - called from interrupt 0x80 or syscall instruction */
static int64_t syscall_handler(uint64_t nr, uint64_t a1, uint64_t a2, 
                                uint64_t a3, uint64_t a4, uint64_t a5) {
    switch (nr) {
        case SYS_READ: {
            /* read(fd, buf, count) */
            /* In real impl: validate buf pointer, find file, read */
            return ENOSYS;
        }
        
        case SYS_WRITE: {
            /* write(fd, buf, count) */
            /* Special: fd=1 = stdout = framebuffer console */
            if (a1 == 1 || a1 == 2) {
                const char *str = (const char *)a2;
                uint64_t count = a3;
                /* Write to console */
                for (uint64_t i = 0; i < count; i++) {
                    /* console_putchar would be called here */
                    (void)str;
                }
                return (int64_t)count;
            }
            return ENOSYS;
        }
        
        case SYS_OPEN: {
            /* open(path, flags) */
            return ENOSYS;
        }
        
        case SYS_CLOSE: {
            return 0;
        }
        
        case SYS_ATP_QUERY: {
            /* Return remaining ATP for current process */
            return 0; /* Would return current_proc->atp_budget - current_proc->atp_used */
        }
        
        case SYS_ATP_CONSUME: {
            /* Consume ATP */
            return 0;
        }
        
        case SYS_QUAT_AND: {
            /* Quaternary AND (min) */
            uint64_t ra = a1, rb = a2;
            uint64_t result = 0;
            for (int i = 0; i < 4; i++) {
                uint8_t x = (ra >> (i*2)) & 3;
                uint8_t y = (rb >> (i*2)) & 3;
                result |= (uint64_t)(x < y ? x : y) << (i*2);
            }
            return (int64_t)result;
        }
        
        case SYS_QUAT_OR: {
            /* Quaternary OR (max) */
            uint64_t ra = a1, rb = a2;
            uint64_t result = 0;
            for (int i = 0; i < 4; i++) {
                uint8_t x = (ra >> (i*2)) & 3;
                uint8_t y = (rb >> (i*2)) & 3;
                result |= (uint64_t)(x > y ? x : y) << (i*2);
            }
            return (int64_t)result;
        }
        
        case SYS_QUAT_NOT: {
            /* Quaternary NOT (3-x) */
            uint64_t ra = a1;
            uint64_t result = 0;
            for (int i = 0; i < 4; i++) {
                uint8_t x = (ra >> (i*2)) & 3;
                result |= (uint64_t)(3 - x) << (i*2);
            }
            return (int64_t)result;
        }
        
        case SYS_QUAT_ADD: {
            /* Quaternary ADD with carry */
            uint64_t ra = a1, rb = a2;
            uint64_t result = 0;
            uint8_t carry = 0;
            for (int i = 0; i < 4; i++) {
                uint8_t x = (ra >> (i*2)) & 3;
                uint8_t y = (rb >> (i*2)) & 3;
                uint8_t s = x + y + carry;
                result |= (uint64_t)(s % 4) << (i*2);
                carry = s / 4;
            }
            return (int64_t)result;
        }
        
        case SYS_ENCODE_ATCG: {
            /* Encode buffer as ATCG */
            return ENOSYS;
        }
        
        case SYS_DECODE_ATCG: {
            /* Decode ATCG buffer */
            return ENOSYS;
        }
        
        case SYS_GETPID: {
            return 0; /* current_proc->pid */
        }
        
        case SYS_YIELD: {
            /* scheduler_tick(); */
            return 0;
        }
        
        case SYS_TIME: {
            /* Return tick count */
            return 0; /* scheduler_ticks */
        }
        
        case SYS_EXIT: {
            /* proc_kill(current_proc, a1); */
            return 0;
        }
        
        default:
            return ENOSYS;
    }
}

/* Syscall entry point (called from assembly) */
/* User code: syscall instruction or int 0x80 */
void syscall_entry(void); /* Implemented in boot.S */

/* Initialize syscall interface */
static void syscall_init(void) {
    /* Set up MSR for SYSCALL/SYSRET (faster than int 0x80) */
    uint64_t star = ((uint64_t)0x08 << 32) | ((uint64_t)0x00 << 48);
    uint64_t lstar = (uint64_t)syscall_entry;
    uint64_t sfmask = 0;
    
    __asm__ volatile (
        "wrmsr" :: "c"(0xC0000081), "a"((uint32_t)star), "d"((uint32_t)(star >> 32))
    );
    __asm__ volatile (
        "wrmsr" :: "c"(0xC0000082), "a"((uint32_t)lstar), "d"((uint32_t)(lstar >> 32))
    );
    __asm__ volatile (
        "wrmsr" :: "c"(0xC0000084), "a"((uint32_t)sfmask), "d"((uint32_t)(sfmask >> 32))
    );
    
    /* Enable SCE (System Call Enable) in EFER */
    uint32_t efer_lo, efer_hi;
    __asm__ volatile (
        "rdmsr" : "=a"(efer_lo), "=d"(efer_hi) : "c"(0xC0000080)
    );
    efer_lo |= 1; /* SCE bit */
    __asm__ volatile (
        "wrmsr" :: "c"(0xC0000080), "a"(efer_lo), "d"(efer_hi)
    );
}

#endif /* SYSCALL_H */
