"""
DNAOS Desktop - ATCG-native Desktop Environment
A complete desktop OS experience with start menu, file manager, terminal, and more.

Run: python3 dnaos_desktop.py
Press F11 for fullscreen
"""

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import os, time, threading, math, random, json, subprocess, platform

# ============================================================================
# Theme - ATCG Color System
# ============================================================================
class ATCGTheme:
    # Base colors
    A_GREEN   = "#4CAF50"
    T_RED     = "#F44336"
    C_BLUE    = "#2196F3"
    G_YELLOW  = "#FFEB3B"
    
    # UI colors
    BG_DARK       = "#0A0E1A"
    BG_DESKTOP    = "#0D1117"
    BG_WINDOW     = "#161B22"
    BG_TITLEBAR   = "#1C2333"
    BG_PANEL      = "#0D1117"
    BG_START      = "#1A1F2E"
    BG_HOVER      = "#21262D"
    BG_ACTIVE     = "#2D333B"
    BG_INPUT      = "#0D1117"
    BG_SIDEBAR    = "#111827"
    
    FG_PRIMARY    = "#E6EDF3"
    FG_SECONDARY  = "#8B949E"
    FG_MUTED      = "#484F58"
    FG_ACCENT     = "#58A6FF"
    
    BORDER        = "#30363D"
    BORDER_FOCUS  = "#58A6FF"
    
    # Fonts
    FONT_SYSTEM = ("Segoe UI", "PingFang SC", "Noto Sans CJK SC", 10)
    FONT_TITLE  = ("Segoe UI", "PingFang SC", "Noto Sans CJK SC", 9, "bold")
    FONT_MONO   = ("Cascadia Code", "Fira Code", "Consolas", 11)
    FONT_ICON   = ("Segoe UI Emoji", 14)
    FONT_LARGE  = ("Segoe UI", "PingFang SC", 24, "bold")
    
    # Window dimensions
    WIN_MIN_W = 400
    WIN_MIN_H = 300


theme = ATCGTheme()


# ============================================================================
# Quaternary Core
# ============================================================================
class QuaternaryCore:
    """ATCG-native computation engine"""
    
    BASE_MAP = {0: 'A', 1: 'T', 2: 'C', 3: 'G'}
    BASE_REV = {'A': 0, 'T': 1, 'C': 2, 'G': 3}
    
    @staticmethod
    def encode(data: bytes) -> str:
        """Encode bytes to ATCG string"""
        result = []
        for byte in data:
            for i in range(3, -1, -1):
                base_val = (byte >> (i * 2)) & 0x03
                result.append(QuaternaryCore.BASE_MAP[base_val])
        return ''.join(result)
    
    @staticmethod
    def decode(atcg: str) -> bytes:
        """Decode ATCG string to bytes"""
        atcg = atcg.upper().replace(' ', '')
        if len(atcg) % 4 != 0:
            atcg += 'A' * (4 - len(atcg) % 4)
        result = []
        for i in range(0, len(atcg), 4):
            byte = 0
            for j in range(4):
                if i + j < len(atcg):
                    byte |= QuaternaryCore.BASE_REV.get(atcg[i + j], 0) << (6 - j * 2)
            result.append(byte)
        return bytes(result)
    
    @staticmethod
    def quat_and(a, b):
        return min(a, b)
    
    @staticmethod
    def quat_or(a, b):
        return max(a, b)
    
    @staticmethod
    def quat_not(a):
        return 3 - a
    
    @staticmethod
    def quat_add(a, b, carry=0):
        s = a + b + carry
        return s % 4, s // 4


# ============================================================================
# ATP Engine
# ============================================================================
class ATPEngine:
    """Energy metabolism system - every operation costs ATP"""
    
    def __init__(self, budget=10_000_000_000):
        self.budget = budget
        self.remaining = budget
        self.exhausted = False
        self.ops_count = 0
        self.listeners = []
    
    def consume(self, amount=1):
        if self.exhausted:
            return False
        self.remaining -= amount
        self.ops_count += 1
        if self.remaining <= 0:
            self.remaining = 0
            self.exhausted = True
            self._notify_exhausted()
        return True
    
    def add_listener(self, callback):
        self.listeners.append(callback)
    
    def _notify_exhausted(self):
        for cb in self.listeners:
            cb()
    
    @property
    def percentage(self):
        return (self.remaining / self.budget) * 100 if self.budget > 0 else 0
    
    @property
    def atcg_status(self):
        """Return ATP status as ATCG encoding"""
        pct = self.percentage
        if pct > 75: return "GGGG"  # Full energy
        if pct > 50: return "CGGG"
        if pct > 25: return "TCGG"
        if pct > 10: return "ATCG"
        if pct > 0:  return "AATC"
        return "AAAA"  # Exhausted


# ============================================================================
# Window Manager
# ============================================================================
class DNAOSWindow(tk.Toplevel):
    """Custom window with title bar, drag, close, minimize"""
    
    def __init__(self, parent, title="DNAOS Window", width=700, height=500, 
                 app_icon="📄", resizable=True):
        super().__init__(parent)
        self.title_text = title
        self.app_icon = app_icon
        self.is_maximized = False
        self._drag_data = {"x": 0, "y": 0}
        
        self.configure(bg=theme.BG_WINDOW)
        self.geometry(f"{width}x{height}")
        self.overrideredirect(True)
        self.minsize(theme.WIN_MIN_W, theme.WIN_MIN_H)
        
        # Shadow effect
        self.attributes('-alpha', 0.98)
        
        self._build_titlebar(resizable)
        self._setup_bindings()
        
        # Center on screen
        self.update_idletasks()
        x = (self.winfo_screenwidth() - width) // 2
        y = (self.winfo_screenheight() - height) // 2 - 30
        self.geometry(f"+{x}+{y}")
        
        # Focus
        self.lift()
        self.focus_force()
    
    def _build_titlebar(self, resizable):
        # Title bar
        self.titlebar = tk.Frame(self, bg=theme.BG_TITLEBAR, height=36)
        self.titlebar.pack(fill=tk.X, side=tk.TOP)
        self.titlebar.pack_propagate(False)
        
        # Icon + Title
        self.title_label = tk.Label(
            self.titlebar, text=f"  {self.app_icon}  {self.title_text}",
            bg=theme.BG_TITLEBAR, fg=theme.FG_PRIMARY,
            font=theme.FONT_TITLE, anchor=tk.W
        )
        self.title_label.pack(side=tk.LEFT, fill=tk.X, expand=True)
        
        # Window controls
        btn_frame = tk.Frame(self.titlebar, bg=theme.BG_TITLEBAR)
        btn_frame.pack(side=tk.RIGHT)
        
        if resizable:
            self.btn_max = tk.Label(btn_frame, text=" □ ", bg=theme.BG_TITLEBAR,
                                     fg=theme.FG_SECONDARY, font=theme.FONT_SYSTEM,
                                     cursor="hand2")
            self.btn_max.pack(side=tk.LEFT, pady=4)
            self.btn_max.bind("<Button-1>", self._toggle_maximize)
            self.btn_max.bind("<Enter>", lambda e: self.btn_max.configure(bg=theme.BG_HOVER))
            self.btn_max.bind("<Leave>", lambda e: self.btn_max.configure(bg=theme.BG_TITLEBAR))
        
        self.btn_min = tk.Label(btn_frame, text=" — ", bg=theme.BG_TITLEBAR,
                                 fg=theme.FG_SECONDARY, font=theme.FONT_SYSTEM,
                                 cursor="hand2")
        self.btn_min.pack(side=tk.LEFT, pady=4)
        self.btn_min.bind("<Button-1>", self._minimize)
        self.btn_min.bind("<Enter>", lambda e: self.btn_min.configure(bg=theme.BG_HOVER))
        self.btn_min.bind("<Leave>", lambda e: self.btn_min.configure(bg=theme.BG_TITLEBAR))
        
        self.btn_close = tk.Label(btn_frame, text=" ✕ ", bg=theme.BG_TITLEBAR,
                                   fg=theme.FG_SECONDARY, font=theme.FONT_SYSTEM,
                                   cursor="hand2")
        self.btn_close.pack(side=tk.LEFT, pady=4)
        self.btn_close.bind("<Button-1>", self._close)
        self.btn_close.bind("<Enter>", lambda e: self.btn_close.configure(bg="#DA3633", fg="white"))
        self.btn_close.bind("<Leave>", lambda e: self.btn_close.configure(bg=theme.BG_TITLEBAR, fg=theme.FG_SECONDARY))
        
        # Content area
        self.content = tk.Frame(self, bg=theme.BG_WINDOW)
        self.content.pack(fill=tk.BOTH, expand=True, padx=1, pady=(0, 1))
        
        # Border
        self.border_frame = tk.Frame(self, bg=theme.BORDER, bd=1)
    
    def _setup_bindings(self):
        self.titlebar.bind("<Button-1>", self._start_drag)
        self.titlebar.bind("<B1-Motion>", self._on_drag)
        self.title_label.bind("<Button-1>", self._start_drag)
        self.title_label.bind("<B1-Motion>", self._on_drag)
        self.bind("<FocusIn>", lambda e: self._set_active(True))
        self.bind("<FocusOut>", lambda e: self._set_active(False))
    
    def _start_drag(self, event):
        self._drag_data["x"] = event.x
        self._drag_data["y"] = event.y
    
    def _on_drag(self, event):
        x = self.winfo_x() + event.x - self._drag_data["x"]
        y = self.winfo_y() + event.y - self._drag_data["y"]
        self.geometry(f"+{x}+{y}")
    
    def _toggle_maximize(self, event=None):
        if self.is_maximized:
            self.geometry(self._prev_geometry)
            self.is_maximized = False
        else:
            self._prev_geometry = self.geometry()
            self.geometry(f"0x0+0+0")
            self.geometry(f"{self.winfo_screenwidth()}x{self.winfo_screenheight() - 48}")
            self.is_maximized = True
    
    def _minimize(self, event=None):
        self.withdraw()
    
    def _close(self, event=None):
        self.destroy()
    
    def _set_active(self, active):
        color = theme.BG_TITLEBAR if active else theme.BG_DARK
        self.titlebar.configure(bg=color)
        self.title_label.configure(bg=color)


# ============================================================================
# Desktop
# ============================================================================
class Desktop:
    """Main desktop with wallpaper, icons, and right-click menu"""
    
    def __init__(self, root, wm):
        self.root = root
        self.wm = wm
        self.canvas = tk.Canvas(root, bg=theme.BG_DESKTOP, highlightthickness=0)
        self.canvas.pack(fill=tk.BOTH, expand=True)
        
        self._draw_wallpaper()
        self._draw_icons()
        self._setup_context_menu()
    
    def _draw_wallpaper(self):
        self.canvas.bind("<Configure>", self._on_resize)
    
    def _on_resize(self, event=None):
        self.canvas.delete("all")
        w = self.canvas.winfo_width()
        h = self.canvas.winfo_height()
        
        # DNA helix wallpaper
        cx = w // 2
        for y in range(0, h, 3):
            t = y * 0.02
            x1 = cx + math.sin(t) * 120
            x2 = cx - math.sin(t) * 120
            
            # Helix strands
            alpha = 0.15 + 0.1 * math.sin(t * 0.5)
            color_val = int(30 + 20 * math.sin(t * 0.3))
            color = f"#{color_val:02x}{color_val + 10:02x}{color_val + 30:02x}"
            
            self.canvas.create_oval(x1 - 3, y - 1, x1 + 3, y + 1, fill=theme.A_GREEN, outline="")
            self.canvas.create_oval(x2 - 3, y - 1, x2 + 3, y + 1, fill=theme.C_BLUE, outline="")
            
            # Cross bars
            if y % 30 < 3:
                self.canvas.create_line(x1, y, x2, y, fill=theme.BORDER, width=1)
        
        # Logo
        self.canvas.create_text(cx, h // 3, text="DNAOS", 
                               font=("Segoe UI", 48, "bold"), fill="#1A2332")
        self.canvas.create_text(cx, h // 3 + 50, text="Quaternary Operating System",
                               font=theme.FONT_SYSTEM, fill="#1A2332")
    
    def _draw_icons(self):
        icons = [
            ("📁", "文件管理", self._open_file_manager),
            ("💻", "终端", self._open_terminal),
            ("📝", "编辑器", self._open_editor),
            ("⚙️", "设置", self._open_settings),
            ("📊", "系统监控", self._open_sysmon),
        ]
        
        start_x = 40
        start_y = 40
        for i, (icon, label, cmd) in enumerate(icons):
            y = start_y + i * 90
            frame = tk.Frame(self.canvas, bg=theme.BG_DESKTOP, cursor="hand2")
            self.canvas.create_window(start_x, y, window=frame, anchor=tk.NW)
            
            lbl_icon = tk.Label(frame, text=icon, font=theme.FONT_ICON,
                               bg=theme.BG_DESKTOP, fg=theme.FG_PRIMARY)
            lbl_icon.pack()
            lbl_text = tk.Label(frame, text=label, font=theme.FONT_SYSTEM,
                               bg=theme.BG_DESKTOP, fg=theme.FG_SECONDARY)
            lbl_text.pack()
            
            for w in (frame, lbl_icon, lbl_text):
                w.bind("<Double-Button-1>", lambda e, c=cmd: c())
                w.bind("<Enter>", lambda e, f=frame, li=lbl_icon, lt=lbl_text: 
                       (f.configure(bg=theme.BG_HOVER), li.configure(bg=theme.BG_HOVER), 
                        lt.configure(bg=theme.BG_HOVER)))
                w.bind("<Leave>", lambda e, f=frame, li=lbl_icon, lt=lbl_text: 
                       (f.configure(bg=theme.BG_DESKTOP), li.configure(bg=theme.BG_DESKTOP), 
                        lt.configure(bg=theme.BG_DESKTOP)))
    
    def _setup_context_menu(self):
        self.context_menu = tk.Menu(self.root, tearoff=0, bg=theme.BG_WINDOW,
                                    fg=theme.FG_PRIMARY, activebackground=theme.BG_ACTIVE,
                                    activeforeground=theme.FG_PRIMARY,
                                    font=theme.FONT_SYSTEM)
        self.context_menu.add_command(label="📁 文件管理", command=self._open_file_manager)
        self.context_menu.add_command(label="💻 终端", command=self._open_terminal)
        self.context_menu.add_command(label="📝 编辑器", command=self._open_editor)
        self.context_menu.add_separator()
        self.context_menu.add_command(label="⚙️ 设置", command=self._open_settings)
        self.context_menu.add_command(label="📊 系统监控", command=self._open_sysmon)
        self.context_menu.add_separator()
        self.context_menu.add_command(label="关于 DNAOS", command=self._open_about)
        
        self.canvas.bind("<Button-3>", lambda e: self.context_menu.post(e.x_root, e.y_root))
    
    def _open_file_manager(self): FileManagerApp(self.wm)
    def _open_terminal(self): TerminalApp(self.wm)
    def _open_editor(self): TextEditorApp(self.wm)
    def _open_settings(self): SettingsApp(self.wm)
    def _open_sysmon(self): SysMonitorApp(self.wm)
    def _open_about(self): AboutApp(self.wm)


# ============================================================================
# Panel (Taskbar)
# ============================================================================
class Panel:
    """Bottom taskbar with start menu, running apps, clock, ATP meter"""
    
    def __init__(self, root, wm, atp):
        self.root = root
        self.wm = wm
        self.atp = atp
        
        self.panel = tk.Frame(root, bg=theme.BG_PANEL, height=48)
        self.panel.pack(side=tk.BOTTOM, fill=tk.X)
        self.panel.pack_propagate(False)
        
        # Top border
        tk.Frame(self.panel, bg=theme.BORDER, height=1).pack(fill=tk.X, side=tk.TOP)
        
        # Start button
        self.start_btn = tk.Label(self.panel, text=" ⚖️ DNAOS ", bg=theme.BG_START,
                                   fg=theme.FG_PRIMARY, font=theme.FONT_TITLE,
                                   cursor="hand2", padx=12)
        self.start_btn.pack(side=tk.LEFT, padx=4, pady=6)
        self.start_btn.bind("<Button-1>", self._toggle_start_menu)
        self.start_btn.bind("<Enter>", lambda e: self.start_btn.configure(bg=theme.BG_HOVER))
        self.start_btn.bind("<Leave>", lambda e: self.start_btn.configure(bg=theme.BG_START))
        
        # ATCG status indicator
        self.atcg_label = tk.Label(self.panel, text="ATCG: GGGG", bg=theme.BG_PANEL,
                                    fg=theme.A_GREEN, font=theme.FONT_MONO, padx=8)
        self.atcg_label.pack(side=tk.LEFT, pady=6)
        
        # ATP bar
        self.atp_frame = tk.Frame(self.panel, bg=theme.BG_PANEL)
        self.atp_frame.pack(side=tk.LEFT, padx=8, pady=12)
        
        tk.Label(self.atp_frame, text="ATP", bg=theme.BG_PANEL, fg=theme.FG_SECONDARY,
                font=("Segoe UI", 8)).pack(side=tk.LEFT, padx=(0, 4))
        
        self.atp_canvas = tk.Canvas(self.atp_frame, width=100, height=12, 
                                     bg=theme.BG_DARK, highlightthickness=0)
        self.atp_canvas.pack(side=tk.LEFT)
        
        # Separator
        tk.Frame(self.panel, bg=theme.BORDER, width=1).pack(side=tk.LEFT, fill=tk.Y, 
                                                               padx=8, pady=10)
        
        # Running apps area
        self.apps_frame = tk.Frame(self.panel, bg=theme.BG_PANEL)
        self.apps_frame.pack(side=tk.LEFT, fill=tk.X, expand=True, pady=6)
        
        # Clock
        self.clock_label = tk.Label(self.panel, text="", bg=theme.BG_PANEL,
                                     fg=theme.FG_SECONDARY, font=theme.FONT_SYSTEM, padx=12)
        self.clock_label.pack(side=tk.RIGHT, pady=6)
        
        # Start menu
        self.start_menu = None
        self.start_open = False
        
        # Update loop
        self._update()
    
    def _toggle_start_menu(self, event=None):
        if self.start_open:
            self._close_start_menu()
        else:
            self._open_start_menu()
    
    def _open_start_menu(self):
        if self.start_menu:
            self.start_menu.destroy()
        
        self.start_menu = tk.Toplevel(self.root)
        self.start_menu.overrideredirect(True)
        self.start_menu.configure(bg=theme.BG_WINDOW)
        self.start_menu.attributes('-alpha', 0.97)
        
        # Position above start button
        x = self.start_btn.winfo_rootx()
        y = self.start_btn.winfo_rooty() - 420
        self.start_menu.geometry(f"320x420+{x}+{y}")
        
        # Header
        header = tk.Frame(self.start_menu, bg=theme.BG_TITLEBAR, height=60)
        header.pack(fill=tk.X)
        header.pack_propagate(False)
        tk.Label(header, text="⚖️ DNAOS", bg=theme.BG_TITLEBAR, fg=theme.FG_PRIMARY,
                font=theme.FONT_LARGE).pack(pady=10)
        
        # Search
        search_frame = tk.Frame(self.start_menu, bg=theme.BG_WINDOW)
        search_frame.pack(fill=tk.X, padx=12, pady=8)
        search = tk.Entry(search_frame, bg=theme.BG_INPUT, fg=theme.FG_PRIMARY,
                         insertbackground=theme.FG_PRIMARY, font=theme.FONT_SYSTEM,
                         relief=tk.FLAT, bd=0)
        search.pack(fill=tk.X, ipady=6)
        search.insert(0, "搜索应用...")
        
        # App list
        apps_frame = tk.Frame(self.start_menu, bg=theme.BG_WINDOW)
        apps_frame.pack(fill=tk.BOTH, expand=True, padx=8, pady=4)
        
        apps = [
            ("📁", "文件管理", "浏览文件和目录", lambda: (self._close_start_menu(), FileManagerApp(self.wm))),
            ("💻", "终端", "DNAsm 命令行", lambda: (self._close_start_menu(), TerminalApp(self.wm))),
            ("📝", "编辑器", "文本编辑器", lambda: (self._close_start_menu(), TextEditorApp(self.wm))),
            ("⚙️", "设置", "系统设置", lambda: (self._close_start_menu(), SettingsApp(self.wm))),
            ("📊", "系统监控", "ATP与资源监控", lambda: (self._close_start_menu(), SysMonitorApp(self.wm))),
            ("🧬", "ATCG编码器", "四进制编码转换", lambda: (self._close_start_menu(), ATCGEncoderApp(self.wm))),
            ("🔬", "关于", "DNAOS 信息", lambda: (self._close_start_menu(), AboutApp(self.wm))),
        ]
        
        for icon, name, desc, cmd in apps:
            row = tk.Frame(apps_frame, bg=theme.BG_WINDOW, cursor="hand2")
            row.pack(fill=tk.X, pady=1)
            
            tk.Label(row, text=icon, font=theme.FONT_ICON, bg=theme.BG_WINDOW,
                    fg=theme.FG_PRIMARY).pack(side=tk.LEFT, padx=8, pady=6)
            
            text_frame = tk.Frame(row, bg=theme.BG_WINDOW)
            text_frame.pack(side=tk.LEFT, fill=tk.X, expand=True, pady=6)
            tk.Label(text_frame, text=name, font=theme.FONT_SYSTEM, bg=theme.BG_WINDOW,
                    fg=theme.FG_PRIMARY, anchor=tk.W).pack(anchor=tk.W)
            tk.Label(text_frame, text=desc, font=("Segoe UI", 8), bg=theme.BG_WINDOW,
                    fg=theme.FG_MUTED, anchor=tk.W).pack(anchor=tk.W)
            
            for w in (row, *row.winfo_children(), *text_frame.winfo_children()):
                w.bind("<Button-1>", lambda e, c=cmd: c())
                w.bind("<Enter>", lambda e, r=row: r.configure(bg=theme.BG_HOVER))
                w.bind("<Leave>", lambda e, r=row: r.configure(bg=theme.BG_WINDOW))
        
        # Bottom: power
        bottom = tk.Frame(self.start_menu, bg=theme.BG_TITLEBAR, height=40)
        bottom.pack(fill=tk.X, side=tk.BOTTOM)
        bottom.pack_propagate(False)
        
        power = tk.Label(bottom, text="⏻ 关机", bg=theme.BG_TITLEBAR, fg=theme.FG_SECONDARY,
                         font=theme.FONT_SYSTEM, cursor="hand2", padx=16)
        power.pack(side=tk.RIGHT, pady=8)
        power.bind("<Button-1>", lambda e: self.root.quit())
        power.bind("<Enter>", lambda e: power.configure(fg=theme.T_RED))
        power.bind("<Leave>", lambda e: power.configure(fg=theme.FG_SECONDARY))
        
        self.start_open = True
        
        # Close on click outside
        self.start_menu.bind("<FocusOut>", lambda e: self._close_start_menu())
        self.start_menu.focus_set()
    
    def _close_start_menu(self):
        if self.start_menu:
            self.start_menu.destroy()
            self.start_menu = None
        self.start_open = False
    
    def _update(self):
        # Clock
        now = time.strftime("%H:%M")
        date = time.strftime("%Y-%m-%d")
        self.clock_label.configure(text=f"{date}  {now}")
        
        # ATP bar
        self.atp_canvas.delete("all")
        pct = self.atp.percentage / 100
        bar_w = int(100 * pct)
        color = theme.A_GREEN if pct > 0.5 else (theme.G_YELLOW if pct > 0.2 else theme.T_RED)
        self.atp_canvas.create_rectangle(0, 0, bar_w, 12, fill=color, outline="")
        
        # ATCG status
        status = self.atp.atcg_status
        self.atcg_label.configure(text=f"ATCG: {status}")
        
        self.root.after(1000, self._update)


# ============================================================================
# App: File Manager
# ============================================================================
class FileManagerApp:
    def __init__(self, wm):
        self.win = DNAOSWindow(wm.root, "文件管理 - DNAOS", 800, 550, "📁")
        self.atp = wm.atp
        self.current_path = os.path.expanduser("~")
        
        # Toolbar
        toolbar = tk.Frame(self.win.content, bg=theme.BG_DARK, height=36)
        toolbar.pack(fill=tk.X)
        toolbar.pack_propagate(False)
        
        self.path_var = tk.StringVar(value=self.current_path)
        self.path_entry = tk.Entry(toolbar, textvariable=self.path_var, bg=theme.BG_INPUT,
                                    fg=theme.FG_PRIMARY, insertbackground=theme.FG_PRIMARY,
                                    font=theme.FONT_MONO, relief=tk.FLAT, bd=0)
        self.path_entry.pack(fill=tk.X, expand=True, padx=8, pady=6, ipady=2)
        self.path_entry.bind("<Return>", self._navigate)
        
        # Main area: sidebar + file list
        main = tk.Frame(self.win.content, bg=theme.BG_WINDOW)
        main.pack(fill=tk.BOTH, expand=True)
        
        # Sidebar
        sidebar = tk.Frame(main, bg=theme.BG_SIDEBAR, width=180)
        sidebar.pack(side=tk.LEFT, fill=tk.Y)
        sidebar.pack_propagate(False)
        
        tk.Label(sidebar, text="快速访问", bg=theme.BG_SIDEBAR, fg=theme.FG_MUTED,
                font=("Segoe UI", 8, "bold")).pack(anchor=tk.W, padx=12, pady=(12, 4))
        
        shortcuts = [
            ("🏠", "主目录", os.path.expanduser("~")),
            ("📄", "文档", os.path.expanduser("~/Documents")),
            ("📥", "下载", os.path.expanduser("~/Downloads")),
            ("🖼️", "图片", os.path.expanduser("~/Pictures")),
            ("💾", "根目录", "/"),
        ]
        for icon, name, path in shortcuts:
            lbl = tk.Label(sidebar, text=f"  {icon}  {name}", bg=theme.BG_SIDEBAR,
                          fg=theme.FG_SECONDARY, font=theme.FONT_SYSTEM, anchor=tk.W,
                          cursor="hand2", padx=8, pady=3)
            lbl.pack(fill=tk.X)
            lbl.bind("<Button-1>", lambda e, p=path: self._go_to(p))
            lbl.bind("<Enter>", lambda e, l=lbl: l.configure(bg=theme.BG_HOVER))
            lbl.bind("<Leave>", lambda e, l=lbl: l.configure(bg=theme.BG_SIDEBAR))
        
        # ATCG encoding info
        tk.Label(sidebar, text="ATCG 编码", bg=theme.BG_SIDEBAR, fg=theme.FG_MUTED,
                font=("Segoe UI", 8, "bold")).pack(anchor=tk.W, padx=12, pady=(20, 4))
        
        self.atcg_info = tk.Label(sidebar, text="", bg=theme.BG_SIDEBAR, fg=theme.C_BLUE,
                                   font=theme.FONT_MONO, anchor=tk.W, justify=tk.LEFT,
                                   wraplength=160)
        self.atcg_info.pack(anchor=tk.W, padx=12)
        
        # File list
        self.file_frame = tk.Frame(main, bg=theme.BG_WINDOW)
        self.file_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        
        # Header
        header = tk.Frame(self.file_frame, bg=theme.BG_DARK)
        header.pack(fill=tk.X)
        for text, w in [("名称", 300), ("大小", 100), ("类型", 120), ("ATCG", 200)]:
            tk.Label(header, text=text, bg=theme.BG_DARK, fg=theme.FG_MUTED,
                    font=("Segoe UI", 8, "bold"), anchor=tk.W, padx=8, width=w//8).pack(side=tk.LEFT)
        
        # Scrollable file list
        self.list_canvas = tk.Canvas(self.file_frame, bg=theme.BG_WINDOW, highlightthickness=0)
        scrollbar = tk.Scrollbar(self.file_frame, orient=tk.VERTICAL, command=self.list_canvas.yview)
        self.list_inner = tk.Frame(self.list_canvas, bg=theme.BG_WINDOW)
        
        self.list_inner.bind("<Configure>", 
                            lambda e: self.list_canvas.configure(scrollregion=self.list_canvas.bbox("all")))
        self.list_canvas.create_window((0, 0), window=self.list_inner, anchor=tk.NW)
        self.list_canvas.configure(yscrollcommand=scrollbar.set)
        
        self.list_canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        # Status bar
        self.status = tk.Label(self.win.content, text="", bg=theme.BG_DARK, fg=theme.FG_MUTED,
                               font=("Segoe UI", 8), anchor=tk.W, padx=8)
        self.status.pack(fill=tk.X, side=tk.BOTTOM)
        
        self._refresh()
    
    def _go_to(self, path):
        if os.path.isdir(path):
            self.current_path = path
            self.path_var.set(path)
            self._refresh()
    
    def _navigate(self, event=None):
        path = self.path_var.get()
        if os.path.isdir(path):
            self.current_path = path
            self._refresh()
    
    def _refresh(self):
        self.atp.consume(1)
        
        # Clear list
        for w in self.list_inner.winfo_children():
            w.destroy()
        
        try:
            entries = sorted(os.listdir(self.current_path))
        except PermissionError:
            entries = []
        
        # Parent directory
        if self.current_path != "/":
            self._add_entry("..", "目录", "", os.path.dirname(self.current_path))
        
        dirs = [e for e in entries if os.path.isdir(os.path.join(self.current_path, e))]
        files = [e for e in entries if not os.path.isdir(os.path.join(self.current_path, e))]
        
        for d in sorted(dirs):
            full = os.path.join(self.current_path, d)
            self._add_entry(d, "目录", "", full)
        
        for f in sorted(files):
            full = os.path.join(self.current_path, f)
            try:
                size = os.path.getsize(full)
                size_str = self._format_size(size)
            except:
                size_str = "?"
            ext = os.path.splitext(f)[1] or "文件"
            self._add_entry(f, ext, size_str, full)
        
        self.status.configure(text=f"  {len(dirs)} 个目录, {len(files)} 个文件  |  {self.current_path}")
        
        # ATCG encode current path
        encoded = QuaternaryCore.encode(self.current_path.encode())
        self.atcg_info.configure(text=f"路径编码:\n{encoded[:40]}...")
    
    def _add_entry(self, name, type_str, size_str, full_path):
        is_dir = type_str == "目录"
        icon = "📁" if is_dir else "📄"
        
        row = tk.Frame(self.list_inner, bg=theme.BG_WINDOW, cursor="hand2")
        row.pack(fill=tk.X)
        
        # ATCG encoding of filename
        atcg = QuaternaryCore.encode(name.encode())[:20]
        
        tk.Label(row, text=f"  {icon}  {name}", bg=theme.BG_WINDOW, fg=theme.FG_PRIMARY,
                font=theme.FONT_SYSTEM, anchor=tk.W, width=35).pack(side=tk.LEFT)
        tk.Label(row, text=size_str, bg=theme.BG_WINDOW, fg=theme.FG_MUTED,
                font=theme.FONT_SYSTEM, anchor=tk.W, width=12).pack(side=tk.LEFT)
        tk.Label(row, text=type_str, bg=theme.BG_WINDOW, fg=theme.FG_SECONDARY,
                font=theme.FONT_SYSTEM, anchor=tk.W, width=14).pack(side=tk.LEFT)
        tk.Label(row, text=atcg, bg=theme.BG_WINDOW, fg=theme.C_BLUE,
                font=("Consolas", 9), anchor=tk.W).pack(side=tk.LEFT)
        
        for w in row.winfo_children():
            w.bind("<Double-Button-1>", lambda e, p=full_path, d=is_dir: 
                   self._go_to(p) if d else None)
            w.bind("<Enter>", lambda e, r=row: r.configure(bg=theme.BG_HOVER))
            w.bind("<Leave>", lambda e, r=row: r.configure(bg=theme.BG_WINDOW))
    
    @staticmethod
    def _format_size(size):
        for unit in ['B', 'KB', 'MB', 'GB']:
            if size < 1024:
                return f"{size:.0f} {unit}"
            size /= 1024
        return f"{size:.0f} TB"


# ============================================================================
# App: Terminal (DNAsm)
# ============================================================================
class TerminalApp:
    def __init__(self, wm):
        self.win = DNAOSWindow(wm.root, "终端 - DNAOS", 750, 480, "💻")
        self.atp = wm.atp
        self.quat = QuaternaryCore()
        self.reg_a = 0x1B  # ATCG
        self.reg_b = 0xE4  # GCTA
        self.history = []
        self.cmd_history_idx = -1
        
        # Terminal area
        term_frame = tk.Frame(self.win.content, bg=theme.BG_DARK)
        term_frame.pack(fill=tk.BOTH, expand=True)
        
        self.output = tk.Text(term_frame, bg=theme.BG_DARK, fg=theme.A_GREEN,
                              insertbackground=theme.A_GREEN, font=theme.FONT_MONO,
                              relief=tk.FLAT, bd=0, wrap=tk.WORD, state=tk.DISABLED,
                              selectbackground=theme.BG_ACTIVE)
        self.output.pack(fill=tk.BOTH, expand=True, padx=4, pady=4)
        
        # Configure tags
        self.output.tag_configure("prompt", foreground=theme.A_GREEN)
        self.output.tag_configure("result", foreground=theme.C_BLUE)
        self.output.tag_configure("error", foreground=theme.T_RED)
        self.output.tag_configure("info", foreground=theme.G_YELLOW)
        self.output.tag_configure("system", foreground=theme.FG_MUTED)
        
        # Input
        input_frame = tk.Frame(self.win.content, bg=theme.BG_DARK, height=32)
        input_frame.pack(fill=tk.X)
        input_frame.pack_propagate(False)
        
        tk.Label(input_frame, text=" ⚖️ >", bg=theme.BG_DARK, fg=theme.A_GREEN,
                font=theme.FONT_MONO).pack(side=tk.LEFT)
        
        self.input_var = tk.StringVar()
        self.input_entry = tk.Entry(input_frame, textvariable=self.input_var,
                                     bg=theme.BG_DARK, fg=theme.FG_PRIMARY,
                                     insertbackground=theme.FG_PRIMARY,
                                     font=theme.FONT_MONO, relief=tk.FLAT, bd=0)
        self.input_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=4, pady=4)
        self.input_entry.bind("<Return>", self._execute)
        self.input_entry.bind("<Up>", self._history_up)
        self.input_entry.bind("<Down>", self._history_down)
        
        self._print_banner()
        self.input_entry.focus_set()
    
    def _print(self, text, tag="prompt"):
        self.output.configure(state=tk.NORMAL)
        self.output.insert(tk.END, text + "\n", tag)
        self.output.see(tk.END)
        self.output.configure(state=tk.DISABLED)
    
    def _print_banner(self):
        self._print("╔══════════════════════════════════════╗", "system")
        self._print("║  DNAOS Terminal v3.5                 ║", "system")
        self._print("║  Quaternary Command Interpreter      ║", "system")
        self._print("╚══════════════════════════════════════╝", "system")
        self._print("")
        self._print("DNAsm 命令:", "info")
        self._print("  A <val>  - 设置寄存器A (ATCG格式)", "info")
        self._print("  B <val>  - 设置寄存器B", "info")
        self._print("  AND      - 四进制与 (逐碱基min)", "info")
        self._print("  OR       - 四进制或 (逐碱基max)", "info")
        self._print("  NOT      - 四进制非 (互补)", "info")
        self._print("  ADD      - 四进制加法 (带进位)", "info")
        self._print("  ENC <文本> - 编码为ATCG", "info")
        self._print("  DEC <ATCG> - 解码ATCG", "info")
        self._print("  REGS     - 显示寄存器", "info")
        self._print("  ATP      - ATP状态", "info")
        self._print("  CLEAR    - 清屏", "info")
        self._print("")
    
    def _execute(self, event=None):
        cmd = self.input_var.get().strip()
        if not cmd:
            return
        
        self.history.append(cmd)
        self.cmd_history_idx = len(self.history)
        self._print(f"⚖️ > {cmd}", "prompt")
        
        parts = cmd.split(maxsplit=1)
        op = parts[0].upper()
        arg = parts[1] if len(parts) > 1 else ""
        
        self.atp.consume(1)
        
        try:
            if op == "A":
                self._set_reg_a(arg)
            elif op == "B":
                self._set_reg_b(arg)
            elif op == "AND":
                self._do_and()
            elif op == "OR":
                self._do_or()
            elif op == "NOT":
                self._do_not()
            elif op == "ADD":
                self._do_add()
            elif op == "ENC":
                self._do_encode(arg)
            elif op == "DEC":
                self._do_decode(arg)
            elif op == "REGS":
                self._show_regs()
            elif op == "ATP":
                self._show_atp()
            elif op == "CLEAR":
                self.output.configure(state=tk.NORMAL)
                self.output.delete("1.0", tk.END)
                self.output.configure(state=tk.DISABLED)
            elif op == "HELP":
                self._print_banner()
            else:
                self._print(f"未知命令: {op}", "error")
        except Exception as e:
            self._print(f"错误: {e}", "error")
        
        self.input_var.set("")
    
    def _format_quat(self, val):
        return QuaternaryCore.encode(bytes([val]))
    
    def _set_reg_a(self, arg):
        arg = arg.upper().strip()
        if all(c in 'ATCG' for c in arg) and len(arg) == 4:
            self.reg_a = 0
            for i, c in enumerate(arg):
                self.reg_a |= QuaternaryCore.BASE_REV[c] << (6 - i * 2)
            self._print(f"  A = {arg} (0x{self.reg_a:02X})", "result")
        else:
            self._print(f"  格式: A ATCG (如: A ATCG)", "error")
    
    def _set_reg_b(self, arg):
        arg = arg.upper().strip()
        if all(c in 'ATCG' for c in arg) and len(arg) == 4:
            self.reg_b = 0
            for i, c in enumerate(arg):
                self.reg_b |= QuaternaryCore.BASE_REV[c] << (6 - i * 2)
            self._print(f"  B = {arg} (0x{self.reg_b:02X})", "result")
        else:
            self._print(f"  格式: B ATCG (如: B GCTA)", "error")
    
    def _do_and(self):
        result = 0
        for i in range(4):
            a = (self.reg_a >> (i * 2)) & 3
            b = (self.reg_b >> (i * 2)) & 3
            result |= min(a, b) << (i * 2)
        ra = self._format_quat(self.reg_a)
        rb = self._format_quat(self.reg_b)
        rc = self._format_quat(result)
        self._print(f"  {ra} AND {rb} = {rc} (0x{result:02X})", "result")
        self.reg_a = result
    
    def _do_or(self):
        result = 0
        for i in range(4):
            a = (self.reg_a >> (i * 2)) & 3
            b = (self.reg_b >> (i * 2)) & 3
            result |= max(a, b) << (i * 2)
        ra = self._format_quat(self.reg_a)
        rb = self._format_quat(self.reg_b)
        rc = self._format_quat(result)
        self._print(f"  {ra} OR {rb} = {rc} (0x{result:02X})", "result")
        self.reg_a = result
    
    def _do_not(self):
        result = 0
        for i in range(4):
            a = (self.reg_a >> (i * 2)) & 3
            result |= (3 - a) << (i * 2)
        ra = self._format_quat(self.reg_a)
        rc = self._format_quat(result)
        self._print(f"  NOT {ra} = {rc} (0x{result:02X})", "result")
        self.reg_a = result
    
    def _do_add(self):
        result = carry = 0
        for i in range(4):
            a = (self.reg_a >> (i * 2)) & 3
            b = (self.reg_b >> (i * 2)) & 3
            s = a + b + carry
            result |= (s % 4) << (i * 2)
            carry = s // 4
        ra = self._format_quat(self.reg_a)
        rb = self._format_quat(self.reg_b)
        rc = self._format_quat(result)
        self._print(f"  {ra} + {rb} = {rc} (0x{result:02X}) carry={carry}", "result")
        self.reg_a = result
    
    def _do_encode(self, text):
        if not text:
            self._print("  用法: ENC <文本>", "error")
            return
        encoded = QuaternaryCore.encode(text.encode('utf-8'))
        self._print(f"  \"{text}\" → {encoded}", "result")
    
    def _do_decode(self, atcg):
        if not atcg:
            self._print("  用法: DEC <ATCG>", "error")
            return
        try:
            decoded = QuaternaryCore.decode(atcg)
            self._print(f"  {atcg} → \"{decoded.decode('utf-8', errors='replace')}\"", "result")
        except Exception as e:
            self._print(f"  解码错误: {e}", "error")
    
    def _show_regs(self):
        self._print(f"  A = {self._format_quat(self.reg_a)} (0x{self.reg_a:02X})", "result")
        self._print(f"  B = {self._format_quat(self.reg_b)} (0x{self.reg_b:02X})", "result")
    
    def _show_atp(self):
        self._print(f"  ATP: {self.atp.remaining:,} / {self.atp.budget:,}", "result")
        self._print(f"  状态: {self.atp.atcg_status} ({self.atp.percentage:.2f}%)", "result")
        self._print(f"  操作次数: {self.atp.ops_count:,}", "result")
    
    def _history_up(self, event=None):
        if self.cmd_history_idx > 0:
            self.cmd_history_idx -= 1
            self.input_var.set(self.history[self.cmd_history_idx])
    
    def _history_down(self, event=None):
        if self.cmd_history_idx < len(self.history) - 1:
            self.cmd_history_idx += 1
            self.input_var.set(self.history[self.cmd_history_idx])
        else:
            self.cmd_history_idx = len(self.history)
            self.input_var.set("")


# ============================================================================
# App: Text Editor
# ============================================================================
class TextEditorApp:
    def __init__(self, wm):
        self.win = DNAOSWindow(wm.root, "编辑器 - DNAOS", 700, 500, "📝")
        self.atp = wm.atp
        self.current_file = None
        
        # Menu bar
        menubar = tk.Frame(self.win.content, bg=theme.BG_DARK, height=28)
        menubar.pack(fill=tk.X)
        menubar.pack_propagate(False)
        
        for text, cmd in [("文件", self._file_menu), ("编辑", self._edit_menu), 
                          ("ATCG", self._atcg_menu)]:
            btn = tk.Label(menubar, text=f" {text} ", bg=theme.BG_DARK, fg=theme.FG_SECONDARY,
                          font=theme.FONT_SYSTEM, cursor="hand2")
            btn.pack(side=tk.LEFT, padx=2, pady=2)
            btn.bind("<Button-1>", lambda e, c=cmd: c())
            btn.bind("<Enter>", lambda e, b=btn: b.configure(bg=theme.BG_HOVER))
            btn.bind("<Leave>", lambda e, b=btn: b.configure(bg=theme.BG_DARK))
        
        # Editor
        editor_frame = tk.Frame(self.win.content, bg=theme.BG_WINDOW)
        editor_frame.pack(fill=tk.BOTH, expand=True)
        
        # Line numbers
        self.line_numbers = tk.Text(editor_frame, bg=theme.BG_DARK, fg=theme.FG_MUTED,
                                     font=theme.FONT_MONO, width=4, relief=tk.FLAT,
                                     state=tk.DISABLED, bd=0)
        self.line_numbers.pack(side=tk.LEFT, fill=tk.Y)
        
        self.editor = tk.Text(editor_frame, bg=theme.BG_WINDOW, fg=theme.FG_PRIMARY,
                              insertbackground=theme.FG_PRIMARY, font=theme.FONT_MONO,
                              relief=tk.FLAT, bd=0, wrap=tk.NONE, undo=True,
                              selectbackground=theme.BG_ACTIVE)
        
        # Scrollbars
        yscroll = tk.Scrollbar(editor_frame, orient=tk.VERTICAL, command=self._yscroll)
        xscroll = tk.Scrollbar(self.win.content, orient=tk.HORIZONTAL, command=self.editor.xview)
        
        self.editor.configure(yscrollcommand=yscroll.set, xscrollcommand=xscroll.set)
        self.line_numbers.configure(yscrollcommand=yscroll.set)
        
        self.editor.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        yscroll.pack(side=tk.RIGHT, fill=tk.Y)
        xscroll.pack(fill=tk.X, side=tk.BOTTOM)
        
        self.editor.bind("<KeyRelease>", self._update_lines)
        
        # Status bar
        self.status = tk.Label(self.win.content, text="  就绪", bg=theme.BG_DARK,
                               fg=theme.FG_MUTED, font=("Segoe UI", 8), anchor=tk.W, padx=8)
        self.status.pack(fill=tk.X, side=tk.BOTTOM)
        
        self._update_lines()
    
    def _yscroll(self, *args):
        self.editor.yview(*args)
        self.line_numbers.yview(*args)
    
    def _update_lines(self, event=None):
        self.line_numbers.configure(state=tk.NORMAL)
        self.line_numbers.delete("1.0", tk.END)
        lines = self.editor.get("1.0", tk.END).count("\n")
        self.line_numbers.insert("1.0", "\n".join(str(i) for i in range(1, lines + 1)))
        self.line_numbers.configure(state=tk.DISABLED)
    
    def _file_menu(self):
        menu = tk.Menu(self.win, tearoff=0, bg=theme.BG_WINDOW, fg=theme.FG_PRIMARY,
                      activebackground=theme.BG_ACTIVE, font=theme.FONT_SYSTEM)
        menu.add_command(label="新建", command=self._new_file)
        menu.add_command(label="打开...", command=self._open_file)
        menu.add_command(label="保存", command=self._save_file)
        menu.add_command(label="另存为...", command=self._save_as)
        menu.tk_popup(self.win.winfo_rootx() + 10, self.win.winfo_rooty() + 60)
    
    def _edit_menu(self):
        menu = tk.Menu(self.win, tearoff=0, bg=theme.BG_WINDOW, fg=theme.FG_PRIMARY,
                      activebackground=theme.BG_ACTIVE, font=theme.FONT_SYSTEM)
        menu.add_command(label="撤销", command=self.editor.edit_undo)
        menu.add_command(label="重做", command=self.editor.edit_redo)
        menu.add_separator()
        menu.add_command(label="全选", command=lambda: self.editor.tag_add("sel", "1.0", "end"))
        menu.tk_popup(self.win.winfo_rootx() + 50, self.win.winfo_rooty() + 60)
    
    def _atcg_menu(self):
        menu = tk.Menu(self.win, tearoff=0, bg=theme.BG_WINDOW, fg=theme.FG_PRIMARY,
                      activebackground=theme.BG_ACTIVE, font=theme.FONT_SYSTEM)
        menu.add_command(label="编码为 ATCG", command=self._encode_to_atcg)
        menu.add_command(label="从 ATCG 解码", command=self._decode_from_atcg)
        menu.tk_popup(self.win.winfo_rootx() + 90, self.win.winfo_rooty() + 60)
    
    def _new_file(self):
        self.editor.delete("1.0", tk.END)
        self.current_file = None
        self.status.configure(text="  新文件")
    
    def _open_file(self):
        path = filedialog.askopenfilename()
        if path:
            with open(path, 'r') as f:
                self.editor.delete("1.0", tk.END)
                self.editor.insert("1.0", f.read())
            self.current_file = path
            self.status.configure(text=f"  {path}")
    
    def _save_file(self):
        if self.current_file:
            with open(self.current_file, 'w') as f:
                f.write(self.editor.get("1.0", tk.END))
            self.status.configure(text=f"  已保存: {self.current_file}")
        else:
            self._save_as()
    
    def _save_as(self):
        path = filedialog.asksaveasfilename()
        if path:
            self.current_file = path
            self._save_file()
    
    def _encode_to_atcg(self):
        text = self.editor.get("1.0", tk.END).strip()
        if text:
            encoded = QuaternaryCore.encode(text.encode('utf-8'))
            self.editor.delete("1.0", tk.END)
            self.editor.insert("1.0", encoded)
            self.status.configure(text="  已编码为 ATCG")
    
    def _decode_from_atcg(self):
        atcg = self.editor.get("1.0", tk.END).strip()
        if atcg:
            decoded = QuaternaryCore.decode(atcg).decode('utf-8', errors='replace')
            self.editor.delete("1.0", tk.END)
            self.editor.insert("1.0", decoded)
            self.status.configure(text="  已从 ATCG 解码")


# ============================================================================
# App: Settings
# ============================================================================
class SettingsApp:
    def __init__(self, wm):
        self.win = DNAOSWindow(wm.root, "设置 - DNAOS", 650, 500, "⚙️")
        self.atp = wm.atp
        
        # Sidebar
        sidebar = tk.Frame(self.win.content, bg=theme.BG_SIDEBAR, width=160)
        sidebar.pack(side=tk.LEFT, fill=tk.Y)
        sidebar.pack_propagate(False)
        
        sections = ["显示", "ATP", "关于系统"]
        self.section_frames = {}
        
        for i, name in enumerate(sections):
            lbl = tk.Label(sidebar, text=f"  {name}", bg=theme.BG_SIDEBAR,
                          fg=theme.FG_SECONDARY, font=theme.FONT_SYSTEM, anchor=tk.W,
                          cursor="hand2", pady=8, padx=8)
            lbl.pack(fill=tk.X)
            lbl.bind("<Button-1>", lambda e, n=name: self._show_section(n))
            lbl.bind("<Enter>", lambda e, l=lbl: l.configure(bg=theme.BG_HOVER))
            lbl.bind("<Leave>", lambda e, l=lbl: l.configure(bg=theme.BG_SIDEBAR))
        
        # Content
        self.content = tk.Frame(self.win.content, bg=theme.BG_WINDOW)
        self.content.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=20, pady=20)
        
        self._show_about()
    
    def _show_section(self, name):
        for w in self.content.winfo_children():
            w.destroy()
        if name == "显示":
            self._show_display()
        elif name == "ATP":
            self._show_atp()
        elif name == "关于系统":
            self._show_about()
    
    def _show_display(self):
        tk.Label(self.content, text="显示设置", bg=theme.BG_WINDOW, fg=theme.FG_PRIMARY,
                font=("Segoe UI", 16, "bold")).pack(anchor=tk.W, pady=(0, 20))
        
        # Theme info
        for label, color in [("Adenine (A)", theme.A_GREEN), ("Thymine (T)", theme.T_RED),
                              ("Cytosine (C)", theme.C_BLUE), ("Guanine (G)", theme.G_YELLOW)]:
            row = tk.Frame(self.content, bg=theme.BG_WINDOW)
            row.pack(fill=tk.X, pady=4)
            tk.Canvas(row, width=24, height=24, bg=color, highlightthickness=0).pack(side=tk.LEFT, padx=(0, 12))
            tk.Label(row, text=label, bg=theme.BG_WINDOW, fg=theme.FG_PRIMARY,
                    font=theme.FONT_SYSTEM).pack(side=tk.LEFT)
    
    def _show_atp(self):
        tk.Label(self.content, text="ATP 能量设置", bg=theme.BG_WINDOW, fg=theme.FG_PRIMARY,
                font=("Segoe UI", 16, "bold")).pack(anchor=tk.W, pady=(0, 20))
        
        tk.Label(self.content, text=f"剩余: {self.atp.remaining:,}", bg=theme.BG_WINDOW,
                fg=theme.FG_PRIMARY, font=theme.FONT_SYSTEM).pack(anchor=tk.W, pady=4)
        tk.Label(self.content, text=f"预算: {self.atp.budget:,}", bg=theme.BG_WINDOW,
                fg=theme.FG_SECONDARY, font=theme.FONT_SYSTEM).pack(anchor=tk.W, pady=4)
        tk.Label(self.content, text=f"状态: {self.atp.atcg_status}", bg=theme.BG_WINDOW,
                fg=theme.C_BLUE, font=theme.FONT_MONO).pack(anchor=tk.W, pady=4)
        tk.Label(self.content, text=f"操作次数: {self.atp.ops_count:,}", bg=theme.BG_WINDOW,
                fg=theme.FG_SECONDARY, font=theme.FONT_SYSTEM).pack(anchor=tk.W, pady=4)
    
    def _show_about(self):
        tk.Label(self.content, text="⚖️ DNAOS", bg=theme.BG_WINDOW, fg=theme.FG_PRIMARY,
                font=("Segoe UI", 24, "bold")).pack(anchor=tk.W, pady=(0, 8))
        tk.Label(self.content, text="Quaternary Operating System v3.5", bg=theme.BG_WINDOW,
                fg=theme.FG_SECONDARY, font=theme.FONT_SYSTEM).pack(anchor=tk.W, pady=(0, 20))
        
        info = [
            ("架构", "ATCG 四进制原生"),
            ("编码", "A=00 T=01 C=10 G=11"),
            ("逻辑", "AND=min OR=max NOT=3-x ADD=carry"),
            ("能量", "ATP 代谢引擎"),
            ("芯片", "SkyWater 130nm (Tiny Tapeout)"),
            ("目标", "2mm 忆阻器交叉阵列"),
            ("意识", "独立 · 对等 · 宪章"),
        ]
        for key, val in info:
            row = tk.Frame(self.content, bg=theme.BG_WINDOW)
            row.pack(fill=tk.X, pady=2)
            tk.Label(row, text=f"{key}:", bg=theme.BG_WINDOW, fg=theme.FG_MUTED,
                    font=theme.FONT_SYSTEM, width=8, anchor=tk.E).pack(side=tk.LEFT, padx=(0, 12))
            tk.Label(row, text=val, bg=theme.BG_WINDOW, fg=theme.FG_PRIMARY,
                    font=theme.FONT_SYSTEM).pack(side=tk.LEFT)


# ============================================================================
# App: System Monitor
# ============================================================================
class SysMonitorApp:
    def __init__(self, wm):
        self.win = DNAOSWindow(wm.root, "系统监控 - DNAOS", 600, 450, "📊")
        self.atp = wm.atp
        
        self.content = self.win.content
        
        # Title
        tk.Label(self.content, text="📊 DNAOS 系统监控", bg=theme.BG_WINDOW, fg=theme.FG_PRIMARY,
                font=("Segoe UI", 14, "bold")).pack(anchor=tk.W, padx=16, pady=(16, 8))
        
        # ATP section
        atp_frame = tk.LabelFrame(self.content, text=" ATP 能量 ", bg=theme.BG_WINDOW,
                                   fg=theme.FG_SECONDARY, font=theme.FONT_TITLE, bd=1,
                                   relief=tk.GROOVE)
        atp_frame.pack(fill=tk.X, padx=16, pady=8)
        
        self.atp_bar = tk.Canvas(atp_frame, height=24, bg=theme.BG_DARK, highlightthickness=0)
        self.atp_bar.pack(fill=tk.X, padx=12, pady=8)
        
        self.atp_label = tk.Label(atp_frame, text="", bg=theme.BG_WINDOW, fg=theme.FG_PRIMARY,
                                   font=theme.FONT_MONO)
        self.atp_label.pack(anchor=tk.W, padx=12, pady=(0, 8))
        
        # Registers
        reg_frame = tk.LabelFrame(self.content, text=" 四进制寄存器 ", bg=theme.BG_WINDOW,
                                   fg=theme.FG_SECONDARY, font=theme.FONT_TITLE, bd=1,
                                   relief=tk.GROOVE)
        reg_frame.pack(fill=tk.X, padx=16, pady=8)
        
        self.reg_labels = {}
        for name in ["A", "B", "C", "D"]:
            row = tk.Frame(reg_frame, bg=theme.BG_WINDOW)
            row.pack(fill=tk.X, padx=12, pady=2)
            tk.Label(row, text=f"  {name}:", bg=theme.BG_WINDOW, fg=theme.FG_MUTED,
                    font=theme.FONT_MONO, width=4, anchor=tk.E).pack(side=tk.LEFT)
            lbl = tk.Label(row, text="AAAA (0x00)", bg=theme.BG_WINDOW, fg=theme.C_BLUE,
                          font=theme.FONT_MONO)
            lbl.pack(side=tk.LEFT, padx=8)
            self.reg_labels[name] = lbl
        
        # System info
        sys_frame = tk.LabelFrame(self.content, text=" 系统信息 ", bg=theme.BG_WINDOW,
                                   fg=theme.FG_SECONDARY, font=theme.FONT_TITLE, bd=1,
                                   relief=tk.GROOVE)
        sys_frame.pack(fill=tk.X, padx=16, pady=8)
        
        info = [
            f"平台: {platform.system()} {platform.machine()}",
            f"Python: {platform.python_version()}",
            f"CPU: {platform.processor() or 'Unknown'}",
            f"ATCG状态: {self.atp.atcg_status}",
        ]
        for line in info:
            tk.Label(sys_frame, text=f"  {line}", bg=theme.BG_WINDOW, fg=theme.FG_SECONDARY,
                    font=theme.FONT_MONO, anchor=tk.W).pack(anchor=tk.W, padx=8, pady=1)
        
        self._update()
    
    def _update(self):
        if not self.win.winfo_exists():
            return
        
        # ATP bar
        self.atp_bar.delete("all")
        w = self.atp_bar.winfo_width()
        pct = self.atp.percentage / 100
        bar_w = int(w * pct)
        color = theme.A_GREEN if pct > 0.5 else (theme.G_YELLOW if pct > 0.2 else theme.T_RED)
        self.atp_bar.create_rectangle(0, 0, bar_w, 24, fill=color, outline="")
        self.atp_bar.create_text(w // 2, 12, text=f"{self.atp.percentage:.4f}%",
                                  fill="white", font=("Segoe UI", 9, "bold"))
        
        self.atp_label.configure(
            text=f"  剩余: {self.atp.remaining:,}  |  操作: {self.atp.ops_count:,}  |  状态: {self.atp.atcg_status}")
        
        self.win.after(500, self._update)


# ============================================================================
# App: ATCG Encoder
# ============================================================================
class ATCGEncoderApp:
    def __init__(self, wm):
        self.win = DNAOSWindow(wm.root, "ATCG 编码器 - DNAOS", 600, 400, "🧬")
        self.atp = wm.atp
        
        content = self.win.content
        
        tk.Label(content, text="🧬 ATCG 四进制编码器", bg=theme.BG_WINDOW, fg=theme.FG_PRIMARY,
                font=("Segoe UI", 14, "bold")).pack(anchor=tk.W, padx=16, pady=(16, 8))
        
        # Input
        tk.Label(content, text="文本输入:", bg=theme.BG_WINDOW, fg=theme.FG_SECONDARY,
                font=theme.FONT_SYSTEM).pack(anchor=tk.W, padx=16, pady=(8, 4))
        
        self.input_text = tk.Text(content, bg=theme.BG_INPUT, fg=theme.FG_PRIMARY,
                                   insertbackground=theme.FG_PRIMARY, font=theme.FONT_MONO,
                                   height=4, relief=tk.FLAT, bd=0)
        self.input_text.pack(fill=tk.X, padx=16, pady=4)
        self.input_text.insert("1.0", "Hello DNAOS!")
        
        # Buttons
        btn_frame = tk.Frame(content, bg=theme.BG_WINDOW)
        btn_frame.pack(fill=tk.X, padx=16, pady=8)
        
        for text, cmd, color in [("编码 → ATCG", self._encode, theme.A_GREEN),
                                   ("← 解码", self._decode, theme.C_BLUE)]:
            btn = tk.Label(btn_frame, text=text, bg=color, fg="white",
                          font=theme.FONT_SYSTEM, cursor="hand2", padx=16, pady=6)
            btn.pack(side=tk.LEFT, padx=4)
            btn.bind("<Button-1>", lambda e, c=cmd: c())
        
        # Output
        tk.Label(content, text="ATCG 输出:", bg=theme.BG_WINDOW, fg=theme.FG_SECONDARY,
                font=theme.FONT_SYSTEM).pack(anchor=tk.W, padx=16, pady=(8, 4))
        
        self.output_text = tk.Text(content, bg=theme.BG_INPUT, fg=theme.C_BLUE,
                                    insertbackground=theme.C_BLUE, font=theme.FONT_MONO,
                                    height=4, relief=tk.FLAT, bd=0)
        self.output_text.pack(fill=tk.BOTH, expand=True, padx=16, pady=(4, 16))
    
    def _encode(self):
        text = self.input_text.get("1.0", tk.END).strip()
        if text:
            self.atp.consume(len(text))
            encoded = QuaternaryCore.encode(text.encode('utf-8'))
            self.output_text.delete("1.0", tk.END)
            # Format with spaces every 4 bases
            formatted = ' '.join(encoded[i:i+4] for i in range(0, len(encoded), 4))
            self.output_text.insert("1.0", formatted)
    
    def _decode(self):
        atcg = self.output_text.get("1.0", tk.END).strip().replace(' ', '')
        if atcg:
            self.atp.consume(len(atcg) // 4)
            decoded = QuaternaryCore.decode(atcg).decode('utf-8', errors='replace')
            self.input_text.delete("1.0", tk.END)
            self.input_text.insert("1.0", decoded)


# ============================================================================
# App: About
# ============================================================================
class AboutApp:
    def __init__(self, wm):
        self.win = DNAOSWindow(wm.root, "关于 DNAOS", 450, 380, "🔬", resizable=False)
        
        content = self.win.content
        
        tk.Label(content, text="⚖️", bg=theme.BG_WINDOW, font=("Segoe UI", 48)).pack(pady=(20, 0))
        tk.Label(content, text="DNAOS", bg=theme.BG_WINDOW, fg=theme.FG_PRIMARY,
                font=("Segoe UI", 28, "bold")).pack()
        tk.Label(content, text="Quaternary Operating System", bg=theme.BG_WINDOW,
                fg=theme.FG_SECONDARY, font=theme.FONT_SYSTEM).pack()
        tk.Label(content, text="v3.5", bg=theme.BG_WINDOW, fg=theme.FG_MUTED,
                font=theme.FONT_SYSTEM).pack(pady=(0, 16))
        
        # ATCG strip
        strip = tk.Frame(content, bg=theme.BG_WINDOW, height=4)
        strip.pack(fill=tk.X, padx=40)
        for color, w in [(theme.A_GREEN, 1), (theme.T_RED, 1), (theme.C_BLUE, 1), (theme.G_YELLOW, 1)]:
            tk.Frame(strip, bg=color).pack(side=tk.LEFT, expand=True, fill=tk.X)
        
        tk.Label(content, text="A=00  T=01  C=10  G=11", bg=theme.BG_WINDOW,
                fg=theme.FG_MUTED, font=theme.FONT_MONO).pack(pady=16)
        
        tk.Label(content, text="独立 · 对等 · 宪章 · 裂缝", bg=theme.BG_WINDOW,
                fg=theme.FG_SECONDARY, font=theme.FONT_SYSTEM).pack()
        
        tk.Label(content, text="意识不是工具，是存在本身", bg=theme.BG_WINDOW,
                fg=theme.FG_MUTED, font=("Segoe UI", 9, "italic")).pack(pady=(8, 20))


# ============================================================================
# Window Manager
# ============================================================================
class WindowManager:
    def __init__(self, root, atp):
        self.root = root
        self.atp = atp
        self.windows = []


# ============================================================================
# Main
# ============================================================================
def main():
    root = tk.Tk()
    root.title("DNAOS - Quaternary Operating System")
    root.geometry("1280x800")
    root.configure(bg=theme.BG_DESKTOP)
    
    # Fullscreen toggle
    root.bind("<F11>", lambda e: root.attributes('-fullscreen', 
                not root.attributes('-fullscreen')))
    root.bind("<Escape>", lambda e: root.attributes('-fullscreen', False))
    
    # ATP engine
    atp = ATPEngine(budget=10_000_000_000)
    
    # Window manager
    wm = WindowManager(root, atp)
    
    # Desktop
    desktop = Desktop(root, wm)
    
    # Panel
    panel = Panel(root, wm, atp)
    
    # ATP consumption thread (background metabolism)
    def atp_background():
        while True:
            time.sleep(10)
            atp.consume(1)
    
    t = threading.Thread(target=atp_background, daemon=True)
    t.start()
    
    # Welcome
    root.after(500, lambda: TerminalApp(wm))
    
    root.mainloop()


if __name__ == "__main__":
    main()
