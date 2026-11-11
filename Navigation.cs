// Часть MainForm: разделы и вкладки, боковая панель (сворачивание, анимация), переходы между страницами.

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
        //  Разделы боковой панели. Несколько страниц под одним пунктом
        //  переключаются вкладками; ключи страниц прежние, поэтому переходы
        //  и тестовые прогоны по страницам работают как раньше.
        // ================================================================== //
        private static readonly string[][] NavGroupPages = {
            new[] { "home" }, new[] { "settings" }, new[] { "apps", "startup" },
            new[] { "xray", "dossier", "monitor", "timeline" }, new[] { "gdid" },
            new[] { "audit", "changes" }, new[] { "guard" }, new[] { "about", "log" } };
        private readonly Dictionary<string, string> _groupOf = new Dictionary<string, string>();
        private readonly Dictionary<string, string> _groupLast = new Dictionary<string, string>();
        private readonly Dictionary<string, string> _pageBadges = new Dictionary<string, string>();
        private Panel _groupHead;
        private Label _groupTitle;
        private TabStrip _tabs;

        private string GroupOf(string page) { string g; return _groupOf.TryGetValue(page, out g) ? g : page; }

        private string[] GroupPages(string grp)
        {
            foreach (string[] g in NavGroupPages) if (g[0] == grp) return g;
            return new[] { grp };
        }

        private string GroupTitle(string grp)
        {
            switch (grp)
            {
                case "apps": return L.T("Приложения");
                case "xray": return L.T("Наблюдение");
                case "audit": return L.T("Проверка");
                case "about": return L.T("О программе");
            }
            return "";
        }

        private string TabText(string page)
        {
            switch (page)
            {
                case "apps": return L.T("Приложения");
                case "startup": return L.T("Автозагрузка");
                case "xray": return L.T("Сбор данных");
                case "dossier": return L.T("Следы на компьютере");
                case "monitor": return L.T("Сеть");
                case "timeline": return L.T("Хронология");
                case "audit": return L.T("Проверка");
                case "changes": return L.T("Изменения");
                case "about": return L.T("О программе");
                case "log": return L.T("Журнал");
            }
            return page;
        }

        // Пункт панели открывает ту вкладку раздела, на которой были в прошлый раз
        private void NavigateGroup(string grp)
        {
            string last;
            Navigate(_groupLast.TryGetValue(grp, out last) ? last : grp);
        }

        private void UpdateGroupHead(string grp, string page)
        {
            if (_groupHead == null) return;
            string[] pages = GroupPages(grp);
            bool multi = pages.Length > 1;
            if (multi)
            {
                _groupTitle.Text = GroupTitle(grp);
                List<string> texts = new List<string>();
                foreach (string p in pages) texts.Add(TabText(p));
                _tabs.SetTabs(pages, texts, page);
                foreach (string p in pages) { string b; _tabs.SetDot(p, _pageBadges.TryGetValue(p, out b) && b.Length > 0); }
            }
            if (_groupHead.Visible != multi) _groupHead.Visible = multi;
            LayoutGroupHead();
        }

        private void LayoutGroupHead()
        {
            if (_groupHead == null || _groupTitle == null || _tabs == null) return;
            int u = Font.Height;
            _groupTitle.Location = new Point(0, 0);
            _tabs.SetBounds(0, _groupTitle.Bottom + (int)(u * 0.5F), Math.Max(10, _groupHead.ClientSize.Width), _tabs.Height);
            int h = _tabs.Bottom + (int)(u * 0.8F);
            if (_groupHead.Height != h) _groupHead.Height = h;
        }

        // Отметка «загляните» у страницы: точка на её вкладке и на пункте раздела
        private void SetPageBadge(string page, string text)
        {
            _pageBadges[page] = text ?? "";
            string grp = GroupOf(page);
            bool any = false;
            foreach (KeyValuePair<string, string> kv in _pageBadges)
                if (kv.Value.Length > 0 && GroupOf(kv.Key) == grp) any = true;
            foreach (NavItem n in _nav) if ((string)n.Tag == grp) { n.Badge = any ? "1" : ""; n.Invalidate(); }
            if (_tabs != null) _tabs.SetDot(page, (text ?? "").Length > 0);
        }

        // Своё название страницы под шапкой раздела повторяло бы вкладку
        private static void HidePageTitle(Control root)
        {
            foreach (Control c in root.Controls)
            {
                if (c is Label && "pagetitle".Equals(c.Tag)) { c.Visible = false; return; }
                HidePageTitle(c);
            }
        }

        private Control BuildSidebar()
        {
            int u = Font.Height;
            SidePanel side = new SidePanel();
            _side = side;
            side.Dock = DockStyle.Fill;
            side.Width = (int)(u * 15.5F);
            side.BackColor = Theme.SideBottom;
            side.Padding = new Padding((int)(u * 0.6F), (int)(u * 0.5F), (int)(u * 0.6F), (int)(u * 0.6F));

            _navTip = new ToolTip();

            // навигация занимает всю высоту под кнопкой сворачивания:
            // «О программе» прижат к низу
            NavHost nav = new NavHost();
            nav.Dock = DockStyle.Fill;
            nav.AutoSize = false;
            nav.BackColor = Color.Transparent;
            nav.Padding = new Padding(0, (int)(u * 0.5F), 0, 0);
            nav.Font = Font;
            nav.Resize += delegate { LayoutNav(); };
            _navHost = nav;

            // Восемь разделов вместо четырнадцати: родственные страницы
            // собраны под одним пунктом и переключаются вкладками.
            AddNav(nav, "home",     L.T("Обзор"), GHome);
            AddNav(nav, "settings", L.T("Настройки"), GNav1);
            AddNav(nav, "apps",     L.T("Приложения"), GApp);
            AddNav(nav, "xray",     L.T("Наблюдение"), GEye);
            AddNav(nav, "gdid",     L.T("Номер устройства"), GBadge);
            AddNav(nav, "audit",    L.T("Проверка"), GNav2);
            AddNav(nav, "guard",    L.T("Автозащита"), GShield);
            AddNav(nav, "about",    L.T("О программе"), GNav6);
            side.Controls.Add(nav);

            // Знака с названием в панели нет: логотип и имя программы уже стоят
            // в заголовке окна, а второй экземпляр рядом с разделами только мешал.

            // гамбургер — свернуть/развернуть панель (докуется в самый верх)
            _hamburger = new NavItem("", GMenu);
            _hamburger.Font = Font;
            _hamburger.Dock = DockStyle.Top;
            _hamburger.Height = (int)(u * 2.3F);
            _hamburger.Click += delegate { _userCollapsed = !EffectiveCollapsed(); AnimateSidebar(); };
            _navTip.SetToolTip(_hamburger, L.T("Свернуть или развернуть панель"));
            side.Controls.Add(_hamburger);

            // Сведения о системе переехали в подзаголовок «Обзора». Подпись
            // остаётся объектом (её заполняет определение системы), но в панель
            // не добавляется.
            Label sysInfo = new Label();
            sysInfo.Name = "sysInfo";
            sysInfo.Visible = false;
            sysInfo.Text = L.T("Определение системы…");
            _sysInfoLabel = sysInfo;

            return side;
        }
        private Label _sysInfoLabel;

        // ================================================================== //
        //  Сворачивание боковой панели: вручную (гамбургер) и авто при узком окне
        // ================================================================== //
        private bool EffectiveCollapsed() { return _userCollapsed || _autoCollapsed; }

        private void ApplySidebar()
        {
            if (_side == null) return;
            int u = Font.Height;
            bool c = EffectiveCollapsed();
            int navW = c ? (int)(u * 3.4F) : (int)(u * 14.3F);
            _side.SuspendLayout();
            _side.Width = c ? (int)(u * 4.6F) : (int)(u * 15.5F);
            if (_sysInfoLabel != null) _sysInfoLabel.Visible = !c;
            foreach (NavItem n in _nav)
            {
                n.Width = navW; n.Invalidate();
                if (_navTip != null) _navTip.SetToolTip(n, c ? n.Text : "");
            }
            foreach (NavGroup g in _navGroups) { g.Width = navW; g.Invalidate(); }
            if (_hamburger != null) _hamburger.Invalidate();
            LayoutNav();
            _side.ResumeLayout(true);
            _side.Invalidate(true);
        }

        // ================================================================== //
        //  Пунктов навигации одиннадцать — на невысоком экране они перестают
        //  помещаться и залезают под подпись о системе. Шаг сетки сжимается
        //  под свободную высоту, а подпись прячется первой.
        // ================================================================== //
        private void LayoutNav()
        {
            if (_navHost == null || _side == null || _nav.Count == 0) return;
            int u = Font.Height;
            // Пункты идут сверху с ровным шагом; на невысоком экране шаг
            // сжимается, чтобы список помещался без прокрутки. «О программе»
            // прижат к низу панели.
            int avail = _navHost.ClientSize.Height - _navHost.Padding.Top - (int)(u * 0.4F);
            int pitch = Math.Min((int)(u * 2.5F), Math.Max((int)(u * 1.8F), avail / Math.Max(1, _nav.Count)));
            int ih = Math.Max((int)(u * 1.5F), pitch - (int)(u * 0.25F));
            int y = _navHost.Padding.Top;
            foreach (NavItem n in _nav)
            {
                n.Height = ih;
                if ((string)n.Tag == "about") n.Top = Math.Max(y, _navHost.ClientSize.Height - ih - (int)(u * 0.3F));
                else { n.Top = y; y += pitch; }
            }
            if (_sysInfoLabel != null) _sysInfoLabel.Visible = false;
            foreach (NavItem n in _nav) if (n.Selected) _navHost.MoveTo(n, false);
            _navHost.Invalidate();
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            // Свёрнутое в панель задач окно имеет нулевую ширину: раньше это
            // считалось «узким окном», панель разделов сворачивалась, а при
            // возврате окна разворачивалась обратно — с перекладкой всех страниц.
            if (WindowState == FormWindowState.Minimized) return;
            bool auto = ClientSize.Width < Font.Height * 58;
            if (auto != _autoCollapsed) { _autoCollapsed = auto; AnimateSidebar(); }
            LayoutNav();
        }

        // ================================================================== //
        //  Плавное сворачивание/разворачивание панели.
        //  Раньше на каждом кадре менялась ширина правой части, и открытая
        //  страница перекладывалась целиком (карточки, переносы строк, списки)
        //  — кадры выходили неровными, всё дёргалось. Теперь раскладка правой
        //  части на время движения заморожена: страница просто едет вместе с
        //  краем панели и раскладывается один раз, в конце. Движение идёт по
        //  времени (200 мс, плавное торможение), а не долями шага таймера.
        // ================================================================== //
        private const int SideAnimMs = 200;
        private Timer _sideAnim;
        private int _sideFrom, _sideTo, _sideT0;
        private bool _contentFrozen;

        private int SideTargetWidth()
        {
            int u = Font.Height;
            return EffectiveCollapsed() ? (int)(u * 4.6F) : (int)(u * 15.5F);
        }

        private void AnimateSidebar()
        {
            if (_side == null) return;
            int target = SideTargetWidth();
            if (!IsHandleCreated || !Visible || WindowState == FormWindowState.Minimized || _side.Width == target)
            {
                if (_sideAnim != null) _sideAnim.Stop();
                ApplySidebar(); UnfreezeContent();
                return;
            }
            _sideFrom = _side.Width; _sideTo = target; _sideT0 = Environment.TickCount;
            bool freeze = true;
#if UITEST
            freeze = !TestNoFreeze;      // для сравнения со старым поведением
#endif
            if (freeze && !_contentFrozen && _content != null) { _content.SuspendLayout(); _contentFrozen = true; }
            if (_sideAnim == null)
            {
                _sideAnim = new Timer();
                _sideAnim.Interval = 10;
                _sideAnim.Tick += delegate { SideAnimStep(); };
            }
            _sideAnim.Start();
            SideAnimStep();
        }

        private void SideAnimStep()
        {
            float t = (Environment.TickCount - _sideT0) / (float)SideAnimMs;
            if (t >= 1F || _side == null)
            {
                _sideAnim.Stop();
                ApplySidebar();          // сначала конечная ширина,
                UnfreezeContent();       // потом одна раскладка страницы
                return;
            }
            float k = 1F - (1F - t) * (1F - t) * (1F - t);   // плавное торможение к концу
            int w = _sideFrom + (int)Math.Round((_sideTo - _sideFrom) * k);
            if (w == _side.Width) return;
            int u = Font.Height;
            int navW = Math.Max((int)(u * 3.4F), w - (int)(u * 1.2F));
            foreach (NavItem n in _nav) n.Width = navW;
            foreach (NavGroup g in _navGroups) g.Width = navW;
            _side.Width = w;
            // кадр рисуем сразу, а не когда до него дойдёт очередь сообщений
            RedrawWindow(Handle, IntPtr.Zero, IntPtr.Zero, 0x0100 | 0x0080);   // RDW_UPDATENOW | RDW_ALLCHILDREN
#if UITEST
            if (SideFrameHook != null) SideFrameHook(w);
#endif
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool RedrawWindow(IntPtr hWnd, IntPtr rect, IntPtr rgn, int flags);

        private void UnfreezeContent()
        {
            if (!_contentFrozen || _content == null) return;
            _contentFrozen = false;
            _content.ResumeLayout(true);
        }

        // Переход на другую страницу посреди движения: новая страница не должна
        // показаться в замороженной раскладке — доводим панель до конца сразу.
        private void FinishSidebarAnim()
        {
            if (_sideAnim == null || !_sideAnim.Enabled) return;
            _sideAnim.Stop();
            ApplySidebar();
            UnfreezeContent();
        }

#if UITEST
        internal Action<int> SideFrameHook;
        internal static bool TestNoFreeze = Environment.GetEnvironmentVariable("WIN11_TEST_SIDE_NOFREEZE") == "1";

        // WIN11_TEST_SIDE=папка: свернуть и развернуть панель разделов, печатая
        // время каждого кадра (SIDEFRAME) и, если папка не «-», сохраняя кадры.
        internal void StartSideTest(string dir)
        {
            bool save = dir != "-";
            if (save) Directory.CreateDirectory(dir);
            int n = 0, last = 0, worst = 0, frames = 0;
            SideFrameHook = delegate(int w)
            {
                int now = Environment.TickCount, dt = last == 0 ? 0 : now - last;
                last = now; frames++;
                if (dt > worst) worst = dt;
                Console.WriteLine("SIDEFRAME " + (++n) + " w=" + w + " dt=" + dt);
                if (save)
                    using (Bitmap bmp = new Bitmap(Width, Height))
                    {
                        DrawToBitmap(bmp, new Rectangle(0, 0, Width, Height));
                        bmp.Save(Path.Combine(dir, "frame-" + n.ToString("00") + ".png"));
                    }
            };
            Timer step = new Timer(); step.Interval = 1500;
            int phase = 0;
            step.Tick += delegate
            {
                phase++;
                if (phase == 1 || phase == 2)
                {
                    last = 0;
                    Console.WriteLine("SIDETOGGLE " + (phase == 1 ? "collapse" : "expand"));
                    _userCollapsed = phase == 1; AnimateSidebar();
                    return;
                }
                step.Stop();
                Console.WriteLine("SIDESTATS frames=" + frames + " worst_dt=" + worst + " side=" + _side.Width +
                    " content=" + _content.Width + " page=" + PageOf(_current).Width);
                // после свернуть/развернуть ни у одного списка не должно остаться
                // горизонтальной прокрутки и строк шире самого списка
                ReportHScroll(PageOf(_current));
                if (save)
                    using (Bitmap bmp = new Bitmap(Width, Height))
                    {
                        DrawToBitmap(bmp, new Rectangle(0, 0, Width, Height));
                        bmp.Save(Path.Combine(dir, "final.png"));
                    }
            };
            step.Start();
        }

        private static void ReportHScroll(Control root)
        {
            foreach (Control c in root.Controls)
            {
                ScrollableControl sc = c as ScrollableControl;
                if (sc != null && c.Visible && sc.AutoScroll && sc.HorizontalScroll.Visible)
                {
                    int widest = 0;
                    foreach (Control ch in c.Controls) if (ch.Visible) widest = Math.Max(widest, ch.Right);
                    Console.WriteLine("SIDEHSCROLL " + c.GetType().Name + " client=" + sc.ClientSize.Width +
                        " widest=" + widest + " hpos=" + sc.HorizontalScroll.Value + " display=" + sc.DisplayRectangle);
                }
                ReportHScroll(c);
            }
        }
#endif

        private void AddNav(NavHost host, string key, string text, string glyph)
        {
            int u = Font.Height;
            NavItem n = new NavItem(text, glyph);
            n.Font = Font;
            n.Tag = key;
            n.Width = (int)(u * 14.3F);
            n.FullWidth = n.Width;
            n.Left = 0;
            n.Click += delegate { NavigateGroup(key); };
            host.Controls.Add(n);
            _nav.Add(n);
            _navRows.Add(n);
            LayoutNav();
        }

        private void AddNavGroup(NavHost host, string text)
        {
            int u = Font.Height;
            NavGroup g = new NavGroup(text);
            g.Font = Font;
            g.Width = (int)(u * 14.3F);
            g.Left = 0;
            host.Controls.Add(g);
            _navGroups.Add(g);
            _navRows.Add(g);
        }

        private Control PageOf(string key)
        {
            Control page;
            return _pages.TryGetValue(key, out page) ? page : _pages["about"];
        }

        // Плавный въезд страницы слева-направо
        private void AnimatePageIn(Control page)
        {
            if (_content == null || page == null) return;
            Rectangle t = new Rectangle(_content.Padding.Left, _content.Padding.Top,
                _content.ClientSize.Width - _content.Padding.Horizontal,
                _content.ClientSize.Height - _content.Padding.Vertical);
            // под шапкой раздела страница начинается ниже
            if (_groupHead != null && _groupHead.Visible) { t.Y += _groupHead.Height; t.Height -= _groupHead.Height; }
            if (t.Width < 60 || t.Height < 60) return;
            FinishPageAnim();
            if (_pageTimer == null)
            {
                _pageTimer = new Timer();
                _pageTimer.Interval = 13;
                _pageTimer.Tick += delegate
                {
                    if (_animPage == null) { _pageTimer.Stop(); return; }
                    int dx = _animPage.Left - _animTargetX;
                    dx = (int)(dx * 0.55F);
                    if (dx <= 1) FinishPageAnim();
                    else _animPage.Left = _animTargetX + dx;
                };
            }
            page.Dock = DockStyle.None;
            page.Bounds = new Rectangle(t.X + (int)(Font.Height * 1.6F), t.Y, t.Width, t.Height);
            _animPage = page; _animTargetX = t.X;
            _pageTimer.Start();
        }

        private void FinishPageAnim()
        {
            if (_pageTimer != null) _pageTimer.Stop();
            if (_animPage != null) { Control p = _animPage; _animPage = null; p.Dock = DockStyle.Fill; }
        }

        private void Navigate(string key)
        {
            FinishSidebarAnim();
            bool first = (_current == "");
            bool changed = (_current != key);
            _current = key;
            string grp = GroupOf(key);
            _groupLast[grp] = key;
            foreach (NavItem n in _nav)
            {
                n.Selected = ((string)n.Tag == grp); n.Invalidate();
                if (n.Selected && _navHost != null) _navHost.MoveTo(n, !first);
            }
            UpdateGroupHead(grp, key);
            FinishPageAnim();
            foreach (KeyValuePair<string, Control> p in _pages) p.Value.Visible = (p.Key == key);
            if (changed && !first) AnimatePageIn(PageOf(key));
            if (key == "home") { if (_homeScroll != null) _homeScroll.AutoScrollPosition = Point.Empty; RefreshHome(); }
            if (key == "settings" && _settingsList != null) _settingsList.Restack();
            if (key == "xray" && _xrayList != null) { _xrayList.Restack(); if (_lastXray == null) RunXrayStatus(); }
            if (key == "dossier" && _dossierList != null) { _dossierList.Restack(); if (_lastFoot == null) RefreshDossier(); }
            if (key == "gdid" && _gdidList != null) { _gdidList.Restack(); if (_lastGdid == null && !_mockMode) RefreshGdid(); }
            if (key == "audit" && _auditGroups != null && _auditGroups.Controls.Count == 0) RunAudit();   // идёт уже — не повторит
            if (key == "monitor" && _monitorList != null && _monitorList.Controls.Count == 0) RefreshMonitor();
            if (key == "apps" && _appsList != null && _appsList.Controls.Count == 0) RefreshApps();
            if (key == "startup" && _startupList != null && _startupList.Controls.Count == 0) RefreshStartup();
            if (key == "changes" && _changesList != null && _changesList.Controls.Count == 0) RefreshChanges();
            if (key == "timeline" && _timelineNotes != null && _timelineNotes.Controls.Count == 0 && !_mockMode) RefreshTimeline();
            if (key == "about" && _aboutData != null && !_mockMode) RefreshDataInfo();
        }
    }
}
