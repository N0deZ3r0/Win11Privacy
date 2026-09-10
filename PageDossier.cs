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
    // Страница «Досье»: кто включал камеру и микрофон, цифровой след.
    public partial class MainForm : Form
    {
        // ================================================================== //
        //  Страница: Досье — кто подглядывал и цифровой след
        // ================================================================== //
        private Control BuildDossierPage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 4;
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            TableLayoutPanel head = new TableLayoutPanel();
            head.ColumnCount = 2; head.Dock = DockStyle.Fill; head.AutoSize = true;
            head.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            page.RowStyles[1] = new RowStyle(SizeType.Absolute, (int)(u * 7.6F));
            head.Controls.Add(PageTitle(L.T("Досье Windows на вас")), 0, 0);
            page.Controls.Add(head, 0, 0);

            Card ctl = new Card();
            ctl.Dock = DockStyle.Fill;
            ctl.Margin = new Padding(0, (int)(u * 0.5F), 0, (int)(u * 0.5F));
            ctl.Padding = new Padding((int)(u * 0.9F), (int)(u * 0.7F), (int)(u * 0.9F), (int)(u * 0.7F));
            TableLayoutPanel ci = new TableLayoutPanel();
            ci.Dock = DockStyle.Fill; ci.AutoSize = true; ci.ColumnCount = 1; ci.RowCount = 2;
            ci.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            ci.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            ci.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            _dossierState = new Label();
            _dossierState.AutoSize = false; _dossierState.Dock = DockStyle.Fill;
            _dossierState.TextAlign = ContentAlignment.MiddleLeft; _dossierState.ForeColor = Theme.TextDim;
            _dossierState.Text = L.T("Windows сама ведёт журналы: кто включал камеру и микрофон, какие сети\n") +
                                 L.T("и флешки видел компьютер, что вы открывали и копировали.\n") +
                                 L.T("Программа читает эти журналы локально — наружу ничего не отправляется.");
            ci.Controls.Add(_dossierState, 0, 0);
            FlowLayoutPanel db = new FlowLayoutPanel();
            AttachButtonRow(db, ctl);
            db.Margin = new Padding(0, (int)(u * 0.5F), 0, 0);
            _btnDossierRefresh = new ModernButton(L.T("Собрать досье"), true);
            _btnDossierRefresh.Click += delegate { RefreshDossier(); };
            _btnDossierWipe = new ModernButton(L.T("Стереть выбранное"), false);
            _btnDossierWipe.Enabled = false;
            _btnDossierWipe.Click += OnDossierWipe;
            _btnDossierAll = new ModernButton(L.T("Показать все разрешения"), false);
            _btnDossierAll.Click += delegate { _spyShowAll = !_spyShowAll; RefreshSpy(); };
            ModernButton dossierReport = new ModernButton(L.T("Сохранить отчёт"), false);
            dossierReport.Click += OnSaveReport;
            foreach (ModernButton b in new[] { _btnDossierRefresh, _btnDossierAll, _btnDossierWipe, dossierReport })
            { b.Font = b.Primary ? new Font(Font, FontStyle.Bold) : Font; b.Margin = new Padding((int)(u * 0.4F), 0, 0, (int)(u * 0.3F)); db.Controls.Add(b); }
            ci.Controls.Add(db, 0, 1);
            ctl.Controls.Add(ci);
            page.Controls.Add(ctl, 0, 1);

            _dossierTiles = new TileGrid();
            _dossierTiles.Dock = DockStyle.Fill; _dossierTiles.AutoSize = true; _dossierTiles.Font = Font;
            _dossierTiles.Margin = new Padding(0, 0, 0, (int)(u * 0.4F));
            page.Controls.Add(_dossierTiles, 0, 2);

            Card list = new Card();
            list.Dock = DockStyle.Fill; list.Padding = new Padding((int)(u * 0.6F));
            list.Margin = new Padding(0, 0, 0, (int)(u * 0.3F));
            _dossierList = new StackPanel();
            _dossierList.Dock = DockStyle.Fill; _dossierList.Font = Font;
            _dossierList.Padding = new Padding((int)(u * 0.4F));
            Dwm.DarkScrollbars(_dossierList);
            list.Controls.Add(_dossierList);
            page.Controls.Add(list, 0, 3);
            return page;
        }

        // Только журнал датчиков — без повторного сканирования диска
        private void RefreshSpy()
        {
            if (_btnDossierAll != null)
                _btnDossierAll.Text = _spyShowAll ? L.T("Только использованные") : L.T("Показать все разрешения");
            RunJson(_spyShowAll ? "-Spy -SpyAll" : "-Spy", L.T("Чтение разрешений…"),
                delegate(Dictionary<string, object> d) { if (d != null) { _lastSpy = d; RenderDossier(); } });
        }

        private void RefreshDossier()
        {
            RunJson(_spyShowAll ? "-Spy -SpyAll" : "-Spy", L.T("Чтение журнала доступа к камере и микрофону…"), delegate(Dictionary<string, object> d)
            {
                _lastSpy = d;
                RunJson("-Footprint", L.T("Сканирование цифрового следа…"), delegate(Dictionary<string, object> f)
                {
                    _lastFoot = f;
                    RenderDossier();
                });
            });
        }

        private string CapGlyph(string id)
        {
            if (id == "webcam") return GCam;
            if (id == "microphone") return GMic;
            if (id == "location") return GPin;
            if (id == "contacts" || id == "userAccountInformation") return GContact;
            return GDoc;
        }

        private Color CapColor(string id)
        {
            if (id == "webcam") return Theme.Err;
            if (id == "microphone") return Theme.Warn;
            if (id == "location") return Theme.Accent;
            return Theme.TextDim;
        }

        private string FootGlyph(string id)
        {
            if (id == "adid") return GAds;
            if (id == "machineid") return GChip;
            if (id == "networks") return GWifi;
            if (id == "usb") return GUsb;
            if (id == "activity") return GHist;
            if (id == "recent") return GDoc;
            if (id == "searchhistory") return GSearch;
            if (id == "typedpaths") return GKeyboard;
            if (id == "clipboard") return GClipb;
            if (id == "wer") return GError;
            if (id == "inputpers") return GKeyboard;
            if (id == "dnscache") return GGlobe;
            return GDoc;
        }

        // «2026-08-31 18:36» -> «сегодня 18:36», «вчера», «3 дн назад»
        private static string Ago(string s)
        {
            DateTime t;
            if (!DateTime.TryParseExact(s, "yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out t)) return s;
            TimeSpan d = DateTime.Now - t;
            if (d.TotalMinutes < 1) return L.T("только что");
            if (d.TotalHours < 1) return ((int)d.TotalMinutes) + L.T(" мин назад");
            if (t.Date == DateTime.Today) return L.T("сегодня ") + t.ToString("HH:mm");
            if (t.Date == DateTime.Today.AddDays(-1)) return L.T("вчера ") + t.ToString("HH:mm");
            if (d.TotalDays < 7) return ((int)d.TotalDays) + L.T(" дн назад");
            return t.ToString("dd.MM.yyyy");
        }

        private static string Dur(double m)
        {
            if (m <= 0) return "";
            if (m < 1) return L.T("меньше минуты");
            if (m < 60) return ((int)Math.Round(m)) + L.T(" мин");
            int h = (int)(m / 60);
            return h + L.T(" ч ") + ((int)Math.Round(m - h * 60)) + L.T(" мин");
        }

        private void RenderDossier()
        {
            if (_dossierList == null) return;
            _dossierTiles.Controls.Clear();
            _dossierList.Controls.Clear();

            int activeNow = 0, week = 0;
            if (_lastSpy != null)
            {
                activeNow = Json.GetInt(_lastSpy, "activeNow");
                week = Json.GetInt(_lastSpy, "week");
                _dossierTiles.Controls.Add(Tile(L.T("Сейчас используют датчики"), activeNow.ToString(),
                    activeNow > 0 ? L.T("смотрите список ниже!") : L.T("в данный момент никто"), activeNow > 0 ? Theme.Err : Theme.Ok));
                _dossierTiles.Controls.Add(Tile(L.T("Обращений за 7 дней"), week.ToString(), L.T("камера, микрофон, геолокация"), Theme.Warn));
            }
            if (_lastFoot != null)
            {
                _dossierTiles.Controls.Add(Tile(L.T("След на диске"), Json.GetStr(_lastFoot, "totalMb") + L.T(" МБ"),
                    L.T("журналов и историй о вас"), Theme.Accent));
                _dossierTiles.Controls.Add(Tile(L.T("Можно стереть"), Json.GetInt(_lastFoot, "wipeable").ToString(),
                    L.T("пунктов — отметьте ниже"), Theme.Accent));
            }

            if (_lastSpy != null)
            {
                bool any = false;
                foreach (object o in Json.GetArr(_lastSpy, "caps"))
                {
                    Dictionary<string, object> c = Json.Obj(o);
                    List<object> items = Json.GetArr(c, "items");
                    if (items.Count == 0) continue;
                    any = true;
                    string title = L.T(Json.GetStr(c, "title"));
                    string glob = Json.GetStr(c, "global");
                    SectionHeader sh = new SectionHeader(title + L.T(" — доступ ") + (glob == "Deny" ? L.T("запрещён") : L.T("разрешён")) +
                        L.T(", программ в журнале: ") + items.Count);
                    sh.Font = Font; _dossierList.Controls.Add(sh);
                    string id = Json.GetStr(c, "id");
                    foreach (object io in items)
                    {
                        Dictionary<string, object> it = Json.Obj(io);
                        double mins = 0;
                        object mv = Json.Get(it, "minutes");
                        if (mv != null) double.TryParse(mv.ToString().Replace(',', '.'), NumberStyles.Any, CultureInfo.InvariantCulture, out mins);
                        bool never = Json.GetBool(it, "never");
                        SpyRow sr = new SpyRow(
                            Json.GetStr(it, "app"), title, CapGlyph(id), CapColor(id),
                            never ? L.T("не пользовалась") : Ago(Json.GetStr(it, "last")),
                            Dur(mins), Json.GetBool(it, "active"),
                            Json.GetStr(it, "key"), Json.GetStr(it, "value") == "Deny");
                        sr.Font = this.Font;
                        sr.ToggleAccess += OnSensorToggleAccess;
                        _dossierList.Controls.Add(sr);
                    }
                }
                if (!any)
                {
                    SectionHeader sh = new SectionHeader(L.T("Журнал доступа к датчикам пуст")); sh.Font = Font; _dossierList.Controls.Add(sh);
                }
            }

            if (_lastFoot != null)
            {
                SectionHeader sh2 = new SectionHeader(L.T("Цифровой след — отметьте, что стереть, и нажмите «Стереть выбранное»"));
                sh2.Font = Font; _dossierList.Controls.Add(sh2);
                foreach (object o in Json.GetArr(_lastFoot, "items"))
                {
                    Dictionary<string, object> it = Json.Obj(o);
                    string id = Json.GetStr(it, "id");
                    _dossierList.Controls.Add(new WipeRow(id, L.T(Json.GetStr(it, "title")), L.T(Json.GetStr(it, "what")),
                        Json.GetStr(it, "value"), FootGlyph(id), Json.GetBool(it, "canWipe")) { Font = this.Font });
                }
                _btnDossierWipe.Enabled = Json.GetInt(_lastFoot, "wipeable") > 0;
            }

            try { _dossierList.AutoScrollPosition = Point.Empty; } catch { }
            _dossierList.Restack();
            if (_lastFoot != null)
                _dossierState.Text = L.T("Досье собрано ") + Json.GetStr(_lastFoot, "time") +
                    L.T(". Всё прочитано с этого компьютера, наружу ничего не отправляется.\n") +
                    L.T("Красная метка «СЕЙЧАС» — программа использует датчик прямо в эту минуту.");
            else
                _dossierState.Text = L.T("Журнал датчиков прочитан. Нажмите «Собрать досье» — программа просканирует\n") +
                    L.T("ещё и цифровой след на диске (рекламный ID, сети, флешки, истории).");

            foreach (NavItem n in _nav)
                if ((string)n.Tag == "dossier") { n.Badge = activeNow > 0 ? "!" : ""; n.Invalidate(); }
            RefreshHome();
        }

        // Запретить или вернуть программе доступ к камере, микрофону, геолокации
        private void OnSensorToggleAccess(object sender, EventArgs e)
        {
            SpyRow r = sender as SpyRow;
            if (r == null || r.Key.Length == 0) return;
            string want = r.Denied ? "Allow" : "Deny";
            RunJson("-SensorSet -SensorKey \"" + r.Key + "\" -SensorValue " + want,
                r.Denied ? L.T("Возврат доступа…") : L.T("Запрет доступа…"),
                delegate(Dictionary<string, object> d)
                {
                    if (d != null && Json.GetBool(d, "ok"))
                    {
                        r.Denied = (want == "Deny");
                        r.Invalidate();
                        _status.Text = r.Denied ? L.T("Доступ запрещён. Программе может потребоваться перезапуск.")
                                                : L.T("Доступ возвращён.");
                    }
                    else
                    {
                        string err = d != null ? Json.GetStr(d, "error") : "";
                        MessageBox.Show(this, L.T("Не удалось изменить доступ.") + (err.Length > 0 ? "\n\n" + err : ""),
                            L.T("Доступ к датчику"), MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    }
                });
        }

        // Закрыть программе выход в сеть прямо из списка «кто отправляет»
        private void OnToggleAppBlock(object sender, EventArgs e)
        {
            NetAppRow r = sender as NetAppRow;
            if (r == null || r.AppPath.Length == 0) return;
            bool want = !r.Blocked;
            if (want && MessageBox.Show(this,
                    L.T("Программе будет запрещён выход в интернет:\n\n") + r.AppPath +
                    L.T("\n\nПравило создаётся в брандмауэре Windows и снимается\n") +
                    L.T("этой же кнопкой или общим откатом. Программа останется\n") +
                    L.T("на месте, но потеряет связь с сетью.\n\nПродолжить?"),
                    L.T("Запрет выхода в сеть"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunJson((want ? "-BlockApp" : "-UnblockApp") + " -AppPath \"" + r.AppPath + "\"",
                want ? L.T("Запрет выхода в сеть…") : L.T("Возврат доступа в сеть…"),
                delegate(Dictionary<string, object> d)
                {
                    string err = d != null ? Json.GetStr(d, "error") : L.T("движок не ответил");
                    if (d == null || err.Length > 0)
                    {
                        MessageBox.Show(this, L.T("Не удалось изменить правило брандмауэра.") + (err.Length > 0 ? "\n\n" + err : ""),
                            L.T("Запрет выхода в сеть"), MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return;
                    }
                    r.Blocked = Json.GetBool(d, "blocked");
                    r.Invalidate();
                    _status.Text = r.Blocked ? L.T("Выход в сеть закрыт.") : L.T("Выход в сеть возвращён.");
                });
        }

        private void OnDossierWipe(object sender, EventArgs e)
        {
            List<string> ids = new List<string>();
            List<string> names = new List<string>();
            foreach (Control c in _dossierList.Controls)
            {
                WipeRow w = c as WipeRow;
                if (w != null && w.CanWipe && w.Checked) { ids.Add(w.Id); names.Add(w.Id); }
            }
            if (ids.Count == 0)
            { MessageBox.Show(this, L.T("Отметьте галочками, какие следы стереть."), L.T("Ничего не выбрано"), MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            if (MessageBox.Show(this, L.T("Выбранные следы (") + ids.Count + L.T(" шт.) будут удалены безвозвратно.\n") +
                L.T("Пароли Wi-Fi и системные данные не затрагиваются.\n\nПродолжить?"),
                L.T("Стереть цифровой след"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming("-FootprintWipe -WipeItems " + string.Join(",", ids.ToArray()), L.T("Стирание следов…"), delegate
            {
                RunJson("-Footprint", L.T("Повторное сканирование…"), delegate(Dictionary<string, object> f)
                { _lastFoot = f; Navigate("dossier"); RenderDossier(); });
            });
        }
    }
}
