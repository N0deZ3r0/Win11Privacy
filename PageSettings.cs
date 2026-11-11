// Часть MainForm: страница «Настройки», выбор разделов и готовые профили.

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
        //  Страница: Настройки
        // ================================================================== //
        private Control BuildSettingsPage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 3;
            page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));   // иначе страница растёт под самую широкую строку
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            // --- заголовок с пояснением и главные действия ----------------------
            TableLayoutPanel head = new TableLayoutPanel();
            head.ColumnCount = 2; head.RowCount = 1;
            head.Dock = DockStyle.Fill; head.AutoSize = true;
            head.BackColor = Theme.WindowBg;
            head.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

            FlowLayoutPanel titles = new FlowLayoutPanel();
            titles.FlowDirection = FlowDirection.TopDown; titles.WrapContents = false;
            titles.AutoSize = true; titles.Margin = new Padding(0);
            Label h = PageTitle(L.T("Настройки"));
            h.Margin = new Padding(0, 0, 0, (int)(u * 0.1F));
            Label sub = new Label();
            sub.Text = L.T("Выберите, что отключить. Изменения вступают в силу после «Применить».");
            sub.ForeColor = Theme.TextDim; sub.AutoSize = true; sub.Margin = new Padding(1, 0, 0, 0);
            titles.Controls.Add(h); titles.Controls.Add(sub);
            head.Controls.Add(titles, 0, 0);

            FlowLayoutPanel acts = new FlowLayoutPanel();
            acts.AutoSize = true; acts.WrapContents = false;
            acts.Anchor = AnchorStyles.Right | AnchorStyles.Top;
            acts.Margin = new Padding(0, (int)(u * 0.2F), 0, 0);
            ModernButton pv = new ModernButton(L.T("Что изменится"), false); pv.Font = Font;
            pv.Click += delegate { ShowPreview(); };
            ModernButton more = new ModernButton(L.T("Ещё") + "  ▾", false); more.Font = Font;
            ContextMenuStrip menu = BuildSettingsMenu();
            more.Click += delegate { menu.Show(more, new Point(0, more.Height + 2)); };
            _btnApply = new ModernButton(L.T("Применить"), true); _btnApply.Font = Theme.Bold(Font);
            _btnApply.Click += OnApply;
            pv.Margin = new Padding(0, 0, (int)(u * 0.5F), 0);
            more.Margin = new Padding(0, 0, (int)(u * 0.5F), 0);
            _btnApply.Margin = new Padding(0);
            acts.Controls.Add(pv); acts.Controls.Add(more); acts.Controls.Add(_btnApply);
            head.Controls.Add(acts, 1, 0);
            WrapHeadButtons(head, acts);
            page.Controls.Add(head, 0, 0);

            // --- поиск и профиль -------------------------------------------------
            TableLayoutPanel tools = new TableLayoutPanel();
            tools.ColumnCount = 3; tools.RowCount = 1;
            tools.Dock = DockStyle.Fill; tools.AutoSize = true;
            tools.BackColor = Theme.WindowBg;
            tools.Margin = new Padding(0, (int)(u * 0.9F), 0, 0);
            tools.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            tools.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            tools.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            SearchBox sb = new SearchBox(Font, L.T("Поиск по настройкам…"));
            sb.Width = (int)(u * 16F);
            sb.Anchor = AnchorStyles.Left;
            sb.Margin = new Padding(0, 0, (int)(u * 0.8F), 0);
            _search = sb.Box;
            _search.TextChanged += delegate { ApplySettingsFilter(); };
            tools.Controls.Add(sb, 0, 0);

            FlowLayoutPanel prof = new FlowLayoutPanel();
            prof.AutoSize = true; prof.WrapContents = false; prof.Anchor = AnchorStyles.Right;
            prof.Margin = new Padding(0);
            Label pl = new Label();
            pl.Text = L.T("Профиль"); pl.AutoSize = true; pl.ForeColor = Theme.TextDim;
            pl.Anchor = AnchorStyles.Left; pl.Margin = new Padding(0, (int)(u * 0.45F), (int)(u * 0.6F), 0);
            _preset = new Segmented();
            _preset.Font = Font;
            _preset.Add("base", L.T("Базовый"));
            _preset.Add("strict", L.T("Строгий"));
            _preset.Add("max", L.T("Максимум"));
            _preset.Add("custom", L.T("Свой"));
            _preset.Margin = new Padding(0);
            _preset.Picked += delegate(string k) { if (k != "custom") ApplyPreset(k); };
            prof.Controls.Add(pl); prof.Controls.Add(_preset);
            tools.Controls.Add(prof, 2, 0);
            page.Controls.Add(tools, 0, 1);

            // --- карточка со списком ---------------------------------------------
            Card card = new Card();
            card.Dock = DockStyle.Fill;
            card.Margin = new Padding(0, (int)(u * 0.8F), 0, (int)(u * 0.3F));
            card.Padding = new Padding((int)(u * 0.5F));
            _settingsList = new StackPanel();
            _settingsList.Dock = DockStyle.Fill;
            _settingsList.Font = Font;
            _settingsList.Padding = new Padding((int)(u * 0.3F), (int)(u * 0.2F), (int)(u * 0.3F), (int)(u * 0.4F));
            Dwm.DarkScrollbars(_settingsList);

            string lastSec = null;
            foreach (ModuleDef m in _mods)
            {
                if (m.Section != lastSec) { SectionHeader sh = new SectionHeader(m.Section); sh.Font = Font; _settingsList.Controls.Add(sh); lastSec = m.Section; }
                OptionRow r = new OptionRow(m.Title, m.Description, m.Glyph, m.DefaultOn, m.Hard);
                r.Font = Font; m.Row = r;
                // ручная правка — уже не готовый профиль, а свой
                r.Toggle.CheckedChanged += delegate { if (!_presetBusy && _preset != null) _preset.Selected = "custom"; };
                _settingsList.Controls.Add(r);
            }
            SectionHeader safe = new SectionHeader(L.T("Безопасность")); safe.Font = Font; _settingsList.Controls.Add(safe);
            _optBackup  = MakeSafeRow(L.T("Резервная копия реестра"), L.T("На рабочий стол сохраняются .reg-файлы затрагиваемых веток."), GSave, true);
            _optRestore = MakeSafeRow(L.T("Точка восстановления"), L.T("Позволяет откатить всё через «Восстановление системы»."), GUndo, true);
            _optDry     = MakeSafeRow(L.T("Тестовый прогон"), L.T("Показать список действий в журнале, ничего не меняя."), GEye, false);
            _optDry.Toggle.CheckedChanged += delegate { UpdateApplyText(); };
            _optProfiles = MakeSafeRow(L.T("Для всех пользователей"), L.T("Настройки пользователя ложатся и в другие профили этого компьютера, и в профиль по умолчанию — новые пользователи получат их сразу."), GContact, false);
            _settingsList.Controls.Add(_optBackup); _settingsList.Controls.Add(_optRestore); _settingsList.Controls.Add(_optDry); _settingsList.Controls.Add(_optProfiles);
            card.Controls.Add(_settingsList);
            page.Controls.Add(card, 0, 2);
            return page;
        }

        // Редкие действия — в меню «Ещё», чтобы не держать под списком ряд из
        // шести кнопок
        private ContextMenuStrip BuildSettingsMenu()
        {
            ContextMenuStrip m = new ContextMenuStrip();
            m.Renderer = new ConsoleMenuRenderer();
            m.Font = Font;
            m.ShowImageMargin = false;
            m.Items.Add(L.T("Снять всё"), null, delegate { SetAll(false); });
            m.Items.Add(L.T("По умолчанию"), null, delegate { ResetDefaults(); });
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add(L.T("Загрузить профиль…"), null, OnLoadProfile);
            m.Items.Add(L.T("Сохранить профиль…"), null, OnSaveProfile);
            m.Items.Add(L.T("Файл для других ПК…"), null, OnExportDeploy);
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add(L.T("Открыть папку резервных копий"), null,
                delegate { try { Process.Start("explorer.exe", Environment.GetFolderPath(Environment.SpecialFolder.Desktop)); } catch { } });
            _miRevert = (ToolStripMenuItem)m.Items.Add(L.T("Откатить изменения…"), null, OnRevert);
            foreach (ToolStripItem it in m.Items) { it.ForeColor = Theme.Text; it.Padding = new Padding(4, 3, 4, 3); }
            return m;
        }
        private ModernButton _btnApply;
        private ToolStripMenuItem _miRevert;
        private Segmented _preset;
        private bool _presetBusy;
        private OptionRow _optProfiles;

        private OptionRow MakeSafeRow(string t, string d, string g, bool on)
        { OptionRow r = new OptionRow(t, d, g, on, false); r.Font = Font; return r; }

        // ================================================================== //
        //  Логика выбора
        // ================================================================== //
        private void SetAll(bool on) { foreach (ModuleDef m in _mods) if (m.Row != null && (m.Installed || !m.App)) m.Row.Checked = on; }

        // ================================================================== //
        //  Готовые наборы. Выбрать «насколько жёстко» проще, чем разобраться
        //  в двух десятках разделов: «Базовый» — то, что никому не мешает,
        //  «Строгий» — плюс службы, домены и геолокация, «Максимум» — всё.
        // ================================================================== //
        private void ApplyPreset(string kind)
        {
            string[] baseMods = { "telemetry", "errors", "activity", "input", "edge", "delivery",
                                  "ads", "search", "copilot", "ai", "cleanup", "apppriv", "network" };
            string[] strictAdd = { "widgets", "location", "onedrive", "cloudsync", "defender", "services", "hosts" };
            int n = 0;
            _presetBusy = true;
            foreach (ModuleDef m in _mods)
            {
                if (m.Row == null) continue;
                bool on;
                if (kind == "max") on = true;
                else if (m.App) on = true;                       // телеметрия программ — если они есть
                else on = Array.IndexOf(baseMods, m.Id) >= 0 ||
                          (kind == "strict" && Array.IndexOf(strictAdd, m.Id) >= 0);
                on = on && (m.Installed || !m.App);
                m.Row.Checked = on;
                if (on) n++;
            }
            _presetBusy = false;
            if (_preset != null) _preset.Selected = kind;
            string title = kind == "max" ? L.T("Максимум") : (kind == "strict" ? L.T("Строгий") : L.T("Базовый"));
            _status.Text = L.T("Набор «") + title + L.T("»: отмечено разделов — ") + n + ".";
            if (_settingsList != null) _settingsList.Invalidate(true);
        }
        private void ResetDefaults() { foreach (ModuleDef m in _mods) if (m.Row != null) m.Row.Checked = m.DefaultOn && (m.Installed || !m.App); }
        private void UpdateApplyText() { if (_btnApply != null && _optDry != null) _btnApply.Text = _optDry.Checked ? L.T("Проверить") : L.T("Применить"); }

        // Фильтр поиска по странице «Настройки»
        private void ApplySettingsFilter()
        {
            if (_settingsList == null || _search == null) return;
            string q = _search.Text.Trim().ToLowerInvariant();
            _settingsList.Hidden.Clear();
            if (q.Length > 0)
            {
                SectionHeader curHead = null; bool curVisible = false;
                foreach (Control c in _settingsList.Controls)
                {
                    SectionHeader sh = c as SectionHeader;
                    if (sh != null)
                    {
                        if (curHead != null && !curVisible) _settingsList.Hidden.Add(curHead);
                        curHead = sh; curVisible = false;
                        continue;
                    }
                    SubOptionRow sub = c as SubOptionRow;
                    if (sub != null) { if (!sub.Visible) _settingsList.Hidden.Add(sub); continue; }
                    OptionRow r = c as OptionRow;
                    bool match = false;
                    if (r != null)
                        match = r.Title.ToLowerInvariant().Contains(q) ||
                                r.Description.ToLowerInvariant().Contains(q) ||
                                (curHead != null && curHead.Text.ToLowerInvariant().Contains(q));
                    if (!match) _settingsList.Hidden.Add(c); else curVisible = true;
                }
                if (curHead != null && !curVisible) _settingsList.Hidden.Add(curHead);
            }
            try { _settingsList.VerticalScroll.Value = 0; } catch { }
            _settingsList.Restack();
        }

        // Ctrl+1..9 — переключение страниц
        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if ((keyData & Keys.Control) == Keys.Control)
            {
                Keys k = keyData & Keys.KeyCode;
                int idx = -1;
                if (k >= Keys.D1 && k <= Keys.D9) idx = (int)(k - Keys.D1);
                else if (k == Keys.D0) idx = 9;
                if (idx >= 0 && idx < _nav.Count) { Navigate((string)_nav[idx].Tag); return true; }
                if (k == Keys.F)
                {
                    TextBox box;
                    if (_pageSearch.TryGetValue(_current, out box) && box != null) { box.Focus(); return true; }
                    if (_search != null) { Navigate("settings"); _search.Focus(); return true; }
                }
            }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        private List<string> SelectedModules()
        {
            List<string> ids = new List<string>();
            foreach (ModuleDef m in _mods) if (m.Row != null && m.Row.Checked) ids.Add(m.Id);
            return ids;
        }
    }
}
