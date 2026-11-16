#if SELFTEST
using System;
using System.Collections.Generic;
using System.IO;

namespace Win11Privacy
{
    // ====================================================================== //
    //  Проверки для той части программы, где ошибка тихая. Движок покрыт
    //  своими тестами, страницы — открытием в тестовой сборке, а вот чистые
    //  функции интерфейса не проверял никто: сравнение версий, разбор ответов
    //  движка, решение «эта команда меняет систему или только читает» — от
    //  последнего зависит, спросят ли человека перед тем, как оборвать
    //  применение настроек.
    //
    //  Собирается отдельным exe:
    //      csc /define:SELFTEST /main:Win11Privacy.SelfTest ... /recurse:src\*.cs
    // ====================================================================== //
    internal static class SelfTest
    {
        private static int _failed;
        private static int _passed;

        private static void Check(string name, bool ok, string detail)
        {
            if (ok) { Console.WriteLine("  [ok]   " + name); _passed++; }
            else
            {
                Console.WriteLine("  [FAIL] " + name + (detail.Length > 0 ? "  --  " + detail : ""));
                Console.WriteLine("::error::" + name + " " + detail);
                _failed++;
            }
        }

        private static void Check(string name, bool ok) { Check(name, ok, ""); }

        public static int Main()
        {
            try { Console.OutputEncoding = System.Text.Encoding.UTF8; } catch { }

            Versions();
            Commands();
            Requests();
            Boundary();
            Arguments();
            SensorKeys();
            WindowSize();
            Profiles();
            Verdict();
            Answers();
            LogGlyphs();
            Language();
            DataRootChain();
            AppMutex();

            Console.WriteLine();
            Console.WriteLine("Пройдено: " + _passed + ", провалено: " + _failed);
            return _failed > 0 ? 1 : 0;
        }

        // --- журнал: знаки, которых нет в его шрифте --------------------------- //
        // «Команда движка: ?PurgeData»: окно меняло дефисы команды на
        // неразрывные (U+2011), а в Consolas такого знака нет, и RichTextBox
        // рисовал вместо него непонятный значок.
        private static void LogGlyphs()
        {
            Console.WriteLine();
            Console.WriteLine("Журнал: знаки, которых нет в шрифте");
            using (System.Drawing.Font consolas = new System.Drawing.Font("Consolas", 10F))
            {
                // без Consolas GDI+ подставит другой шрифт — тогда проверка не о нём
                if (consolas.Name == "Consolas")
                {
                    Check("в Consolas обычный дефис есть", Theme.HasGlyph(consolas, '-'));
                    Check("в Consolas неразрывного дефиса нет — проверка умеет сказать «нет»", !Theme.HasGlyph(consolas, '\u2011'));
                    Check("журнал в Consolas: «-PurgeData» остаётся с обычным дефисом", MainForm.LogNoBreakFor("-PurgeData", consolas) == "-PurgeData");
                }
            }
            using (System.Drawing.Font segoe = new System.Drawing.Font("Segoe UI", 10F))
            {
                if (segoe.Name == "Segoe UI")
                {
                    Check("в Segoe UI неразрывный дефис есть — проверка умеет сказать «да»", Theme.HasGlyph(segoe, '\u2011'));
                    Check("шрифт с этим знаком: дефисы ключей неразрывные", MainForm.LogNoBreakFor("-Apply -Modules a", segoe) == "\u2011Apply \u2011Modules a");
                }
            }
            Check("шрифт не задан: дефисы не трогаются", MainForm.LogNoBreakFor("-Audit", null) == "-Audit");
            // главное: всё, что журнал покажет в строке команды, есть в его шрифте
            using (System.Drawing.Font mono = Theme.PickFont(Theme.MonoFonts, 10F, System.Drawing.FontStyle.Regular))
            {
                string shown = MainForm.LogNoBreakFor("-Apply -Modules telemetry, ads -NoBackup", mono);
                string missing = "";
                foreach (char ch in shown) if (!Theme.HasGlyph(mono, ch) && missing.IndexOf(ch) < 0) missing += ch;
                Check("строка команды рисуется шрифтом журнала (" + mono.Name + ") без пропусков", missing.Length == 0,
                      "нет знаков: " + missing);
            }
        }

        // --- путь до папки данных (W11P-006) --------------------------------- //
        private static void DataRootChain()
        {
            Console.WriteLine("Путь до папки данных");
            string win = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            Check("путь до папки Windows подменить нельзя", EngineFile.ChainSecure(Path.Combine(win, "System32")));
            Check("путь до ProgramData подменить нельзя", EngineFile.ChainSecure(EngineFile.ProgramDataDir()));
            Check("временная папка пользователя — путь не защищён", !EngineFile.ChainSecure(Path.GetTempPath()));
            Check("несуществующая папка — не защищена", !EngineFile.ChainSecure(Path.Combine(Path.GetTempPath(), "w11p-no-such-" + Guid.NewGuid().ToString("N"))));
        }

        // --- замок окна Global\Win11Privacy-App (T-1) ----------------------- //
        //  Имя может заранее занять любая программа. «Уже запущено» — только
        //  если под именем замок самой программы; чужой объект — окно всё
        //  равно открывается (Squatted), а не закрывается молча.
        private static System.Security.AccessControl.MutexSecurity Sddl(string s)
        {
            System.Security.AccessControl.MutexSecurity x = new System.Security.AccessControl.MutexSecurity();
            x.SetSecurityDescriptorSddlForm(s);
            return x;
        }

        private static void AppMutex()
        {
            Console.WriteLine();
            Console.WriteLine("Замок окна (T-1)");
            string me = System.Security.Principal.WindowsIdentity.GetCurrent().User.Value;
            string[] elev = SingleInstance.TrustedSids(true, me);
            string[] plain = SingleInstance.TrustedSids(false, me);
            Check("свои у повышенного окна — только система и администраторы", elev.Length == 2 && Array.IndexOf(elev, me) < 0);
            Check("без повышения своя учётная запись тоже своя", Array.IndexOf(plain, me) >= 0);
            Check("замок программы (BA, права SY+BA) — свой",
                  SingleInstance.Problem(Sddl("O:BAD:P(A;;0x1F0001;;;SY)(A;;0x1F0001;;;BA)"), elev).Length == 0);
            Check("владелец — сам пользователь (так заводит обычная программа) — чужой у повышенного",
                  SingleInstance.Problem(Sddl("O:" + me + "D:P(A;;0x1F0001;;;BA)"), elev).Length > 0);
            Check("владелец — Пользователи — чужой", SingleInstance.Problem(Sddl("O:BUD:P(A;;0x1F0001;;;BA)"), elev).Length > 0);
            Check("Все могут ждать (взять и держать) — чужой", SingleInstance.Problem(Sddl("O:BAD:P(A;;0x100000;;;WD)(A;;0x1F0001;;;BA)"), elev).Length > 0);
            Check("смена прав для Прошедших проверку — чужой", SingleInstance.Problem(Sddl("O:BAD:P(A;;0x40000;;;AU)(A;;0x1F0001;;;BA)"), elev).Length > 0);
            Check("пустой список прав (NULL DACL) — чужой", SingleInstance.Problem(Sddl("O:BAD:NO_ACCESS_CONTROL"), elev).Length > 0);
            Check("чтение прав и состояния для Всех — не опасно", SingleInstance.Problem(Sddl("O:BAD:P(A;;0x20001;;;WD)(A;;0x1F0001;;;BA)"), elev).Length == 0);
            Check("права не читаются — чужой", SingleInstance.Problem(null, elev).Length > 0);

            // живые замки под проверочным именем (не мешают открытому окну)
            string name = "Global\\W11P-selftest-" + Guid.NewGuid().ToString("N");
            bool first = SingleInstance.Take(name);
            Check("имени нет — замок свой, окно открывается", first && SingleInstance.Squatted.Length == 0);
            bool second = SingleInstance.Take(name);
            Check("второй запуск видит свой замок — «уже запущено»", !second && SingleInstance.Squatted.Length == 0);
            SingleInstance.Release();

            string sqName = "Global\\W11P-selftest-" + Guid.NewGuid().ToString("N");
            bool sqCreated;
            using (System.Threading.Mutex squat = new System.Threading.Mutex(false, sqName, out sqCreated, Sddl("D:P(A;;0x1F0001;;;WD)")))
            {
                bool r = SingleInstance.Take(sqName);
                Check("имя занято чужим замком (Все: полный доступ) — окно открывается, это не «уже запущено»", sqCreated && r && SingleInstance.Squatted.Length > 0, SingleInstance.Squatted);
                SingleInstance.Release();
            }
            string evName = "Global\\W11P-selftest-" + Guid.NewGuid().ToString("N");
            using (System.Threading.EventWaitHandle ev = new System.Threading.EventWaitHandle(false, System.Threading.EventResetMode.ManualReset, evName))
            {
                bool r = SingleInstance.Take(evName);
                Check("имя занято объектом другого вида — окно открывается", r && SingleInstance.Squatted.Length > 0, SingleInstance.Squatted);
                SingleInstance.Release();
            }
            string dnName = "Global\\W11P-selftest-" + Guid.NewGuid().ToString("N");
            bool dnCreated;
            using (System.Threading.Mutex deny = new System.Threading.Mutex(false, dnName, out dnCreated, Sddl("D:P")))
            {
                bool r = SingleInstance.Take(dnName);
                Check("чужой замок без доступа — окно открывается", dnCreated && r && SingleInstance.Squatted.Length > 0, SingleInstance.Squatted);
                SingleInstance.Release();
            }
        }

        // --- язык интерфейса ------------------------------------------------- //
        private static void Language()
        {
            Console.WriteLine("Язык интерфейса");
            L.Choice = 1;
            Check("закреплён русский", !L.English && L.Choice == 1);
            L.Choice = 2;
            Check("закреплён английский", L.English && L.Choice == 2);
            L.Choice = 0;
            Check("как в Windows — язык системы", L.English == L.SystemEnglish());
            L.Choice = 7;
            Check("неизвестный выбор — как в Windows", L.Choice == 0);
            Check("старый флаг совпадает с Windows (рус.) — как в Windows", MainForm.LangChoiceFromOld(false, false) == 0);
            Check("старый флаг совпадает с Windows (англ.) — как в Windows", MainForm.LangChoiceFromOld(true, true) == 0);
            Check("английский на русской Windows — закреплён", MainForm.LangChoiceFromOld(true, false) == 2);
            Check("русский на английской Windows — закреплён", MainForm.LangChoiceFromOld(false, true) == 1);
            L.Choice = 1;
        }

        // --- сравнение версий ------------------------------------------------ //
        private static void Versions()
        {
            Console.WriteLine("Сравнение версий");
            Check("1.9.0 старше 1.10.0", AppInfo.Compare("1.9.0", "1.10.0") < 0,
                  "получено: " + AppInfo.Compare("1.9.0", "1.10.0"));
            Check("1.9.1 новее 1.9.0", AppInfo.Compare("1.9.1", "1.9.0") > 0);
            Check("приставка v не мешает", AppInfo.Compare("1.9.0", "v1.9.0") == 0);
            Check("2.0 новее 1.99.99", AppInfo.Compare("2.0", "1.99.99") > 0);
            Check("недостающие части считаются нулями", AppInfo.Compare("1.9", "1.9.0") == 0);
            Check("мусор не роняет сравнение", AppInfo.Compare("", "1.9.0") < 0);
            Check("хвост после дефиса отбрасывается", AppInfo.Compare("1.9.0-beta", "1.9.0") == 0);
        }

        // --- какие команды движка меняют систему ----------------------------- //
        private static void Commands()
        {
            Console.WriteLine();
            Console.WriteLine("Что считается изменением системы");
            Check("применение модулей меняет", MainForm.EngineWrites(new EngineRequest("Apply").List("Modules", new[] { "telemetry", "ads" })));
            Check("тестовый прогон не меняет", !MainForm.EngineWrites(new EngineRequest("Apply").List("Modules", new[] { "telemetry" }).Switch("DryRun")));
            Check("проверка не меняет", !MainForm.EngineWrites(new EngineRequest("Audit").List("Modules", new[] { "telemetry" })));
            Check("проверка с доказательством не меняет", !MainForm.EngineWrites(new EngineRequest("Audit").Switch("WithProof")));
            Check("откат меняет", MainForm.EngineWrites(new EngineRequest("Revert")));
            Check("возврат записей меняет", MainForm.EngineWrites(new EngineRequest("RestoreItems").List("ChangeItems", new[] { "abc" })));
            Check("удаление приложений меняет", MainForm.EngineWrites(new EngineRequest("RemoveApps").List("AppItems", new[] { "a", "b" }).Switch("AllUsers")));
            Check("стирание следа меняет", MainForm.EngineWrites(new EngineRequest("FootprintWipe").List("WipeItems", new[] { "ads" })));
            Check("чтение следа не меняет", !MainForm.EngineWrites(new EngineRequest("Footprint")));
            Check("смена номера устройства меняет", MainForm.EngineWrites(new EngineRequest("GdidReissue")));
            Check("возврат номера устройства меняет", MainForm.EngineWrites(new EngineRequest("GdidRestore")));
            Check("чтение номера устройства не меняет", !MainForm.EngineWrites(new EngineRequest("GdidStatus")));
            Check("досье не меняет", !MainForm.EngineWrites(new EngineRequest("Spy")));
            Check("список настроек не меняет", !MainForm.EngineWrites(new EngineRequest("ListDefs")));
            Check("хронология не меняет", !MainForm.EngineWrites(new EngineRequest("Timeline").Int("TimelineDays", 30)));
            Check("сканирование рентгена не меняет", !MainForm.EngineWrites(new EngineRequest("XrayScan").Int("XrayHours", 24)));
            Check("замер «до» меняет", MainForm.EngineWrites(new EngineRequest("XrayScan").Switch("XrayBaseline")));
            Check("включение записи рентгена меняет", MainForm.EngineWrites(new EngineRequest("XrayEnable")));
            Check("доступ к датчику меняет", MainForm.EngineWrites(new EngineRequest("SensorSet").Str("SensorKey", "webcam").Str("SensorValue", "Deny")));
            Check("без запроса ничего не меняет", !MainForm.EngineWrites(null));

            // W11P-003: успех — только «ok» в ответе И код выхода 0
            Console.WriteLine();
            Console.WriteLine("Ответ движка: «ok» и код выхода");
            Check("ok и код 0 — успех", MainForm.EngineSucceeded(Answer("{\"ok\":true}", 0)));
            Check("ok:false и код 2 — неудача", !MainForm.EngineSucceeded(Answer("{\"ok\":false,\"error\":\"x\"}", 2)));
            Check("ok:true, но код 2 — неудача (расхождение)", !MainForm.EngineSucceeded(Answer("{\"ok\":true}", 2)));
            Check("ok:false и код 0 — неудача (прежнее поведение SensorSet)", !MainForm.EngineSucceeded(Answer("{\"ok\":false}", 0)));
            Check("нет поля ok — неудача", !MainForm.EngineSucceeded(Answer("{\"error\":\"request rejected\"}", 64)));
            Check("нет ответа — неудача", !MainForm.EngineSucceeded(null));
            Check("ответ без кода выхода (как раньше) — по полю ok", MainForm.EngineSucceeded(Json.ParseObject("{\"ok\":true}")));
        }

        private static Dictionary<string, object> Answer(string json, int code)
        {
            Dictionary<string, object> d = Json.ParseObject(json);
            d["_exitCode"] = code;
            return d;
        }

        // --- граница окно → движок по-настоящему (F-08) ------------------------ //
        //  Запускается настоящий powershell.exe с движком (путь — в
        //  WIN11_TEST_ENGINE) теми же функциями, что у окна и тихого режима:
        //  EngineProcess (постоянная командная строка), SendRequest (запись
        //  запроса в фоне, как у окна) и StartWithRequest (тихий режим).
        //  Проверяется, какую операцию движок на самом деле выбрал: с
        //  WIN11_ENGINE_TRACE=1 он печатает «###OP### <операция>». Только
        //  чтение: в положительных случаях — DataInfo, разрушительное не зовётся.
        private sealed class EngineResult
        {
            public int Code;
            public string Out = "";
            public List<string> Ops = new List<string>();
            public string Describe() { return "код " + Code + ", операции: [" + string.Join(",", Ops.ToArray()) + "]"; }
        }

        private static EngineResult RunReal(string engine, EngineRequest req, bool asWindow) { return RunReal(engine, req, asWindow, "1"); }

        private static EngineResult RunReal(string engine, EngineRequest req, bool asWindow, string trace)
        {
            System.Diagnostics.ProcessStartInfo psi = MainForm.EngineProcess(engine);
            psi.EnvironmentVariables["WIN11_ENGINE_TRACE"] = trace;
            System.Diagnostics.Process p;
            System.Text.StringBuilder err = new System.Text.StringBuilder();
            if (asWindow)
            {
                p = System.Diagnostics.Process.Start(psi);
                p.ErrorDataReceived += delegate(object s, System.Diagnostics.DataReceivedEventArgs e) { if (e.Data != null) lock (err) err.AppendLine(e.Data); };
                p.BeginErrorReadLine();
                MainForm.SendRequest(p, req.ToJson());
            }
            else p = MainForm.StartWithRequest(psi, req);
            EngineResult r = new EngineResult();
            r.Out = p.StandardOutput.ReadToEnd();
            p.WaitForExit();
            r.Code = p.ExitCode;
            foreach (string line in r.Out.Split('\n'))
            {
                string t = line.Trim();
                if (t.StartsWith("###OP###")) r.Ops.Add(t.Substring(8).Trim());
            }
            return r;
        }

        private static void Boundary()
        {
            Console.WriteLine();
            Console.WriteLine("Граница окно → движок (F-08)");
            string engine = Environment.GetEnvironmentVariable("WIN11_TEST_ENGINE");
            if (string.IsNullOrEmpty(engine) || !System.IO.File.Exists(engine))
            {
                Console.WriteLine("  [пропуск] WIN11_TEST_ENGINE не задан — движок не запускался");
                return;
            }
            EngineRequest attack = new EngineRequest("SensorSet")
                .Str("SensorKey", "webcam\\NonPackaged\\evil\" -XrayStatus \"").Str("SensorValue", "Deny");
            EngineResult r = RunReal(engine, attack, true);
            Check("A (как окно): кавычка и -XrayStatus в ключе — отказ до выбора операции", r.Code == 64 && r.Ops.Count == 0, r.Describe());
            Check("A (как окно): -XrayStatus не выполнялся", r.Out.IndexOf("###OP### XrayStatus", StringComparison.Ordinal) < 0);
            r = RunReal(engine, attack, false);
            Check("A (тихий режим): тот же отказ", r.Code == 64 && r.Ops.Count == 0, r.Describe());
            r = RunReal(engine, new EngineRequest("SensorSet").Str("SensorKey", "webcam\\NonPackaged\\x -XrayStatus -XrayWipe").Str("SensorValue", "Deny"), true);
            Check("A: «-XrayStatus» без кавычки — данные: выбрана только SensorSet", r.Ops.Count == 1 && r.Ops[0] == "SensorSet", r.Describe());

            r = RunReal(engine, new EngineRequest("DataInfo").WithCommon("C:\\Temp\\x -PurgeData -XrayWipe -Revert", null), true);
            Check("B: «-PurgeData -XrayWipe -Revert» в пути рабочего стола — выбрана только DataInfo", r.Ops.Count == 1 && r.Ops[0] == "DataInfo", r.Describe());
            Check("B: данные программы не удалялись", r.Out.IndexOf("Удаление данных программы", StringComparison.Ordinal) < 0);
            r = RunReal(engine, new EngineRequest("RestoreBackup").Str("BackupPath", "C:\\x\" -PurgeData -RestoreAll \""), true);
            Check("B: путь копии с кавычкой и -PurgeData — отказ, операции нет", r.Code == 64 && r.Ops.Count == 0, r.Describe());

            string[] corpus = {
                "C:\\a b", "C:\\a\"b", "C:\\a\"\"b", "C:\\a\\", "C:\\a\\\\", "C:\\Путь\\Кириллица", "", " ", "C:\\a\nb", "C:\\a\rb",
                "C:\\a\tb", "C:\\a & b | c ^ d", "C:\\a -PurgeData", "-PurgeData", "--% -Revert", "C:\\$(Remove-Item C:\\x)",
                "C:\\a' -XrayWipe '", "C:\\a;b", "C:\\a`b", "C:\\a\u0000b", "\\\\server\\share", "\"-XrayStatus\"", "C:\\\ud83d\ude00" };
            List<string> bad = new List<string>();
            foreach (string v in corpus)
            {
                r = RunReal(engine, new EngineRequest("DataInfo").Str("BackupRoot", v), true);
                bool fine = (r.Code == 64 && r.Ops.Count == 0) || (r.Ops.Count == 1 && r.Ops[0] == "DataInfo");
                if (!fine) bad.Add("[" + v + "] " + r.Describe());
            }
            Check("E: ни одно из " + corpus.Length + " враждебных значений не сменило операцию", bad.Count == 0, string.Join(" | ", bad.ToArray()));
            r = RunReal(engine, new EngineRequest("DataInfo").Str("BackupRoot", "C:\\Путь\\Кириллица"), true);
            Check("E: кириллица в пути доходит до движка (\\u-последовательности)", r.Ops.Count == 1 && r.Ops[0] == "DataInfo", r.Describe());

            // F: каждая форма запроса, которую строит окно, проходит схему движка
            // (режим «только принять запрос»: движок называет операцию и выходит,
            // ничего не делая — разрушительные операции так проверить безопасно)
            string desk = "C:\\Users\\Тест\\Desktop";
            string[] mods = { "telemetry", "ads", "app_vscode" };
            string[] skip = { "telemetry#3", "ads#12" };
            List<EngineRequest> shapes = new List<EngineRequest>();
            shapes.Add(new EngineRequest("Apply").List("Modules", mods).Switch("EmptyRecycleBin").List("SkipItems", skip)
                .Switch("DryRun").Switch("NoBackup").Switch("NoRestorePoint").Switch("AllProfiles"));
            shapes.Add(new EngineRequest("Apply").List("Modules", new[] { "gdid", "gdidlock" }).List("SkipItems", skip));
            shapes.Add(new EngineRequest("Audit").List("Modules", mods).List("SkipItems", skip));
            shapes.Add(new EngineRequest("Audit").Switch("WithProof").List("SkipItems", skip));
            shapes.Add(new EngineRequest("InstallGuard").List("Modules", mods).List("SkipItems", skip).Switch("GuardDaily"));
            shapes.Add(new EngineRequest("Monitor").Int("MonitorHours", 24));
            shapes.Add(new EngineRequest("SnapshotDiff").Str("SnapshotDiff", "snap-20261101-120000.json|snap-20261114-090000.json"));
            shapes.Add(new EngineRequest("Spy").Switch("SpyAll"));
            shapes.Add(new EngineRequest("RemoveApps").List("AppItems", new[] { "Microsoft.BingNews", "Clipchamp.Clipchamp" }).Switch("AllUsers"));
            shapes.Add(new EngineRequest("StartupSet").Str("StartupValue", "Off").List("StartupItems", new[] { "cnVufEhLQ1V8U3RlYW0", "cnVufEhLTE18U2VjdXJpdHlIZWFsdGg" }));
            shapes.Add(new EngineRequest("StartupSet").Str("StartupValue", "On").List("StartupItems", new[] { "cnVufEhLQ1V8U3RlYW0" }));
            shapes.Add(new EngineRequest("RestoreItems").List("ChangeItems", new[] { "cmVnfEhLQ1V8eA", "c3RhcnR1cHx4" }));
            shapes.Add(new EngineRequest("RestoreBackup").Str("BackupPath", desk + "\\Win11Privacy-Backup-20261114-120000"));
            shapes.Add(new EngineRequest("SensorSet").Str("SensorKey", "webcam\\Microsoft.WindowsCamera_8wekyb3d8bbwe").Str("SensorValue", "Deny"));
            shapes.Add(new EngineRequest("SensorSet").Str("SensorKey", "microphone\\NonPackaged\\C:#Program Files#App#app.exe").Str("SensorValue", "Allow"));
            shapes.Add(new EngineRequest("BlockApp").Str("AppPath", "C:\\Program Files\\App (x86)\\app.exe"));
            shapes.Add(new EngineRequest("UnblockApp").Str("AppPath", "C:\\Program Files\\App (x86)\\app.exe"));
            shapes.Add(new EngineRequest("FootprintWipe").List("WipeItems", new[] { "adid", "recent", "dnscache" }));
            shapes.Add(new EngineRequest("Timeline").Int("TimelineDays", 30));
            shapes.Add(new EngineRequest("XrayScan").Int("XrayHours", 24));
            shapes.Add(new EngineRequest("XrayScan").Int("XrayHours", 24).Switch("XrayBaseline"));
            foreach (string op in new[] { "Revert", "LeakTest", "CleanJunk", "EnableMonitor", "DisableMonitor", "InstallNetGuard",
                                          "RemoveNetGuard", "RemoveGuard", "GuardNow", "InstallSensorGuard", "RemoveSensorGuard",
                                          "InstallWatcher", "RemoveWatcher", "Snapshot", "SnapshotList", "ListDefs", "Detect", "Spy",
                                          "Footprint", "DataInfo", "PurgeData", "ListApps", "ListStartup", "ChangeLog", "RestoreAll",
                                          "ListBackups", "GdidStatus", "GdidReissue", "GdidRestore", "XrayStatus", "XrayEnable",
                                          "XrayDisable", "XrayWipe", "SelfTest" })
                shapes.Add(new EngineRequest(op));
            List<string> refused = new List<string>();
            foreach (EngineRequest q in shapes)
            {
                r = RunReal(engine, q.WithCommon(desk, null), true, "2");
                if (!(r.Code == 0 && r.Ops.Count == 1 && r.Ops[0] == q.Op)) refused.Add(q.Describe() + " -> " + r.Describe());
            }
            Check("F: все " + shapes.Count + " форм запросов окна проходят схему движка (без выполнения)", refused.Count == 0,
                  string.Join(" | ", refused.ToArray()));
            r = RunReal(engine, new EngineRequest("DataInfo").WithCommon(desk, "D:\\Портативная\\Win11Privacy-Data"), true, "2");
            Check("F: переносимый режим (DataRoot) проходит схему", r.Code == 0 && r.Ops.Count == 1, r.Describe());
        }

        // --- запрос к движку: данные не превращаются в команды (F-08) -------- //
        //  Командная строка движка постоянная; операция и данные — в JSON на
        //  стандартном вводе. Здесь — что JSON из любых строк остаётся ASCII,
        //  читается обратно в ту же строку и что имя операции из данных не
        //  берётся. Сам движок (разбор, белый список, отказ) проверяют
        //  tests/engine-tests.ps1 и tests/request-boundary.ps1.
        private static void Requests()
        {
            Console.WriteLine();
            Console.WriteLine("Запрос к движку (F-08)");
            string[] nasty = {
                "x\" -XrayStatus \"", "webcam\\NonPackaged\\evil\" -XrayStatus \"", "\"\"\"", "a\\", "a\\\\", "\\\"",
                "C:\\Program Files\\", "", " ", "a b\tc", "line1\nline2\r", "-PurgeData", "-Revert -RestoreAll",
                "$(Remove-Item C:\\)", "`; & | < > ^ % !", "Путь\\Кириллица\\файл.exe", "\u0000\u0001\u001f\u007f",
                "\ud83d\ude00", "\u2028\u2029", "x' -XrayWipe '" };
            bool allAscii = true, allBack = true;
            foreach (string v in nasty)
            {
                string json = new EngineRequest("SensorSet").Str("SensorKey", v).Str("SensorValue", "Deny").ToJson();
                foreach (char c in json) if (c < 0x20 || c > 0x7E) allAscii = false;
                Dictionary<string, object> d = Json.ParseObject(json);
                Dictionary<string, object> a = d == null ? null : Json.GetObj(d, "args");
                if (d == null || Json.GetStr(d, "op") != "SensorSet" || a == null || Json.GetStr(a, "SensorKey") != v ||
                    Json.GetStr(a, "SensorValue") != "Deny" || a.Count != 2) allBack = false;
            }
            Check("JSON запроса — только печатный ASCII", allAscii);
            Check("враждебные строки читаются обратно без изменений, операция та же", allBack);
            List<string> list = new List<string>(nasty);
            string lj = new EngineRequest("FootprintWipe").List("WipeItems", list).ToJson();
            List<object> back = Json.GetArr(Json.GetObj(Json.ParseObject(lj), "args"), "WipeItems");
            bool listOk = back.Count == list.Count;
            for (int i = 0; listOk && i < list.Count; i++) listOk = Json.Str(back[i]) == list[i];
            Check("список с враждебными строками — те же элементы", listOk);
            bool threw = false;
            try { new EngineRequest("SensorSet -XrayStatus"); } catch (ArgumentException) { threw = true; }
            Check("имя операции с пробелом и ключом — отказ", threw);
            threw = false;
            try { new EngineRequest("Detect").Str("Sensor Key", "x"); } catch (ArgumentException) { threw = true; }
            Check("имя аргумента не из букв — отказ", threw);
            threw = false;
            try { new EngineRequest("Detect").Str("BackupRoot", "a").Str("BackupRoot", "b"); } catch (ArgumentException) { threw = true; }
            Check("повтор аргумента — отказ", threw);
            System.Diagnostics.ProcessStartInfo p1 = MainForm.EngineProcess(@"C:\ProgramData\Win11Privacy\bin\engine.ps1");
            Check("командная строка движка постоянная", p1.Arguments ==
                  "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"C:\\ProgramData\\Win11Privacy\\bin\\engine.ps1\" -Request",
                  p1.Arguments);
            Check("запрос идёт через стандартный ввод", p1.RedirectStandardInput);
            threw = false;
            try { MainForm.EngineProcess("C:\\x\" -XrayStatus \"\\engine.ps1"); } catch (InvalidOperationException) { threw = true; }
            Check("кавычка в пути к движку — отказ", threw);
            EngineRequest common = new EngineRequest("Detect").WithCommon("C:\\Users\\u\\Desktop\" -PurgeData \"", null);
            Dictionary<string, object> ca = Json.GetObj(Json.ParseObject(common.ToJson()), "args");
            Check("путь рабочего стола — данные запроса, а не ключи", ca != null && ca.Count == 1 &&
                  Json.GetStr(ca, "BackupRoot") == "C:\\Users\\u\\Desktop\" -PurgeData \"");
        }

        // --- аргументы при перезапуске с правами администратора -------------- //
        private static void Arguments()
        {
            Console.WriteLine();
            Console.WriteLine("Командная строка при перезапуске");
            Check("простые ключи остаются как есть",
                  MainForm.QuoteArgs(new[] { "--audit", "--silent" }) == "--audit --silent");
            string q = MainForm.QuoteArgs(new[] { "--profile", @"C:\My Files\p.json", "--silent" });
            Check("путь с пробелом берётся в кавычки", q == @"--profile ""C:\My Files\p.json"" --silent", "получено: " + q);
            Check("пустой аргумент не пропадает", MainForm.QuoteArgs(new[] { "a", "", "b" }) == "a \"\" b");
            Check("без аргументов — пустая строка", MainForm.QuoteArgs(new string[0]) == "");
        }

        // --- ключ датчика не должен уметь подставить ключ движка ------------- //
        //  Имя подраздела ConsentStore идёт в командную строку движка. Кавычка в
        //  нём закрыла бы -SensorKey, и остаток строки движок разобрал бы как свои
        //  ключи (с правами администратора). Такой ключ окно к запуску не пускает.
        private static void SensorKeys()
        {
            Console.WriteLine();
            Console.WriteLine("Ключ датчика: защита от подстановки ключей движка");
            Check("обычный пакет проходит", MainForm.IsSafeConsentKey(@"webcam\Microsoft.WindowsCamera_8wekyb3d8bbwe"));
            Check("путь NonPackaged проходит", MainForm.IsSafeConsentKey(@"microphone\NonPackaged\C:#Windows#System32#notepad.exe"));
            Check("разрешение без приложения проходит", MainForm.IsSafeConsentKey("location"));
            Check("кавычка с ключом движка — отказ", !MainForm.IsSafeConsentKey("webcam\\NonPackaged\\x\" -XrayWipe \""));
            Check("просто кавычка — отказ", !MainForm.IsSafeConsentKey("webcam\\x\"y"));
            Check("переход вверх (..) — отказ", !MainForm.IsSafeConsentKey(@"webcam\..\..\evil"));
            Check("разрешение не из букв — отказ", !MainForm.IsSafeConsentKey(@"web cam\app"));
            Check("пустой сегмент — отказ", !MainForm.IsSafeConsentKey(@"webcam\\app"));
            Check("пусто — отказ", !MainForm.IsSafeConsentKey(""));
            Check("разрешение с точкой (sensors.custom) проходит", MainForm.IsSafeConsentKey(@"sensors.custom\Microsoft.WindowsMaps_8wekyb3d8bbwe"));
            Check("кириллица в пути программы проходит", MainForm.IsSafeConsentKey("webcam\\NonPackaged\\C:#Программы#Камера#cam.exe"));
            Check("NonPackaged без программы — отказ", !MainForm.IsSafeConsentKey(@"webcam\NonPackaged"));
            Check("путь с диском вместо ключа — отказ", !MainForm.IsSafeConsentKey(@"C:\Windows\x"));
            Check("корень реестра — отказ", !MainForm.IsSafeConsentKey(@"HKLM:\SOFTWARE\x"));
            Check("сетевой путь программы — отказ", !MainForm.IsSafeConsentKey(@"webcam\NonPackaged\##server#share#x.exe"));
            Check("пакет без издателя — отказ", !MainForm.IsSafeConsentKey(@"webcam\JustAName"));
            Check("ведущая обратная косая — отказ", !MainForm.IsSafeConsentKey(@"\webcam\x_8wekyb3d8bbwe"));
            Check("замыкающая обратная косая — отказ", !MainForm.IsSafeConsentKey(@"webcam\"));
            Check("управляющий символ — отказ", !MainForm.IsSafeConsentKey("webcam\\x\n_8wekyb3d8bbwe"));
            Check("слишком длинный ключ — отказ", !MainForm.IsSafeConsentKey("webcam\\NonPackaged\\C:#" + new string('a', 320)));
        }

        // --- размер окна при открытии на разных экранах ----------------------- //
        //  Окно открывается обычного размера (как «Безопасность Windows»), а не
        //  запомненного в пикселях: тот после смены масштаба Windows давал окно
        //  то слишком маленькое, то огромное. u — высота шрифта: 17 при 100 %,
        //  21 при 125 %, 26 при 150 %, 34 при 200 %.
        private static System.Drawing.Size Sz(int w, int h) { return new System.Drawing.Size(w, h); }
        private static System.Drawing.Rectangle Wa(int w, int h) { return new System.Drawing.Rectangle(0, 0, w, h); }

        private static void WindowSize()
        {
            Console.WriteLine();
            Console.WriteLine("Размер окна при открытии на разных экранах");
            System.Drawing.Size s;
            s = MainForm.DefaultClientSize(26, Wa(3072, 1848));
            Check("3072 × 1920, 150 % — полный размер", s == Sz(1976, 1196), s.ToString());
            s = MainForm.DefaultClientSize(26, Wa(2560, 1368));
            Check("2560 × 1440, 150 % — полный размер", s == Sz(1976, 1196), s.ToString());
            s = MainForm.DefaultClientSize(34, Wa(3840, 2064));
            Check("3840 × 2160, 200 % — полный размер", s == Sz(2584, 1564), s.ToString());
            s = MainForm.DefaultClientSize(26, Wa(1920, 1008));
            Check("1920 × 1080, 150 % — по экрану с обеих сторон", s == Sz(1804, 947), s.ToString());
            s = MainForm.DefaultClientSize(17, Wa(1920, 1032));
            Check("1920 × 1080, 100 % — полный размер", s == Sz(1292, 782), s.ToString());
            s = MainForm.DefaultClientSize(17, Wa(1366, 720));
            Check("1366 × 768, 100 % — по экрану с обеих сторон", s == Sz(1284, 676), s.ToString());
            s = MainForm.DefaultClientSize(21, Wa(1366, 708));
            Check("1366 × 768, 125 % — по экрану с обеих сторон", s == Sz(1284, 665), s.ToString());
        }

        // --- тихий режим: что из файла профиля попадёт в командную строку ---- //
        //  Имена модулей и пунктов шли в неё как есть: «telemetry -Revert» в
        //  подложенном файле добавил бы к запуску другой ключ движка.
        private static string SilentArgs(string json)
        {
            string why;
            EngineRequest r = MainForm.SilentProfileArgs(Json.ParseObject(json), out why);
            return r == null ? null : r.ToJson();
        }

        private static void Profiles()
        {
            Console.WriteLine();
            Console.WriteLine("Профиль тихого режима");
            Check("обычный профиль собирается",
                  SilentArgs("{\"modules\":[\"telemetry\",\"app_vscode\"],\"skip\":[\"telemetry#3\"]}") ==
                  "{\"v\":1,\"op\":\"Apply\",\"args\":{\"Modules\":[\"telemetry\",\"app_vscode\"],\"SkipItems\":[\"telemetry#3\"]}}");
            Check("ключ движка в имени модуля — отказ", SilentArgs("{\"modules\":[\"telemetry -Revert\"]}") == null);
            Check("ключ движка в номере пункта — отказ",
                  SilentArgs("{\"modules\":[\"telemetry\"],\"skip\":[\"a#1 -PurgeData\"]}") == null);
            Check("кавычка в имени модуля — отказ", SilentArgs("{\"modules\":[\"tele\\\"metry\"]}") == null);
            Check("пустой список модулей — отказ", SilentArgs("{\"modules\":[]}") == null);
            Check("повтор модуля не удваивается",
                  SilentArgs("{\"modules\":[\"ads\",\"ads\"]}") == "{\"v\":1,\"op\":\"Apply\",\"args\":{\"Modules\":[\"ads\"]}}");
            Check("выключенная копия даёт NoBackup",
                  SilentArgs("{\"modules\":[\"ads\"],\"backup\":false}") ==
                  "{\"v\":1,\"op\":\"Apply\",\"args\":{\"Modules\":[\"ads\"],\"NoBackup\":true}}");
        }

        // --- вердикт о версии на GitHub -------------------------------------- //
        private static void Verdict()
        {
            Console.WriteLine();
            Console.WriteLine("Ответ о новой версии");
            string status, card;

            MainForm.UpdateState st = MainForm.UpdateVerdict("v99.0.0", "", out status, out card);
            Check("релиз новее — предлагаем обновиться", st == MainForm.UpdateState.Newer, "получено: " + st);

            st = MainForm.UpdateVerdict("v" + AppInfo.Version, "", out status, out card);
            Check("та же версия — обновляться нечего", st == MainForm.UpdateState.Same, "получено: " + st);

            st = MainForm.UpdateVerdict("v0.0.1", "", out status, out card);
            Check("своя сборка новее релиза", st == MainForm.UpdateState.Ahead, "получено: " + st);

            st = MainForm.UpdateVerdict("", "сеть недоступна", out status, out card);
            Check("без ответа — это неудача", st == MainForm.UpdateState.Failed, "получено: " + st);
            Check("причина неудачи показывается", card == "сеть недоступна");

            st = MainForm.UpdateVerdict(null, "нет сети", out status, out card);
            Check("пустой ответ не роняет разбор", st == MainForm.UpdateState.Failed);
        }

        // --- разбор ответов движка ------------------------------------------- //
        private static void Answers()
        {
            Console.WriteLine();
            Console.WriteLine("Разбор ответов движка");
            string src = "{\"ok\":58,\"total\":63,\"time\":\"2026-09-06 12:00\",\"hostsBlocked\":true," +
                         "\"groups\":[{\"module\":\"telemetry\",\"items\":[{\"name\":\"уровень\",\"ok\":false}]}]," +
                         "\"buffer\":{\"mb\":\"4.7\"},\"empty\":null}";
            Dictionary<string, object> d = Json.ParseObject(src);
            Check("ответ разобран", d != null);
            if (d == null) return;
            Check("число читается", Json.GetInt(d, "ok") == 58);
            Check("строка читается", Json.GetStr(d, "time") == "2026-09-06 12:00");
            Check("да/нет читается", Json.GetBool(d, "hostsBlocked"));
            Check("вложенный объект читается", Json.GetStr(Json.GetObj(d, "buffer"), "mb") == "4.7");
            List<object> groups = Json.GetArr(d, "groups");
            Check("список читается", groups.Count == 1);
            Dictionary<string, object> g = Json.Obj(groups[0]);
            Check("вложенный список читается", Json.GetArr(g, "items").Count == 1);
            Check("кириллица не теряется", Json.GetStr(Json.Obj(Json.GetArr(g, "items")[0]), "name") == "уровень");
            Check("отсутствующий ключ — пусто, а не падение", Json.GetStr(d, "нет такого") == "");
            Check("null не роняет разбор", Json.GetStr(d, "empty") == "");
            Check("обрезанный ответ не роняет разбор", Json.ParseObject("{\"ok\":1,") == null ||
                                                       Json.GetInt(Json.ParseObject("{\"ok\":1,"), "ok") == 1);
            Check("битый код символа не роняет разбор", Json.GetStr(Json.ParseObject(@"{""a"":""x\uZZZZy""}"), "a").StartsWith("x"));
            Check("код символа читается", Json.GetStr(Json.ParseObject(@"{""a"":""\u0416""}"), "a") == "Ж");
            Check("пустой ответ не роняет разбор", Json.ParseObject(null) == null && Json.ParseObject("") == null);
        }
    }
}
#endif
