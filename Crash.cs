using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace Win11Privacy
{
    // ====================================================================== //
    //  Что происходит, когда программа спотыкается. Раньше — системное окно
    //  .NET со стеком вызовов по-английски и кнопкой «Продолжить», после
    //  которой неясно, работает ли ещё хоть что-то. Теперь — понятное
    //  объяснение и файл, который можно приложить к сообщению об ошибке.
    // ====================================================================== //
    internal static class Crash
    {
        private static string _folder;
        private static bool _shown;                // одно окно за раз: сбой любит повторяться

        // Куда писать. Задаётся при запуске: в переносимом режиме — рядом с
        // программой, иначе в ProgramData.
        internal static void UseFolder(string folder)
        {
            if (!string.IsNullOrEmpty(folder)) _folder = folder;
        }

        internal static string LogPath
        {
            get
            {
                string dir = _folder;
                if (string.IsNullOrEmpty(dir))
                    dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Win11Privacy");
                return Path.Combine(dir, "crash.log");
            }
        }

        internal static void Install()
        {
            try { Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException); } catch { }
            Application.ThreadException += delegate(object s, ThreadExceptionEventArgs e) { Report(e.Exception, false); };
            AppDomain.CurrentDomain.UnhandledException += delegate(object s, UnhandledExceptionEventArgs e)
            { Report(e.ExceptionObject as Exception, true); };
        }

        // --- запись в файл --------------------------------------------------- //
        private static string Save(Exception ex, bool fatal)
        {
            string path = LogPath;
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                // файл не должен пухнуть без предела: старое отбрасываем
                try { if (File.Exists(path) && new FileInfo(path).Length > 256 * 1024) File.Delete(path); } catch { }

                StringBuilder b = new StringBuilder();
                b.AppendLine(new string('-', 70));
                b.AppendLine(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " +
                             (fatal ? "аварийное завершение" : "ошибка в интерфейсе"));
                b.AppendLine("версия программы : " + AppInfo.Version);
                b.AppendLine("Windows          : " + Environment.OSVersion.VersionString + (Environment.Is64BitOperatingSystem ? " x64" : " x86"));
                b.AppendLine(".NET             : " + Environment.Version);
                b.AppendLine("язык интерфейса  : " + (L.English ? "en" : "ru"));
                if (ex == null) b.AppendLine("(текст ошибки недоступен)");
                else
                {
                    for (Exception e = ex; e != null; e = e.InnerException)
                    {
                        b.AppendLine(e.GetType().FullName + ": " + e.Message);
                        b.AppendLine(e.StackTrace);
                    }
                }
                b.AppendLine();
                File.AppendAllText(path, b.ToString(), Encoding.UTF8);
            }
            catch { }
            return path;
        }

        private static void Report(Exception ex, bool fatal)
        {
            string path = Save(ex, fatal);
#if UITEST
            Console.WriteLine("CRASH " + (ex == null ? "(неизвестно)" : ex.GetType().Name + ": " + ex.Message));
            Console.WriteLine("CRASH файл " + path);
            Console.Out.Flush();
            return;
#pragma warning disable 0162
#endif
            if (_shown) return;
            _shown = true;
            try
            {
                string what = ex == null ? L.T("неизвестная ошибка") : ex.Message;
                string text = L.T("Программа наткнулась на ошибку:") + "\n\n" + what + "\n\n" +
                              (fatal ? L.T("Продолжить работу не получится — окно закроется.")
                                     : L.T("Само окно, скорее всего, продолжит работать. Настройки системы при этом не менялись.")) +
                              "\n\n" + L.T("Подробности записаны в файл:") + "\n" + path + "\n\n" +
                              L.T("Открыть папку с файлом? Его можно приложить к сообщению об ошибке на GitHub.");
                DialogResult r = MessageBox.Show(text, L.T("Ошибка в программе"),
                                                 MessageBoxButtons.YesNo, MessageBoxIcon.Error);
                if (r == DialogResult.Yes)
                {
                    try { Process.Start("explorer.exe", "/select,\"" + path + "\""); } catch { }
                }
            }
            catch { }
            _shown = false;
#if UITEST
#pragma warning restore 0162
#endif
        }
    }
}
