// Часть MainForm: точка входа, режим командной строки и тестовые прогоны интерфейса.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Windows.Forms;

namespace Win11Privacy
{
    public partial class MainForm : Form
    {
        // ================================================================== //
        [STAThread]
        public static void Main(string[] argv)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            // Необработанная ошибка больше не показывает системное окно .NET
            // со стеком вызовов: человек получает объяснение и файл, который
            // можно приложить к сообщению об ошибке.
            Crash.UseFolder(PortableRoot());
            Crash.Install();

#if UITEST
            // У оконной программы нет консоли, и вывод уходил в кодировке ANSI:
            // на сборке «ОБРЕЗАНО» и «ВЫЛЕЗ» превращались в вопросительные знаки,
            // и проверка, которая их ищет, не срабатывала никогда.
            try
            {
                StreamWriter utf8 = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false));
                utf8.AutoFlush = true;
                Console.SetOut(utf8);
            }
            catch { }
            if (Environment.GetEnvironmentVariable("WIN11_TEST_EN") == "1") L.English = true;
            MainForm f = new MainForm();
            string page = Environment.GetEnvironmentVariable("WIN11_TEST_PAGE"); if (string.IsNullOrEmpty(page)) page = "settings";
            bool mock = Environment.GetEnvironmentVariable("WIN11_TEST_MOCK") == "1";
            string shot = Environment.GetEnvironmentVariable("WIN11_TEST_SHOT");
            int delayMs = shot != null ? 2500 : 13000;
            string delayEnv = Environment.GetEnvironmentVariable("WIN11_TEST_DELAY");
            if (!string.IsNullOrEmpty(delayEnv)) { int dv; if (int.TryParse(delayEnv, out dv) && dv > 500) delayMs = dv; }
            // Сторож на случай, если выход что-то задержит: сборка должна
            // получить внятный признак зависания, а не ждать шесть часов.
            int guardMs = delayMs + 20000;
            System.Threading.Thread watchdog = new System.Threading.Thread(delegate()
            {
                System.Threading.Thread.Sleep(guardMs);
                Console.WriteLine("UITEST завис: выходим принудительно через " + guardMs + " мс");
                Console.Out.Flush();
                Environment.Exit(9);
            });
            watchdog.IsBackground = true;
            watchdog.Start();

            Timer t = new Timer(); t.Interval = delayMs;
            t.Tick += delegate {
                t.Stop();
                // Снимки для README: настоящий движок за время ожидания успевает
                // перебить часть тестовых данных своими ответами, а строка
                // состояния — показать «идёт чтение». Перед снимком всё
                // возвращается к тестовому состоянию.
                if (mock && Environment.GetEnvironmentVariable("WIN11_TEST_README") == "1")
                {
                    f.InjectMocks();
                    f.SetBusy(false, L.T("Готово."));
                    f.Refresh();
                    Application.DoEvents();
                }
                if (shot != null) { try { using (Bitmap bmp = new Bitmap(f.Width, f.Height)) { f.DrawToBitmap(bmp, new Rectangle(0, 0, f.Width, f.Height)); bmp.Save(shot); Console.WriteLine("SHOT " + shot); } } catch (Exception ex) { Console.WriteLine("SHOTERR " + ex.Message); } }
                // сборке важно не только «окно открылось», но и что на странице что-то есть
                Console.WriteLine("PAGE " + page + " controls=" + CountControls(f.PageOf(page)));
                if (Environment.GetEnvironmentVariable("WIN11_TEST_DUMP") == "1")
                {
                    Console.WriteLine("CLIENT " + f.ClientSize.Width + "x" + f.ClientSize.Height);
                    DumpBounds(f.PageOf(page), 0);
                }
                foreach (string clip in ClipWatch.Clipped) Console.WriteLine(clip);
                Console.WriteLine("UITEST ok"); f.Close();
            };
            f.Shown += delegate {
                string sz = Environment.GetEnvironmentVariable("WIN11_TEST_SIZE");
                if (!string.IsNullOrEmpty(sz))
                {
                    string[] p2 = sz.Split('x');
                    int tw, th2;
                    // «min» — самое маленькое окно, до которого его можно сжать: там текст обрезается первым
                    if (sz == "min") f.ClientSize = new Size(f.Font.Height * 44, f.Font.Height * 30);
                    else if (p2.Length == 2 && int.TryParse(p2[0], out tw) && int.TryParse(p2[1], out th2))
                        f.ClientSize = new Size(tw, th2);
                }
                if (mock) f.InjectMocks();
                // «1» — раскрыть первый модуль; имя модуля — раскрыть его и прокрутить к нему
                string expand = Environment.GetEnvironmentVariable("WIN11_TEST_EXPAND");
                if (!string.IsNullOrEmpty(expand))
                {
                    // пункты приходят из движка после определения системы — ждём их
                    Timer ex = new Timer(); ex.Interval = 1000;
                    int tries = 0;
                    ex.Tick += delegate {
                        if (++tries > 40) { ex.Stop(); return; }
                        foreach (ModuleDef md in f._mods)
                        {
                            if (md.Subs.Count == 0 || (expand != "1" && md.Id != expand)) continue;
                            ex.Stop();
                            f.ToggleModule(md);
                            if (expand != "1") try { f._settingsList.ScrollControlIntoView(md.Subs[md.Subs.Count - 1]); f._settingsList.Restack(); } catch { }
                            break;
                        }
                    };
                    ex.Start();
                }
                f.Navigate(page);
                if (Environment.GetEnvironmentVariable("WIN11_TEST_UPDATE") == "1") f.PressUpdateForTest();
                string sideTest = Environment.GetEnvironmentVariable("WIN11_TEST_SIDE");
                if (!string.IsNullOrEmpty(sideTest)) f.StartSideTest(sideTest);
                string toggles = Environment.GetEnvironmentVariable("WIN11_TEST_TOGGLES");
                if (!string.IsNullOrEmpty(toggles)) ToggleSwitch.RenderSheet(toggles, f.Font);
                string q = Environment.GetEnvironmentVariable("WIN11_TEST_QUERY");
                if (!string.IsNullOrEmpty(q))
                {
                    TextBox box;
                    if (f._pageSearch.TryGetValue(page, out box) && box != null) box.Text = q;
                    else if (f._search != null) f._search.Text = q;
                }
                if (Environment.GetEnvironmentVariable("WIN11_TEST_SCROLL") == "1" && f._dossierList != null)
                {
                    try { f._dossierList.VerticalScroll.Value = f._dossierList.VerticalScroll.Maximum; f._dossierList.Restack(); } catch { }
                }
                t.Start();
            };
            Application.Run(f); return;
#pragma warning disable 0162
#endif
            // Сообщения до главного окна (например, «нужны права администратора»)
            // тоже на языке Windows, а не всегда по-русски
            L.DetectFromSystem();

            // тихий режим командной строки
            string profile = null; bool silent = false, audit = false;
            for (int i = 0; i < argv.Length; i++)
            {
                string a = argv[i].ToLowerInvariant();
                if (a == "--portable")
                {
                    // ставим метку рядом с exe: дальше программа хранит всё там же
                    try
                    {
                        string dir = Path.GetDirectoryName(Application.ExecutablePath);
                        File.WriteAllText(Path.Combine(dir, "portable.txt"),
                            "Пока этот файл лежит рядом с Win11Privacy.exe, программа хранит свои данные" +
                            Environment.NewLine + "в папке Win11Privacy-Data рядом с собой, а не в ProgramData." + Environment.NewLine);
                        // Папку данных уже спрашивали выше, когда метки ещё не было, и
                        // ответ запомнился: первый запуск с ключом работал не переносимо.
                        _portableRoot = null;
                        Crash.UseFolder(PortableRoot());
                    }
                    catch { }
                }
                else if (a == "--profile" && i + 1 < argv.Length) profile = argv[++i];
                else if (a == "--silent" || a == "-silent") silent = true;
                else if (a == "--audit") audit = true;
            }

            if (!IsAdmin())
            {
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo(Application.ExecutablePath);
                    psi.UseShellExecute = true; psi.Verb = "runas";
                    psi.Arguments = QuoteArgs(argv);
                    Process.Start(psi);
                }
                catch
                {
                    if (!silent) MessageBox.Show(L.T("Программа изменяет системные настройки и требует прав администратора."),
                        L.T("Нужны права администратора"), MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
                return;
            }

            // Код возврата — обещанный итог тихого режима: число несоответствий у
            // проверки, успех или неудача у профиля. Раньше он терялся, и
            // программа всегда отвечала нулём.
            if (silent && profile != null) { Environment.ExitCode = RunSilentProfile(profile); return; }
            if (audit) { Environment.ExitCode = RunCliAudit(); return; }

            // Второе окно означало бы два движка разом и переписанный журнал
            // отката. Показываем уже открытое вместо запуска второго.
            if (!SingleInstance.Take())
            {
                SingleInstance.ShowRunning();
                return;
            }
            try { Application.Run(new MainForm()); }
            finally { SingleInstance.Release(); }
        }

        // Собирает аргументы обратно в командную строку. Без кавычек путь к
        // профилю с пробелом распадался на части при перезапуске с правами.
        internal static string QuoteArgs(string[] argv)
        {
            StringBuilder sb = new StringBuilder();
            foreach (string a in argv)
            {
                if (sb.Length > 0) sb.Append(' ');
                bool plain = a.Length > 0 && a.IndexOfAny(new[] { ' ', '\t', '"' }) < 0;
                sb.Append(plain ? a : "\"" + a.Replace("\"", "\\\"") + "\"");
            }
            return sb.ToString();
        }

        private static int RunSilentProfile(string profilePath)
        {
            try
            {
                string txt = File.ReadAllText(profilePath);
                Dictionary<string, object> d = Json.ParseObject(txt);
                List<string> mods = new List<string>();
                foreach (object o in Json.GetArr(d, "modules")) mods.Add(Json.Str(o));
                if (mods.Count == 0) return 2;
                string extra = "-Modules " + string.Join(",", mods.ToArray());
                List<string> skip = new List<string>();
                foreach (object o in Json.GetArr(d, "skip")) skip.Add(Json.Str(o));
                if (skip.Count > 0) extra += " -SkipItems " + string.Join(",", skip.ToArray());
                if (d.ContainsKey("backup") && !Json.GetBool(d, "backup")) extra += " -NoBackup";
                if (d.ContainsKey("restorePoint") && !Json.GetBool(d, "restorePoint")) extra += " -NoRestorePoint";
                if (d.ContainsKey("allProfiles") && Json.GetBool(d, "allProfiles")) extra += " -AllProfiles";
                return RunEngineConsole(extra);
            }
            catch { return 1; }
        }

        private static int RunCliAudit()
        {
            // возвращает число несоответствий как код выхода
            string script = ExtractEngineStatic();
            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe",
                "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\" -Audit");
            psi.UseShellExecute = false; psi.RedirectStandardOutput = true; psi.StandardOutputEncoding = Encoding.UTF8; psi.CreateNoWindow = true;
            Process p = Process.Start(psi);
            string json = null;
            while (!p.StandardOutput.EndOfStream) { string l = p.StandardOutput.ReadLine(); if (l != null && l.TrimStart().StartsWith("###JSON###")) json = l.TrimStart().Substring(10).Trim(); }
            p.WaitForExit();
            if (json == null) return -1;
            Dictionary<string, object> d = Json.ParseObject(json);
            int ok = Json.GetInt(d, "ok"), total = Json.GetInt(d, "total");
            Console.WriteLine(L.T("Применено ") + ok + L.T(" из ") + total + L.T("; несоответствий: ") + (total - ok));
            return total - ok;
        }

        private static int RunEngineConsole(string extra)
        {
            string script = ExtractEngineStatic();
            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe",
                "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\" " + extra + " -BackupRoot \"" + desktop + "\"");
            psi.UseShellExecute = false; psi.RedirectStandardOutput = true; psi.StandardOutputEncoding = Encoding.UTF8; psi.CreateNoWindow = true;
            Process p = Process.Start(psi);
            while (!p.StandardOutput.EndOfStream) { string l = p.StandardOutput.ReadLine(); if (l != null && !l.TrimStart().StartsWith("###JSON###") && l.Trim() != "###DONE###") Console.WriteLine(l); }
            p.WaitForExit();
            return p.ExitCode;
        }

        private static string ExtractEngineStatic() { return EngineFile.Ensure(); }

#if UITEST
        // Печатает дерево с координатами: сразу видно, кто вылез за родителя
        private static void DumpBounds(Control c, int depth)
        {
            if (c == null || depth > 4) return;
            foreach (Control cc in c.Controls)
            {
                if (!cc.Visible) continue;      // скрытая кнопка места не занимает и вылезти не может
                string over = (cc.Right > c.ClientSize.Width) ? "  <== ВЫЛЕЗ за " + c.ClientSize.Width : "";
                Console.WriteLine(new string(' ', depth * 2) + cc.GetType().Name +
                    " [" + cc.Left + "," + cc.Top + " " + cc.Width + "x" + cc.Height + "]" + over);
                DumpBounds(cc, depth + 1);
            }
        }

        private static int CountControls(Control c)
        {
            if (c == null) return 0;
            int n = 0;
            foreach (Control cc in c.Controls) n += 1 + CountControls(cc);
            return n;
        }
#endif

        private static bool IsAdmin()
        {
            try { return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator); }
            catch { return false; }
        }
    }
}
