using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

namespace Win11Privacy
{
    // ====================================================================== //
    //  Программа должна быть одна. Два окна с правами администратора
    //  применяли бы настройки одновременно и переписывали журнал отката
    //  каждое по-своему — а журнал единственный путь назад. Второй запуск
    //  теперь просто показывает уже открытое окно.
    //
    //  Тихий режим командной строки под это правило не подпадает: он для
    //  автоматической настройки нескольких машин, и там окна нет вовсе;
    //  журнал же защищён от одновременной записи замком внутри движка.
    // ====================================================================== //
    internal static class SingleInstance
    {
        private static Mutex _mutex;

        internal static bool Take()
        {
            try
            {
                bool first;
                _mutex = new Mutex(true, "Global\\Win11Privacy-App", out first);
                if (!first) return false;
                return true;
            }
            catch (UnauthorizedAccessException)
            {
                // замок держит сеанс другого пользователя — считаем, что программа уже запущена
                return false;
            }
            catch
            {
                return true;    // не смогли проверить — лучше запуститься, чем не запуститься
            }
        }

        internal static void Release()
        {
            if (_mutex == null) return;
            try { _mutex.ReleaseMutex(); } catch { }
            try { _mutex.Close(); } catch { }
            _mutex = null;
        }

        // --- показать окно, которое уже открыто ----------------------------- //
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hWnd);
        private const int SW_RESTORE = 9;

        internal static void ShowRunning()
        {
            try
            {
                Process me = Process.GetCurrentProcess();
                foreach (Process p in Process.GetProcessesByName(me.ProcessName))
                {
                    if (p.Id == me.Id) continue;
                    IntPtr h = p.MainWindowHandle;
                    if (h == IntPtr.Zero) continue;
                    if (IsIconic(h)) ShowWindow(h, SW_RESTORE);
                    SetForegroundWindow(h);
                    return;
                }
            }
            catch { }
        }
    }
}
