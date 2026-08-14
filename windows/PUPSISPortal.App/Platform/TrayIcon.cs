using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;

namespace PUPSISPortal.App.Platform;

/// <summary>
/// A system-tray icon via raw <c>Shell_NotifyIcon</c> — WinUI 3 (unlike WPF/
/// WinForms) has no tray API of its own, and pulling in a whole notify-icon
/// package for one icon + a two-item menu isn't worth the dependency.
///
/// Shell_NotifyIcon delivers clicks as a window message (<see cref="WM_TRAYICON"/>)
/// through the owning HWND's normal message loop, which WinUI doesn't expose —
/// so this subclasses the window the classic Win32 way (swap GWLP_WNDPROC,
/// forward everything unhandled to the original proc via CallWindowProc). Left-
/// click raises <see cref="OpenRequested"/>; right-click pops a native menu
/// (TrackPopupMenu with TPM_RETURNCMD, so the selection comes back as a plain
/// return value — no extra message routing needed for the menu itself).
///
/// Windows-only P/Invoke; construct after the owning <see cref="Window"/> exists,
/// <see cref="Dispose"/> restores the original WndProc and removes the icon.
/// </summary>
public sealed class TrayIcon : IDisposable
{
    private const uint WM_TRAYICON = 0x8001; // an app-defined message id, above WM_USER
    private const uint WM_LBUTTONUP = 0x0202;
    private const uint WM_RBUTTONUP = 0x0205;
    private const uint NIF_MESSAGE = 0x1, NIF_ICON = 0x2, NIF_TIP = 0x4;
    private const uint NIM_ADD = 0x0, NIM_DELETE = 0x2;
    private const uint TPM_RETURNCMD = 0x0100, TPM_RIGHTBUTTON = 0x0002, MF_STRING = 0x0;
    private const int GWLP_WNDPROC = -4;
    private const nuint IdOpen = 1, IdExit = 2;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NOTIFYICONDATA
    {
        public int cbSize;
        public nint hWnd;
        public int uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public nint hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szTip;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X, Y; }

    private delegate nint WndProcDelegate(nint hWnd, uint msg, nint wParam, nint lParam);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern bool Shell_NotifyIcon(uint dwMessage, ref NOTIFYICONDATA lpData);

    [DllImport("user32.dll")] private static extern nint LoadIconW(nint hInstance, nint lpIconName);
    [DllImport("user32.dll")] private static extern nint CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool AppendMenuW(nint hMenu, uint uFlags, nuint uIDNewItem, string lpNewItem);
    [DllImport("user32.dll")]
    private static extern int TrackPopupMenu(nint hMenu, uint uFlags, int x, int y, int nReserved, nint hWnd, nint prcRect);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] private static extern bool DestroyMenu(nint hMenu);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(nint hWnd);
    [DllImport("user32.dll")]
    private static extern nint CallWindowProc(nint lpPrevWndFunc, nint hWnd, uint msg, nint wParam, nint lParam);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr", SetLastError = true)]
    private static extern nint SetWindowLongPtr64(nint hWnd, int nIndex, nint dwNewLong);
    [DllImport("user32.dll", EntryPoint = "SetWindowLong", SetLastError = true)]
    private static extern int SetWindowLong32(nint hWnd, int nIndex, int dwNewLong);

    private static nint SetWindowLongPtr(nint hWnd, int nIndex, nint dwNewLong) =>
        IntPtr.Size == 8 ? SetWindowLongPtr64(hWnd, nIndex, dwNewLong) : SetWindowLong32(hWnd, nIndex, (int)dwNewLong);

    private readonly nint _hwnd;
    private NOTIFYICONDATA _data;
    private bool _added;
    private nint _originalWndProc;
    // Kept alive for as long as the subclass is installed — the CLR must not
    // collect the delegate while native code holds a function pointer to it.
    private readonly WndProcDelegate _wndProc;

    public event Action? OpenRequested;
    public event Action? ExitRequested;

    public TrayIcon(Window window)
    {
        _hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
        _wndProc = WndProc;

        _data = new NOTIFYICONDATA
        {
            cbSize = Marshal.SizeOf<NOTIFYICONDATA>(),
            hWnd = _hwnd,
            uID = 1,
            uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP,
            uCallbackMessage = WM_TRAYICON,
            hIcon = LoadIconW(0, new nint(32512)), // IDI_APPLICATION — swap for the app icon on Windows
            szTip = "PUPSISPortal",
        };
    }

    public void Show()
    {
        _originalWndProc = SetWindowLongPtr(_hwnd, GWLP_WNDPROC,
            Marshal.GetFunctionPointerForDelegate(_wndProc));
        _added = Shell_NotifyIcon(NIM_ADD, ref _data);
    }

    private nint WndProc(nint hWnd, uint msg, nint wParam, nint lParam)
    {
        if (msg == WM_TRAYICON)
        {
            switch ((uint)lParam.ToInt64())
            {
                case WM_LBUTTONUP:
                    OpenRequested?.Invoke();
                    return 0;
                case WM_RBUTTONUP:
                    ShowMenu();
                    return 0;
            }
        }
        return CallWindowProc(_originalWndProc, hWnd, msg, wParam, lParam);
    }

    private void ShowMenu()
    {
        var menu = CreatePopupMenu();
        AppendMenuW(menu, MF_STRING, IdOpen, "Open");
        AppendMenuW(menu, MF_STRING, IdExit, "Exit");
        GetCursorPos(out var pt);
        SetForegroundWindow(_hwnd); // required so the menu dismisses on an outside click
        var chosen = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, pt.X, pt.Y, 0, _hwnd, 0);
        DestroyMenu(menu);

        if (chosen == (int)IdOpen) OpenRequested?.Invoke();
        else if (chosen == (int)IdExit) ExitRequested?.Invoke();
    }

    public void Dispose()
    {
        if (_added)
            Shell_NotifyIcon(NIM_DELETE, ref _data);
        _added = false;
        if (_originalWndProc != 0)
            SetWindowLongPtr(_hwnd, GWLP_WNDPROC, _originalWndProc);
    }
}
