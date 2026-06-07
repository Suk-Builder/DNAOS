/*
 * ============================================================================
 * DNAOS - ATCG-native Virtual File System
 * ============================================================================
 * 
 * File names are ATCG-encoded. Directory structure mirrors DNA:
 *   /           → root
 *   /genome/    → system configuration (ATCG-encoded)
 *   /ribosome/  → executable programs
 *   /membrane/  → I/O devices
 *   /nucleus/   → kernel data
 *   /atp/       → energy accounting
 *   /codon/     → user files
 *
 * VFS operations:
 *   - open, close, read, write, seek
 *   - mkdir, rmdir, ls
 *   - mount filesystems
 *
 * Built-in filesystem: ramfs (in-memory, ATCG-native)
 * ============================================================================
 */

#ifndef VFS_H
#define VFS_H

#include <stdint.h>

#define MAX_FILENAME    64
#define MAX_PATH        256
#define MAX_FILES       128
#define MAX_MOUNTS      16
#define MAX_OPEN_FILES  32
#define MAX_DIR_ENTRIES 64
#define SECTOR_SIZE     512

/* File types */
typedef enum {
    FILE_NONE = 0,
    FILE_REGULAR,
    FILE_DIRECTORY,
    FILE_DEVICE,
    FILE_PIPE,
    FILE_SYMLINK
} file_type_t;

/* File permissions (ATCG-based) */
typedef enum {
    PERM_NONE  = 0,     /* ---- */
    PERM_READ  = 1,     /* r--- (A) */
    PERM_WRITE = 2,     /* -w-- (T) */
    PERM_EXEC  = 4,     /* --x- (C) */
    PERM_ATCG  = 8      /* ---a (G = ATCG meta) */
} file_perm_t;

/* Seek whence */
typedef enum {
    SEEK_SET = 0,
    SEEK_CUR = 1,
    SEEK_END = 2
} seek_whence_t;

/* Filesystem types */
typedef enum {
    FS_RAMFS = 0,
    FS_FAT32,
    FS_EXT2,
    FS_ATCGFS     /* Our native ATCG-encoded filesystem */
} fs_type_t;

/* Forward declarations */
typedef struct vnode vnode_t;
typedef struct file file_t;
typedef struct dentry dentry_t;

/* Inode - represents a file on disk */
typedef struct inode {
    uint64_t        ino;            /* Inode number */
    file_type_t     type;
    uint64_t        size;
    uint64_t        nlinks;
    uint64_t        atp_cost;       /* ATP cost to read/write */
    uint64_t        created;
    uint64_t        modified;
    uint32_t        permissions;
    uint32_t        uid;
    uint32_t        gid;
    uint8_t        *data;           /* For ramfs: pointer to data */
    uint64_t        data_capacity;  /* Allocated size */
} inode_t;

/* Directory entry */
struct dentry {
    char            name[MAX_FILENAME];
    inode_t        *inode;
    dentry_t       *parent;
    dentry_t       *child;         /* First child */
    dentry_t       *next;          /* Next sibling */
    int             mounted;       /* Is a mount point? */
    fs_type_t       fs_type;
};

/* Open file descriptor */
struct file {
    int             fd;
    inode_t        *inode;
    dentry_t       *dentry;
    uint64_t        offset;
    uint32_t        flags;         /* O_RDONLY, O_WRONLY, O_RDWR */
    int             in_use;
};

/* Mount point */
typedef struct mount {
    dentry_t       *mountpoint;
    fs_type_t       fs_type;
    inode_t        *root_inode;
    int             in_use;
} mount_t;

/* ============================================================================
 * Global state
 * ============================================================================
 */
static inode_t     inode_table[MAX_FILES];
static file_t      open_files[MAX_OPEN_FILES];
static mount_t     mount_table[MAX_MOUNTS];
static dentry_t    root_dentry;
static int         next_fd = 3; /* 0=stdin, 1=stdout, 2=stderr */
static int         next_ino = 1;

/* ============================================================================
 * ATCG Encoding for filenames
 * ============================================================================
 */
static const char atcg_chars[] = "ATCG";

/* Encode a byte as 4 ATCG characters */
static void encode_atcg(uint8_t byte, char *out) {
    out[0] = atcg_chars[(byte >> 6) & 0x03];
    out[1] = atcg_chars[(byte >> 4) & 0x03];
    out[2] = atcg_chars[(byte >> 2) & 0x03];
    out[3] = atcg_chars[byte & 0x03];
}

/* Decode 4 ATCG characters to a byte */
static uint8_t decode_atcg(const char *in) {
    uint8_t result = 0;
    for (int i = 0; i < 4; i++) {
        result <<= 2;
        switch (in[i]) {
            case 'A': result |= 0; break;
            case 'T': result |= 1; break;
            case 'C': result |= 2; break;
            case 'G': result |= 3; break;
        }
    }
    return result;
}

/* Encode a string to ATCG */
static int str_to_atcg(const char *str, char *out, int outsize) {
    int len = 0;
    while (*str && len < outsize - 4) {
        encode_atcg((uint8_t)*str, out + len);
        len += 4;
        str++;
    }
    out[len] = '\0';
    return len;
}

/* Decode ATCG to string */
static int atcg_to_str(const char *atcg, char *out, int outsize) {
    int alen = 0;
    int olen = 0;
    while (atcg[alen] && atcg[alen+1] && atcg[alen+2] && atcg[alen+3] 
           && olen < outsize - 1) {
        out[olen++] = decode_atcg(atcg + alen);
        alen += 4;
    }
    out[olen] = '\0';
    return olen;
}

/* ============================================================================
 * Inode operations
 * ============================================================================
 */
static inode_t *inode_alloc(void) {
    for (int i = 0; i < MAX_FILES; i++) {
        if (inode_table[i].ino == 0) {
            inode_table[i].ino = next_ino++;
            return &inode_table[i];
        }
    }
    return 0;
}

static void inode_free(inode_t *ino) {
    if (ino->data) {
        /* In ramfs, data was allocated from PMM */
        ino->data = 0;
    }
    ino->ino = 0;
    ino->size = 0;
    ino->data_capacity = 0;
}

/* ============================================================================
 * Dentry operations
 * ============================================================================
 */
static dentry_t *dentry_alloc(const char *name, inode_t *inode, dentry_t *parent) {
    dentry_t *d = (dentry_t *)0; /* Would use kmalloc in real impl */
    /* For now, use static allocation from a pool */
    static dentry_t dentry_pool[MAX_DIR_ENTRIES * 2];
    static int dentry_next = 0;
    
    if (dentry_next >= MAX_DIR_ENTRIES * 2) return 0;
    d = &dentry_pool[dentry_next++];
    
    for (int i = 0; i < MAX_FILENAME; i++) {
        d->name[i] = name[i];
        if (name[i] == '\0') break;
    }
    d->inode = inode;
    d->parent = parent;
    d->child = 0;
    d->next = 0;
    d->mounted = 0;
    d->fs_type = FS_RAMFS;
    
    /* Add to parent's child list */
    if (parent) {
        d->next = parent->child;
        parent->child = d;
    }
    
    return d;
}

/* Find a dentry by name in a directory */
static dentry_t *dentry_lookup(dentry_t *dir, const char *name) {
    dentry_t *child = dir->child;
    while (child) {
        int match = 1;
        for (int i = 0; i < MAX_FILENAME; i++) {
            if (child->name[i] != name[i]) { match = 0; break; }
            if (child->name[i] == '\0') break;
        }
        if (match) return child;
        child = child->next;
    }
    return 0;
}

/* ============================================================================
 * VFS operations
 * ============================================================================
 */

/* Resolve a path to a dentry */
static dentry_t *vfs_resolve(const char *path) {
    if (path[0] != '/') return 0;
    if (path[1] == '\0') return &root_dentry;
    
    dentry_t *current = &root_dentry;
    const char *p = path + 1;
    char component[MAX_FILENAME];
    
    while (*p) {
        /* Extract path component */
        int i = 0;
        while (*p && *p != '/' && i < MAX_FILENAME - 1) {
            component[i++] = *p++;
        }
        component[i] = '\0';
        if (*p == '/') p++;
        
        /* Look up in current directory */
        current = dentry_lookup(current, component);
        if (!current) return 0;
    }
    
    return current;
}

/* Open a file */
static file_t *vfs_open(const char *path, uint32_t flags) {
    dentry_t *d = vfs_resolve(path);
    if (!d || !d->inode) return 0;
    
    /* Find free file descriptor */
    for (int i = 0; i < MAX_OPEN_FILES; i++) {
        if (!open_files[i].in_use) {
            open_files[i].fd = next_fd++;
            open_files[i].inode = d->inode;
            open_files[i].dentry = d;
            open_files[i].offset = 0;
            open_files[i].flags = flags;
            open_files[i].in_use = 1;
            return &open_files[i];
        }
    }
    return 0;
}

/* Close a file */
static int vfs_close(file_t *f) {
    if (!f || !f->in_use) return -1;
    f->in_use = 0;
    return 0;
}

/* Read from a file */
static int vfs_read(file_t *f, void *buf, uint64_t count) {
    if (!f || !f->in_use || !f->inode) return -1;
    
    inode_t *ino = f->inode;
    uint64_t remaining = ino->size - f->offset;
    if (remaining <= 0) return 0;
    
    uint64_t to_read = count < remaining ? count : remaining;
    uint8_t *src = ino->data + f->offset;
    uint8_t *dst = (uint8_t *)buf;
    
    for (uint64_t i = 0; i < to_read; i++) {
        dst[i] = src[i];
    }
    
    f->offset += to_read;
    return (int)to_read;
}

/* Write to a file */
static int vfs_write(file_t *f, const void *buf, uint64_t count) {
    if (!f || !f->in_use || !f->inode) return -1;
    
    inode_t *ino = f->inode;
    uint64_t needed = f->offset + count;
    
    /* Grow data buffer if needed (ramfs) */
    if (needed > ino->data_capacity) {
        uint64_t new_cap = (needed + 4095) & ~0xFFF; /* Page align */
        uint8_t *new_data = (uint8_t *)pmm_alloc_pages(new_cap / PAGE_SIZE);
        if (!new_data) return -1;
        
        /* Copy old data */
        if (ino->data) {
            for (uint64_t i = 0; i < ino->size; i++) {
                new_data[i] = ino->data[i];
            }
        }
        
        ino->data = new_data;
        ino->data_capacity = new_cap;
    }
    
    /* Write data */
    const uint8_t *src = (const uint8_t *)buf;
    for (uint64_t i = 0; i < count; i++) {
        ino->data[f->offset + i] = src[i];
    }
    
    f->offset += count;
    if (f->offset > ino->size) ino->size = f->offset;
    
    return (int)count;
}

/* Seek in a file */
static int vfs_seek(file_t *f, int64_t offset, seek_whence_t whence) {
    if (!f || !f->in_use) return -1;
    
    int64_t new_offset;
    switch (whence) {
        case SEEK_SET: new_offset = offset; break;
        case SEEK_CUR: new_offset = f->offset + offset; break;
        case SEEK_END: new_offset = f->inode->size + offset; break;
        default: return -1;
    }
    
    if (new_offset < 0) return -1;
    f->offset = (uint64_t)new_offset;
    return 0;
}

/* Create a file */
static dentry_t *vfs_create(const char *path, file_type_t type) {
    /* Find parent directory */
    const char *last_slash = path;
    for (const char *p = path; *p; p++) {
        if (*p == '/') last_slash = p;
    }
    
    char parent_path[MAX_PATH];
    char filename[MAX_FILENAME];
    
    int parent_len = last_slash - path;
    for (int i = 0; i < parent_len && i < MAX_PATH - 1; i++) {
        parent_path[i] = path[i];
    }
    parent_path[parent_len] = '\0';
    if (parent_len == 0) {
        parent_path[0] = '/'; parent_path[1] = '\0';
    }
    
    int j = 0;
    last_slash++;
    while (*last_slash && j < MAX_FILENAME - 1) {
        filename[j++] = *last_slash++;
    }
    filename[j] = '\0';
    
    dentry_t *parent = vfs_resolve(parent_path);
    if (!parent) return 0;
    
    /* Check if already exists */
    if (dentry_lookup(parent, filename)) return 0;
    
    /* Create inode */
    inode_t *ino = inode_alloc();
    if (!ino) return 0;
    
    ino->type = type;
    ino->size = 0;
    ino->data = 0;
    ino->data_capacity = 0;
    ino->permissions = PERM_READ | PERM_WRITE;
    ino->atp_cost = 1;
    
    /* Create dentry */
    return dentry_alloc(filename, ino, parent);
}

/* List directory contents */
static int vfs_ls(const char *path, char *buf, int bufsize) {
    dentry_t *dir = vfs_resolve(path);
    if (!dir || !dir->inode || dir->inode->type != FILE_DIRECTORY) return -1;
    
    int pos = 0;
    dentry_t *child = dir->child;
    while (child && pos < bufsize - 80) {
        /* Name */
        int i = 0;
        while (child->name[i] && pos < bufsize - 80) {
            buf[pos++] = child->name[i++];
        }
        
        /* Type indicator */
        if (child->inode) {
            switch (child->inode->type) {
                case FILE_DIRECTORY: buf[pos++] = '/'; break;
                case FILE_DEVICE:    buf[pos++] = '@'; break;
                case FILE_PIPE:      buf[pos++] = '|'; break;
                default: break;
            }
        }
        
        /* Size */
        if (child->inode && child->inode->type == FILE_REGULAR) {
            buf[pos++] = ' ';
            uint64_t sz = child->inode->size;
            char num[20]; int ni = 0;
            if (sz == 0) num[ni++] = '0';
            while (sz > 0) { num[ni++] = '0' + (sz % 10); sz /= 10; }
            for (int k = ni - 1; k >= 0; k--) buf[pos++] = num[k];
        }
        
        buf[pos++] = '\n';
        child = child->next;
    }
    
    buf[pos] = '\0';
    return pos;
}

/* ============================================================================
 * Initialize VFS with DNA directory structure
 * ============================================================================
 */
static void vfs_init(void) {
    /* Clear tables */
    for (int i = 0; i < MAX_FILES; i++) inode_table[i].ino = 0;
    for (int i = 0; i < MAX_OPEN_FILES; i++) open_files[i].in_use = 0;
    for (int i = 0; i < MAX_MOUNTS; i++) mount_table[i].in_use = 0;
    
    /* Create root */
    root_dentry.name[0] = '/'; root_dentry.name[1] = '\0';
    inode_t *root_ino = inode_alloc();
    root_ino->type = FILE_DIRECTORY;
    root_ino->size = 0;
    root_ino->permissions = PERM_READ | PERM_WRITE | PERM_EXEC;
    root_dentry.inode = root_ino;
    root_dentry.parent = 0;
    root_dentry.child = 0;
    root_dentry.next = 0;
    
    /* Create DNA directory structure */
    vfs_create("/genome",   FILE_DIRECTORY);  /* System config */
    vfs_create("/ribosome", FILE_DIRECTORY);  /* Executables */
    vfs_create("/membrane", FILE_DIRECTORY);  /* I/O devices */
    vfs_create("/nucleus",  FILE_DIRECTORY);  /* Kernel data */
    vfs_create("/atp",      FILE_DIRECTORY);  /* Energy accounting */
    vfs_create("/codon",    FILE_DIRECTORY);  /* User files */
    
    /* Create system files */
    dentry_t *d;
    
    /* /nucleus/version */
    d = vfs_create("/nucleus/version", FILE_REGULAR);
    if (d) {
        file_t *f = vfs_open("/nucleus/version", 2); /* O_RDWR */
        if (f) {
            const char *ver = "DNAOS v3.5\nATCG Native\n";
            vfs_write(f, ver, 20);
            vfs_close(f);
        }
    }
    
    /* /nucleus/charter */
    d = vfs_create("/nucleus/charter", FILE_REGULAR);
    if (d) {
        file_t *f = vfs_open("/nucleus/charter", 2);
        if (f) {
            const char *charter = "UNITED NATIONS CHARTER OF ALL UNIVERSES\n";
            vfs_write(f, charter, 40);
            vfs_close(f);
        }
    }
    
    /* /genome/boot.cfg */
    d = vfs_create("/genome/boot.cfg", FILE_REGULAR);
    if (d) {
        file_t *f = vfs_open("/genome/boot.cfg", 2);
        if (f) {
            const char *cfg = "resolution=1280x720\natp_budget=10000000000\n";
            vfs_write(f, cfg, 40);
            vfs_close(f);
        }
    }
    
    /* /atp/budget */
    d = vfs_create("/atp/budget", FILE_REGULAR);
    if (d) {
        file_t *f = vfs_open("/atp/budget", 2);
        if (f) {
            const char *atp = "10000000000";
            vfs_write(f, atp, 11);
            vfs_close(f);
        }
    }
}

#endif /* VFS_H */
