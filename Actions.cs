using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace Win11Privacy
{
    // Действия: применение, проверка, монитор и страж — что делает каждая кнопка.
    public partial class MainForm : Form
    {
        // ================================================================== //
        //  Действия — Настройки
        // ================================================================== //
        private void OnApply(object sender, EventArgs e)
        {
            List<string> mods = SelectedModules();
            if (mods.Count == 0) { MessageBox.Show(this, L.T("Не выбран ни один пункт."), L.T("Нечего применять"), MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            bool dry = _optDry.Checked;
            if (!dry)
            {
                string warn = L.T("Будут изменены настройки системы (разделов: ") + mods.Count + ").";
                if (_optBackup.Checked) warn += L.T("\n\nПеред изменениями на рабочий стол будет сохранена резервная копия реестра.");
                if (_optRestore.Checked) warn += L.T("\nТакже будет создана точка восстановления (может занять минуту).");
                bool hard = false; foreach (ModuleDef m in _mods) if (m.Row.Checked && m.Hard) hard = true;
                if (hard) warn += L.T("\n\nВыбраны жёсткие меры (службы / hosts / брандмауэр / буфер).");
                warn += L.T("\n\nПродолжить?");
                if (MessageBox.Show(this, warn, L.T("Подтверждение"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            }
            // Корзина — отдельный вопрос: из неё уже ничего не вернуть, а
            // раньше она очищалась заодно с кэшами, стоило отметить чистку.
            bool bin = false;
            if (!dry && mods.Contains("cleanup"))
            {
                bin = MessageBox.Show(this,
                    L.T("Очистить и корзину?\n\nИз корзины файлы уже не вернуть — ни кнопкой «Откат», ни как-то иначе.\n") +
                    L.T("Остальная чистка (кэши, временные файлы, дампы) идёт в любом случае; во временной папке файлы моложе суток не трогаются."),
                    L.T("Чистка: корзина"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning,
                    MessageBoxDefaultButton.Button2) == DialogResult.Yes;
            }
            string extra = "-Modules " + string.Join(",", mods.ToArray());
            if (bin) extra += " -EmptyRecycleBin";
            List<string> skip = SkippedItems();
            if (skip.Count > 0) extra += " -SkipItems " + string.Join(",", skip.ToArray());
            if (dry) extra += " -DryRun";
            if (!_optBackup.Checked) extra += " -NoBackup";
            if (!_optRestore.Checked) extra += " -NoRestorePoint";
            if (_optProfiles != null && _optProfiles.Checked) extra += " -AllProfiles";
            RunStreaming(extra, dry ? L.T("Тестовый прогон…") : L.T("Применение настроек…"), delegate { });
        }

        // Набор для других компьютеров: тот же движок, что внутри программы, и
        // два файла — применить и вернуть. Подходит для запуска руками от имени
        // администратора и для развёртывания (GPO, Intune, скрипт входа).
        private void OnExportDeploy(object sender, EventArgs e)
        {
            List<string> mods = SelectedModules();
            if (mods.Count == 0) { MessageBox.Show(this, L.T("Не выбран ни один пункт."), L.T("Нечего применять"), MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            string root;
            using (FolderBrowserDialog d = new FolderBrowserDialog())
            {
                d.Description = L.T("Куда сложить набор для других компьютеров");
                if (d.ShowDialog(this) != DialogResult.OK) return;
                root = d.SelectedPath;
            }
            try
            {
                string dir = Path.Combine(root, "Win11Privacy-Deploy");
                Directory.CreateDirectory(dir);
                using (Stream s = System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream("engine.ps1"))
                using (FileStream f = File.Create(Path.Combine(dir, "engine.ps1")))
                    s.CopyTo(f);
                string args = "-Modules " + string.Join(",", mods.ToArray());
                List<string> skip = SkippedItems();
                if (skip.Count > 0) args += " -SkipItems " + string.Join(",", skip.ToArray());
                if (_optProfiles != null && _optProfiles.Checked) args += " -AllProfiles";
                // без копии на рабочий стол и точки восстановления: на чужом компьютере
                // их некому смотреть, а журнал для отката движок ведёт всегда
                args += " -NoBackup -NoRestorePoint";
                File.WriteAllText(Path.Combine(dir, "apply.cmd"), DeployCmd("apply the saved privacy settings", args), new UTF8Encoding(false));
                File.WriteAllText(Path.Combine(dir, "revert.cmd"), DeployCmd("undo everything the program changed", "-Revert"), new UTF8Encoding(false));
                File.WriteAllText(Path.Combine(dir, "readme.txt"),
                    L.T("Win11Privacy — набор для других компьютеров\r\n\r\n") +
                    L.T("apply.cmd  — применить выбранные настройки (разделов: ") + mods.Count + ").\r\n" +
                    L.T("revert.cmd — вернуть всё, что программа изменила, по журналу изменений.\r\n\r\n") +
                    L.T("Запускайте от имени администратора. Подходит и для развёртывания: групповая политика, Intune, скрипт входа.\r\n") +
                    L.T("Журнал отката хранится на каждом компьютере в C:\\ProgramData\\Win11Privacy.\r\n") +
                    (_optProfiles != null && _optProfiles.Checked
                        ? L.T("Настройки пользователя ложатся во все профили и в профиль по умолчанию — так они сработают и при запуске от имени SYSTEM.\r\n")
                        : L.T("Настройки пользователя ложатся только тому, от чьего имени запущен файл. Для запуска от имени SYSTEM включите «Для всех пользователей» и выгрузите набор заново.\r\n")),
                    new UTF8Encoding(true));
                _status.Text = L.T("Набор для других компьютеров сохранён: ") + dir;
                try { System.Diagnostics.Process.Start("explorer.exe", "\"" + dir + "\""); } catch { }
            }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, L.T("Ошибка"), MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }

        // Командные файлы — латиницей: cmd.exe читает их в кодовой странице консоли
        private static string DeployCmd(string what, string args)
        {
            return "@echo off\r\n" +
                   "rem Win11Privacy: " + what + ".\r\n" +
                   "rem Run as administrator, or from a deployment tool as SYSTEM.\r\n" +
                   "net session >nul 2>&1\r\n" +
                   "if errorlevel 1 (\r\n" +
                   "  echo Run this file as administrator.\r\n" +
                   "  exit /b 1\r\n" +
                   ")\r\n" +
                   "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%~dp0engine.ps1\" " + args + "\r\n" +
                   "exit /b %errorlevel%\r\n";
        }

        // Показать список того, что реально изменится, ДО нажатия «Применить»:
        // проверка уже умеет сравнивать «сейчас» с «нужно», остаётся показать.
        private void ShowPreview()
        {
            List<string> mods = SelectedModules();
            if (mods.Count == 0)
            { MessageBox.Show(this, L.T("Не выбран ни один пункт."), L.T("Нечего применять"), MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            string args = "-Audit -Modules " + string.Join(",", mods.ToArray());
            List<string> skip = SkippedItems();
            if (skip.Count > 0) args += " -SkipItems " + string.Join(",", skip.ToArray());
            RunJson(args, L.T("Сверка с текущим состоянием…"), delegate(Dictionary<string, object> d)
            {
                if (d == null) { MessageBox.Show(this, L.T("Не удалось прочитать состояние системы."), L.T("Что изменится"), MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
                List<string> lines = new List<string>();
                foreach (object go in Json.GetArr(d, "groups"))
                {
                    Dictionary<string, object> g = Json.Obj(go);
                    List<string> inGroup = new List<string>();
                    foreach (object io2 in Json.GetArr(g, "items"))
                    {
                        Dictionary<string, object> it = Json.Obj(io2);
                        if (Json.GetBool(it, "ok")) continue;
                        inGroup.Add("      " + L.T(Json.GetStr(it, "name")) + "  :  " +
                                    L.T(Json.GetStr(it, "actual")) + "  →  " + Json.GetStr(it, "expected"));
                        string note;
                        if (_defNotes.TryGetValue(Json.GetStr(it, "id"), out note)) inGroup.Add("            ⚠ " + note);
                    }
                    if (inGroup.Count == 0) continue;
                    lines.Add(L.T(Json.GetStr(g, "title")) + "  (" + inGroup.Count + ")");
                    lines.AddRange(inGroup);
                }
                if (lines.Count == 0)
                {
                    MessageBox.Show(this, L.T("Всё выбранное уже настроено — применять нечего."),
                        L.T("Что изменится"), MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                int total = 0;
                foreach (string l in lines) if (l.StartsWith("      ") && !l.StartsWith("            ⚠")) total++;
                using (ListDialog dlg = new ListDialog(L.T("Что изменится"),
                    L.T("Программа поменяет ") + total + L.T(" настроек. Слева — как сейчас, справа — как станет."),
                    lines.ToArray(), L.T("Применить"), Font, false))
                {
                    if (dlg.ShowDialog(this) == DialogResult.OK) OnApply(this, EventArgs.Empty);
                }
            });
        }

        private void OnRevert(object sender, EventArgs e)
        {
            if (MessageBox.Show(this, L.T("Программа вернёт всё, что меняла:\n\n") +
                L.T("• настройки реестра — по журналу изменений, в те значения, что были до неё;\n") +
                L.T("• службы, задачи планировщика, файл hosts, правила брандмауэра;\n") +
                L.T("• компоненты производителя и настройки сторонних программ;\n") +
                L.T("• автозащиту, слежение за датчиками и живые уведомления.\n\n") +
                L.T("Удалённые приложения не возвращаются — их можно поставить из Microsoft Store.\n\nПродолжить?"),
                L.T("Откат изменений"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming("-Revert", L.T("Откат изменений…"), delegate { RunDetect(); });
        }

        private void OnSaveProfile(object sender, EventArgs e)
        {
            string path;
            using (SaveFileDialog d = new SaveFileDialog())
            {
                d.Filter = L.T("Профиль Win11Privacy (*.json)|*.json"); d.FileName = "win11privacy-profile.json";
                if (d.ShowDialog(this) != DialogResult.OK) return;
                path = d.FileName;
            }
            try
            {
                // Вместе с модулями профиль помнит и снятые пункты внутри них:
                // иначе точная настройка «применить не всё, а выбранное» при
                // переносе на другой компьютер теряется.
                string json = "{\n  \"version\": 1,\n" +
                              "  \"modules\": [" + JsonStrings(SelectedModules()) + "],\n" +
                              "  \"skip\": [" + JsonStrings(SkippedItems()) + "],\n" +
                              "  \"backup\": " + (_optBackup.Checked ? "true" : "false") + ",\n" +
                              "  \"restorePoint\": " + (_optRestore.Checked ? "true" : "false") + ",\n" +
                              "  \"allProfiles\": " + (_optProfiles != null && _optProfiles.Checked ? "true" : "false") + "\n}\n";
                File.WriteAllText(path, json, new UTF8Encoding(false));
                _status.Text = L.T("Профиль сохранён: ") + Path.GetFileName(path);
            }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, L.T("Ошибка"), MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }

        // Идентификаторы модулей и настроек — латиница без кавычек, экранировать нечего
        private static string JsonStrings(List<string> items)
        {
            return items.Count == 0 ? "" : "\"" + string.Join("\", \"", items.ToArray()) + "\"";
        }

        private void OnLoadProfile(object sender, EventArgs e)
        {
            string path;
            using (OpenFileDialog d = new OpenFileDialog())
            {
                d.Filter = L.T("Профиль Win11Privacy (*.json)|*.json|Все файлы|*.*");
                if (d.ShowDialog(this) != DialogResult.OK) return;
                path = d.FileName;
            }
            try { ApplyProfileFile(path); _status.Text = L.T("Профиль загружен: ") + Path.GetFileName(path); }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, L.T("Ошибка"), MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }

        private void ApplyProfileFile(string path)
        {
            string txt = File.ReadAllText(path);
            Dictionary<string, object> d = Json.ParseObject(txt);
            if (d == null) return;
            HashSet<string> want = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (object o in Json.GetArr(d, "modules")) want.Add(Json.Str(o));
            foreach (ModuleDef m in _mods) if (m.Row != null) m.Row.Checked = want.Contains(m.Id);
            _profileSkip = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (object o in Json.GetArr(d, "skip")) _profileSkip.Add(Json.Str(o));
            ApplyProfileSkip();               // если список настроек ещё читается — доснимем галочки, когда он придёт
            if (d.ContainsKey("backup")) _optBackup.Checked = Json.GetBool(d, "backup");
            if (d.ContainsKey("restorePoint")) _optRestore.Checked = Json.GetBool(d, "restorePoint");
            if (d.ContainsKey("allProfiles") && _optProfiles != null) _optProfiles.Checked = Json.GetBool(d, "allProfiles");
        }

        private HashSet<string> _profileSkip;

        private void ApplyProfileSkip()
        {
            if (_profileSkip == null) return;
            bool any = false;
            foreach (ModuleDef m in _mods)
                foreach (SubOptionRow r in m.Subs) { r.Checked = !_profileSkip.Contains(r.Id); any = true; }
            if (any) _profileSkip = null;      // разложили — больше не нужен
        }

        // ================================================================== //
        //  Действия — Проверка
        // ================================================================== //
        private void RunAudit()
        {
            // один прогон вместо двух: -Audit сам отдаёт блок «до и после»,
            // иначе все 191 проверка выполнялись дважды (около 30 секунд)
            List<string> skipAudit = SkippedItems();
            string auditArgs = "-Audit -WithProof";
            if (skipAudit.Count > 0) auditArgs += " -SkipItems " + string.Join(",", skipAudit.ToArray());
            RunAuditInner(auditArgs);
        }

        // Проверка идёт ~30 секунд: второй запуск поверх первого (заход на
        // «Проверку», пока идёт стартовая) только удвоил бы ожидание.
        private bool _auditBusy;

        private void RunAuditInner(string auditArgs)
        {
            if (_auditBusy) return;
            _auditBusy = true;
            RunJson(auditArgs, L.T("Проверка состояния системы…"), delegate(Dictionary<string, object> d)
            {
                _auditBusy = false;      // ответ приходит всегда, и при «Прервать» тоже
                if (d == null) { _auditWhen.Text = L.T("Не удалось получить данные."); return; }
                _lastAudit = d;
                Dictionary<string, object> pf = Json.GetObj(d, "proof");
                if (pf != null) _lastProof = pf;
                RenderAudit(d);
                RefreshHome();
            });
        }

        private ModernButton _btnCleanJunk;

        // Проверка утечек «в бою»: доступны ли известные серверы сбора. Проверка
        // настроек говорит, что выставлено; эта — открыт ли путь к известным
        // адресам. Трафик она не наблюдает, и «никто не ответил» не выдаётся за
        // «телеметрия не уходит».
        private void OnLeakTest(object sender, EventArgs e)
        {
            if (MessageBox.Show(this,
                L.T("Программа разрешит имя каждого известного сервера сбора данных так же, как это сделает любая программа,\n") +
                L.T("и попробует открыть к нему соединение по TCP, порт 443. Данные не отправляются: соединение сразу закрывается.\n") +
                L.T("Это проверка доступности известных адресов, а не наблюдение за трафиком.\n\n") +
                L.T("Займёт до 15 секунд. Продолжить?"),
                L.T("Проверить утечки"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            RunJson("-LeakTest", L.T("Проверка утечек…"), delegate(Dictionary<string, object> d)
            {
                Dictionary<string, object> reach = d == null ? null : Json.GetObj(d, "endpointReachability");
                if (reach == null) { MessageBox.Show(this, L.T("Не удалось провести проверку."), L.T("Проверить утечки"), MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
                List<string> lines = new List<string>();
                string[] order = { "open", "blocked", "hosts", "none" };
                string[] heads = { L.T("Отвечают на TCP 443"), L.T("Закрыты брандмауэром или недоступны"),
                                   L.T("Закрыты в hosts"), L.T("Имя не разрешается") };
                List<object> items = Json.GetArr(reach, "items");
                for (int i = 0; i < order.Length; i++)
                {
                    List<string> names = new List<string>();
                    foreach (object o in items)
                    {
                        Dictionary<string, object> it = Json.Obj(o);
                        if (Json.GetStr(it, "state") == order[i]) names.Add("      " + Json.GetStr(it, "name"));
                    }
                    if (names.Count == 0) continue;
                    lines.Add(heads[i] + "  (" + names.Count + ")");
                    lines.AddRange(names);
                }
                int open = Json.GetInt(reach, "open");
                Dictionary<string, object> doh = Json.GetObj(d, "doh");
                string hint = open == 0
                    ? L.T("Ни один из известных серверов сбора не ответил на TCP 443.")
                    : open + L.T(" серверов отвечают. Закрыть их — модули «Блокировка доменов» и «Блокировка адресов телеметрии».");
                hint += L.T("\nЭто проверка известных адресов, а не трафика: новые адреса, другие порты, UDP/QUIC и сторонние службы она не видит. Что уходит на деле, показывает «Наблюдение» → «Сеть».");
                if (doh != null && !Json.GetBool(doh, "blocked"))
                    hint += L.T("\nШифрованный DNS не запрещён: браузер с ним обойдёт блокировку в hosts.");
                using (ListDialog dlg = new ListDialog(L.T("Проверка утечек"), hint, lines.ToArray(), L.T("Закрыть"), Font, false))
                    dlg.ShowDialog(this);
            });
        }

        // Старые версии писали параметры реестра под числовыми именами —
        // предлагаем убрать этот мусор, если он ещё лежит в системе.
        private void OnCleanJunk(object sender, EventArgs e)
        {
            if (MessageBox.Show(this,
                L.T("Версии программы до 1.6 записывали часть настроек в реестр под\n") +
                L.T("числовыми именами: «0», «1», «2» вместо настоящих. Такие параметры\n") +
                L.T("ничего не настраивают. Программа уберёт только их — те, что совпадают\n") +
                L.T("и по номеру, и по значению.\n\nПродолжить?"),
                L.T("Уборка за старыми версиями"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            RunStreaming("-CleanJunk", L.T("Уборка мусорных параметров…"), delegate { Navigate("audit"); RunAudit(); });
        }

        // Что важно сказать на «Обзоре» прямо сейчас. Порядок не случайный:
        // мусор от старых версий значит, что настройки вообще не применялись,
        // и это важнее свежего отчёта стража.
        private void UpdateHomeAlert()
        {
            string title = null, text = null, btn = null;
            Action go = null;

            if (_junkCount > 0)
            {
                title = L.T("В реестре остались параметры от старых версий");
                text = L.T("В реестре остались параметры под числовыми именами — их записали версии 1.1–1.5, и они ничего не настраивают. Найдено: ") + _junkCount + ".";
                btn = L.T("Убрать мусор");
                go = delegate { Navigate("audit"); OnCleanJunk(null, EventArgs.Empty); };
            }
            else if (_detect != null)
            {
                Dictionary<string, object> gl = Json.GetObj(_detect, "guardLast");
                if (gl != null)
                {
                    int drift = Json.GetArr(gl, "drifted").Count;
                    string when = Json.GetStr(gl, "time");
                    DateTime t;
                    bool fresh = DateTime.TryParse(when, out t) && (DateTime.Now - t).TotalDays <= 14;
                    if (drift > 0 && fresh)
                    {
                        List<object> kbs = Json.GetArr(gl, "hotfixes");
                        title = L.T("Обновление Windows сбило настройки");
                        text = L.T("Автозащита вернула их обратно: ") + drift + L.T(" шт. Проверка ") + when + ".";
                        if (kbs.Count > 0) text += L.T(" После обновления ") + Json.Str(kbs[0]) + ".";
                        btn = L.T("Подробнее");
                        go = delegate { Navigate("guard"); };
                    }
                }
            }

            _homeAlertTitle = title; _homeAlertDesc = text; _homeAlertBtn = btn; _homeAlertGo = go;
            RefreshHome();
        }

        private void RenderAudit(Dictionary<string, object> d)
        {
            int ok = Json.GetInt(d, "ok"), total = Json.GetInt(d, "total");
            int junk = Json.GetInt(d, "junk");
            _junkCount = junk;
            UpdateHomeAlert();
            if (_btnCleanJunk != null)
            {
                _btnCleanJunk.Visible = junk > 0;
                _btnCleanJunk.Text = L.T("Убрать мусор") + (junk > 0 ? " (" + junk + ")" : "");
            }
            _auditWhen.Text = L.T("Проверено: ") + Json.GetStr(d, "time");

            // Итог одной строкой: вывод в заголовке, подробности — пояснением.
            // Раньше здесь были кольцо и семь плиток с крупными числами.
            int fails = total - ok;
            int blockedN = Json.GetInt(d, "blocked");
            int naN = Json.GetInt(d, "notApplicable");
            List<object> dns = Json.GetArr(d, "dns");
            int leaked = 0; foreach (object o in dns) if (!Json.GetBool(Json.Obj(o), "blocked")) leaked++;
            double share = total > 0 ? (double)ok / total : 0;
            string title; Color tone; string glyph;
            if (fails == 0) { title = L.T("Все настройки действуют"); tone = Theme.Ok; glyph = GSignOk; }
            else if (share >= 0.85) { title = L.T("Почти все настройки действуют"); tone = Theme.Ok; glyph = GSignOk; }
            else if (share >= 0.5) { title = L.T("Часть настроек не действует"); tone = Theme.Warn; glyph = GSignWarn; }
            else { title = L.T("Большинство настроек не действует"); tone = Theme.Err; glyph = GSignWarn; }
            List<string> parts = new List<string>();
            parts.Add(L.T("Действует ") + ok + " " + L.T("из") + " " + total);
            if (fails > 0) parts.Add(L.T("не применено ") + fails);
            if (blockedN > 0) parts.Add(L.T("Windows не отдаёт ") + blockedN);
            if (naN > 0) parts.Add(L.T("нет на этой Windows ") + naN);
            Dictionary<string, object> buf = Json.GetObj(d, "buffer");
            if (buf != null && Json.GetStr(buf, "mb") != "-1" && Json.GetInt(buf, "files") > 0)
                parts.Add(L.T("неотправленной телеметрии ") + Json.GetStr(buf, "mb") + L.T(" МБ"));
            if (dns.Count > 0)
                parts.Add(leaked == 0 ? L.T("адреса телеметрии не отвечают") : L.T("телеметрия проходит: адресов ") + leaked);
            _auditStatus.Set(glyph, tone, title, string.Join("  ·  ", parts.ToArray()));
            _auditStatus.SetButton(fails > 0 ? L.T("Открыть настройки") : null, delegate { Navigate("settings"); });

            _auditGroups.Controls.Clear();
            RenderProof();
            foreach (object go in Json.GetArr(d, "groups"))
            {
                Dictionary<string, object> g = Json.Obj(go);
                _auditGroups.Controls.Add(new AuditGroupRow(L.T(Json.GetStr(g, "title")), Json.GetInt(g, "ok"), Json.GetInt(g, "total"), Json.GetArr(g, "items")) { Font = this.Font });
            }
            if (dns.Count > 0)
            {
                SectionHeader sh = new SectionHeader(L.T("Обращения к доменам телеметрии (из кэша DNS)")); sh.Font = Font; _auditGroups.Controls.Add(sh);
                foreach (object o in dns)
                {
                    Dictionary<string, object> dn = Json.Obj(o);
                    _auditGroups.Controls.Add(new DnsRow(Json.GetStr(dn, "name"), Json.GetBool(dn, "blocked")) { Font = this.Font });
                }
            }
            try { _auditGroups.AutoScrollPosition = Point.Empty; } catch { }
            _auditGroups.Restack();
        }

        // Результат, а не намерение: что было до программы и что стало
        private void RenderProof()
        {
            if (_lastProof == null || _auditGroups == null) return;
            Dictionary<string, object> before = Json.GetObj(_lastProof, "before");
            Dictionary<string, object> after = Json.GetObj(_lastProof, "after");
            if (after == null) return;

            SectionHeader sh = new SectionHeader(L.T("Результат: что было до программы и что стало"));
            sh.Font = Font; _auditGroups.Controls.Add(sh);

            if (before == null)
            {
                _auditGroups.Controls.Add(new KvRow(
                    L.T("Снимок «до» будет сделан автоматически при первом применении настроек"),
                    "", false) { Font = this.Font });
                return;
            }

            AddProofRow(L.T("Настроек приватности на месте"), Json.GetInt(before, "ok"), Json.GetInt(after, "ok"),
                        " " + L.T("из") + " " + Json.GetInt(after, "total"), true);
            AddProofRow(L.T("Сборщиков трассировки выключено"), Json.GetInt(before, "etwOff"), Json.GetInt(after, "etwOff"),
                        " " + L.T("из") + " " + Json.GetInt(after, "etwTotal"), true);
            AddProofRow(L.T("Задач телеметрии ещё работает"), Json.GetInt(before, "tasksLive"), Json.GetInt(after, "tasksLive"), "", false);
            AddProofRow(L.T("Доменов телеметрии не отвечает"), Json.GetInt(before, "dnsBlocked"), Json.GetInt(after, "dnsBlocked"), "", true);
            AddProofRow(L.T("Правил брандмауэра против телеметрии"), Json.GetInt(before, "fwRules"), Json.GetInt(after, "fwRules"), "", true);
            AddProofRow(L.T("Программ стартует вместе с Windows"), Json.GetInt(before, "startupOn"), Json.GetInt(after, "startupOn"), "", false);

            int xb = Json.GetInt(before, "xrayPerDay");
            int xa = Json.GetInt(_lastProof, "xrayNow");
            if (xb > 0 && xa > 0)
                AddProofRow(L.T("Событий телеметрии в сутки"), xb, xa, "", false);
        }

        // Строка «было → стало». more = «больше значит лучше»
        private void AddProofRow(string name, int before, int after, string suffix, bool more)
        {
            bool better = more ? (after > before) : (after < before);
            bool same = (after == before);
            string arrow = before + " → " + after + suffix;
            _auditGroups.Controls.Add(new KvRow(name, arrow, !same && !better) { Font = this.Font });
        }

        private StatTile Tile(string cap, string val, string sub, Color accent)
        {
            StatTile t = new StatTile(); t.Font = Font; t.Caption = cap; t.Value = val; t.Sub = sub; t.Accent = accent;
            return t;
        }

        // ================================================================== //
        //  Действия — Монитор
        // ================================================================== //
        private void OnMonitorToggle(object sender, EventArgs e)
        {
            if (_monitorEnabled)
                RunStreaming("-DisableMonitor", L.T("Выключение наблюдения за сетью…"), delegate { _monitorEnabled = false; UpdateMonitorButton(); });
            else
            {
                if (MessageBox.Show(this, L.T("Наблюдение включит правила брандмауэра для служб телеметрии и начнёт\nвести журнал исходящих соединений — разрешённых и заблокированных.\n") +
                    L.T("Журнал безопасности при этом вырастет до 128 МБ, чтобы не вытеснять другие записи.\n\nПродолжить?"),
                    L.T("Включить наблюдение"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
                RunStreaming("-EnableMonitor", L.T("Включение наблюдения за сетью…"), delegate { _monitorEnabled = true; UpdateMonitorButton(); RefreshMonitor(); });
            }
        }
        private void UpdateMonitorButton()
        {
            if (_monitorToggle != null) { _monitorToggle.Text = _monitorEnabled ? L.T("Выключить наблюдение") : L.T("Включить наблюдение"); _monitorToggle.Primary = !_monitorEnabled; _monitorToggle.Invalidate(); }
            if (_netGuardToggle != null) { _netGuardToggle.Text = _netGuardOn ? L.T("Не следить за новыми") : L.T("Следить за новыми"); _netGuardToggle.Invalidate(); }
        }

        // Слежение за сетью: уведомление, когда в сеть впервые выходит новая программа
        private ModernButton _netGuardToggle;
        private bool _netGuardOn;
        private void OnNetGuardToggle(object sender, EventArgs e)
        {
            if (_netGuardOn)
            { RunStreaming("-RemoveNetGuard", L.T("Отключение слежения за сетью…"), delegate { _netGuardOn = false; UpdateMonitorButton(); }); return; }
            if (MessageBox.Show(this,
                L.T("Каждые 15 минут программа будет сверять журнал брандмауэра. Если в сеть впервые выйдет\n") +
                L.T("НОВАЯ программа — придёт уведомление, а здесь, на вкладке «Сеть», её можно будет отрезать.\n\n") +
                L.T("Первый час слежение учится: всё, что выходит в сеть, считается своим.\n\nПродолжить?"),
                L.T("Следить за новыми программами"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            RunStreaming("-InstallNetGuard", L.T("Включение слежения за сетью…"), delegate { _netGuardOn = true; RefreshMonitor(); });
        }

        private void RefreshMonitor()
        {
            RunJson("-Monitor -MonitorHours 24", L.T("Сбор статистики соединений…"), RenderMonitor);
        }

        private void RenderMonitor(Dictionary<string, object> d)
        {
            if (d == null || d.ContainsKey("error")) { _monitorList.Controls.Clear(); SectionHeader sh = new SectionHeader(d != null ? Json.GetStr(d, "error") : L.T("Нет данных — PowerShell недоступен")); sh.Font = Font; _monitorList.Controls.Add(sh); _monitorList.Restack(); return; }
            _lastMonitor = d;
            _monitorEnabled = Json.GetBool(d, "enabled"); _netGuardOn = Json.GetBool(d, "netGuard"); UpdateMonitorButton();
            int total = Json.GetInt(d, "total"), tele = Json.GetInt(d, "telemetryHits");
            _monitorTiles.Controls.Clear();
            _monitorTiles.Controls.Add(Tile(L.T("Исходящих соединений"), total.ToString(), L.T("за 24 часа"), Theme.Accent));
            _monitorTiles.Controls.Add(Tile(L.T("К телеметрии"), tele.ToString(), L.T("распознано по имени домена"), tele == 0 ? Theme.Ok : Theme.Warn));
            _monitorTiles.Controls.Add(Tile(L.T("Отклонено"), Json.GetInt(d, "blocked").ToString(), L.T("попыток срезал брандмауэр"), Theme.Ok));
            _monitorTiles.Controls.Add(Tile(L.T("Правил брандмауэра"), Json.GetInt(d, "firewallRules").ToString(), _monitorEnabled ? L.T("наблюдение включено") : L.T("наблюдение выключено"), _monitorEnabled ? Theme.Ok : Theme.TextFaint));

            _monitorList.Controls.Clear();
            // Журнал безопасности не прочитался — это не «никто ничего не
            // отправлял». Раньше в таком случае список просто был пуст.
            string readErr = Json.GetStr(d, "readError");
            if (!string.IsNullOrEmpty(readErr))
            {
                SectionHeader se = new SectionHeader(L.T("Журнал безопасности не читается — цифры ниже неполные: ") + readErr); se.Font = Font; _monitorList.Controls.Add(se);
            }
            string guardErr = Json.GetStr(d, "netGuardError");
            if (!string.IsNullOrEmpty(guardErr))
            {
                SectionHeader sg = new SectionHeader(L.T("Слежение за сетью не смогло прочитать журнал безопасности: ") + guardErr); sg.Font = Font; _monitorList.Controls.Add(sg);
            }
            List<object> fresh = Json.GetArr(d, "newApps");
            if (fresh.Count > 0)
            {
                SectionHeader sh0 = new SectionHeader(L.T("Впервые вышли в сеть — можно закрыть выход")); sh0.Font = Font; _monitorList.Controls.Add(sh0);
                foreach (object o in fresh)
                {
                    Dictionary<string, object> na = Json.Obj(o);
                    NetAppRow r = new NetAppRow(Json.GetStr(na, "name"), Ago(Json.GetStr(na, "time")),
                                                Json.GetStr(na, "path"), Json.GetBool(na, "blocked"));
                    r.Font = Font;
                    r.ToggleBlock += OnToggleAppBlock;
                    _monitorList.Controls.Add(r);
                }
            }
            List<object> procs = Json.GetArr(d, "byProcess");
            if (procs.Count > 0)
            {
                SectionHeader sh = new SectionHeader(L.T("Кто отправляет — можно закрыть выход в сеть")); sh.Font = Font; _monitorList.Controls.Add(sh);
                foreach (object o in procs)
                {
                    Dictionary<string, object> pr = Json.Obj(o);
                    NetAppRow r = new NetAppRow(Json.GetStr(pr, "name"), Json.GetInt(pr, "count") + L.T(" соед."),
                                                Json.GetStr(pr, "path"), Json.GetBool(pr, "blocked"));
                    r.Font = Font;
                    r.ToggleBlock += OnToggleAppBlock;
                    _monitorList.Controls.Add(r);
                }
            }
            List<object> dests = Json.GetArr(d, "byDest");
            if (dests.Count > 0)
            {
                SectionHeader sh = new SectionHeader(L.T("Куда (адреса назначения)")); sh.Font = Font; _monitorList.Controls.Add(sh);
                foreach (object o in dests)
                {
                    Dictionary<string, object> ds = Json.Obj(o);
                    string dom = Json.GetStr(ds, "domain"); string ip = Json.GetStr(ds, "ip");
                    string label = string.IsNullOrEmpty(dom) ? ip : (dom + "  (" + ip + ")");
                    bool tel = Regex.IsMatch(dom, "telemetry|events\\.data|vortex|aria|watson|data\\.microsoft", RegexOptions.IgnoreCase);
                    _monitorList.Controls.Add(new KvRow(label, Json.GetInt(ds, "count") + "×", tel) { Font = this.Font });
                }
            }
            if (procs.Count == 0 && dests.Count == 0)
            { SectionHeader sh = new SectionHeader(_monitorEnabled ? L.T("Пока ничего не зафиксировано — данные появятся по мере работы") : L.T("Включите наблюдение за сетью, чтобы начать сбор")); sh.Font = Font; _monitorList.Controls.Add(sh); }
            try { _monitorList.AutoScrollPosition = Point.Empty; } catch { }
            _monitorList.Restack();
        }

        // ================================================================== //
        //  Действия — Страж
        // ================================================================== //
        private void OnGuardInstall(object sender, EventArgs e)
        {
            List<string> mods = SelectedModules();
            if (mods.Count == 0) { MessageBox.Show(this, L.T("Сначала выберите на странице «Настройки», что отслеживать."), L.T("Автозащита"), MessageBoxButtons.OK, MessageBoxIcon.Information); Navigate("settings"); return; }
            // снятые пункты страж не трогает: иначе вернул бы то, что оставлено нарочно
            List<string> skip = SkippedItems();
            RunStreaming("-InstallGuard -Modules " + string.Join(",", mods.ToArray()) +
                (skip.Count > 0 ? " -SkipItems " + string.Join(",", skip.ToArray()) : "") + (_guardDaily ? " -GuardDaily" : ""),
                L.T("Включение автозащиты…"), delegate { RunDetect(); });
        }
        private void OnGuardRemove(object sender, EventArgs e)
        { RunStreaming("-RemoveGuard", L.T("Отключение автозащиты…"), delegate { RunDetect(); }); }
        private void OnGuardNow(object sender, EventArgs e)
        { RunStreaming("-GuardNow", L.T("Проверка автозащитой…"), delegate { RunDetect(); }); }

        private void OnSensorToggle(object sender, EventArgs e)
        {
            if (_sensorOn)
            { RunStreaming("-RemoveSensorGuard", L.T("Отключение слежения за датчиками…"), delegate { RunDetect(); }); return; }
            if (MessageBox.Show(this,
                L.T("Каждые 30 минут программа будет тихо сверять журнал доступа к камере,\n") +
                L.T("микрофону и геолокации. Если доступ впервые получит НОВАЯ программа —\n") +
                L.T("вы сразу увидите уведомление.\n\n") +
                L.T("Заодно накапливается история для графика «Кто подглядывал» на «Обзоре».\n\nПродолжить?"),
                L.T("Слежение за датчиками"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            RunStreaming("-InstallSensorGuard", L.T("Включение слежения за датчиками…"), delegate { RunDetect(); });
        }

        private void OnWatcherToggle(object sender, EventArgs e)
        {
            if (_watcherOn) { RunStreaming("-RemoveWatcher", L.T("Выключение уведомлений…"), delegate { RunDetect(); }); return; }
            if (MessageBox.Show(this,
                L.T("Программа будет показывать всплывающее уведомление в момент, когда\n") +
                L.T("перехвачена попытка отправить телеметрию наружу.\n\n") +
                L.T("Включатся правила брандмауэра и журнал безопасности. Уведомления\n") +
                L.T("приходят не чаще одного раза в 10 минут, чтобы не мешать.\n\nПродолжить?"),
                L.T("Живые уведомления"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            RunStreaming("-InstallWatcher", L.T("Включение уведомлений…"), delegate { RunDetect(); });
        }

        private void OnSnapshot(object sender, EventArgs e)
        { RunStreaming("-Snapshot", L.T("Снимок состояния…"), delegate { RefreshSnapshots(); }); }

        private void RefreshSnapshots()
        {
            RunJson("-SnapshotList", L.T("Чтение снимков…"), delegate(Dictionary<string, object> d)
            {
                _snapshots = d != null ? Json.GetArr(d, "snapshots") : new List<object>();
                RenderGuard();
                if (_snapshots.Count >= 2)
                {
                    string a = Json.GetStr(Json.Obj(_snapshots[1]), "file");
                    string b = Json.GetStr(Json.Obj(_snapshots[0]), "file");
                    RunJson("-SnapshotDiff \"" + a + "|" + b + "\"", L.T("Сравнение снимков…"), delegate(Dictionary<string, object> df)
                    { _lastDiff = df; RenderGuard(); });
                }
            });
        }

        private static string JoinList(List<object> items)
        {
            return string.Join(", ", items.ConvertAll<string>(Json.Str).ToArray());
        }

        private void RenderGuard()
        {
            if (_guardBody == null) return;
            _guardBody.Controls.Clear();
            _btnGuardInstall.Text = _guardInstalled ? L.T("Переустановить") : L.T("Включить автозащиту");
            _btnGuardRemove.Enabled = _guardInstalled; _btnGuardNow.Enabled = _guardInstalled;

            SectionHeader sh = new SectionHeader(L.T("Состояние")); sh.Font = Font; _guardBody.Controls.Add(sh);
            _guardBody.Controls.Add(new KvRow(L.T("Автозащита"), _guardInstalled ? L.T("включена") : L.T("выключена"), false) { Font = this.Font });
            _guardBody.Controls.Add(new KvRow(L.T("Слежение за датчиками (камера, микрофон, гео)"), _sensorOn ? L.T("включено") : L.T("выключено"), false) { Font = this.Font });
            _guardBody.Controls.Add(new KvRow(L.T("Живые уведомления о перехвате отправки"), _watcherOn ? L.T("включены") : L.T("выключены"), false) { Font = this.Font });
            if (_detect != null)
            {
                List<object> gm = Json.GetArr(_detect, "guardModules");
                if (gm.Count > 0) _guardBody.Controls.Add(new KvRow(L.T("Отслеживается модулей"), gm.Count.ToString(), false) { Font = this.Font });
                Dictionary<string, object> last = Json.GetObj(_detect, "guardLast");
                if (last != null)
                {
                    SectionHeader sh2 = new SectionHeader(L.T("Последняя проверка")); sh2.Font = Font; _guardBody.Controls.Add(sh2);
                    _guardBody.Controls.Add(new KvRow(L.T("Время"), Json.GetStr(last, "time"), false) { Font = this.Font });
                    _guardBody.Controls.Add(new KvRow(L.T("Сбито обновлениями"), Json.GetArr(last, "drifted").Count.ToString(), false) { Font = this.Font });
                    _guardBody.Controls.Add(new KvRow(L.T("Исправлено"), Json.GetInt(last, "fixed").ToString(), false) { Font = this.Font });
                    List<object> kb = Json.GetArr(last, "hotfixes");
                    if (kb.Count > 0) _guardBody.Controls.Add(new KvRow(L.T("Обновления Windows"), JoinList(kb), false) { Font = this.Font });
                }
            }

            // машина времени
            SectionHeader sh3 = new SectionHeader(L.T("Машина времени — снимки состояния")); sh3.Font = Font; _guardBody.Controls.Add(sh3);
            if (_snapshots.Count == 0)
                _guardBody.Controls.Add(new KvRow(L.T("Снимков пока нет — нажмите «Снимок состояния»"), "", false) { Font = this.Font });
            else
                foreach (object o in _snapshots)
                {
                    Dictionary<string, object> sn = Json.Obj(o);
                    _guardBody.Controls.Add(new KvRow(Json.GetStr(sn, "time") + L.T("   (сборка ") + Json.GetStr(sn, "build") + ")",
                        Json.GetInt(sn, "ok") + " / " + Json.GetInt(sn, "total"), false) { Font = this.Font });
                }

            if (_lastDiff != null && Json.GetArr(_lastDiff, "changes").Count > 0)
            {
                int broke = Json.GetInt(_lastDiff, "broke");
                SectionHeader sh4 = new SectionHeader(L.T("Что изменилось между двумя последними снимками"));
                sh4.Font = Font; _guardBody.Controls.Add(sh4);
                List<object> kb2 = Json.GetArr(_lastDiff, "hotfixes");
                if (kb2.Count > 0)
                    _guardBody.Controls.Add(new KvRow(L.T("За этот период установлены обновления"), JoinList(kb2), broke > 0) { Font = this.Font });
                foreach (object o in Json.GetArr(_lastDiff, "changes"))
                {
                    Dictionary<string, object> c = Json.Obj(o);
                    bool bad = Json.GetBool(c, "broke");
                    _guardBody.Controls.Add(new KvRow(Json.GetStr(c, "name"),
                        Json.GetStr(c, "was") + " → " + Json.GetStr(c, "now"), bad) { Font = this.Font });
                }
            }
            _guardBody.Restack();
        }
    }
}
