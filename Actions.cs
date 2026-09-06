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
            string extra = "-Modules " + string.Join(",", mods.ToArray());
            List<string> skip = SkippedItems();
            if (skip.Count > 0) extra += " -SkipItems " + string.Join(",", skip.ToArray());
            if (dry) extra += " -DryRun";
            if (!_optBackup.Checked) extra += " -NoBackup";
            if (!_optRestore.Checked) extra += " -NoRestorePoint";
            RunStreaming(extra, dry ? L.T("Тестовый прогон…") : L.T("Применение настроек…"), delegate { });
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
                foreach (string l in lines) if (l.StartsWith("      ")) total++;
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
                L.T("• стража, слежение за датчиками и живые уведомления.\n\n") +
                L.T("Удалённые приложения не возвращаются — их можно поставить из Microsoft Store.\n\nПродолжить?"),
                L.T("Откат изменений"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming("-Revert", L.T("Откат изменений…"), delegate { RunDetect(); });
        }

        private void OnSaveProfile(object sender, EventArgs e)
        {
            List<string> mods = SelectedModules();
            SaveFileDialog d = new SaveFileDialog();
            d.Filter = L.T("Профиль Win11Privacy (*.json)|*.json"); d.FileName = "win11privacy-profile.json";
            if (d.ShowDialog(this) != DialogResult.OK) return;
            try
            {
                StringBuilder sb = new StringBuilder();
                sb.Append("{\n  \"version\": 1,\n  \"modules\": [");
                for (int i = 0; i < mods.Count; i++) { sb.Append("\"").Append(mods[i]).Append("\""); if (i < mods.Count - 1) sb.Append(", "); }
                sb.Append("],\n");
                // Раньше профиль помнил только модули, и точная настройка
                // «применить не всё, а выбранное» при переносе на другой
                // компьютер терялась.
                List<string> skip = SkippedItems();
                sb.Append("  \"skip\": [");
                for (int i = 0; i < skip.Count; i++) { sb.Append("\"").Append(skip[i]).Append("\""); if (i < skip.Count - 1) sb.Append(", "); }
                sb.Append("],\n");
                sb.Append("  \"backup\": ").Append(_optBackup.Checked ? "true" : "false").Append(",\n");
                sb.Append("  \"restorePoint\": ").Append(_optRestore.Checked ? "true" : "false").Append("\n}\n");
                File.WriteAllText(d.FileName, sb.ToString(), new UTF8Encoding(false));
                _status.Text = L.T("Профиль сохранён: ") + Path.GetFileName(d.FileName);
            }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, L.T("Ошибка"), MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }

        private void OnLoadProfile(object sender, EventArgs e)
        {
            OpenFileDialog d = new OpenFileDialog();
            d.Filter = L.T("Профиль Win11Privacy (*.json)|*.json|Все файлы|*.*");
            if (d.ShowDialog(this) != DialogResult.OK) return;
            try { ApplyProfileFile(d.FileName); _status.Text = L.T("Профиль загружен: ") + Path.GetFileName(d.FileName); }
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

        private void RunAuditInner(string auditArgs)
        {
            RunJson(auditArgs, L.T("Проверка состояния системы…"), delegate(Dictionary<string, object> d)
            {
                if (d == null) { _auditWhen.Text = L.T("Не удалось получить данные."); return; }
                _lastAudit = d;
                Dictionary<string, object> pf = Json.GetObj(d, "proof");
                if (pf != null) _lastProof = pf;
                RenderAudit(d);
                RefreshHome();
            });
        }

        private ModernButton _btnCleanJunk;

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
            if (_homeAlert == null) return;
            string text = null, btn = null;
            Action go = null;

            if (_junkCount > 0)
            {
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
                        text = L.T("Страж вернул настройки, сбитые Windows: ") + drift + L.T(" шт. Проверка ") + when + ".";
                        if (kbs.Count > 0) text += L.T(" После обновления ") + Json.Str(kbs[0]) + ".";
                        btn = L.T("Подробнее");
                        go = delegate { Navigate("guard"); };
                    }
                }
            }

            if (text == null) { _homeAlert.Visible = false; FitHomeHeight(); return; }
            _homeAlertText.Text = text;
            _homeAlertBtn.Text = btn;
            _homeAlertBtn.Fit();
            _homeAlertGo = go;
            _homeAlert.Visible = true;
            FitHomeHeight();
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
            _ring.SetScore(ok, total);
            _auditHint.Visible = false;
            _auditWhen.Text = L.T("Проверено: ") + Json.GetStr(d, "time");

            _auditTiles.Controls.Clear();
            int fails = total - ok;
            _auditTiles.Controls.Add(Tile(L.T("Применено"), ok + " / " + total, L.T("настроек подтверждено"), fails == 0 ? Theme.Ok : Theme.Accent));
            _auditTiles.Controls.Add(Tile(L.T("Не применено"), fails.ToString(), fails == 0 ? L.T("всё на месте") : L.T("требуют внимания"), fails == 0 ? Theme.Ok : Theme.Warn));
            int blockedTiles = Json.GetInt(d, "blocked");
            if (blockedTiles > 0)
                _auditTiles.Controls.Add(Tile(L.T("Windows не отдаёт"), blockedTiles.ToString(), L.T("не считаются в индексе"), Theme.TextFaint));
            int naTiles = Json.GetInt(d, "notApplicable");
            if (naTiles > 0)
                _auditTiles.Controls.Add(Tile(L.T("Нет на этой Windows"), naTiles.ToString(), L.T("не считаются в индексе"), Theme.TextFaint));
            Dictionary<string, object> buf = Json.GetObj(d, "buffer");
            if (buf != null) { string mb = Json.GetStr(buf, "mb"); _auditTiles.Controls.Add(Tile(L.T("Буфер телеметрии"), (mb == "-1" ? L.T("нет") : mb + L.T(" МБ")), Json.GetInt(buf, "files") + L.T(" файлов ждут отправки"), Theme.Accent)); }
            List<object> dns = Json.GetArr(d, "dns");
            int leaked = 0; foreach (object o in dns) if (!Json.GetBool(Json.Obj(o), "blocked")) leaked++;
            _auditTiles.Controls.Add(Tile(L.T("Обращения к телеметрии"), dns.Count.ToString(), leaked + L.T(" проходит, по кэшу DNS"), leaked == 0 ? Theme.Ok : Theme.Err));

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
                RunStreaming("-DisableMonitor", L.T("Выключение монитора…"), delegate { _monitorEnabled = false; UpdateMonitorButton(); });
            else
            {
                if (MessageBox.Show(this, L.T("Монитор включит правила брандмауэра для служб телеметрии и начнёт\nвести журнал заблокированных исходящих соединений.\n\nПродолжить?"),
                    L.T("Включить монитор"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
                RunStreaming("-EnableMonitor", L.T("Включение монитора…"), delegate { _monitorEnabled = true; UpdateMonitorButton(); });
            }
        }
        private void UpdateMonitorButton()
        { if (_monitorToggle != null) { _monitorToggle.Text = _monitorEnabled ? L.T("Выключить монитор") : L.T("Включить монитор"); _monitorToggle.Primary = !_monitorEnabled; _monitorToggle.Invalidate(); } }

        private void RefreshMonitor()
        {
            RunJson("-Monitor -MonitorHours 24", L.T("Сбор статистики соединений…"), delegate(Dictionary<string, object> d) { RenderMonitor(d); });
        }

        private void RenderMonitor(Dictionary<string, object> d)
        {
            {
                if (d == null || d.ContainsKey("error")) { _monitorList.Controls.Clear(); SectionHeader sh = new SectionHeader(d != null ? Json.GetStr(d, "error") : L.T("Нет данных — PowerShell недоступен")); sh.Font = Font; _monitorList.Controls.Add(sh); _monitorList.Restack(); return; }
                _lastMonitor = d;
                _monitorEnabled = Json.GetBool(d, "enabled"); UpdateMonitorButton();
                int total = Json.GetInt(d, "total"), tele = Json.GetInt(d, "telemetryHits");
                _monitorTiles.Controls.Clear();
                _monitorTiles.Controls.Add(Tile(L.T("Исходящих соединений"), total.ToString(), L.T("за 24 часа"), Theme.Accent));
                _monitorTiles.Controls.Add(Tile(L.T("К телеметрии"), tele.ToString(), L.T("распознано по имени домена"), tele == 0 ? Theme.Ok : Theme.Warn));
                _monitorTiles.Controls.Add(Tile(L.T("Отклонено"), Json.GetInt(d, "blocked").ToString(), L.T("попыток срезал брандмауэр"), Theme.Ok));
                _monitorTiles.Controls.Add(Tile(L.T("Правил брандмауэра"), Json.GetInt(d, "firewallRules").ToString(), _monitorEnabled ? L.T("монитор включён") : L.T("монитор выключен"), _monitorEnabled ? Theme.Ok : Theme.TextFaint));

                _monitorList.Controls.Clear();
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
                        bool tel = System.Text.RegularExpressions.Regex.IsMatch(dom, "telemetry|events\\.data|vortex|aria|watson|data\\.microsoft", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                        _monitorList.Controls.Add(new KvRow(label, Json.GetInt(ds, "count") + "×", tel) { Font = this.Font });
                    }
                }
                if (procs.Count == 0 && dests.Count == 0)
                { SectionHeader sh = new SectionHeader(_monitorEnabled ? L.T("Пока ничего не зафиксировано — данные появятся по мере работы") : L.T("Включите монитор, чтобы начать сбор")); sh.Font = Font; _monitorList.Controls.Add(sh); }
                try { _monitorList.AutoScrollPosition = Point.Empty; } catch { }
            _monitorList.Restack();
            }
        }

        // ================================================================== //
        //  Действия — Страж
        // ================================================================== //
        private void OnGuardInstall(object sender, EventArgs e)
        {
            List<string> mods = SelectedModules();
            if (mods.Count == 0) { MessageBox.Show(this, L.T("Сначала выберите на странице «Настройки», что отслеживать."), L.T("Страж"), MessageBoxButtons.OK, MessageBoxIcon.Information); Navigate("settings"); return; }
            RunStreaming("-InstallGuard -Modules " + string.Join(",", mods.ToArray()) + (_guardDaily ? " -GuardDaily" : ""),
                L.T("Установка стража…"), delegate { RunDetect(); });
        }
        private void OnGuardRemove(object sender, EventArgs e)
        { RunStreaming("-RemoveGuard", L.T("Удаление стража…"), delegate { RunDetect(); }); }
        private void OnGuardNow(object sender, EventArgs e)
        { RunStreaming("-GuardNow", L.T("Проверка стражем…"), delegate { RunDetect(); }); }

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

        private void RenderGuard()
        {
            if (_guardBody == null) return;
            _guardBody.Controls.Clear();
            _btnGuardInstall.Text = _guardInstalled ? L.T("Переустановить") : L.T("Включить стража");
            _btnGuardRemove.Enabled = _guardInstalled; _btnGuardNow.Enabled = _guardInstalled;

            SectionHeader sh = new SectionHeader(L.T("Состояние")); sh.Font = Font; _guardBody.Controls.Add(sh);
            _guardBody.Controls.Add(new KvRow(L.T("Страж"), _guardInstalled ? L.T("включён") : L.T("выключен"), false) { Font = this.Font });
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
                    if (kb.Count > 0) { StringBuilder sb = new StringBuilder(); foreach (object o in kb) { if (sb.Length > 0) sb.Append(", "); sb.Append(Json.Str(o)); } _guardBody.Controls.Add(new KvRow(L.T("Обновления Windows"), sb.ToString(), false) { Font = this.Font }); }
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
                {
                    StringBuilder sb = new StringBuilder();
                    foreach (object o in kb2) { if (sb.Length > 0) sb.Append(", "); sb.Append(Json.Str(o)); }
                    _guardBody.Controls.Add(new KvRow(L.T("За этот период установлены обновления"), sb.ToString(), broke > 0) { Font = this.Font });
                }
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
