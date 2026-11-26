# Script-based launcher for the DR2C trainer (self-contained: C# source embedded).
# It compiles the WinForms UI in memory, so no .exe is ever written to disk and
# Windows SmartScreen / Defender never shows the "unrecognized app" prompt.
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Add-Type cannot embed resources, so point the panel at the loose hack.df.
$env:DR2C_HACKDF = Join-Path (Split-Path -Parent $PSScriptRoot) 'hack\hack.df'

$source = @'
using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

// DR2C Trainer: one window that can install/remove the mod file and toggle
// cheats by posting Ctrl+<n> to the game window. It never touches memory or
// save files: effects live in the game session only.
public class DR2CTrainer : Form
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint MapVirtualKey(uint uCode, uint uMapType);

    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumProc cb, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder s, int n);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

    private const uint WM_KEYDOWN = 0x0100;
    private const uint WM_KEYUP = 0x0101;
    private const uint WM_CHAR = 0x0102;
    private const int VK_CONTROL = 0x11;
    private const int VK_RETURN = 0x0D;

    private const int HK_ALL = 0;
    private const int HK_RES = 1;
    private const int HK_HEAL = 2;
    private const int HK_CAR = 3;
    private const int HK_CONSOLE = 9;

    private const string MOD_DIR = "deathforth\\hack";
    private const string MOD_FILE = "hack.df";

    private IntPtr hwnd = IntPtr.Zero;
    private int gamePid;

    private Label lblTitle;
    private Label lblStatus;
    private Label lblMod;
    private Label lblHint;
    private CheckBox cbRes;
    private CheckBox cbHeal;
    private CheckBox cbCar;
    private Button btnNoBreak;
    private Button btnNoStam;
    private Button btnOhk;
    private Button btnMorale;
    private Button btnZombo;
    private Button btnChassis;
    private Button btnEngine;
    private Button btnAll;
    private Button btnStop;
    private Button btnInstall;
    private Button btnUninstall;
    private TextBox txtLog;

    private Timer tick;
    private DateTime nextRes = DateTime.MinValue;
    private DateTime nextHeal = DateTime.MinValue;
    private DateTime nextStatus = DateTime.MinValue;

    private bool chassisOn;
    private bool engineOn;
    private bool busy;
    private volatile bool sending;
    private readonly object sendLock = new object();

    public DR2CTrainer()
    {
        Text = "DR2C Trainer v0.1.1";
        ClientSize = new Size(400, 672);
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        BackColor = Color.FromArgb(24, 26, 30);
        ForeColor = Color.FromArgb(230, 232, 236);
        Font = new Font("Microsoft YaHei UI", 9f);

        lblTitle = new Label();
        lblTitle.Text = "DEATH ROAD TO CANADA  ·  TRAINER";
        lblTitle.Font = new Font("Microsoft YaHei UI", 11f, FontStyle.Bold);
        lblTitle.ForeColor = Color.FromArgb(255, 196, 92);
        lblTitle.SetBounds(14, 13, 372, 24);

        Panel accent = new Panel();
        accent.BackColor = Color.FromArgb(64, 68, 80);
        accent.SetBounds(14, 41, 372, 1);

        lblStatus = new Label();
        lblStatus.Text = "● 游戏状态：检测中…";
        lblStatus.SetBounds(14, 50, 372, 18);

        lblMod = new Label();
        lblMod.Text = "● Mod 状态：检测中…";
        lblMod.ForeColor = Color.FromArgb(140, 144, 156);
        lblMod.SetBounds(14, 69, 372, 18);

        Label cap1 = MakeCaption("热键功能  (勾选即生效，自动保持)", 96);
        cbRes = MakeCheck("无限资源", "(Ctrl+1)", 120);
        cbHeal = MakeCheck("全队回满血", "(Ctrl+2)", 146);
        cbCar = MakeCheck("载具耐久：底盘 + 引擎", "(Ctrl+3)", 172);

        Label cap2 = MakeCaption("面板按钮  (无热键，点一次执行一次)", 204);
        btnNoBreak = MakeButton("武器永不损坏", 14, 228, 176, 34, false);
        btnOhk = MakeButton("一击必杀", 210, 228, 176, 34, false);
        btnNoStam = MakeButton("不耗体力 + 清疲劳", 14, 268, 176, 34, false);
        btnMorale = MakeButton("全体士气拉满", 210, 268, 176, 34, false);
        btnChassis = MakeButton("底盘：关", 14, 308, 176, 34, false);
        btnEngine = MakeButton("引擎：关", 210, 308, 176, 34, false);
        btnZombo = MakeButton("佐博点 +999", 14, 348, 176, 34, true);

        Label cap3 = MakeCaption("维护", 392);
        btnAll = MakeButton("一键全开  (Ctrl+0)", 14, 416, 176, 34, true);
        btnStop = MakeButton("全部停止", 210, 416, 176, 34, false);
        btnInstall = MakeButton("安装 / 更新 Mod", 14, 456, 176, 34, false);
        btnUninstall = MakeButton("卸载 Mod", 210, 456, 176, 34, false);

        lblHint = new Label();
        lblHint.Text = "热键只保留 Ctrl+0~3，Ctrl+4~9 未占用。\r\n"
                     + "面板按钮通过游戏控制台执行，点击时控制台会短暂出现。\r\n"
                     + "Ctrl+0 不含佐博点；佐博点会写入 gstats.save（安装时已备份）。";
        lblHint.ForeColor = Color.FromArgb(130, 134, 146);
        lblHint.SetBounds(14, 500, 372, 50);

        txtLog = new TextBox();
        txtLog.Multiline = true;
        txtLog.ReadOnly = true;
        txtLog.ScrollBars = ScrollBars.Vertical;
        txtLog.BackColor = Color.FromArgb(15, 17, 20);
        txtLog.ForeColor = Color.FromArgb(132, 210, 140);
        txtLog.BorderStyle = BorderStyle.FixedSingle;
        txtLog.Font = new Font("Consolas", 8.25f);
        txtLog.SetBounds(14, 550, 372, 110);

        Controls.Add(lblTitle);
        Controls.Add(accent);
        Controls.Add(lblStatus);
        Controls.Add(lblMod);
        Controls.Add(cap1);
        Controls.Add(cbRes);
        Controls.Add(cbHeal);
        Controls.Add(cbCar);
        Controls.Add(cap2);
        Controls.Add(btnNoBreak);
        Controls.Add(btnOhk);
        Controls.Add(btnNoStam);
        Controls.Add(btnMorale);
        Controls.Add(btnChassis);
        Controls.Add(btnEngine);
        Controls.Add(btnZombo);
        Controls.Add(cap3);
        Controls.Add(btnAll);
        Controls.Add(btnStop);
        Controls.Add(btnInstall);
        Controls.Add(btnUninstall);
        Controls.Add(lblHint);
        Controls.Add(txtLog);

        cbRes.CheckedChanged += OnResChanged;
        cbHeal.CheckedChanged += OnHealChanged;
        cbCar.CheckedChanged += OnCarChanged;
        btnNoBreak.Click += OnNoBreakClick;
        btnNoStam.Click += OnNoStamClick;
        btnOhk.Click += OnOhkClick;
        btnMorale.Click += OnMoraleClick;
        btnZombo.Click += OnZomboClick;
        btnChassis.Click += OnChassisClick;
        btnEngine.Click += OnEngineClick;
        btnAll.Click += OnAll;
        btnStop.Click += OnStop;
        btnInstall.Click += OnInstallClick;
        btnUninstall.Click += OnUninstallClick;
        FormClosing += OnClosing;

        tick = new Timer();
        tick.Interval = 100;
        tick.Tick += OnTick;
        tick.Start();

        Log("就绪。等待游戏窗口 DR2C …");
    }

    private Label MakeCaption(string text, int y)
    {
        Label l = new Label();
        l.Text = text;
        l.Font = new Font("Microsoft YaHei UI", 8.25f, FontStyle.Bold);
        l.ForeColor = Color.FromArgb(120, 150, 190);
        l.SetBounds(14, y, 372, 18);
        return l;
    }

    private CheckBox MakeCheck(string text, string key, int y)
    {
        CheckBox cb = new CheckBox();
        cb.Text = text + "   " + key;
        cb.ForeColor = Color.FromArgb(222, 226, 232);
        cb.FlatStyle = FlatStyle.Flat;
        cb.Cursor = Cursors.Hand;
        cb.SetBounds(18, y, 368, 24);
        return cb;
    }

    private Button MakeButton(string text, int x, int y, int w, int h, bool primary)
    {
        Button b = new Button();
        b.Text = text;
        b.SetBounds(x, y, w, h);
        b.FlatStyle = FlatStyle.Flat;
        b.Cursor = Cursors.Hand;
        b.BackColor = primary ? Color.FromArgb(74, 92, 62) : Color.FromArgb(44, 47, 56);
        b.ForeColor = primary ? Color.FromArgb(214, 240, 190) : Color.FromArgb(232, 234, 240);
        b.FlatAppearance.BorderColor = primary ? Color.FromArgb(120, 150, 96) : Color.FromArgb(84, 88, 104);
        b.FlatAppearance.MouseOverBackColor = primary ? Color.FromArgb(90, 112, 74) : Color.FromArgb(58, 62, 74);
        return b;
    }

    private void Log(string s)
    {
        txtLog.AppendText(DateTime.Now.ToString("HH:mm:ss") + "  " + s + Environment.NewLine);
        txtLog.SelectionStart = txtLog.TextLength;
        txtLog.ScrollToCaret();
    }

    // ---------------- game window ----------------

    private bool Attach()
    {
        hwnd = IntPtr.Zero;
        gamePid = 0;
        try { EnumWindows(FindGameWindow, IntPtr.Zero); }
        catch { }
        return hwnd != IntPtr.Zero;
    }

    private bool FindGameWindow(IntPtr h, IntPtr lParam)
    {
        if (!IsWindowVisible(h)) return true;

        // 先用窗口类名做廉价预筛，避免对每个窗口都去查进程
        StringBuilder cls = new StringBuilder(128);
        GetClassName(h, cls, 128);
        if (cls.ToString() != "SDL_app") return true;

        StringBuilder title = new StringBuilder(128);
        GetWindowText(h, title, 128);

        uint pid;
        GetWindowThreadProcessId(h, out pid);
        if (pid == 0) return true;

        string proc = "";
        try { proc = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch { }

        // 进程名或窗口标题任一命中即可，避免本地化标题导致连不上
        bool procMatch = proc.Equals("DR2C", StringComparison.OrdinalIgnoreCase)
                      || proc.Equals("DeathRoadToCanada", StringComparison.OrdinalIgnoreCase);
        bool titleMatch = title.ToString().IndexOf("DR2C", StringComparison.OrdinalIgnoreCase) >= 0;
        if (!procMatch && !titleMatch) return true;

        hwnd = h;
        gamePid = (int)pid;
        return false;
    }

    private bool PostKeyTo(IntPtr target, int vk, bool up)
    {
        uint scan = MapVirtualKey((uint)vk, 0);
        long lp = 1 | ((long)scan << 16);
        if (up) lp |= 0xC0000000L;
        uint msg = up ? WM_KEYUP : WM_KEYDOWN;
        return PostMessage(target, msg, (IntPtr)vk, new IntPtr(lp));
    }

    private bool SendHotkey(int number)
    {
        return SendHotkeyTo(hwnd, number);
    }

    // 完整按键序列：按下/松开 Ctrl 与数字键。
    private bool SendHotkeyTo(IntPtr target, int number)
    {
        if (target == IntPtr.Zero) return false;
        int vk = 0x30 + number;
        PostKeyTo(target, VK_CONTROL, false);
        System.Threading.Thread.Sleep(30);
        bool ok = PostKeyTo(target, vk, false);
        System.Threading.Thread.Sleep(30);
        PostKeyTo(target, vk, true);
        System.Threading.Thread.Sleep(30);
        PostKeyTo(target, VK_CONTROL, true);
        return ok;
    }

    // 周期性重发放到后台线程，避免每次发送都阻塞 UI 线程。
    private void SendPeriodic(int number)
    {
        if (sending) return;
        IntPtr target = hwnd;
        if (target == IntPtr.Zero) return;
        sending = true;
        System.Threading.ThreadPool.QueueUserWorkItem(delegate
        {
            try
            {
                lock (sendLock) { SendHotkeyTo(target, number); }
            }
            finally { sending = false; }
        });
    }

    private void SendNow(int number, string label)
    {
        if (!Attach())
        {
            Log("游戏未运行，忽略：" + label);
            return;
        }
        bool ok;
        lock (sendLock) { ok = SendHotkey(number); }
        if (ok) Log("已发送 " + label + " (Ctrl+" + number + ")");
        else Log("发送失败：" + label + "（请右键以管理员身份运行）");
    }

    // ---------------- console channel for panel-only buttons ----------------
    // Functions without a hotkey are executed by opening the game's own
    // console (Ctrl+9, PANTEST4) and typing a df command into it.

    private void TypeTextTo(IntPtr target, string text)
    {
        for (int i = 0; i < 12; i++)
        {
            PostMessage(target, WM_CHAR, (IntPtr)8, IntPtr.Zero);
            System.Threading.Thread.Sleep(40);
        }
        foreach (char c in text)
        {
            PostMessage(target, WM_CHAR, (IntPtr)c, IntPtr.Zero);
            System.Threading.Thread.Sleep(60);
        }
    }

    private void PressEnter(IntPtr target)
    {
        PostKeyTo(target, VK_RETURN, false);
        System.Threading.Thread.Sleep(80);
        PostKeyTo(target, VK_RETURN, true);
        System.Threading.Thread.Sleep(120);
        PostMessage(target, WM_CHAR, (IntPtr)VK_RETURN, IntPtr.Zero);
    }

    private void RunConsole(string cmd, string label)
    {
        if (!Attach())
        {
            Log("游戏未运行，忽略：" + label);
            return;
        }
        IntPtr target = hwnd;
        System.Threading.ThreadPool.QueueUserWorkItem(delegate
        {
            bool got = false;
            for (int i = 0; i < 30 && !got; i++)
                got = System.Threading.Monitor.TryEnter(sendLock, 100);
            if (!got)
            {
                LogSafe("上一条命令还没执行完，忽略：" + label);
                return;
            }
            try
            {
                SendHotkeyTo(target, HK_CONSOLE);
                System.Threading.Thread.Sleep(400);
                TypeTextTo(target, cmd);
                PressEnter(target);
                System.Threading.Thread.Sleep(400);
                TypeTextTo(target, "console-close");
                PressEnter(target);
                System.Threading.Thread.Sleep(200);
                LogSafe("已执行：" + label);
            }
            catch (Exception ex)
            {
                LogSafe("执行失败：" + label + "：" + ex.Message);
            }
            finally
            {
                System.Threading.Monitor.Exit(sendLock);
            }
        });
    }

    private void LogSafe(string s)
    {
        try
        {
            if (txtLog.IsDisposed) return;
            if (txtLog.InvokeRequired) txtLog.BeginInvoke(new Action<string>(Log), s);
            else Log(s);
        }
        catch { }
    }

    // ---------------- mod install / remove ----------------

    private static string FindGameDir()
    {
        string[] candidates = new string[]
        {
            "D:\\Program Files (x86)\\Steam\\steamapps\\common\\DeathRoadToCanada",
            "C:\\Program Files (x86)\\Steam\\steamapps\\common\\DeathRoadToCanada",
            "C:\\Program Files\\Steam\\steamapps\\common\\DeathRoadToCanada",
            "E:\\SteamLibrary\\steamapps\\common\\DeathRoadToCanada",
            "D:\\SteamLibrary\\steamapps\\common\\DeathRoadToCanada"
        };
        for (int i = 0; i < candidates.Length; i++)
        {
            if (File.Exists(Path.Combine(candidates[i], "deathforth\\boot.df"))) return candidates[i];
        }

        try
        {
            Microsoft.Win32.RegistryKey k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey("Software\\Valve\\Steam");
            if (k != null)
            {
                object v = k.GetValue("SteamPath");
                if (v != null)
                {
                    string p = Path.Combine(v.ToString(), "steamapps\\common\\DeathRoadToCanada");
                    if (File.Exists(Path.Combine(p, "deathforth\\boot.df"))) return p;
                }
            }
        }
        catch { }
        return null;
    }

    private static byte[] LoadModBytes()
    {
        string env = Environment.GetEnvironmentVariable("DR2C_HACKDF");
        if (!string.IsNullOrEmpty(env) && File.Exists(env)) return File.ReadAllBytes(env);

        try
        {
            Assembly asm = Assembly.GetExecutingAssembly();
            Stream st = asm.GetManifestResourceStream("hack.df");
            if (st != null)
            {
                byte[] buf = new byte[st.Length];
                st.Read(buf, 0, buf.Length);
                st.Close();
                if (buf.Length > 3) return buf;
            }
        }
        catch { }

        string local = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "hack\\hack.df");
        if (File.Exists(local)) return File.ReadAllBytes(local);

        return null;
    }

    private static string ModStateText(string game)
    {
        if (game == null) return "● Mod 状态：找不到游戏目录";
        string f = Path.Combine(Path.Combine(game, MOD_DIR), MOD_FILE);
        return File.Exists(f) ? "● Mod 状态：已安装" : "● Mod 状态：未安装";
    }

    private void OnInstallClick(object sender, EventArgs e)
    {
        string msg = InstallMod();
        Log(msg);
        lblMod.Text = ModStateText(FindGameDir());
    }

    private void OnUninstallClick(object sender, EventArgs e)
    {
        string msg = UninstallMod();
        Log(msg);
        lblMod.Text = ModStateText(FindGameDir());
    }

    private static string InstallMod()
    {
        try
        {
            string game = FindGameDir();
            if (game == null) return "安装失败：找不到游戏目录";
            byte[] data = LoadModBytes();
            if (data == null) return "安装失败：读不到内嵌的 hack.df";

            // 游戏解析器会把 UTF-8 BOM 当成未知词，写入前统一去掉
            if (data.Length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF)
            {
                byte[] trimmed = new byte[data.Length - 3];
                Array.Copy(data, 3, trimmed, 0, trimmed.Length);
                data = trimmed;
            }

            string dir = Path.Combine(game, MOD_DIR);
            Directory.CreateDirectory(dir);
            string target = Path.Combine(dir, MOD_FILE);
            File.WriteAllBytes(target, data);

            if (!File.Exists(target)) return "安装失败：写入后文件不存在";
            return "已安装：" + target + "（" + data.Length + " 字节）";
        }
        catch (Exception ex) { return "安装失败：" + ex.Message; }
    }

    private static string UninstallMod()
    {
        try
        {
            string game = FindGameDir();
            if (game == null) return "卸载失败：找不到游戏目录";
            string dir = Path.Combine(game, MOD_DIR);
            string file = Path.Combine(dir, MOD_FILE);
            if (File.Exists(file)) File.Delete(file);
            // 只有在目录已空时才删除目录，避免误删用户的其他 mod
            if (Directory.Exists(dir) && Directory.GetFileSystemEntries(dir).Length == 0)
                Directory.Delete(dir, false);
            return "已卸载，游戏恢复原版。";
        }
        catch (Exception ex) { return "卸载失败：" + ex.Message; }
    }

    // ---------------- toggles ----------------

    private void OnResChanged(object sender, EventArgs e)
    {
        if (busy) return;
        if (cbRes.Checked) { SendNow(HK_RES, "无限资源"); nextRes = DateTime.Now.AddSeconds(2); }
        else Log("已停止：无限资源");
    }

    private void OnHealChanged(object sender, EventArgs e)
    {
        if (busy) return;
        if (cbHeal.Checked) { SendNow(HK_HEAL, "不死/回血"); nextHeal = DateTime.Now.AddMilliseconds(400); }
        else Log("已停止：不死/回血");
    }

    private void OnCarChanged(object sender, EventArgs e)
    {
        if (busy) return;
        if (cbCar.Checked)
        {
            SendNow(HK_CAR, "载具耐久（底盘+引擎）");
            chassisOn = true;
            engineOn = true;
            UpdateToggleLabels();
        }
        else
        {
            RunConsole("cheat-car-off", "载具耐久 关");
            chassisOn = false;
            engineOn = false;
            UpdateToggleLabels();
        }
    }

    private void OnNoBreakClick(object sender, EventArgs e) { RunConsole("cheat-nobreak", "武器永不损坏"); }
    private void OnNoStamClick(object sender, EventArgs e) { RunConsole("cheat-nostam", "不耗体力 + 清疲劳"); }
    private void OnOhkClick(object sender, EventArgs e) { RunConsole("cheat-ohk", "一击必杀"); }
    private void OnMoraleClick(object sender, EventArgs e) { RunConsole("cheat-morale", "全体士气拉满"); }
    private void OnZomboClick(object sender, EventArgs e) { RunConsole("cheat-zombo", "佐博点 +999"); }

    private void OnChassisClick(object sender, EventArgs e)
    {
        chassisOn = !chassisOn;
        RunConsole("cheat-chassis", chassisOn ? "底盘 开" : "底盘 关");
        UpdateToggleLabels();
    }

    private void OnEngineClick(object sender, EventArgs e)
    {
        engineOn = !engineOn;
        RunConsole("cheat-engine", engineOn ? "引擎 开" : "引擎 关");
        UpdateToggleLabels();
    }

    private void UpdateToggleLabels()
    {
        btnChassis.Text = chassisOn ? "底盘：开" : "底盘：关";
        btnEngine.Text = engineOn ? "引擎：开" : "引擎：关";
    }

    private void OnAll(object sender, EventArgs e)
    {
        busy = true;
        cbRes.Checked = true;
        cbHeal.Checked = true;
        cbCar.Checked = true;
        chassisOn = true;
        engineOn = true;
        UpdateToggleLabels();
        busy = false;
        SendNow(HK_ALL, "一键全开");
        Log("一键全开已发送（不含佐博点）。");
    }

    private void OnStop(object sender, EventArgs e)
    {
        busy = true;
        bool carWasOn = cbCar.Checked || chassisOn || engineOn;
        cbRes.Checked = false;
        cbHeal.Checked = false;
        cbCar.Checked = false;
        chassisOn = false;
        engineOn = false;
        UpdateToggleLabels();
        busy = false;
        if (carWasOn) RunConsole("cheat-car-off", "载具耐久 关");
        Log("已全部停止（已生效的效果保留到本次游戏结束）。");
    }

    private void OnTick(object sender, EventArgs e)
    {
        if (DateTime.Now >= nextStatus)
        {
            nextStatus = DateTime.Now.AddSeconds(1);
            bool ok = Attach();
            lblStatus.Text = ok
                ? "● 游戏状态：已连接 DR2C 窗口  (PID " + gamePid + ")"
                : "● 游戏状态：未运行（请先启动游戏）";
            lblStatus.ForeColor = ok ? Color.FromArgb(120, 210, 130) : Color.FromArgb(220, 120, 120);

            lblMod.Text = ModStateText(FindGameDir());
        }

        DateTime now = DateTime.Now;
        if (cbRes.Checked && now >= nextRes) { nextRes = now.AddSeconds(2); SendPeriodic(HK_RES); }
        if (cbHeal.Checked && now >= nextHeal) { nextHeal = now.AddMilliseconds(400); SendPeriodic(HK_HEAL); }
    }

    private void OnClosing(object sender, FormClosingEventArgs e)
    {
        tick.Stop();
    }

    // ---------------- entry point ----------------

    [STAThread]
    public static void Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new DR2CTrainer());
    }
}

'@

try {
    Add-Type -TypeDefinition $source -ReferencedAssemblies System.Windows.Forms, System.Drawing
} catch {
    [System.Windows.Forms.MessageBox]::Show("编译面板失败：`n$($_.Exception.Message)", 'DR2C Trainer') | Out-Null
    exit 2
}

[DR2CTrainer]::Main(@())