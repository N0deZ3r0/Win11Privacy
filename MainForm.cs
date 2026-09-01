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
    internal sealed class ModuleDef
    {
        public string Id, Title, Description, Glyph, Section;
        public bool DefaultOn, Hard, App;
        public OptionRow Row;
        public readonly List<SubOptionRow> Subs = new List<SubOptionRow>();
        public bool Expanded;
        public bool Installed = true;    // для программных модулей — найдено ли ПО
        public string InstallNote = "";
        public ModuleDef(string section, string id, string title, string desc, string glyph, bool on, bool hard, bool app)
        { Section = section; Id = id; Title = title; Description = desc; Glyph = glyph; DefaultOn = on; Hard = hard; App = app; }
    }

    public class MainForm : Form
    {
        internal readonly List<ModuleDef> _mods = new List<ModuleDef>();
        private readonly List<NavItem> _nav = new List<NavItem>();

        private Panel _content;
        private RichTextBox _log;
        private Label _status;
        private ProgressBar _progress;
        private Process _proc;
        private Icon _appIcon;
        private Image _appImage;

        // страницы
        private Control _pageHome, _pageSettings, _pageXray, _pageAudit, _pageMonitor, _pageGuard, _pageLog, _pageAbout, _pageDossier;
        private TileGrid _dossierTiles;
        private StackPanel _dossierList;
        private Label _dossierState;
        private ModernButton _btnDossierRefresh, _btnDossierWipe, _btnDossierAll;
        private bool _spyShowAll;
        private Dictionary<string, object> _lastSpy, _lastFoot, _lastProof;
        private TextBox _search;
        private NavHost _navHost;
        private TitleBar _titleBar;
        private IndexRing _homeRing; private DonutChart _homeDonut; private SensorChart _homeSensors;
        private Label _homeHint;
        private TableLayoutPanel _homeMid, _homePage;
        private Card _homeDonutCard, _homeChartCard;
        private Label _verdictTitle, _verdictSub;
        private MiniStat _msEvents, _msYear, _msBlocked;
        private ActionCard _qcXray, _qcDossier, _qcMonitor, _qcGuard;
        private ChipLabel _homeSysChip;
        private Panel _homeScroll;
        private Control _pageApps;
        private StackPanel _appsList;
        private Label _appsState;
        private ModernButton _btnAppsRefresh, _btnAppsRemove;
        private Control _pageStartup;
        private StackPanel _startupList;
        private Label _startupState;
        private ModernButton _btnStartupOff, _btnStartupOn;
        private bool _defsLoaded;
        private FlowLayoutPanel _homeActions;
        private float _chartsMinU = 15.5F;
        private string _current = "";
        private StackPanel _xrayList;
        private TileGrid _xrayTiles;

        // боковая панель: сворачивание
        private SidePanel _side;
        private Label _brandLabel;
        private NavItem _hamburger;
        private ToolTip _navTip;
        private bool _userCollapsed, _autoCollapsed;

        // анимация перехода страниц
        private Timer _pageTimer;
        private Control _animPage;
        private int _animTargetX;
        private Label _xrayState;
        private ModernButton _btnXrayRec, _btnXrayScan, _btnXrayBase, _btnXrayWipe, _btnReport;
        private bool _xrayRecording;
        private Dictionary<string, object> _lastXray, _lastAudit, _lastMonitor;
        private Dictionary<string, object> _lastStartup, _lastApps;   // для отчёта

        // состояние из -Detect
        private Dictionary<string, object> _detect;
        private string _editionKind = "";
        private bool _guardInstalled, _monitorEnabled;

        // элементы страниц, обновляемые по данным
        private StackPanel _settingsList;
        private OptionRow _optBackup, _optRestore, _optDry;
        private IndexRing _ring;
        private Label _auditWhen, _auditHint;
        private StackPanel _auditGroups;
        private TileGrid _auditTiles;
        private TileGrid _monitorTiles;
        private StackPanel _monitorList;
        private Label _monitorState;
        private ModernButton _monitorToggle;
        private StackPanel _guardBody;
        private Label _guardState;
        private List<object> _snapshots = new List<object>();
        private Dictionary<string, object> _lastDiff;

#if BIGFONT
        private const float BaseFontSize = 13.5F;
#else
        private const float BaseFontSize = 9.5F;
#endif

        // Глифы Segoe Fluent Icons
        private const string GDiag="", GError="", GAds="", GHistory="", GKeyboard="",
            GSearch="", GRobot="", GGlobe="", GSync="", GShield="", GDoc="", GDelete="",
            GPower="", GSave="", GUndo="", GEye="", GChip="", GApp="", GFactory="",
            GNav1="", GNav2="", GNav3="", GNav4="", GNav5="", GNav6="", GFire="", GBroom="",
            GXray="", GClock="", GBell="", GHome="",
            GCam="", GMic="", GPin="", GWifi="", GFinger="",
            GUsb="", GClipb="", GHist="", GContact="",
            GMenu="";

        public MainForm()
        {
            LoadLangPref();
            L.DetectFromSystem();
            Theme.Detect();
#if LIGHTTEST
            Theme.Apply(false);
#endif
            BuildModules();
            BuildUi();
        }

        private void BuildModules()
        {
            string S1=L.T("Сбор данных Windows"), S2=L.T("Реклама и подсказки"), S3=L.T("ИИ Windows"),
                         S4=L.T("Жёсткие меры"), S5=L.T("Программы"), S6=L.T("Обслуживание");
            Action<string,string,string,string,string,bool,bool,bool> A =
                (sec,id,t,d,g,on,hard,app) => _mods.Add(new ModuleDef(sec,id,t,d,g,on,hard,app));

            A(S1,"telemetry",L.T("Телеметрия и диагностика"),L.T("Диагностические данные, логи и дампы памяти в Microsoft."),GDiag,true,false,false);
            A(S1,"errors",L.T("Отчёты об ошибках"),L.T("Отчёты о сбоях программ и системы."),GError,true,false,false);
            A(S1,"activity",L.T("История активности и буфер обмена"),L.T("Лента активности и синхронизация буфера через облако."),GHistory,true,false,false);
            A(S1,"input",L.T("Персонализация ввода и речь"),L.T("Сбор набранного текста, рукописного ввода, облачная речь."),GKeyboard,true,false,false);
            A(S1,"edge","Microsoft Edge",L.T("Статистика и персонализация Edge; блокировка трекеров."),GGlobe,true,false,false);
            A(S1,"delivery",L.T("Раздача обновлений в интернет"),L.T("Отдача файлов обновлений чужим ПК."),GSync,true,false,false);
            A(S1,"onedrive",L.T("OneDrive: синхронизация и реклама"),L.T("Отключает выгрузку файлов в облако и рекламу OneDrive в Проводнике. Файлы на диске остаются."),GSync,false,false,false);
            A(S1,"location",L.T("Геолокация и «Поиск устройства»"),L.T("Служба местоположения целиком и отправка координат в Microsoft."),GPin,false,false,false);

            A(S2,"ads",L.T("Рекламный ID и реклама"),L.T("Реклама в Пуске, на экране блокировки и в Параметрах."),GAds,true,false,false);
            A(S2,"widgets",L.T("Виджеты и лента новостей"),L.T("Лента MSN на панели задач, которая изучает ваши интересы."),GGlobe,false,false,false);
            A(S2,"search",L.T("Поиск: Bing и Cortana"),L.T("Поиск в Пуске без обращения в интернет и к Cortana."),GSearch,true,false,false);

            A(S3,"copilot",L.T("Copilot и Recall"),L.T("ИИ-помощник и запись снимков экрана Recall."),GRobot,true,false,false);
            A(S3,"ai",L.T("Все ИИ-функции"),L.T("Click to Do, Copilot в Блокноте/Paint/Edge, ИИ в Проводнике и поиске."),GChip,true,false,false);

            A(S4,"services",L.T("Службы и задачи телеметрии"),L.T("Останавливает DiagTrack и задачи планировщика."),GShield,false,true,false);
            A(S4,"hosts",L.T("Блокировка доменов (hosts)"),L.T("25 адресов Microsoft в файл hosts."),GDoc,false,true,false);
            A(S4,"firewall",L.T("Блокировка через брандмауэр"),L.T("Исходящие соединения служб телеметрии. Надёжнее hosts."),GFire,false,true,false);
            A(S4,"buffer",L.T("Стереть неотправленную телеметрию"),L.T("Удаляет накопленный буфер C:\\ProgramData\\Microsoft\\Diagnosis."),GBroom,false,true,false);
            A(S4,"defender",L.T("Защитник: облако и образцы"),L.T("Отправка подозрительных файлов и облачная проверка MAPS. Чуть снижает защиту."),GShield,false,true,false);
            A(S4,"fwips",L.T("Блокировка адресов телеметрии"),L.T("Брандмауэр режет сами IP сбора данных — hosts телеметрия обходит. Если что-то отвалится, снимите и откатите."),GFire,false,true,false);
            A(S4,"doh",L.T("Запретить шифрованный DNS"),L.T("Через DoH браузеры и Windows обходят блокировку по доменам. Отключение вернёт видимость запросов провайдеру."),GGlobe,false,true,false);

            A(S5,"app_nvidia","NVIDIA",L.T("Телеметрия драйвера и GeForce Experience."),GApp,true,false,true);
            A(S5,"app_vscode","Visual Studio Code",L.T("Телеметрия и эксперименты редактора."),GApp,true,false,true);
            A(S5,"app_chrome","Google Chrome",L.T("Статистика, Privacy Sandbox, отправка адресов."),GApp,true,false,true);
            A(S5,"app_firefox","Mozilla Firefox",L.T("Телеметрия и исследования Firefox."),GApp,true,false,true);
            A(S5,"app_office","Microsoft Office",L.T("Телеметрия клиента и отправка данных."),GApp,true,false,true);
            A(S5,"app_devtools","PowerShell 7 / .NET SDK",L.T("Телеметрия средств разработки."),GApp,true,false,true);
            A(S5,"app_vs","Visual Studio",L.T("Программа улучшения качества и телеметрия."),GApp,true,false,true);
            A(S5,"oem",L.T("Слежка производителя ноутбука"),L.T("Компоненты сбора данных Honor/HP/Lenovo/Dell/ASUS. Драйверы не трогаются."),GFactory,true,false,true);

            A(S6,"cleanup",L.T("Чистка временных файлов"),L.T("Temp, кэш обновлений, эскизы, дампы, корзина."),GDelete,true,false,false);
        }

        // ================================================================== //
        private void BuildUi()
        {
            Font = Theme.PickFont(Theme.UiFonts, BaseFontSize, FontStyle.Regular);
            AutoScaleMode = AutoScaleMode.Font;
            Text = L.T("Приватность Windows 11");
            BackColor = Theme.WindowBg;
            ForeColor = Theme.Text;
            DoubleBuffered = true;
            FormBorderStyle = FormBorderStyle.None;
            TryLoadIcon();

            int u = Font.Height;
            Rectangle wa = Screen.PrimaryScreen.WorkingArea;
            ClientSize = new Size(Math.Min((int)(u * 78), (int)(wa.Width * 0.94)),
                                  Math.Min((int)(u * 48), (int)(wa.Height * 0.94)));
            StartPosition = FormStartPosition.CenterScreen;
            LoadUiState();

            TableLayoutPanel root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.ColumnCount = 2;
            root.RowCount = 3;
            root.BackColor = Theme.WindowBg;
            root.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            Controls.Add(root);

            _titleBar = new TitleBar(this);
            _titleBar.Dock = DockStyle.Fill;
            _titleBar.Height = (int)(u * 2.15F);
            _titleBar.Font = Font;
            _titleBar.Logo = _appImage;
            _titleBar.Caption = L.T("Приватность Windows 11");
            _titleBar.Margin = new Padding(0);
            root.Controls.Add(_titleBar, 0, 0);
            root.SetColumnSpan(_titleBar, 2);

            root.Controls.Add(BuildSidebar(), 0, 1);

            _content = new ContentPanel();
            _content.Dock = DockStyle.Fill;
            _content.BackColor = Theme.WindowBg;
            _content.Padding = new Padding((int)(u * 1.2F), (int)(u * 1.0F), (int)(u * 1.2F), (int)(u * 0.6F));
            _content.Resize += delegate { FinishPageAnim(); };
            root.Controls.Add(_content, 1, 1);

            Control footer = BuildStatusBar();
            root.Controls.Add(footer, 0, 2);
            root.SetColumnSpan(footer, 2);

            // страницы
            _pageHome     = BuildHomePage();
            _pageSettings = BuildSettingsPage();
            _pageXray     = BuildXrayPage();
            _pageDossier  = BuildDossierPage();
            _pageAudit    = BuildAuditPage();
            _pageMonitor  = BuildMonitorPage();
            _pageApps     = BuildAppsPage();
            _pageStartup  = BuildStartupPage();
            _pageGuard    = BuildGuardPage();
            _pageLog      = BuildLogPage();
            _pageAbout    = BuildAboutPage();
            foreach (Control p in new[] { _pageHome, _pageSettings, _pageXray, _pageDossier, _pageAudit, _pageMonitor, _pageApps, _pageStartup, _pageGuard, _pageLog, _pageAbout })
            {
                p.Dock = DockStyle.Fill; p.Visible = false; _content.Controls.Add(p);
            }
            Navigate("home");
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

            // навигация (добавляется первой: докуется в самом низу верхней группы)
            NavHost nav = new NavHost();
            nav.Dock = DockStyle.Top;
            nav.AutoSize = false;
            nav.BackColor = Color.Transparent;
            nav.Padding = new Padding(0, (int)(u * 0.6F), 0, 0);
            _navHost = nav;

            AddNav(nav, "home", L.T("Обзор"), GHome);
            AddNav(nav, "settings", L.T("Настройки"), GNav1);
            AddNav(nav, "xray",     L.T("Рентген"),   GXray);
            AddNav(nav, "dossier",  L.T("Досье"),     GFinger);
            AddNav(nav, "audit",    L.T("Проверка"),  GNav2);
            AddNav(nav, "monitor",  L.T("Монитор"),   GNav3);
            AddNav(nav, "apps",     L.T("Приложения"), GApp);
            AddNav(nav, "startup",  L.T("Автозапуск"), GPower);
            AddNav(nav, "guard",    L.T("Страж"),     GShield);
            AddNav(nav, "log",      L.T("Журнал"),    GNav5);
            AddNav(nav, "about",    L.T("О программе"),GNav6);
            nav.Height = (int)(u * 2.7F * _nav.Count + u * 1.0F);
            side.Controls.Add(nav);

            // шапка бренда
            TableLayoutPanel brand = new TableLayoutPanel();
            brand.Dock = DockStyle.Top;
            brand.Height = (int)(u * 3.2F);
            brand.ColumnCount = 2; brand.RowCount = 1;
            brand.BackColor = Color.Transparent;
            brand.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            brand.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            brand.Margin = new Padding(0);

            PictureBox logo = new PictureBox();
            int lb = (int)(u * 2.3F);
            logo.Size = new Size(lb, lb);
            logo.SizeMode = PictureBoxSizeMode.Zoom;
            logo.Image = _appImage;
            logo.BackColor = Color.Transparent;
            logo.Margin = new Padding((int)(u * 0.4F), (int)(u * 0.4F), (int)(u * 0.5F), 0);
            brand.Controls.Add(logo, 0, 0);

            _brandLabel = new Label();
            _brandLabel.Text = L.T("Приватность\nWindows 11");
            _brandLabel.Font = new Font(Font, FontStyle.Bold);
            _brandLabel.ForeColor = Theme.Text;
            _brandLabel.AutoSize = false;
            _brandLabel.Dock = DockStyle.Fill;
            _brandLabel.BackColor = Color.Transparent;
            _brandLabel.TextAlign = ContentAlignment.MiddleLeft;
            brand.Controls.Add(_brandLabel, 1, 0);
            side.Controls.Add(brand);

            // гамбургер — свернуть/развернуть панель (докуется в самый верх)
            _hamburger = new NavItem("", GMenu);
            _hamburger.Font = Font;
            _hamburger.Dock = DockStyle.Top;
            _hamburger.Height = (int)(u * 2.3F);
            _hamburger.Click += delegate { _userCollapsed = !EffectiveCollapsed(); AnimateSidebar(); };
            _navTip.SetToolTip(_hamburger, L.T("Свернуть или развернуть панель"));
            side.Controls.Add(_hamburger);

            // индикатор системы внизу
            Label sysInfo = new Label();
            sysInfo.Name = "sysInfo";
            sysInfo.Dock = DockStyle.Bottom;
            sysInfo.AutoSize = false;
            sysInfo.Height = (int)(u * 3.2F);
            sysInfo.ForeColor = Theme.TextFaint;
            sysInfo.Font = new Font(Font.FontFamily, Font.Size * 0.85F);
            sysInfo.Text = L.T("Определение системы…");
            sysInfo.TextAlign = ContentAlignment.BottomLeft;
            sysInfo.BackColor = Color.Transparent;
            side.Controls.Add(sysInfo);
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
            if (_brandLabel != null) _brandLabel.Visible = !c;
            if (_sysInfoLabel != null) _sysInfoLabel.Visible = !c;
            foreach (NavItem n in _nav)
            {
                n.Width = navW; n.Invalidate();
                if (_navTip != null) _navTip.SetToolTip(n, c ? n.Text : "");
            }
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
            int head = (int)(u * 3.2F) + (int)(u * 2.3F);          // шапка бренда + гамбургер
            int free = _side.ClientSize.Height - _side.Padding.Vertical - head - _navHost.Padding.Top;
            int full = (int)(u * 2.7F) * _nav.Count;
            int sysH = (int)(u * 3.2F);
            bool showSys = !EffectiveCollapsed() && (free - sysH) >= full;
            if (_sysInfoLabel != null) _sysInfoLabel.Visible = showSys;
            if (showSys) free -= sysH;
            int pitch = Math.Min((int)(u * 2.7F), Math.Max((int)(u * 2.05F), free / _nav.Count));
            int ih = Math.Max((int)(u * 1.7F), pitch - (int)(u * 0.2F));
            for (int i = 0; i < _nav.Count; i++)
            {
                _nav[i].Height = ih;
                _nav[i].Top = _navHost.Padding.Top + i * pitch;
            }
            _navHost.Height = _navHost.Padding.Top + pitch * _nav.Count + (int)(u * 0.4F);
            foreach (NavItem n in _nav) if (n.Selected) _navHost.MoveTo(n, false);
            _navHost.Invalidate();
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            bool auto = ClientSize.Width < Font.Height * 58;
            if (auto != _autoCollapsed) { _autoCollapsed = auto; AnimateSidebar(); }
            LayoutNav();
        }

        // Плавное сворачивание/разворачивание панели
        private Timer _sideAnim;
        private void AnimateSidebar()
        {
            if (_side == null) return;
            int u = Font.Height;
            int target = EffectiveCollapsed() ? (int)(u * 4.6F) : (int)(u * 15.5F);
            if (!IsHandleCreated || !Visible || _side.Width == target) { ApplySidebar(); return; }
            // текст прячем сразу, чтобы он не сминался во время движения
            if (_brandLabel != null) _brandLabel.Visible = false;
            if (_sysInfoLabel != null) _sysInfoLabel.Visible = false;
            if (_sideAnim == null)
            {
                _sideAnim = new Timer();
                _sideAnim.Interval = 13;
                _sideAnim.Tick += delegate
                {
                    int uu = Font.Height;
                    int t = EffectiveCollapsed() ? (int)(uu * 4.6F) : (int)(uu * 15.5F);
                    int d = t - _side.Width;
                    if (Math.Abs(d) <= 3) { _sideAnim.Stop(); ApplySidebar(); return; }
                    int step = (int)(d * 0.42F);
                    if (step == 0) step = d > 0 ? 1 : -1;
                    _side.Width += step;
                    int navW = Math.Max((int)(uu * 3.4F), _side.Width - (int)(uu * 1.2F));
                    foreach (NavItem n in _nav) n.Width = navW;
                    if (_navHost != null) _navHost.Invalidate();
                };
            }
            _sideAnim.Start();
        }

        private void AddNav(NavHost host, string key, string text, string glyph)
        {
            int u = Font.Height;
            NavItem n = new NavItem(text, glyph);
            n.Font = Font;
            n.Tag = key;
            n.Width = (int)(u * 14.3F);
            n.Left = 0;
            n.Top = host.Padding.Top + _nav.Count * (int)(u * 2.7F);
            n.Click += delegate { Navigate(key); };
            host.Controls.Add(n);
            _nav.Add(n);
        }

        private Control PageOf(string key)
        {
            if (key == "home") return _pageHome;
            if (key == "settings") return _pageSettings;
            if (key == "xray") return _pageXray;
            if (key == "dossier") return _pageDossier;
            if (key == "audit") return _pageAudit;
            if (key == "monitor") return _pageMonitor;
            if (key == "apps") return _pageApps;
            if (key == "startup") return _pageStartup;
            if (key == "guard") return _pageGuard;
            if (key == "log") return _pageLog;
            return _pageAbout;
        }

        // Плавный въезд страницы слева-направо
        private void AnimatePageIn(Control page)
        {
            if (_content == null || page == null) return;
            Rectangle t = new Rectangle(_content.Padding.Left, _content.Padding.Top,
                _content.ClientSize.Width - _content.Padding.Horizontal,
                _content.ClientSize.Height - _content.Padding.Vertical);
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
            bool first = (_current == "");
            bool changed = (_current != key);
            _current = key;
            foreach (NavItem n in _nav)
            {
                n.Selected = ((string)n.Tag == key); n.Invalidate();
                if (n.Selected && _navHost != null) _navHost.MoveTo(n, !first);
            }
            FinishPageAnim();
            _pageHome.Visible     = (key == "home");
            _pageSettings.Visible = (key == "settings");
            _pageXray.Visible     = (key == "xray");
            _pageDossier.Visible  = (key == "dossier");
            _pageAudit.Visible    = (key == "audit");
            _pageMonitor.Visible  = (key == "monitor");
            _pageApps.Visible     = (key == "apps");
            _pageStartup.Visible  = (key == "startup");
            _pageGuard.Visible    = (key == "guard");
            _pageLog.Visible      = (key == "log");
            _pageAbout.Visible    = (key == "about");
            if (changed && !first) AnimatePageIn(PageOf(key));
            if (key == "home") { if (_homeScroll != null) _homeScroll.AutoScrollPosition = Point.Empty; RefreshHome(); FitHomeHeight(); }
            if (key == "settings" && _settingsList != null) _settingsList.Restack();
            if (key == "xray" && _xrayList != null) { _xrayList.Restack(); if (_lastXray == null) RunXrayStatus(); }
            if (key == "dossier" && _dossierList != null) { _dossierList.Restack(); if (_lastFoot == null) RefreshDossier(); }
            if (key == "audit" && _auditGroups != null && _auditGroups.Controls.Count == 0) RunAudit();
            if (key == "monitor" && _monitorList != null && _monitorList.Controls.Count == 0) RefreshMonitor();
            if (key == "apps" && _appsList != null && _appsList.Controls.Count == 0) RefreshApps();
            if (key == "startup" && _startupList != null && _startupList.Controls.Count == 0) RefreshStartup();
        }

        // ================================================================== //
        //  Страница: Настройки
        // ================================================================== //
        private Control BuildSettingsPage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 3;
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));

            // заголовок + поиск + быстрые кнопки
            TableLayoutPanel head = new TableLayoutPanel();
            head.ColumnCount = 3; head.RowCount = 1;
            head.Dock = DockStyle.Fill; head.AutoSize = true;
            head.BackColor = Theme.WindowBg;
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

            Label h = PageTitle(L.T("Что отключить"));
            head.Controls.Add(h, 0, 0);

            _search = new TextBox();
            _search.Font = Font;
            _search.BackColor = Theme.CardBg;
            _search.ForeColor = Theme.Text;
            _search.BorderStyle = BorderStyle.FixedSingle;
            _search.Width = (int)(u * 13F);
            _search.Anchor = AnchorStyles.Left | AnchorStyles.Bottom;
            _search.Margin = new Padding((int)(u * 0.8F), 0, (int)(u * 0.5F), (int)(u * 0.45F));
            _search.TextChanged += delegate { ApplySettingsFilter(); };
            Dwm.Placeholder(_search, L.T("Поиск по настройкам…"));
            head.Controls.Add(_search, 1, 0);

            FlowLayoutPanel quick = new FlowLayoutPanel();
            quick.AutoSize = true; quick.WrapContents = false; quick.Anchor = AnchorStyles.Right | AnchorStyles.Bottom;
            ModernButton p1 = Ghost(L.T("Базовый")); p1.Click += delegate { ApplyPreset("base"); };
            ModernButton p2 = Ghost(L.T("Строгий")); p2.Click += delegate { ApplyPreset("strict"); };
            ModernButton p3 = Ghost(L.T("Максимум")); p3.Click += delegate { ApplyPreset("max"); };
            ModernButton a2 = Ghost(L.T("Снять всё")); a2.Click += delegate { SetAll(false); };
            ModernButton a3 = Ghost(L.T("По умолчанию")); a3.Click += delegate { ResetDefaults(); };
            quick.Controls.Add(p1); quick.Controls.Add(p2); quick.Controls.Add(p3);
            quick.Controls.Add(a2); quick.Controls.Add(a3);
            head.Controls.Add(quick, 2, 0);
            page.Controls.Add(head, 0, 0);

            // карточка со списком
            Card card = new Card();
            card.Dock = DockStyle.Fill;
            card.Margin = new Padding(0, (int)(u * 0.5F), 0, (int)(u * 0.5F));
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
                _settingsList.Controls.Add(r);
            }
            SectionHeader safe = new SectionHeader(L.T("Безопасность")); safe.Font = Font; _settingsList.Controls.Add(safe);
            _optBackup  = MakeSafeRow(L.T("Резервная копия реестра"), L.T("На рабочий стол сохраняются .reg-файлы затрагиваемых веток."), GSave, true);
            _optRestore = MakeSafeRow(L.T("Точка восстановления"), L.T("Позволяет откатить всё через «Восстановление системы»."), GUndo, true);
            _optDry     = MakeSafeRow(L.T("Тестовый прогон"), L.T("Показать список действий в журнале, ничего не меняя."), GEye, false);
            _optDry.Toggle.CheckedChanged += delegate { UpdateApplyText(); };
            _settingsList.Controls.Add(_optBackup); _settingsList.Controls.Add(_optRestore); _settingsList.Controls.Add(_optDry);
            card.Controls.Add(_settingsList);
            page.Controls.Add(card, 0, 1);

            // кнопки действий
            FlowLayoutPanel act = new FlowLayoutPanel();
            act.Dock = DockStyle.Fill; act.AutoSize = true;
            act.FlowDirection = FlowDirection.RightToLeft;
            act.WrapContents = false;
            _btnApply = new ModernButton(L.T("Применить"), true); _btnApply.Font = new Font(Font, FontStyle.Bold);
            _btnApply.Click += OnApply;
            _btnRevert = new ModernButton(L.T("Откат"), false); _btnRevert.Click += OnRevert;
            _btnFolder = new ModernButton(L.T("Папка копий"), false);
            _btnFolder.Click += delegate { try { Process.Start("explorer.exe", Environment.GetFolderPath(Environment.SpecialFolder.Desktop)); } catch { } };
            _btnProfileSave = new ModernButton(L.T("Сохранить профиль"), false); _btnProfileSave.Click += OnSaveProfile;
            _btnProfileLoad = new ModernButton(L.T("Загрузить профиль"), false); _btnProfileLoad.Click += OnLoadProfile;
            foreach (ModernButton b in new[] { _btnApply, _btnRevert, _btnFolder, _btnProfileSave, _btnProfileLoad })
            { b.Font = b.Primary ? new Font(Font, FontStyle.Bold) : Font; b.Margin = new Padding((int)(u * 0.5F), (int)(u * 0.3F), 0, 0); act.Controls.Add(b); }
            page.Controls.Add(act, 0, 2);
            return page;
        }
        private ModernButton _btnApply, _btnRevert, _btnFolder, _btnProfileSave, _btnProfileLoad;

        private OptionRow MakeSafeRow(string t, string d, string g, bool on)
        { OptionRow r = new OptionRow(t, d, g, on, false); r.Font = Font; return r; }

        // ================================================================== //
        //  Страница: Обзор — главный экран
        // ================================================================== //
        private Control BuildHomePage()
        {
            int u = Font.Height;
            // страница прокручивается, если окну не хватает высоты
            Panel scroll = new Panel();
            scroll.AutoScroll = true;
            scroll.BackColor = Theme.WindowBg;
            Dwm.DarkScrollbars(scroll);
            _homeScroll = scroll;
            scroll.Resize += delegate { FitHomeHeight(); };

            TableLayoutPanel page = new TableLayoutPanel();
            _homePage = page;
            page.ColumnCount = 1; page.RowCount = 4;
            page.BackColor = Theme.WindowBg;
            page.Dock = DockStyle.Top;
            page.AutoSize = true; page.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));                       // шапка
            page.RowStyles.Add(new RowStyle(SizeType.Absolute, (int)(u * 9.4F)));      // статусная панель
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));                       // карточки разделов
            page.RowStyles.Add(new RowStyle(SizeType.Absolute, (int)(u * 15.5F)));     // диаграммы

            // --- шапка: заголовок + чип системы --------------------------------
            TableLayoutPanel head = new TableLayoutPanel();
            head.Dock = DockStyle.Fill; head.AutoSize = true;
            head.ColumnCount = 2; head.RowCount = 1;
            head.BackColor = Theme.WindowBg;
            head.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            head.Margin = new Padding(0, 0, 0, (int)(u * 0.7F));

            FlowLayoutPanel titles = new FlowLayoutPanel();
            titles.FlowDirection = FlowDirection.TopDown; titles.WrapContents = false;
            titles.AutoSize = true; titles.Margin = new Padding(0);
            Label big = new Label();
            big.Text = L.T("Ваша приватность");
            big.Font = Theme.PickFont(new[] { "Segoe UI Variable Display", "Segoe UI", "Tahoma" }, Font.Size * 1.95F, FontStyle.Bold);
            big.ForeColor = Theme.Text; big.AutoSize = true; big.Margin = new Padding(0, 0, 0, 2);
            _homeHint = new Label();
            _homeHint.Text = L.T("Идёт первая проверка — страница заполнится сама.");
            _homeHint.ForeColor = Theme.TextDim; _homeHint.AutoSize = true; _homeHint.Margin = new Padding(2, 0, 0, 0);
            titles.Controls.Add(big); titles.Controls.Add(_homeHint);
            head.Controls.Add(titles, 0, 0);

            _homeSysChip = new ChipLabel();
            _homeSysChip.Font = Font;
            _homeSysChip.Anchor = AnchorStyles.Right | AnchorStyles.Top;
            _homeSysChip.Margin = new Padding(0, (int)(u * 0.4F), 0, 0);
            _homeSysChip.SetText(L.T("Определение системы…"));
            head.Controls.Add(_homeSysChip, 1, 0);
            page.Controls.Add(head, 0, 0);

            // --- статусная панель: кольцо, вердикт, мини-показатели, действия ---
            Card band = new Card();
            band.Dock = DockStyle.Fill;
            band.Margin = new Padding(0, 0, 0, (int)(u * 0.7F));
            band.Padding = new Padding((int)(u * 1.0F), (int)(u * 0.8F), (int)(u * 1.0F), (int)(u * 0.8F));

            TableLayoutPanel bi = new TableLayoutPanel();
            bi.Dock = DockStyle.Fill; bi.BackColor = Theme.CardBg;
            bi.ColumnCount = 3; bi.RowCount = 2;
            bi.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            bi.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            bi.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, (int)(u * 7.4F)));
            bi.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            bi.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

            _homeRing = new IndexRing();
            _homeRing.Font = Font; _homeRing.Dock = DockStyle.Fill;
            _homeRing.Margin = new Padding(0, 0, (int)(u * 0.6F), 0);
            bi.Controls.Add(_homeRing, 0, 0);
            bi.SetRowSpan(_homeRing, 2);

            TableLayoutPanel verdict = new TableLayoutPanel();
            verdict.Dock = DockStyle.Fill; verdict.BackColor = Theme.CardBg;
            verdict.ColumnCount = 1; verdict.RowCount = 2;
            verdict.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            verdict.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            verdict.Margin = new Padding((int)(u * 0.4F), (int)(u * 0.2F), 0, 0);
            _verdictTitle = new Label();
            _verdictTitle.AutoSize = false; _verdictTitle.Dock = DockStyle.Top;
            _verdictTitle.Height = (int)(Font.Height * 1.85F); _verdictTitle.AutoEllipsis = true;
            _verdictTitle.Font = Theme.PickFont(new[] { "Segoe UI Variable Display", "Segoe UI", "Tahoma" }, Font.Size * 1.25F, FontStyle.Bold);
            _verdictTitle.ForeColor = Theme.Text;
            _verdictTitle.Text = L.T("Идёт проверка системы…");
            _verdictTitle.Margin = new Padding(0, 0, 0, (int)(u * 0.15F));
            _verdictSub = new Label();
            _verdictSub.AutoSize = false; _verdictSub.Dock = DockStyle.Top;
            _verdictSub.Height = (int)(Font.Height * 1.6F); _verdictSub.AutoEllipsis = true;
            _verdictSub.ForeColor = Theme.TextDim;
            _verdictSub.Text = L.T("Читаю реальное состояние настроек — это займёт несколько секунд.");
            _verdictSub.Margin = new Padding(2, 0, 0, (int)(u * 0.5F));
            FlowLayoutPanel minis = new FlowLayoutPanel();
            minis.AutoSize = true; minis.WrapContents = false; minis.Margin = new Padding(0);
            minis.Anchor = AnchorStyles.Left | AnchorStyles.Bottom;
            minis.Padding = new Padding(0, (int)(u * 0.15F), 0, 0);
            _msEvents  = new MiniStat(L.T("событий в сутки"), GXray, Theme.Warn);
            _msYear    = new MiniStat(L.T("уйдёт за год"), GClock, Theme.Err);
            _msBlocked = new MiniStat(L.T("доменов молчат"), GFire, Theme.Accent);
            foreach (MiniStat m in new[] { _msEvents, _msYear, _msBlocked })
            { m.Font = Font; m.Margin = new Padding(0, 0, (int)(u * 1.0F), 0); minis.Controls.Add(m); }
            verdict.Controls.Add(_verdictTitle, 0, 0);
            verdict.Controls.Add(_verdictSub, 0, 1);
            bi.Controls.Add(verdict, 1, 0);
            bi.Controls.Add(minis, 1, 1);
            bi.SetColumnSpan(minis, 2);

            FlowLayoutPanel actions = new FlowLayoutPanel();
            actions.FlowDirection = FlowDirection.LeftToRight;
            actions.AutoSize = true; actions.WrapContents = false;
            actions.Anchor = AnchorStyles.Right;
            actions.Margin = new Padding((int)(u * 0.6F), 0, 0, 0);
            _homeActions = actions;
            ModernButton bApply = new ModernButton(L.T("Настроить и применить"), true);
            bApply.Font = new Font(Font, FontStyle.Bold);
            bApply.Click += delegate { Navigate("settings"); };
            ModernButton bAudit = new ModernButton(L.T("Проверить"), false);
            bAudit.Font = Font;
            bAudit.Click += delegate { Navigate("audit"); RunAudit(); };
            ModernButton bDiag = new ModernButton(L.T("Диагностика"), false);
            bDiag.Font = Font;
            bDiag.Click += OnSelfTest;
            foreach (ModernButton b in new[] { bApply, bAudit, bDiag })
            { b.Margin = new Padding((int)(u * 0.4F), 0, 0, 0); actions.Controls.Add(b); }
            band.Resize += delegate { LayoutHomeActions(band); };
            bi.Controls.Add(actions, 2, 0);
            band.Controls.Add(bi);
            page.Controls.Add(band, 0, 1);

            // --- карточки разделов с живыми статусами --------------------------
            TileGrid quick = new TileGrid();
            quick.Dock = DockStyle.Fill; quick.AutoSize = true; quick.Font = Font;
            quick.MinTileWidthU = 13.0F; quick.TileHeightU = 4.0F; quick.MaxCols = 4;
            quick.Margin = new Padding(0, 0, 0, (int)(u * 0.7F));
            quick.Resize += delegate { FitHomeHeight(); };
            _qcXray    = new ActionCard(L.T("Рентген"), GXray, Theme.Warn);
            _qcDossier = new ActionCard(L.T("Досье"), GFinger, Theme.Err);
            _qcMonitor = new ActionCard(L.T("Монитор"), GNav3, Theme.Accent);
            _qcGuard   = new ActionCard(L.T("Страж"), GShield, Theme.Ok);
            _qcXray.Click    += delegate { Navigate("xray"); };
            _qcDossier.Click += delegate { Navigate("dossier"); };
            _qcMonitor.Click += delegate { Navigate("monitor"); };
            _qcGuard.Click   += delegate { Navigate("guard"); };
            foreach (ActionCard c in new[] { _qcXray, _qcDossier, _qcMonitor, _qcGuard })
            { c.Font = Font; c.SetStatus(L.T("ожидание данных…"), Theme.TextFaint); quick.Controls.Add(c); }
            page.Controls.Add(quick, 0, 2);

            // --- диаграммы: что собирают + кто подглядывал ----------------------
            TableLayoutPanel mid = new TableLayoutPanel();
            mid.Dock = DockStyle.Fill; mid.BackColor = Theme.WindowBg;
            mid.ColumnCount = 2; mid.RowCount = 2;
            mid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50F));
            mid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50F));
            mid.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            mid.RowStyles.Add(new RowStyle(SizeType.Absolute, 0F));

            _homeDonutCard = MakeChartCard(L.T("Что о вас собирают"));
            _homeDonut = new DonutChart(); _homeDonut.Font = Font; _homeDonut.Dock = DockStyle.Fill;
            _homeDonut.EmptyHint = L.T("Данные появятся после «Рентгена»:") + "\n" + L.T("включите запись и просканируйте.");
            _homeDonutCard.Controls.Add(_homeDonut);
            _homeDonut.BringToFront();
            _homeDonutCard.Margin = new Padding(0, 0, (int)(u * 0.35F), 0);
            mid.Controls.Add(_homeDonutCard, 0, 0);

            _homeChartCard = MakeChartCard(L.T("Кто подглядывал — по дням"));
            _homeSensors = new SensorChart(); _homeSensors.Font = Font; _homeSensors.Dock = DockStyle.Fill;
            _homeSensors.BackColor = Theme.CardBg;
            _homeSensors.Cursor = Cursors.Hand;
            _homeSensors.Click += delegate { Navigate("dossier"); };
            _homeChartCard.Controls.Add(_homeSensors);
            _homeSensors.BringToFront();
            _homeChartCard.Margin = new Padding((int)(u * 0.35F), 0, 0, 0);
            mid.Controls.Add(_homeChartCard, 1, 0);

            _homeMid = mid;
            mid.Resize += delegate { LayoutHomeMid(); };
            page.Controls.Add(mid, 0, 3);

            scroll.Controls.Add(page);
            return scroll;
        }

        // На узком окне кнопки встают столбиком, на широком — в один ряд
        private void LayoutHomeActions(Control band)
        {
            if (_homeActions == null || band == null) return;
            int u = Font.Height;
            bool row = band.ClientSize.Width >= u * 58;
            FlowDirection want = row ? FlowDirection.LeftToRight : FlowDirection.TopDown;
            if (_homeActions.FlowDirection == want) return;
            _homeActions.SuspendLayout();
            _homeActions.FlowDirection = want;
            foreach (Control c in _homeActions.Controls)
                c.Margin = row ? new Padding((int)(u * 0.4F), 0, 0, 0)
                               : new Padding(0, 0, 0, (int)(u * 0.35F));
            _homeActions.ResumeLayout(true);
        }

        // Ряд кнопок: выровнен вправо и сам переносится, если не хватает ширины
        private void AttachButtonRow(FlowLayoutPanel row, Control card)
        {
            row.FlowDirection = FlowDirection.LeftToRight;
            row.WrapContents = true;
            row.AutoSize = true;
            row.Anchor = AnchorStyles.Right;
            card.Resize += delegate
            {
                int w = card.ClientSize.Width - card.Padding.Horizontal;
                if (w <= 120 || row.MaximumSize.Width == w) return;
                row.MaximumSize = new Size(w, 0);
                row.PerformLayout();
                if (row.Parent != null) row.Parent.PerformLayout();
            };
        }

        private Card MakeChartCard(string title)
        {
            int u = Font.Height;
            Card c = new Card();
            c.Dock = DockStyle.Fill;
            c.Padding = new Padding((int)(u * 0.8F), (int)(u * 0.55F), (int)(u * 0.8F), (int)(u * 0.5F));
            Label l = new Label();
            l.Text = title; l.Dock = DockStyle.Top; l.AutoSize = false;
            l.Height = (int)(u * 1.7F); l.Font = new Font(Font, FontStyle.Bold); l.ForeColor = Theme.Text;
            l.TextAlign = ContentAlignment.MiddleLeft; l.BackColor = Theme.CardBg;
            c.Controls.Add(l);
            return c;
        }

        // Узкое окно: диаграммы встают друг под другом
        private void LayoutHomeMid()
        {
            if (_homeMid == null || _homePage == null || _homeDonutCard == null) return;
            int u = Font.Height;
            bool narrow = _homeMid.ClientSize.Width < u * 42;
            bool isNarrow = _homeMid.GetColumnSpan(_homeDonutCard) == 2;
            if (narrow == isNarrow) return;
            _homeMid.SuspendLayout();
            if (narrow)
            {
                _homeMid.SetColumnSpan(_homeDonutCard, 2);
                _homeMid.SetCellPosition(_homeChartCard, new TableLayoutPanelCellPosition(0, 1));
                _homeMid.SetColumnSpan(_homeChartCard, 2);
                _homeMid.RowStyles[0].SizeType = SizeType.Percent; _homeMid.RowStyles[0].Height = 50F;
                _homeMid.RowStyles[1].SizeType = SizeType.Percent; _homeMid.RowStyles[1].Height = 50F;
                _chartsMinU = 27F;
                _homeDonutCard.Margin = new Padding(0, 0, 0, (int)(u * 0.35F));
                _homeChartCard.Margin = new Padding(0, (int)(u * 0.35F), 0, 0);
            }
            else
            {
                _homeMid.SetColumnSpan(_homeChartCard, 1);
                _homeMid.SetCellPosition(_homeChartCard, new TableLayoutPanelCellPosition(1, 0));
                _homeMid.SetColumnSpan(_homeDonutCard, 1);
                _homeMid.RowStyles[0].SizeType = SizeType.Percent; _homeMid.RowStyles[0].Height = 100F;
                _homeMid.RowStyles[1].SizeType = SizeType.Absolute; _homeMid.RowStyles[1].Height = 0F;
                _chartsMinU = 15.5F;
                _homeDonutCard.Margin = new Padding(0, 0, (int)(u * 0.35F), 0);
                _homeChartCard.Margin = new Padding((int)(u * 0.35F), 0, 0, 0);
            }
            _homeMid.ResumeLayout(true);
            FitHomeHeight();
        }

        // Диаграммы тянутся на всю свободную высоту окна
        private void FitHomeHeight()
        {
            if (_homeScroll == null || _homePage == null) return;
            int u = Font.Height;
            int min = (int)(u * _chartsMinU);
            int others = 0;
            try
            {
                int[] rows = _homePage.GetRowHeights();
                for (int r = 0; r < rows.Length - 1; r++) others += rows[r];
            }
            catch { return; }
            int avail = _homeScroll.ClientSize.Height - others - (int)(u * 0.3F);
            int h = Math.Max(min, avail);
            if (Math.Abs(_homePage.RowStyles[3].Height - h) > 2)
                _homePage.RowStyles[3].Height = h;
        }

        // Заполняет главный экран по уже полученным данным
        private void RefreshHome()
        {
            if (_homeRing == null) return;

            // вердикт и кольцо
            if (_lastAudit != null)
            {
                int ok = Json.GetInt(_lastAudit, "ok"), total = Json.GetInt(_lastAudit, "total");
                int pct = total > 0 ? (int)Math.Round(100.0 * ok / total) : 0;
                _homeRing.SetScore(ok, total);
                _verdictTitle.ForeColor = pct >= 85 ? Theme.Ok : (pct >= 50 ? Theme.Warn : Theme.Err);
                _verdictTitle.Text = pct >= 85 ? L.T("Система хорошо закрыта")
                    : (pct >= 50 ? L.T("Защита настроена не полностью") : L.T("Система почти не защищена"));
                int fails = total - ok;
                _verdictSub.Text = ok + L.T(" из ") + total + L.T(" применено") +
                    (fails > 0 ? "  ·  " + fails + L.T(" требуют внимания") : L.T("  ·  всё на месте"));
                int blocked = 0;
                foreach (object o in Json.GetArr(_lastAudit, "dns")) if (Json.GetBool(Json.Obj(o), "blocked")) blocked++;
                _msBlocked.SetValue(blocked.ToString());
                _homeHint.Text = L.T("Данные получены с этого компьютера ") + Json.GetStr(_lastAudit, "time") + ".";
            }

            // мини-показатели и пончик — из рентгена
            if (_lastXray != null)
            {
                _msEvents.SetValue(FormatBig(Json.GetInt(_lastXray, "perDay")));
                _msYear.SetValue(FormatBig(Json.GetInt(_lastXray, "perYear")));
                List<KeyValuePair<string, float>> d = new List<KeyValuePair<string, float>>();
                int n = 0;
                foreach (object o in Json.GetArr(_lastXray, "categories"))
                {
                    if (n++ >= 6) break;
                    Dictionary<string, object> c = Json.Obj(o);
                    d.Add(new KeyValuePair<string, float>(L.T(Json.GetStr(c, "name")), Json.GetInt(c, "count")));
                }
                _homeDonut.SetData(d, FormatBig(Json.GetInt(_lastXray, "total")), L.T("событий"));
            }
            else _homeDonut.SetData(null, "", "");

            // график датчиков
            if (_homeSensors != null && _lastSpy != null)
                _homeSensors.SetData(Json.GetArr(_lastSpy, "days"));

            // живые статусы карточек разделов
            if (_qcXray != null)
            {
                if (_lastXray != null)
                    _qcXray.SetStatus(FormatBig(Json.GetInt(_lastXray, "perDay")) + L.T(" событий/сутки"), Theme.TextDim);
                else
                    _qcXray.SetStatus(_xrayRecording ? L.T("запись включена") : L.T("что собрано о вас"), Theme.TextDim);

                int act = _lastSpy != null ? Json.GetInt(_lastSpy, "activeNow") : 0;
                int week = _lastSpy != null ? Json.GetInt(_lastSpy, "week") : -1;
                if (act > 0) _qcDossier.SetStatus(L.T("используются сейчас!"), Theme.Err);
                else if (week >= 0) _qcDossier.SetStatus(week + L.T(" обращений за 7 дней"), Theme.TextDim);
                else _qcDossier.SetStatus(L.T("камера, микрофон, след"), Theme.TextDim);

                if (_monitorEnabled)
                    _qcMonitor.SetStatus(_lastMonitor != null
                        ? Json.GetInt(_lastMonitor, "total") + L.T(" соединений/сутки")
                        : L.T("включён"), Theme.TextDim);
                else _qcMonitor.SetStatus(L.T("выключен"), Theme.Warn);

                _qcGuard.SetStatus(_guardInstalled ? L.T("на посту") : L.T("выключен"),
                    _guardInstalled ? Theme.TextDim : Theme.Warn);
            }
        }

        // ================================================================== //
        //  Страница: Рентген телеметрии
        // ================================================================== //
        private Control BuildXrayPage()
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
            head.Controls.Add(PageTitle(L.T("Рентген телеметрии")), 0, 0);
            _btnReport = new ModernButton(L.T("Сохранить отчёт"), false);
            _btnReport.Font = Font; _btnReport.Anchor = AnchorStyles.Right | AnchorStyles.Bottom;
            _btnReport.Click += OnSaveReport;
            head.Controls.Add(_btnReport, 1, 0);
            page.Controls.Add(head, 0, 0);

            // панель управления
            Card ctl = new Card();
            ctl.Dock = DockStyle.Fill;
            ctl.Margin = new Padding(0, (int)(u * 0.5F), 0, (int)(u * 0.5F));
            ctl.Padding = new Padding((int)(u * 0.9F), (int)(u * 0.7F), (int)(u * 0.9F), (int)(u * 0.7F));
            TableLayoutPanel ci = new TableLayoutPanel();
            ci.Dock = DockStyle.Fill; ci.AutoSize = true; ci.ColumnCount = 1; ci.RowCount = 2;
            ci.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            ci.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            ci.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            _xrayState = new Label();
            _xrayState.AutoSize = false; _xrayState.Dock = DockStyle.Fill;
            _xrayState.TextAlign = ContentAlignment.MiddleLeft; _xrayState.ForeColor = Theme.TextDim;
            _xrayState.Text = L.T("Показывает НАСТОЯЩИЕ события, которые Windows собрала об этом компьютере,\n") +
                              L.T("с расшифровкой и сырым содержимым. Включите запись, дайте системе поработать\n") +
                              L.T("хотя бы час — и нажмите «Сканировать».");
            ci.Controls.Add(_xrayState, 0, 0);
            FlowLayoutPanel xb = new FlowLayoutPanel();
            AttachButtonRow(xb, ctl);
            xb.Margin = new Padding(0, (int)(u * 0.5F), 0, 0);
            _btnXrayRec  = new ModernButton(L.T("Включить запись"), true);
            _btnXrayRec.Click += OnXrayToggleRecording;
            _btnXrayScan = new ModernButton(L.T("Сканировать"), false); _btnXrayScan.Click += delegate { RunXrayScan(false); };
            _btnXrayBase = new ModernButton(L.T("Запомнить как «до»"), false); _btnXrayBase.Click += delegate { RunXrayScan(true); };
            _btnXrayWipe = new ModernButton(L.T("Стереть копию"), false); _btnXrayWipe.Click += OnXrayWipe;
            foreach (ModernButton b in new[] { _btnXrayRec, _btnXrayScan, _btnXrayBase, _btnXrayWipe })
            { b.Font = b.Primary ? new Font(Font, FontStyle.Bold) : Font; b.Margin = new Padding((int)(u * 0.4F), 0, 0, (int)(u * 0.3F)); xb.Controls.Add(b); }
            ci.Controls.Add(xb, 0, 1);
            ctl.Controls.Add(ci);
            page.Controls.Add(ctl, 0, 1);

            _xrayTiles = new TileGrid();
            _xrayTiles.Dock = DockStyle.Fill; _xrayTiles.AutoSize = true; _xrayTiles.Font = Font;
            _xrayTiles.Margin = new Padding(0, 0, 0, (int)(u * 0.4F));
            page.Controls.Add(_xrayTiles, 0, 2);

            Card list = new Card();
            list.Dock = DockStyle.Fill; list.Padding = new Padding((int)(u * 0.6F));
            list.Margin = new Padding(0, 0, 0, (int)(u * 0.3F));
            _xrayList = new StackPanel();
            _xrayList.Dock = DockStyle.Fill; _xrayList.Font = Font;
            _xrayList.Padding = new Padding((int)(u * 0.4F));
            Dwm.DarkScrollbars(_xrayList);
            list.Controls.Add(_xrayList);
            page.Controls.Add(list, 0, 3);
            return page;
        }

        private void OnXrayToggleRecording(object sender, EventArgs e)
        {
            if (_xrayRecording)
            { RunStreaming("-XrayDisable", L.T("Выключение записи…"), delegate { RunXrayStatus(); }); return; }
            if (MessageBox.Show(this,
                L.T("Windows начнёт вести ЛОКАЛЬНУЮ копию своих диагностических событий,\n") +
                L.T("чтобы их можно было прочитать и показать вам.\n\n") +
                L.T("Объём отправляемых данных при этом НЕ увеличивается — меняется только\n") +
                L.T("то, что копия сохраняется на диске. Стереть её можно кнопкой «Стереть копию».\n\n") +
                L.T("Продолжить?"), L.T("Включить запись"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            RunStreaming("-XrayEnable", L.T("Включение записи…"), delegate { RunXrayStatus(); });
        }

        private void OnXrayWipe(object sender, EventArgs e)
        {
            if (MessageBox.Show(this, L.T("Локальная копия собранных событий будет удалена.\nПродолжить?"),
                L.T("Стереть копию"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming("-XrayWipe", L.T("Стирание копии…"), delegate { RunXrayStatus(); });
        }

        private void RunXrayStatus()
        {
            RunJson("-XrayStatus", L.T("Проверка рентгена…"), delegate(Dictionary<string, object> d)
            {
                if (d == null) return;
                _xrayRecording = Json.GetBool(d, "recording");
                bool mod = Json.GetBool(d, "moduleAvailable");
                Dictionary<string, object> db = Json.GetObj(d, "db");
                _btnXrayRec.Text = _xrayRecording ? L.T("Выключить запись") : L.T("Включить запись");
                _btnXrayRec.Primary = !_xrayRecording; _btnXrayRec.Invalidate();
                _btnXrayScan.Enabled = _xrayRecording;
                string s = _xrayRecording
                    ? L.T("Запись включена. Windows ведёт локальную копию событий — можно сканировать.")
                    : L.T("Запись выключена. Пока она выключена, прочитать собранные данные нельзя.");
                if (!mod) s = L.T("На этой системе нет модуля Microsoft.DiagnosticDataViewer — рентген недоступен.");
                if (db != null && Json.GetStr(db, "mb") != "0") s += L.T("\nЛокальная копия на диске: ") + Json.GetStr(db, "mb") + L.T(" МБ.");
                Dictionary<string, object> b = Json.GetObj(d, "baseline");
                if (b != null) s += L.T("\nЭталон «до» сохранён: ") + Json.GetStr(b, "time") + " (" + Json.GetStr(b, "perDay") + L.T(" событий в сутки).");
                _xrayState.Text = s;
                foreach (NavItem n in _nav) if ((string)n.Tag == "xray") { n.Badge = _xrayRecording ? "rec" : ""; n.Invalidate(); }
            });
        }

        private void RunXrayScan(bool asBaseline)
        {
            string extra = "-XrayScan -XrayHours 24" + (asBaseline ? " -XrayBaseline" : "");
            RunJson(extra, asBaseline ? L.T("Замер «до»…") : L.T("Чтение собранных данных…"), delegate(Dictionary<string, object> d)
            {
                if (d == null) { _xrayState.Text = L.T("Не удалось получить данные."); return; }
                string err = Json.GetStr(d, "error");
                if (err.Length > 0)
                {
                    _xrayList.Controls.Clear();
                    SectionHeader sh = new SectionHeader(err); sh.Font = Font; _xrayList.Controls.Add(sh);
                    try { _xrayList.AutoScrollPosition = Point.Empty; } catch { }
            _xrayList.Restack(); _xrayState.Text = err; return;
                }
                _lastXray = d;
                RenderXray(d);
                RefreshHome();
                if (asBaseline) _xrayState.Text = L.T("Замер сохранён как «до». Примените настройки и просканируйте снова — покажу разницу.");
            });
        }

        private void RenderXray(Dictionary<string, object> d)
        {
            int total = Json.GetInt(d, "total");
            int perDay = Json.GetInt(d, "perDay");
            _xrayTiles.Controls.Clear();
            _xrayTiles.Controls.Add(Tile(L.T("Событий собрано"), total.ToString(), L.T("за последние ") + Json.GetInt(d, "hours") + L.T(" ч"), Theme.Accent));
            _xrayTiles.Controls.Add(Tile(L.T("В сутки"), perDay.ToString(), Json.GetStr(d, "mbPerDay") + L.T(" МБ данных о вас"), Theme.Warn));
            _xrayTiles.Controls.Add(Tile(L.T("Прогноз за год"), FormatBig(Json.GetInt(d, "perYear")), Json.GetStr(d, "mbPerYear") + L.T(" МБ в год"), Theme.Err));

            if (d.ContainsKey("baselinePerDay"))
            {
                int bp = Json.GetInt(d, "baselinePerDay");
                double delta = 0;
                object dp = Json.Get(d, "deltaPercent");
                if (dp != null) double.TryParse(dp.ToString().Replace(',', '.'), System.Globalization.NumberStyles.Any,
                    System.Globalization.CultureInfo.InvariantCulture, out delta);
                bool better = perDay < bp;
                _xrayTiles.Controls.Add(Tile(better ? L.T("Стало меньше на") : L.T("Изменение"),
                    (better ? "" : "+") + Math.Abs(delta).ToString("0.#") + "%",
                    L.T("было ") + bp + L.T(" → стало ") + perDay + L.T(" в сутки"), better ? Theme.Ok : Theme.Err));
            }
            else
            {
                _xrayTiles.Controls.Add(Tile(L.T("Уникальных событий"), Json.GetInt(d, "distinctNames").ToString(),
                    L.T("разных типов данных"), Theme.Accent));
            }

            _xrayList.Controls.Clear();

            SectionHeader s1 = new SectionHeader(L.T("Что именно собрано — нажмите, чтобы увидеть сырое событие"));
            s1.Font = Font; _xrayList.Controls.Add(s1);
            foreach (object o in Json.GetArr(d, "categories"))
            {
                Dictionary<string, object> c = Json.Obj(o);
                Dictionary<string, object> sm = Json.GetObj(c, "sample");
                double share = 0;
                object sh = Json.Get(c, "share");
                if (sh != null) double.TryParse(sh.ToString().Replace(',', '.'), System.Globalization.NumberStyles.Any,
                    System.Globalization.CultureInfo.InvariantCulture, out share);
                XrayCatRow row = new XrayCatRow(
                    L.T(Json.GetStr(c, "name")), Json.GetInt(c, "count"), share, Json.GetStr(c, "what"),
                    Json.GetArr(c, "topNames"),
                    sm != null ? Json.GetStr(sm, "name") : "",
                    sm != null ? Json.GetStr(sm, "time") : "",
                    sm != null ? Json.GetStr(sm, "payload") : "");
                row.Font = Font;
                _xrayList.Controls.Add(row);
            }

            List<object> ids = Json.GetArr(d, "identifiers");
            if (ids.Count > 0)
            {
                SectionHeader s2 = new SectionHeader(L.T("Метки, которыми помечены события (по ним вас узнают)"));
                s2.Font = Font; _xrayList.Controls.Add(s2);
                foreach (object o in ids)
                {
                    Dictionary<string, object> i = Json.Obj(o);
                    List<object> vals = Json.GetArr(i, "values");
                    string v = vals.Count > 0 ? Json.GetStr(Json.Obj(vals[0]), "value") : "";
                    _xrayList.Controls.Add(new KvRow(Json.GetStr(i, "key") + "  →  " + v,
                        Json.GetInt(i, "distinct") + L.T(" знач."), true) { Font = this.Font });
                }
            }

            List<object> apps = Json.GetArr(d, "apps");
            if (apps.Count > 0)
            {
                SectionHeader s3 = new SectionHeader(L.T("Программы, попавшие в отчёты о вас"));
                s3.Font = Font; _xrayList.Controls.Add(s3);
                foreach (object o in apps)
                {
                    Dictionary<string, object> a = Json.Obj(o);
                    _xrayList.Controls.Add(new KvRow(Json.GetStr(a, "name"), Json.GetInt(a, "count") + "×", false) { Font = this.Font });
                }
            }
            _xrayList.Restack();
            _xrayState.Text = L.T("Прочитано ") + total + L.T(" событий за ") + Json.GetInt(d, "hours") + L.T(" ч. ") +
                              L.T("Нажмите на категорию — покажу настоящий JSON, который ушёл в Microsoft.");
        }

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
                    _dossierList.Controls.Add(new WipeRow(id, L.T(Json.GetStr(it, "title")), Json.GetStr(it, "what"),
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

        // ================================================================== //
        //  Отчёт-доказательство (HTML)
        // ================================================================== //
        // Самопроверка: показывает, может ли программа реально менять настройки
        private void OnSelfTest(object sender, EventArgs e)
        {
            RunStreaming("-SelfTest", L.T("Самопроверка…"), delegate { });
        }

        private void OnSaveReport(object sender, EventArgs e)
        {
            SaveFileDialog sd = new SaveFileDialog();
            sd.Filter = L.T("HTML-отчёт (*.html)|*.html");
            sd.FileName = "otchet-privatnost-" + DateTime.Now.ToString("yyyy-MM-dd") + ".html";
            if (sd.ShowDialog(this) != DialogResult.OK) return;
            try
            {
                File.WriteAllText(sd.FileName, BuildReportHtml(), new UTF8Encoding(true));
                _status.Text = L.T("Отчёт сохранён: ") + Path.GetFileName(sd.FileName);
                try { Process.Start(sd.FileName); } catch { }
            }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, L.T("Ошибка"), MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }

        private static string Esc(string s)
        {
            if (s == null) return "";
            return s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");
        }

        private string BuildReportHtml()
        {
            StringBuilder h = new StringBuilder();
            h.Append("<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\">");
            h.Append(L.T("<title>Отчёт о приватности Windows 11</title><style>"));
            h.Append("body{font-family:'Segoe UI',system-ui,sans-serif;max-width:900px;margin:40px auto;padding:0 20px;background:#fafafa;color:#1b1b1b;line-height:1.55}");
            h.Append("h1{font-size:28px;margin:0 0 4px}h2{font-size:19px;margin:32px 0 10px;border-bottom:2px solid #e3e3e3;padding-bottom:6px}");
            h.Append(".sub{color:#666;margin-bottom:28px}.grid{display:flex;flex-wrap:wrap;gap:12px;margin:16px 0}");
            h.Append(".tile{flex:1 1 180px;background:#fff;border:1px solid #e3e3e3;border-left:4px solid #0067c0;border-radius:8px;padding:14px 16px}");
            h.Append(".tile .c{font-size:11px;text-transform:uppercase;letter-spacing:.5px;color:#888}");
            h.Append(".tile .v{font-size:26px;font-weight:700;color:#0067c0;margin:4px 0}.tile .s{font-size:13px;color:#666}");
            h.Append("table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #e3e3e3;border-radius:8px;overflow:hidden}");
            h.Append("th,td{text-align:left;padding:9px 14px;border-bottom:1px solid #eee;font-size:14px}th{background:#f4f6f8;font-weight:600}");
            h.Append("tr:last-child td{border-bottom:none}.ok{color:#1e8e3e;font-weight:600}.bad{color:#c42b1c;font-weight:600}");
            h.Append("pre{background:#1f1f1f;color:#ddd;padding:14px;border-radius:8px;overflow-x:auto;font-size:12px;white-space:pre-wrap;word-break:break-all}");
            h.Append(".note{background:#fff8e6;border-left:4px solid #b45309;padding:12px 16px;border-radius:6px;margin:20px 0;font-size:14px}");
            h.Append("footer{margin-top:40px;color:#888;font-size:12px;border-top:1px solid #e3e3e3;padding-top:14px}");
            h.Append("</style></head><body>");
            h.Append(L.T("<h1>Отчёт о приватности Windows 11</h1>"));
            h.Append(L.T("<div class=\"sub\">Составлен ")).Append(DateTime.Now.ToString("dd.MM.yyyy HH:mm"));
            if (_detect != null) h.Append(" · ").Append(Esc(Json.GetStr(_detect, "os"))).Append(L.T(" · сборка ")).Append(Esc(Json.GetStr(_detect, "build")));
            h.Append("</div>");

            // Проверка
            if (_lastAudit != null)
            {
                int ok = Json.GetInt(_lastAudit, "ok"), total = Json.GetInt(_lastAudit, "total");
                h.Append(L.T("<h2>Проверка настроек</h2><div class=\"grid\">"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">Индекс приватности</div><div class=\"v\">"))
                 .Append(total > 0 ? (int)Math.Round(100.0 * ok / total) : 0).Append("%</div><div class=\"s\">")
                 .Append(ok).Append(L.T(" из ")).Append(total).Append(L.T(" настроек подтверждено</div></div>"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">Не применено</div><div class=\"v\">")).Append(total - ok)
                 .Append(L.T("</div><div class=\"s\">требуют внимания</div></div></div>"));
                h.Append(L.T("<table><tr><th>Раздел</th><th>Применено</th></tr>"));
                foreach (object o in Json.GetArr(_lastAudit, "groups"))
                {
                    Dictionary<string, object> g = Json.Obj(o);
                    int go = Json.GetInt(g, "ok"), gt = Json.GetInt(g, "total");
                    h.Append("<tr><td>").Append(Esc(Json.GetStr(g, "title"))).Append("</td><td class=\"")
                     .Append(go == gt ? "ok" : "bad").Append("\">").Append(go).Append(" / ").Append(gt).Append("</td></tr>");
                }
                h.Append("</table>");
                List<object> dns = Json.GetArr(_lastAudit, "dns");
                if (dns.Count > 0)
                {
                    h.Append(L.T("<h2>Обращения к доменам телеметрии (кэш DNS)</h2><table><tr><th>Домен</th><th>Состояние</th></tr>"));
                    foreach (object o in dns)
                    {
                        Dictionary<string, object> dn = Json.Obj(o);
                        bool bl = Json.GetBool(dn, "blocked");
                        h.Append("<tr><td>").Append(Esc(Json.GetStr(dn, "name"))).Append("</td><td class=\"")
                         .Append(bl ? "ok" : "bad").Append("\">").Append(bl ? L.T("заблокировано") : L.T("проходит")).Append("</td></tr>");
                    }
                    h.Append("</table>");
                }
            }

            // Рентген
            if (_lastXray != null)
            {
                h.Append(L.T("<h2>Рентген телеметрии — что было собрано</h2><div class=\"grid\">"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">Событий в сутки</div><div class=\"v\">"))
                 .Append(Json.GetInt(_lastXray, "perDay")).Append("</div><div class=\"s\">")
                 .Append(Esc(Json.GetStr(_lastXray, "mbPerDay"))).Append(L.T(" МБ данных</div></div>"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">Прогноз за год</div><div class=\"v\">"))
                 .Append(Esc(FormatBig(Json.GetInt(_lastXray, "perYear")))).Append("</div><div class=\"s\">")
                 .Append(Esc(Json.GetStr(_lastXray, "mbPerYear"))).Append(L.T(" МБ в год</div></div>"));
                if (_lastXray.ContainsKey("baselinePerDay"))
                    h.Append(L.T("<div class=\"tile\"><div class=\"c\">Было до настройки</div><div class=\"v\">"))
                     .Append(Json.GetInt(_lastXray, "baselinePerDay")).Append(L.T("</div><div class=\"s\">событий в сутки</div></div>"));
                h.Append("</div>");
                h.Append(L.T("<table><tr><th>Категория данных</th><th>Событий</th><th>Доля</th><th>Что это</th></tr>"));
                foreach (object o in Json.GetArr(_lastXray, "categories"))
                {
                    Dictionary<string, object> c = Json.Obj(o);
                    h.Append("<tr><td>").Append(Esc(Json.GetStr(c, "name"))).Append("</td><td>").Append(Json.GetInt(c, "count"))
                     .Append("</td><td>").Append(Esc(Json.GetStr(c, "share"))).Append("%</td><td>")
                     .Append(Esc(Json.GetStr(c, "what"))).Append("</td></tr>");
                }
                h.Append("</table>");
                foreach (object o in Json.GetArr(_lastXray, "categories"))
                {
                    Dictionary<string, object> c = Json.Obj(o);
                    Dictionary<string, object> sm = Json.GetObj(c, "sample");
                    if (sm == null) continue;
                    h.Append(L.T("<h2>Пример настоящего события: ")).Append(Esc(Json.GetStr(c, "name"))).Append("</h2>");
                    h.Append("<div class=\"sub\">").Append(Esc(Json.GetStr(sm, "name"))).Append(" · ").Append(Esc(Json.GetStr(sm, "time"))).Append("</div>");
                    h.Append("<pre>").Append(Esc(Json.GetStr(sm, "payload"))).Append("</pre>");
                    break;   // одного примера в отчёте достаточно
                }
            }

            // Монитор
            if (_lastMonitor != null)
            {
                h.Append(L.T("<h2>Монитор исходящих соединений</h2><div class=\"grid\">"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">Соединений</div><div class=\"v\">"))
                 .Append(Json.GetInt(_lastMonitor, "total")).Append(L.T("</div><div class=\"s\">за 24 часа</div></div>"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">К телеметрии</div><div class=\"v\">"))
                 .Append(Json.GetInt(_lastMonitor, "telemetryHits")).Append(L.T("</div><div class=\"s\">распознано по домену</div></div></div>"));
            }

            // Результат: до и после
            if (_lastProof != null && Json.GetObj(_lastProof, "before") != null)
            {
                Dictionary<string, object> pb = Json.GetObj(_lastProof, "before");
                Dictionary<string, object> pa = Json.GetObj(_lastProof, "after");
                h.Append("<h2>").Append(Esc(L.T("Результат: что было до программы и что стало"))).Append("</h2>");
                h.Append("<table><tr><th>").Append(Esc(L.T("Показатель"))).Append("</th><th>")
                 .Append(Esc(L.T("Было"))).Append("</th><th>").Append(Esc(L.T("Стало"))).Append("</th></tr>");
                string[,] rows = {
                    { L.T("Настроек приватности на месте"), "ok" },
                    { L.T("Сборщиков трассировки выключено"), "etwOff" },
                    { L.T("Задач телеметрии ещё работает"), "tasksLive" },
                    { L.T("Доменов телеметрии не отвечает"), "dnsBlocked" },
                    { L.T("Правил брандмауэра против телеметрии"), "fwRules" },
                    { L.T("Программ стартует вместе с Windows"), "startupOn" }
                };
                for (int i = 0; i < rows.GetLength(0); i++)
                    h.Append("<tr><td>").Append(Esc(rows[i, 0])).Append("</td><td>")
                     .Append(Json.GetInt(pb, rows[i, 1])).Append("</td><td>")
                     .Append(Json.GetInt(pa, rows[i, 1])).Append("</td></tr>");
                int xb2 = Json.GetInt(pb, "xrayPerDay"), xa2 = Json.GetInt(_lastProof, "xrayNow");
                if (xb2 > 0 && xa2 > 0)
                    h.Append("<tr><td>").Append(Esc(L.T("Событий телеметрии в сутки"))).Append("</td><td>")
                     .Append(xb2).Append("</td><td>").Append(xa2).Append("</td></tr>");
                h.Append("</table>");
                h.Append("<div class=\"sub\">").Append(Esc(L.T("Снимок «до» сделан "))).Append(Esc(Json.GetStr(pb, "time")))
                 .Append(Esc(L.T(", текущее состояние — "))).Append(Esc(Json.GetStr(pa, "time"))).Append("</div>");
            }

            // Автозапуск
            if (_lastStartup != null)
            {
                h.Append(L.T("<h2>Автозапуск: что стартует вместе с Windows</h2><div class=\"grid\">"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">Записей всего</div><div class=\"v\">"))
                 .Append(Json.GetInt(_lastStartup, "total")).Append(L.T("</div><div class=\"s\">в реестре, папках и планировщике</div></div>"));
                h.Append(L.T("<div class=\"tile\"><div class=\"c\">Запускается</div><div class=\"v\">"))
                 .Append(Json.GetInt(_lastStartup, "on")).Append(L.T("</div><div class=\"s\">из них лишних: "))
                 .Append(Json.GetInt(_lastStartup, "advise")).Append("</div></div></div>");
                h.Append(L.T("<table><tr><th>Программа</th><th>Что это</th><th>Откуда</th><th>Состояние</th></tr>"));
                foreach (object o in Json.GetArr(_lastStartup, "items"))
                {
                    Dictionary<string, object> it = Json.Obj(o);
                    bool on = Json.GetBool(it, "enabled");
                    h.Append("<tr><td>").Append(Esc(Json.GetStr(it, "name"))).Append("</td><td>")
                     .Append(Esc(L.T(Json.GetStr(it, "note")))).Append("</td><td>")
                     .Append(Esc(L.T(Json.GetStr(it, "source")))).Append("</td><td class=\"")
                     .Append(on ? (Json.GetBool(it, "advise") ? "bad" : "") : "ok").Append("\">")
                     .Append(on ? L.T("запускается") : L.T("отключено")).Append("</td></tr>");
                }
                h.Append("</table>");
            }

            // Предустановленные приложения
            if (_lastApps != null)
            {
                List<object> appItems = Json.GetArr(_lastApps, "apps");
                int bloatCount = 0;
                foreach (object o in appItems) if (Json.GetBool(Json.Obj(o), "bloat")) bloatCount++;
                h.Append(L.T("<h2>Предустановленные приложения</h2>"));
                h.Append("<div class=\"sub\">").Append(Esc(L.T("Найдено приложений: "))).Append(appItems.Count)
                 .Append(Esc(L.T(", из них лишних: "))).Append(bloatCount).Append("</div>");
                if (bloatCount > 0)
                {
                    h.Append(L.T("<table><tr><th>Приложение</th><th>Идентификатор</th></tr>"));
                    foreach (object o in appItems)
                    {
                        Dictionary<string, object> a = Json.Obj(o);
                        if (!Json.GetBool(a, "bloat")) continue;
                        h.Append("<tr><td>").Append(Esc(L.T(Json.GetStr(a, "title")))).Append("</td><td>")
                         .Append(Esc(Json.GetStr(a, "name"))).Append("</td></tr>");
                    }
                    h.Append("</table>");
                }
            }

            // Досье
            if (_lastSpy != null)
            {
                h.Append(L.T("<h2>Досье: кто включал камеру, микрофон и геолокацию</h2>"));
                h.Append(L.T("<table><tr><th>Программа</th><th>Датчик</th><th>Когда</th><th>Длительность</th></tr>"));
                foreach (object co in Json.GetArr(_lastSpy, "caps"))
                {
                    Dictionary<string, object> c = Json.Obj(co);
                    string capTitle = Json.GetStr(c, "title");
                    int n = 0;
                    foreach (object io in Json.GetArr(c, "items"))
                    {
                        if (n++ >= 8) break;
                        Dictionary<string, object> it = Json.Obj(io);
                        double mins = 0;
                        object mv = Json.Get(it, "minutes");
                        if (mv != null) double.TryParse(mv.ToString().Replace(',', '.'), NumberStyles.Any, CultureInfo.InvariantCulture, out mins);
                        h.Append("<tr><td>").Append(Esc(Json.GetStr(it, "app"))).Append("</td><td>").Append(Esc(capTitle))
                         .Append("</td><td>").Append(Esc(Json.GetStr(it, "last"))).Append("</td><td>")
                         .Append(Json.GetBool(it, "active") ? L.T("<span class=\"bad\">прямо сейчас</span>") : Esc(Dur(mins)))
                         .Append("</td></tr>");
                    }
                }
                h.Append("</table>");
            }
            if (_lastFoot != null)
            {
                h.Append(L.T("<h2>Цифровой след на диске</h2>"));
                h.Append(L.T("<table><tr><th>Что хранится</th><th>Сколько</th></tr>"));
                foreach (object o in Json.GetArr(_lastFoot, "items"))
                {
                    Dictionary<string, object> it = Json.Obj(o);
                    h.Append("<tr><td>").Append(Esc(Json.GetStr(it, "title"))).Append("</td><td>")
                     .Append(Esc(Json.GetStr(it, "value"))).Append("</td></tr>");
                }
                h.Append("</table>");
            }

            h.Append(L.T("<div class=\"note\"><b>Честно о пределах.</b> Полностью прекратить обмен данными с Microsoft "));
            h.Append(L.T("на Windows нельзя: остаются проверка обновлений, активация лицензии и проверка сертификатов. "));
            h.Append(L.T("На редакциях Home и Pro минимальный уровень телеметрии система трактует как «Обязательные данные» — "));
            h.Append(L.T("это ограничение редакции, а не программы.</div>"));
            h.Append(L.T("<footer>Отчёт сформирован программой «Приватность Windows 11». "));
            h.Append(L.T("Данные получены из реестра, служб, планировщика, кэша DNS, журнала брандмауэра "));
            h.Append(L.T("и встроенного механизма диагностики Windows.</footer></body></html>"));
            return h.ToString();
        }

        private static string FormatBig(int n)
        {
            if (n >= 1000000) return (n / 1000000.0).ToString("0.#") + L.T(" млн");
            if (n >= 1000) return (n / 1000.0).ToString("0.#") + L.T(" тыс");
            return n.ToString();
        }

        // ================================================================== //
        //  Страница: Проверка
        // ================================================================== //
        private Control BuildAuditPage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 3;
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            TableLayoutPanel head = new TableLayoutPanel();
            head.ColumnCount = 2; head.Dock = DockStyle.Fill; head.AutoSize = true;
            head.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            head.Controls.Add(PageTitle(L.T("Проверка на деле")), 0, 0);
            ModernButton rerun = new ModernButton(L.T("Проверить сейчас"), true); rerun.Font = new Font(Font, FontStyle.Bold);
            rerun.Anchor = AnchorStyles.Right | AnchorStyles.Bottom;
            rerun.Click += delegate { RunAudit(); };
            head.Controls.Add(rerun, 1, 0);
            page.Controls.Add(head, 0, 0);

            // верх: кольцо + плитки
            TableLayoutPanel top = new TableLayoutPanel();
            top.ColumnCount = 2; top.RowCount = 1; top.Dock = DockStyle.Fill; top.AutoSize = true;
            top.Margin = new Padding(0, (int)(u * 0.5F), 0, (int)(u * 0.5F));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));

            Card ringCard = new Card();
            ringCard.Size = new Size((int)(u * 6.9F), (int)(u * 6.9F));
            ringCard.Margin = new Padding(0, 0, (int)(u * 0.7F), 0);
            _ring = new IndexRing(); _ring.Font = Font; _ring.Dock = DockStyle.Fill; _ring.Margin = new Padding((int)(u*0.35F));
            ringCard.Controls.Add(_ring);
            top.Controls.Add(ringCard, 0, 0);

            Panel rightTop = new Panel(); rightTop.Dock = DockStyle.Fill; rightTop.Height = (int)(u * 6.9F);
            _auditHint = new Label();
            _auditHint.Dock = DockStyle.Bottom; _auditHint.AutoSize = false; _auditHint.Height = (int)(u * 3F);
            _auditHint.ForeColor = Theme.TextDim;
            _auditHint.Text = L.T("Нажмите «Проверить сейчас» — программа прочитает реальное состояние системы\nи покажет, что сработало, а что нет.");
            rightTop.Controls.Add(_auditHint);
            _auditTiles = new TileGrid();
            _auditTiles.Dock = DockStyle.Fill; _auditTiles.Font = Font; _auditTiles.MaxCols = 4;
            _auditTiles.MinTileWidthU = 11.5F; _auditTiles.TileHeightU = 5.6F;
            rightTop.Controls.Add(_auditTiles);
            _auditTiles.BringToFront();
            top.Controls.Add(rightTop, 1, 0);
            page.Controls.Add(top, 0, 1);

            // низ: разбивка по модулям
            Card listCard = new Card();
            listCard.Dock = DockStyle.Fill;
            listCard.Padding = new Padding((int)(u * 0.5F));
            listCard.Margin = new Padding(0, 0, 0, (int)(u * 0.3F));
            _auditGroups = new StackPanel();
            _auditGroups.Dock = DockStyle.Fill; _auditGroups.Font = Font;
            _auditGroups.Padding = new Padding((int)(u * 0.3F));
            Dwm.DarkScrollbars(_auditGroups);
            _auditWhen = new Label();
            _auditWhen.Dock = DockStyle.Top; _auditWhen.AutoSize = false; _auditWhen.Height = (int)(u * 1.8F);
            _auditWhen.ForeColor = Theme.TextFaint; _auditWhen.TextAlign = ContentAlignment.MiddleLeft;
            _auditWhen.Padding = new Padding((int)(u * 0.4F), 0, 0, 0);
            listCard.Controls.Add(_auditGroups);
            listCard.Controls.Add(_auditWhen);
            page.Controls.Add(listCard, 0, 2);
            return page;
        }

        // ================================================================== //
        //  Страница: Монитор
        // ================================================================== //
        private Control BuildMonitorPage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 4;
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            page.Controls.Add(PageTitle(L.T("Монитор утечек")), 0, 0);

            Card ctl = new Card();
            ctl.Dock = DockStyle.Fill; ctl.Margin = new Padding(0, (int)(u*0.5F), 0, (int)(u*0.5F));
            ctl.Padding = new Padding((int)(u * 0.8F), (int)(u * 0.6F), (int)(u * 0.8F), (int)(u * 0.6F));
            TableLayoutPanel ctlIn = new TableLayoutPanel();
            ctlIn.Dock = DockStyle.Fill; ctlIn.AutoSize = true; ctlIn.ColumnCount = 2; ctlIn.RowCount = 1;
            ctlIn.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            ctlIn.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            _monitorState = new Label();
            _monitorState.AutoSize = false; _monitorState.Dock = DockStyle.Fill;
            _monitorState.TextAlign = ContentAlignment.MiddleLeft; _monitorState.ForeColor = Theme.TextDim;
            _monitorState.Text = L.T("Монитор фиксирует попытки программ отправить данные наружу и показывает,\nкто и куда стучится. Использует брандмауэр и журнал безопасности Windows.");
            ctlIn.Controls.Add(_monitorState, 0, 0);
            FlowLayoutPanel mb = new FlowLayoutPanel(); mb.AutoSize = true; mb.WrapContents = false; mb.Anchor = AnchorStyles.Right;
            _monitorToggle = new ModernButton(L.T("Включить монитор"), true); _monitorToggle.Font = new Font(Font, FontStyle.Bold);
            _monitorToggle.Click += OnMonitorToggle;
            ModernButton refresh = new ModernButton(L.T("Обновить"), false); refresh.Click += delegate { RefreshMonitor(); };
            refresh.Margin = new Padding((int)(u*0.5F),0,0,0);
            mb.Controls.Add(_monitorToggle); mb.Controls.Add(refresh);
            ctlIn.Controls.Add(mb, 1, 0);
            ctl.Controls.Add(ctlIn);
            page.Controls.Add(ctl, 0, 1);

            _monitorTiles = new TileGrid();
            _monitorTiles.Dock = DockStyle.Fill; _monitorTiles.AutoSize = true; _monitorTiles.Font = Font;
            _monitorTiles.Margin = new Padding(0, 0, 0, (int)(u*0.4F));
            page.Controls.Add(_monitorTiles, 0, 2);

            Card listCard = new Card(); listCard.Dock = DockStyle.Fill; listCard.Padding = new Padding((int)(u*0.5F));
            listCard.Margin = new Padding(0, 0, 0, (int)(u*0.3F));
            _monitorList = new StackPanel(); _monitorList.Dock = DockStyle.Fill; _monitorList.Font = Font;
            _monitorList.Padding = new Padding((int)(u*0.3F));
            Dwm.DarkScrollbars(_monitorList);
            listCard.Controls.Add(_monitorList);
            page.Controls.Add(listCard, 0, 3);
            return page;
        }

        // ================================================================== //
        //  Страница: Приложения — удаление предустановленного
        // ================================================================== //
        private Control BuildAppsPage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 3;
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Absolute, (int)(u * 7.6F)));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            page.Controls.Add(PageTitle(L.T("Предустановленные приложения")), 0, 0);

            Card ctl = new Card();
            ctl.Dock = DockStyle.Fill;
            ctl.Margin = new Padding(0, (int)(u * 0.5F), 0, (int)(u * 0.5F));
            ctl.Padding = new Padding((int)(u * 0.9F), (int)(u * 0.7F), (int)(u * 0.9F), (int)(u * 0.7F));
            TableLayoutPanel ci = new TableLayoutPanel();
            ci.Dock = DockStyle.Fill; ci.AutoSize = true; ci.ColumnCount = 1; ci.RowCount = 2;
            ci.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            ci.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            ci.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            _appsState = new Label();
            _appsState.AutoSize = false; _appsState.Dock = DockStyle.Fill;
            _appsState.TextAlign = ContentAlignment.MiddleLeft; _appsState.ForeColor = Theme.TextDim;
            _appsState.Text = L.T("Приложения, которые Windows ставит без спроса. Отмеченные «можно убрать» —\n") +
                              L.T("проверенный список; системные компоненты в перечень не попадают вовсе.");
            ci.Controls.Add(_appsState, 0, 0);
            FlowLayoutPanel ab = new FlowLayoutPanel();
            AttachButtonRow(ab, ctl);
            ab.Margin = new Padding(0, (int)(u * 0.5F), 0, 0);
            _btnAppsRefresh = new ModernButton(L.T("Обновить список"), false);
            _btnAppsRefresh.Click += delegate { RefreshApps(); };
            ModernButton pickBloat = new ModernButton(L.T("Отметить лишнее"), false);
            pickBloat.Click += delegate { SelectBloat(); };
            _btnAppsRemove = new ModernButton(L.T("Удалить выбранные"), true);
            _btnAppsRemove.Click += OnRemoveApps;
            foreach (ModernButton b in new[] { _btnAppsRefresh, pickBloat, _btnAppsRemove })
            { b.Font = b.Primary ? new Font(Font, FontStyle.Bold) : Font; b.Margin = new Padding((int)(u * 0.4F), 0, 0, (int)(u * 0.3F)); ab.Controls.Add(b); }
            ci.Controls.Add(ab, 0, 1);
            ctl.Controls.Add(ci);
            page.Controls.Add(ctl, 0, 1);

            Card list = new Card();
            list.Dock = DockStyle.Fill; list.Padding = new Padding((int)(u * 0.6F));
            list.Margin = new Padding(0, 0, 0, (int)(u * 0.3F));
            _appsList = new StackPanel();
            _appsList.Dock = DockStyle.Fill; _appsList.Font = Font;
            _appsList.Padding = new Padding((int)(u * 0.4F));
            Dwm.DarkScrollbars(_appsList);
            list.Controls.Add(_appsList);
            page.Controls.Add(list, 0, 2);
            return page;
        }

        private void RefreshApps()
        {
            RunJson("-ListApps", L.T("Чтение списка приложений…"), delegate(Dictionary<string, object> d)
            {
                RenderApps(d);
            });
        }

        private void RenderApps(Dictionary<string, object> d)
        {
            {
                _appsList.Controls.Clear();
                if (d == null)
                {
                    SectionHeader sh = new SectionHeader(L.T("Не удалось получить список")); sh.Font = Font;
                    _appsList.Controls.Add(sh); _appsList.Restack(); return;
                }
                _lastApps = d;
                List<object> apps = Json.GetArr(d, "apps");
                int bloat = 0;
                bool headBloat = false, headRest = false;
                foreach (object o in apps)
                {
                    Dictionary<string, object> a = Json.Obj(o);
                    bool isBloat = Json.GetBool(a, "bloat");
                    if (isBloat && !headBloat)
                    {
                        SectionHeader sh = new SectionHeader(L.T("Можно убрать — ставится без спроса"));
                        sh.Font = Font; _appsList.Controls.Add(sh); headBloat = true;
                    }
                    if (!isBloat && !headRest)
                    {
                        SectionHeader sh = new SectionHeader(L.T("Остальное — удаляйте, только если знаете, что это"));
                        sh.Font = Font; _appsList.Controls.Add(sh); headRest = true;
                    }
                    if (isBloat) bloat++;
                    WipeRow r = new WipeRow(Json.GetStr(a, "name"), L.T(Json.GetStr(a, "title")),
                        Json.GetStr(a, "name") + "   ·   " + Json.GetStr(a, "publisher"),
                        isBloat ? L.T("можно убрать") : "", GApp, true);
                    r.Font = Font;
                    _appsList.Controls.Add(r);
                }
                _appsList.Restack();
                _appsState.Text = L.T("Найдено приложений: ") + apps.Count + L.T(", из них лишних: ") + bloat + ".\n" +
                                  L.T("Любое удалённое можно вернуть из Microsoft Store.");
            }
        }

        private void SelectBloat()
        {
            // сравниваем с полным заголовком раздела: сравнение по первому слову
            // держалось на отдельной записи в словаре и молча ломалось от правки
            string head = L.T("Можно убрать — ставится без спроса").ToUpperInvariant();
            bool inBloat = false;
            foreach (Control c in _appsList.Controls)
            {
                SectionHeader sh = c as SectionHeader;
                if (sh != null) { inBloat = (sh.Text == head); continue; }
                WipeRow r = c as WipeRow;
                if (r != null) r.Checked = inBloat;
            }
            _appsList.Invalidate(true);
        }

        private void OnRemoveApps(object sender, EventArgs e)
        {
            List<string> ids = new List<string>();
            foreach (Control c in _appsList.Controls)
            {
                WipeRow r = c as WipeRow;
                if (r != null && r.Checked) ids.Add(r.Id);
            }
            if (ids.Count == 0)
            { MessageBox.Show(this, L.T("Отметьте галочками, какие приложения удалить."), L.T("Ничего не выбрано"), MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            if (MessageBox.Show(this, L.T("Будет удалено приложений: ") + ids.Count + ".\n\n" +
                L.T("Любое из них можно вернуть из Microsoft Store. Системные компоненты\n") +
                L.T("программа не трогает.\n\nПродолжить?"),
                L.T("Удаление приложений"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming("-RemoveApps -AppItems " + string.Join(",", ids.ToArray()) + " -AllUsers",
                L.T("Удаление приложений…"), delegate { Navigate("apps"); RefreshApps(); });
        }

        // ================================================================== //
        //  Страница: Автозапуск
        //  Что стартует вместе с Windows. Отключается ровно так же, как в
        //  диспетчере задач — отметкой, а не удалением: включить обратно
        //  можно той же кнопкой, и всё это попадает в журнал отката.
        // ================================================================== //
        private Control BuildStartupPage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 3;
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Absolute, (int)(u * 7.6F)));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            page.Controls.Add(PageTitle(L.T("Что стартует вместе с Windows")), 0, 0);

            Card ctl = new Card();
            ctl.Dock = DockStyle.Fill;
            ctl.Margin = new Padding(0, (int)(u * 0.5F), 0, (int)(u * 0.5F));
            ctl.Padding = new Padding((int)(u * 0.9F), (int)(u * 0.7F), (int)(u * 0.9F), (int)(u * 0.7F));
            TableLayoutPanel ci = new TableLayoutPanel();
            ci.Dock = DockStyle.Fill; ci.AutoSize = true; ci.ColumnCount = 1; ci.RowCount = 2;
            ci.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            ci.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            ci.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            _startupState = new Label();
            _startupState.AutoSize = false; _startupState.Dock = DockStyle.Fill;
            _startupState.TextAlign = ContentAlignment.MiddleLeft; _startupState.ForeColor = Theme.TextDim;
            _startupState.Text = L.T("Обновляторы, агенты телеметрии и помощники производителя запускаются при\n") +
                                 L.T("каждом входе. Отключение обратимо: запись остаётся на месте, просто гасится.");
            ci.Controls.Add(_startupState, 0, 0);
            FlowLayoutPanel sb = new FlowLayoutPanel();
            AttachButtonRow(sb, ctl);
            sb.Margin = new Padding(0, (int)(u * 0.5F), 0, 0);
            ModernButton refresh = new ModernButton(L.T("Обновить список"), false);
            refresh.Click += delegate { RefreshStartup(); };
            ModernButton pick = new ModernButton(L.T("Отметить лишнее"), false);
            pick.Click += delegate { SelectStartupBloat(); };
            _btnStartupOff = new ModernButton(L.T("Отключить выбранные"), true);
            _btnStartupOff.Click += delegate { SetStartupSelected(false); };
            _btnStartupOn = new ModernButton(L.T("Вернуть выбранные"), false);
            _btnStartupOn.Click += delegate { SetStartupSelected(true); };
            foreach (ModernButton b in new[] { refresh, pick, _btnStartupOff, _btnStartupOn })
            { b.Font = b.Primary ? new Font(Font, FontStyle.Bold) : Font; b.Margin = new Padding((int)(u * 0.4F), 0, 0, (int)(u * 0.3F)); sb.Controls.Add(b); }
            ci.Controls.Add(sb, 0, 1);
            ctl.Controls.Add(ci);
            page.Controls.Add(ctl, 0, 1);

            Card list = new Card();
            list.Dock = DockStyle.Fill; list.Padding = new Padding((int)(u * 0.6F));
            list.Margin = new Padding(0, 0, 0, (int)(u * 0.3F));
            _startupList = new StackPanel();
            _startupList.Dock = DockStyle.Fill; _startupList.Font = Font;
            _startupList.Padding = new Padding((int)(u * 0.4F));
            Dwm.DarkScrollbars(_startupList);
            list.Controls.Add(_startupList);
            page.Controls.Add(list, 0, 2);
            return page;
        }

        private void RefreshStartup()
        {
            RunJson("-ListStartup", L.T("Чтение автозагрузки…"), delegate(Dictionary<string, object> d)
            {
                RenderStartup(d);
            });
        }

        private void RenderStartup(Dictionary<string, object> d)
        {
            _lastStartup = d;
            _startupList.Controls.Clear();
            if (d == null)
            {
                SectionHeader sh = new SectionHeader(L.T("Не удалось прочитать автозагрузку")); sh.Font = Font;
                _startupList.Controls.Add(sh); _startupList.Restack(); return;
            }
            List<object> items = Json.GetArr(d, "items");
            // три группы: лишнее, остальное работающее, уже погашенное
            string[] heads = new string[] {
                L.T("Стартует без нужды — можно отключить"),
                L.T("Остальное — отключайте, только если знаете, что это"),
                L.T("Уже отключено")
            };
            for (int pass = 0; pass < 3; pass++)
            {
                bool head = false;
                foreach (object o in items)
                {
                    Dictionary<string, object> a = Json.Obj(o);
                    bool on = Json.GetBool(a, "enabled");
                    bool advise = Json.GetBool(a, "advise");
                    int group = !on ? 2 : (advise ? 0 : 1);
                    if (group != pass) continue;
                    if (!head)
                    {
                        SectionHeader sh = new SectionHeader(heads[pass]);
                        sh.Font = Font; _startupList.Controls.Add(sh); head = true;
                    }
                    string name = Json.GetStr(a, "name");
                    string pub = Json.GetStr(a, "publisher");
                    string note = L.T(Json.GetStr(a, "note"));
                    string cmd = Json.GetStr(a, "cmd");
                    string what = (note.Length > 0 ? note : cmd);
                    if (what.Length == 0) what = cmd;
                    string chip = !on ? L.T("отключено")
                                : (Json.GetBool(a, "keep") ? L.T("лучше не трогать") : (advise ? L.T("лишнее") : ""));
                    WipeRow r = new WipeRow(Json.GetStr(a, "id"),
                        pub.Length > 0 ? name + "   ·   " + pub : name,
                        what + "   ·   " + L.T(Json.GetStr(a, "source")),
                        chip, GPower, true);
                    r.Font = Font;
                    _startupList.Controls.Add(r);
                }
            }
            _startupList.Restack();
            int total = Json.GetInt(d, "total"), onCount = Json.GetInt(d, "on"), bad = Json.GetInt(d, "advise");
            _startupState.Text = L.T("Записей автозапуска: ") + total + L.T(", работает: ") + onCount +
                                 L.T(", лишних: ") + bad + ".\n" +
                                 L.T("Отключённое возвращается кнопкой «Вернуть выбранные» или общим откатом.");
        }

        private void SelectStartupBloat()
        {
            // разделов может не быть вовсе, поэтому ищем по названию, а не по счёту
            string head = L.T("Стартует без нужды — можно отключить").ToUpperInvariant();
            bool inBloat = false;
            foreach (Control c in _startupList.Controls)
            {
                SectionHeader sh = c as SectionHeader;
                if (sh != null) { inBloat = (sh.Text == head); continue; }
                WipeRow r = c as WipeRow;
                if (r != null) r.Checked = inBloat;
            }
            _startupList.Invalidate(true);
        }

        private void SetStartupSelected(bool on)
        {
            List<string> ids = new List<string>();
            foreach (Control c in _startupList.Controls)
            {
                WipeRow r = c as WipeRow;
                if (r != null && r.Checked) ids.Add(r.Id);
            }
            if (ids.Count == 0)
            {
                MessageBox.Show(this, L.T("Отметьте галочками, какие записи менять."), L.T("Ничего не выбрано"),
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            if (!on && MessageBox.Show(this, L.T("Будет отключено записей автозапуска: ") + ids.Count + ".\n\n" +
                L.T("Сами программы остаются на месте — они просто перестанут\n") +
                L.T("запускаться при входе. Вернуть можно этой же страницей.\n\nПродолжить?"),
                L.T("Отключение автозапуска"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming("-StartupSet -StartupValue " + (on ? "On" : "Off") + " -StartupItems \"" + string.Join(",", ids.ToArray()) + "\"",
                on ? L.T("Возврат автозапуска…") : L.T("Отключение автозапуска…"),
                delegate { Navigate("startup"); RefreshStartup(); });
        }

        // ================================================================== //
        //  Страница: Страж
        // ================================================================== //
        private Control BuildGuardPage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 3;
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            page.RowStyles[1] = new RowStyle(SizeType.Absolute, (int)(u * 7.6F));
            page.Controls.Add(PageTitle(L.T("Страж приватности")), 0, 0);

            Card intro = new Card();
            intro.Dock = DockStyle.Fill; intro.Margin = new Padding(0,(int)(u*0.5F),0,(int)(u*0.5F));
            intro.Padding = new Padding((int)(u*0.9F),(int)(u*0.7F),(int)(u*0.9F),(int)(u*0.7F));
            TableLayoutPanel ii = new TableLayoutPanel(); ii.Dock = DockStyle.Fill; ii.AutoSize = true;
            ii.ColumnCount = 1; ii.RowCount = 2;
            ii.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            ii.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            ii.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            _guardState = new Label(); _guardState.AutoSize = false; _guardState.Dock = DockStyle.Fill;
            _guardState.TextAlign = ContentAlignment.MiddleLeft; _guardState.ForeColor = Theme.TextDim;
            _guardState.Text = L.T("Крупные обновления Windows тихо возвращают часть настроек назад.\n") +
                              L.T("Страж проверяет систему по расписанию, возвращает сбитое и предупреждает.");
            ii.Controls.Add(_guardState, 0, 0);
            FlowLayoutPanel gb = new FlowLayoutPanel(); gb.AutoSize = true; gb.FlowDirection = FlowDirection.LeftToRight;
            AttachButtonRow(gb, intro);
            gb.Margin = new Padding(0, (int)(u * 0.5F), 0, 0);
            _btnGuardInstall = new ModernButton(L.T("Включить стража"), true); _btnGuardInstall.Font = new Font(Font, FontStyle.Bold);
            _btnGuardInstall.Click += OnGuardInstall;
            _btnGuardNow = new ModernButton(L.T("Проверить"), false); _btnGuardNow.Click += OnGuardNow;
            _btnGuardRemove = new ModernButton(L.T("Отключить"), false); _btnGuardRemove.Click += OnGuardRemove;
            _btnWatcher = new ModernButton(L.T("Уведомления"), false); _btnWatcher.Click += OnWatcherToggle;
            _btnSensorGuard = new ModernButton(L.T("Датчики"), false); _btnSensorGuard.Click += OnSensorToggle;
            _btnSnapshot = new ModernButton(L.T("Снимок"), false); _btnSnapshot.Click += OnSnapshot;
            foreach (ModernButton b in new[] { _btnGuardInstall, _btnGuardNow, _btnGuardRemove, _btnWatcher, _btnSensorGuard, _btnSnapshot })
            { b.Font = b.Primary ? new Font(Font, FontStyle.Bold) : Font; b.Margin = new Padding((int)(u*0.4F),0,0,(int)(u*0.3F)); gb.Controls.Add(b); }
            ii.Controls.Add(gb, 0, 1);
            intro.Controls.Add(ii);
            page.Controls.Add(intro, 0, 1);

            Card body = new Card(); body.Dock = DockStyle.Fill; body.Padding = new Padding((int)(u*0.6F));
            body.Margin = new Padding(0,0,0,(int)(u*0.3F));
            _guardBody = new StackPanel(); _guardBody.Dock = DockStyle.Fill; _guardBody.Font = Font;
            _guardBody.Padding = new Padding((int)(u*0.4F));
            Dwm.DarkScrollbars(_guardBody);
            body.Controls.Add(_guardBody);
            page.Controls.Add(body, 0, 2);
            return page;
        }
        private ModernButton _btnGuardInstall, _btnGuardNow, _btnGuardRemove, _btnWatcher, _btnSensorGuard, _btnSnapshot;
        private bool _watcherOn, _sensorOn;

        // ================================================================== //
        //  Страница: Журнал
        // ================================================================== //
        private Control BuildLogPage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 2;
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            page.Controls.Add(PageTitle(L.T("Журнал выполнения")), 0, 0);

            Card card = new Card(); card.Dock = DockStyle.Fill; card.Padding = new Padding((int)(u*0.6F));
            card.Margin = new Padding(0,(int)(u*0.5F),0,(int)(u*0.3F));
            _log = new RichTextBox();
            _log.Dock = DockStyle.Fill; _log.ReadOnly = true; _log.BorderStyle = BorderStyle.None;
            _log.BackColor = Theme.LogBg; _log.ForeColor = Theme.TextDim;
            _log.Font = Theme.PickFont(Theme.MonoFonts, Font.Size * 0.95F, FontStyle.Regular);
            _log.WordWrap = true; _log.ScrollBars = RichTextBoxScrollBars.Vertical; _log.DetectUrls = false;
            Dwm.DarkScrollbars(_log);
            card.Controls.Add(_log);
            page.Controls.Add(card, 0, 1);
            LogLine(L.T("Здесь появляется подробный вывод при применении настроек, откате,"), Theme.TextDim);
            LogLine(L.T("работе стража и монитора."), Theme.TextDim);
            return page;
        }

        // ================================================================== //
        //  Страница: О программе
        // ================================================================== //
        private Control BuildAboutPage()
        {
            int u = Font.Height;
            Panel page = new Panel(); page.BackColor = Theme.WindowBg; page.AutoScroll = true;
            FlowLayoutPanel f = new FlowLayoutPanel();
            f.FlowDirection = FlowDirection.TopDown; f.WrapContents = false; f.AutoSize = true;
            f.Dock = DockStyle.Top; f.Padding = new Padding(0);
            TableLayoutPanel aboutHead = new TableLayoutPanel();
            aboutHead.ColumnCount = 2; aboutHead.RowCount = 1; aboutHead.AutoSize = true;
            aboutHead.BackColor = Theme.WindowBg;
            aboutHead.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            aboutHead.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            aboutHead.Controls.Add(PageTitle(L.T("О программе")), 0, 0);
            ModernButton bLang = new ModernButton(L.English ? "Русский" : "English", false);
            bLang.Font = Font;
            bLang.Anchor = AnchorStyles.Left | AnchorStyles.Bottom;
            bLang.Margin = new Padding((int)(u * 1.2F), 0, 0, (int)(u * 0.5F));
            bLang.Click += delegate
            {
                L.English = !L.English;
                SaveUiState();
                MessageBox.Show(this,
                    L.English ? "The language will change after restarting the program."
                              : "Язык интерфейса сменится после перезапуска программы.",
                    L.T("Приватность Windows 11"), MessageBoxButtons.OK, MessageBoxIcon.Information);
                bLang.Text = L.English ? "Русский" : "English";
            };
            aboutHead.Controls.Add(bLang, 1, 0);
            f.Controls.Add(aboutHead);

            _aboutEdition = AboutCard(L.T("Ваша система"), L.T("Определение…"));
            f.Controls.Add(_aboutEdition);

            f.Controls.Add(AboutCard(L.T("Что умеет эта программа, чего нет у других"),
                L.T("• Досье: кто и когда реально включал камеру, микрофон и геолокацию — с длительностью и меткой «сейчас».\n") +
                L.T("• Слежение за датчиками: уведомление в момент, когда НОВАЯ программа впервые получила доступ; график по дням.\n") +
                L.T("• Цифровой след: рекламный ID, история сетей и флешек, всё, что Windows помнит о вас — с выборочным стиранием.\n") +
                L.T("• Рентген телеметрии: настоящие события, собранные о компьютере, с сырым содержимым.\n") +
                L.T("• Проверка на деле: читает реальное состояние системы и показывает индекс, а не «галочки».\n") +
                L.T("• Монитор утечек: показывает, кто и куда реально отправляет данные.\n") +
                L.T("• Страж: возвращает настройки, сбитые обновлениями Windows; машина времени со снимками состояния.\n") +
                L.T("• Телеметрия сторонних программ и слежка производителя ноутбука.\n") +
                L.T("• Блокировка через брандмауэр, а не только hosts; удаление накопленного буфера телеметрии.\n") +
                L.T("• Профили и тихий запуск из командной строки для настройки нескольких ПК.\n") +
                L.T("• Быстрые клавиши: Ctrl+1…9 и Ctrl+0 — страницы, Ctrl+F — поиск по настройкам.")));

            f.Controls.Add(AboutCard(L.T("Командная строка"),
                L.T("Win11Privacy.exe --profile \"C:\\путь\\profile.json\" --silent   тихо применить профиль\n") +
                L.T("Win11Privacy.exe --audit                                        проверка (код возврата = число несоответствий)\n") +
                L.T("Профиль сохраняется кнопкой «Сохранить профиль» на странице «Настройки».")));

            f.Controls.Add(AboutCard(L.T("Честно о пределах"),
                L.T("Полностью прекратить обмен данными с Microsoft на Windows нельзя: остаются проверка обновлений,\n") +
                L.T("активация лицензии и проверка сертификатов. На редакциях Home и Pro минимальный уровень телеметрии\n") +
                L.T("система трактует как «Обязательные данные» — это ограничение редакции, а не программы. Всё, что можно\n") +
                L.T("отключить без поломки системы, эта программа отключает, а Страж не даёт вернуть обратно.")));

            f.Controls.Add(AboutCard(L.T("Запуск без предупреждения SmartScreen"),
                L.T("Синее окно показывается любому неподписанному приложению из интернета. Убрать его можно так:\n") +
                L.T("правый клик по файлу → Свойства → внизу галочка «Разблокировать» → ОК. Запрос прав администратора\n") +
                L.T("(UAC) остаётся — он нужен, потому что программа меняет системные настройки.")));
            page.Controls.Add(f);
            return page;
        }
        private Control _aboutEdition;

        private Control AboutCard(string title, string body)
        {
            int u = Font.Height;
            int cardW = (int)(u * 54F);
            int padX = (int)(u * 0.9F);
            Card c = new Card();
            c.Width = cardW;
            c.Margin = new Padding(0, 0, 0, (int)(u * 0.6F));
            c.Padding = new Padding(padX, (int)(u * 0.7F), padX, (int)(u * 0.7F));

            TableLayoutPanel tl = new TableLayoutPanel();
            tl.Dock = DockStyle.Top; tl.AutoSize = true; tl.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            tl.ColumnCount = 1; tl.RowCount = 2; tl.BackColor = Theme.CardBg;
            tl.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            tl.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            tl.RowStyles.Add(new RowStyle(SizeType.AutoSize));

            Label t = new Label(); t.Text = title; t.Font = new Font(Font, FontStyle.Bold); t.ForeColor = Theme.Text;
            t.AutoSize = true; t.Margin = new Padding(0, 0, 0, (int)(u * 0.4F));
            Label b = new Label(); b.Text = body; b.ForeColor = Theme.TextDim; b.AutoSize = true;
            b.MaximumSize = new Size(cardW - padX * 2, 0); b.Tag = "body";
            tl.Controls.Add(t, 0, 0); tl.Controls.Add(b, 0, 1);
            c.Controls.Add(tl);
            c.Height = tl.PreferredSize.Height + (int)(u * 1.4F);
            return c;
        }
        private void SetAboutBody(Control card, string text)
        {
            foreach (Control c in card.Controls)   // c = TableLayoutPanel
            {
                foreach (Control cc in c.Controls)
                    if (cc is Label && (string)cc.Tag == "body") cc.Text = text;
                card.Height = c.PreferredSize.Height + (int)(Font.Height * 1.4F);
            }
        }

        // ================================================================== //
        //  Общие элементы
        // ================================================================== //
        private Label PageTitle(string text)
        {
            Label l = new Label();
            l.Text = text;
            l.Font = Theme.PickFont(new[] { "Segoe UI Variable Display", "Segoe UI", "Tahoma" }, Font.Size * 1.6F, FontStyle.Bold);
            l.ForeColor = Theme.Text; l.AutoSize = true; l.Margin = new Padding(0,0,0,(int)(Font.Height*0.3F));
            return l;
        }

        private ModernButton Ghost(string text)
        { ModernButton b = new ModernButton(text, false); b.Ghost = true; b.Font = Font; b.Margin = new Padding(0,0,(int)(Font.Height*0.2F),0); return b; }

        private Control BuildStatusBar()
        {
            int u = Font.Height;
            Panel bar = new Panel(); bar.Dock = DockStyle.Fill; bar.Height = (int)(u * 2.6F);
            bar.BackColor = Theme.Dark ? Theme.Mix(Theme.WindowBg, Color.Black, 0.15F) : Theme.CardBg;
            Panel line = new Panel(); line.Dock = DockStyle.Top; line.Height = 1; line.BackColor = Theme.CardBorder; bar.Controls.Add(line);

            _progress = new ProgressBar();
            _progress.Style = ProgressBarStyle.Marquee; _progress.MarqueeAnimationSpeed = 25;
            _progress.Size = new Size((int)(u * 9F), (int)(u * 0.5F));
            _progress.Location = new Point((int)(u * 1.2F), (int)(u * 1.0F));
            _progress.Visible = false; bar.Controls.Add(_progress);

            _status = new Label();
            _status.Text = L.T("Готово к работе."); _status.ForeColor = Theme.TextDim; _status.AutoSize = true;
            _status.Location = new Point((int)(u * 1.2F), (int)(u * 0.75F)); bar.Controls.Add(_status);
            bar.Resize += delegate {
                _progress.Location = new Point((int)(u * 1.2F), (bar.Height - _progress.Height)/2 + 1);
                _status.Location = new Point(_progress.Visible ? (int)(u * 11F) : (int)(u * 1.2F), (bar.Height - _status.Height)/2);
            };
            return bar;
        }

        // ================================================================== //
        //  Иконка / DWM / запуск
        // ================================================================== //
        private void TryLoadIcon()
        {
            Assembly asm = Assembly.GetExecutingAssembly();
            try { using (Stream s = asm.GetManifestResourceStream("app.png")) { if (s != null) using (Image tmp = Image.FromStream(s)) _appImage = new Bitmap(tmp); } } catch { }
            try { using (Stream s = asm.GetManifestResourceStream("app.ico")) { if (s != null) { _appIcon = new Icon(s); Icon = _appIcon; } } } catch { }
        }

        protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Dwm.Style(Handle, Theme.Dark); }

        // Рамка окна нарисована нами, поэтому изменение размера обрабатываем вручную.
        private const int WM_NCHITTEST = 0x0084;
        private const int HTLEFT = 10, HTRIGHT = 11, HTTOP = 12, HTTOPLEFT = 13, HTTOPRIGHT = 14,
                          HTBOTTOM = 15, HTBOTTOMLEFT = 16, HTBOTTOMRIGHT = 17;

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_NCHITTEST && WindowState == FormWindowState.Normal)
            {
                base.WndProc(ref m);
                int lp = m.LParam.ToInt32();
                Point p = PointToClient(new Point((short)(lp & 0xFFFF), (short)((lp >> 16) & 0xFFFF)));
                int b = 6;
                bool left = p.X <= b, right = p.X >= ClientSize.Width - b;
                bool top = p.Y <= b, bottom = p.Y >= ClientSize.Height - b;
                if (top && left) m.Result = (IntPtr)HTTOPLEFT;
                else if (top && right) m.Result = (IntPtr)HTTOPRIGHT;
                else if (bottom && left) m.Result = (IntPtr)HTBOTTOMLEFT;
                else if (bottom && right) m.Result = (IntPtr)HTBOTTOMRIGHT;
                else if (left) m.Result = (IntPtr)HTLEFT;
                else if (right) m.Result = (IntPtr)HTRIGHT;
                else if (top) m.Result = (IntPtr)HTTOP;
                else if (bottom) m.Result = (IntPtr)HTBOTTOM;
                return;
            }
            base.WndProc(ref m);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            // рамка окна вместо системной
            using (Pen p = new Pen(Theme.CardBorder))
                e.Graphics.DrawRectangle(p, 0, 0, ClientSize.Width - 1, ClientSize.Height - 1);
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            MinimumSize = new Size(Math.Min((int)(Font.Height * 44), Screen.PrimaryScreen.WorkingArea.Width),
                                   Math.Min((int)(Font.Height * 30), Screen.PrimaryScreen.WorkingArea.Height));
            try { MaximizedBounds = Screen.FromControl(this).WorkingArea; } catch { }
            ApplySidebar();
            if (_settingsList != null) _settingsList.Restack();
            UpdateApplyText();
            RunDetect();
        }

        // Развёрнутое окно без рамки не должно накрывать панель задач
        protected override void OnLocationChanged(EventArgs e)
        {
            base.OnLocationChanged(e);
            if (WindowState == FormWindowState.Normal)
                try { MaximizedBounds = Screen.FromControl(this).WorkingArea; } catch { }
        }

        // ================================================================== //
        //  Запоминание размера окна и состояния панели между запусками
        // ================================================================== //
        private static string UiStatePath()
        {
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                                "Win11Privacy", "ui.json");
        }

        // Язык нужен раньше всего: с ним создаются подписи модулей и страниц
        private void LoadLangPref()
        {
#if UITEST
            if (true) return;
#endif
            try
            {
                string p = UiStatePath();
                if (!File.Exists(p)) return;
                Dictionary<string, object> d = Json.ParseObject(File.ReadAllText(p));
                if (d != null && d.ContainsKey("en")) L.English = Json.GetBool(d, "en");
            }
            catch { }
        }

        private void LoadUiState()
        {
#if UITEST
            if (true) return;
#endif
            try
            {
                string p = UiStatePath();
                if (!File.Exists(p)) return;
                Dictionary<string, object> d = Json.ParseObject(File.ReadAllText(p));
                if (d == null) return;
                int w = Json.GetInt(d, "w"), h = Json.GetInt(d, "h");
                Rectangle wa = Screen.PrimaryScreen.WorkingArea;
                if (w >= 600 && h >= 420) ClientSize = new Size(Math.Min(w, wa.Width), Math.Min(h, wa.Height));
                _userCollapsed = Json.GetBool(d, "side");
                if (d.ContainsKey("en")) L.English = Json.GetBool(d, "en");
                if (Json.GetBool(d, "max")) WindowState = FormWindowState.Maximized;
            }
            catch { }
        }

        private void SaveUiState()
        {
#if UITEST
            if (true) return;
#endif
            try
            {
                string p = UiStatePath();
                Directory.CreateDirectory(Path.GetDirectoryName(p));
                Size s = (WindowState == FormWindowState.Normal) ? ClientSize : RestoreBounds.Size;
                string txt = "{ \"w\": " + s.Width + ", \"h\": " + s.Height +
                             ", \"max\": " + (WindowState == FormWindowState.Maximized ? "true" : "false") +
                             ", \"side\": " + (_userCollapsed ? "true" : "false") +
                             ", \"en\": " + (L.English ? "true" : "false") + " }";
                File.WriteAllText(p, txt);
            }
            catch { }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            SaveUiState();
            base.OnFormClosing(e);
        }

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
                                  "ads", "search", "copilot", "ai", "cleanup" };
            string[] strictAdd = { "widgets", "location", "onedrive", "defender", "services", "hosts" };
            int n = 0;
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
                if (k == Keys.F && _search != null) { Navigate("settings"); _search.Focus(); return true; }
            }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        private List<string> SelectedModules()
        {
            List<string> ids = new List<string>();
            foreach (ModuleDef m in _mods) if (m.Row != null && m.Row.Checked) ids.Add(m.Id);
            return ids;
        }

        // ================================================================== //
        //  Журнал
        // ================================================================== //
        private void LogLine(string s, Color c)
        {
            if (_log == null) return;
            _log.SelectionStart = _log.TextLength; _log.SelectionLength = 0; _log.SelectionColor = c;
            _log.AppendText(s + Environment.NewLine); _log.SelectionColor = _log.ForeColor;
        }
        private void LogEngine(string s)
        {
            string t = s.TrimStart();
            if (t.StartsWith("###JSON###")) return;
            Color c = Theme.TextDim;
            if (t.StartsWith("[+]")) c = Theme.Ok;
            else if (t.StartsWith("[!]")) c = Theme.Err;
            else if (t.StartsWith("[-]")) c = Theme.TextFaint;
            else if (t.StartsWith("---")) c = Theme.Accent;
            else if (t.StartsWith(L.T("Система")) || t.StartsWith(L.T("ИТОГО")) || t.StartsWith(L.T("Изменений")) || t.StartsWith(L.T("Ошибок")) || t.StartsWith(L.T("Модули"))) c = Theme.Text;
            LogLine(s, c);
            _log.SelectionStart = _log.TextLength; _log.ScrollToCaret();
        }

        // ================================================================== //
        //  Запуск движка
        // ================================================================== //
        // Движок распаковывается один раз за сеанс и в файл со своим именем:
        // параллельные запуски (проверка, досье, применение) больше не затирают
        // скрипт друг у друга прямо во время чтения.
        private string _enginePath;
        private bool _streamRunning;

        private string ExtractEngine()
        {
            if (_enginePath != null && File.Exists(_enginePath)) return _enginePath;
            string dir = Path.Combine(Path.GetTempPath(), "Win11Privacy");
            Directory.CreateDirectory(dir);
            string path = Path.Combine(dir, "engine-" + Process.GetCurrentProcess().Id + ".ps1");
            Assembly asm = Assembly.GetExecutingAssembly();
            using (Stream src = asm.GetManifestResourceStream("engine.ps1"))
            {
                if (src == null) throw new InvalidOperationException(L.T("встроенный скрипт движка не найден в программе"));
                using (FileStream dst = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.Read))
                { byte[] buf = new byte[8192]; int n; while ((n = src.Read(buf, 0, buf.Length)) > 0) dst.Write(buf, 0, n); }
            }
            long len = 0;
            try { len = new FileInfo(path).Length; } catch { }
            if (len < 1000)
                throw new InvalidOperationException(L.T("не удалось распаковать движок во временную папку:\n") + path +
                                                    L.T("\n\nВозможно, мешает антивирус."));
            _enginePath = path;
            return path;
        }

        // Полный путь к PowerShell — надёжнее, чем расчёт на PATH
        private static string PowerShellExe()
        {
            try
            {
                string full = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                                           "WindowsPowerShell\\v1.0\\powershell.exe");
                if (File.Exists(full)) return full;
            }
            catch { }
            return "powershell.exe";
        }

        private ProcessStartInfo EnginePsi(string extra)
        {
            string script = ExtractEngine();
            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
            string args = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\" " + extra +
                          " -BackupRoot \"" + desktop + "\"";
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = PowerShellExe(); psi.Arguments = args;
            psi.UseShellExecute = false; psi.CreateNoWindow = true;
            psi.WorkingDirectory = Path.GetTempPath();
            psi.RedirectStandardOutput = true; psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = Encoding.UTF8; psi.StandardErrorEncoding = Encoding.UTF8;
            return psi;
        }

        // потоковый запуск (для действий) — вывод в журнал
        private void RunStreaming(string extra, string statusText, Action onDone)
        {
            if (_streamRunning)
            {
                MessageBox.Show(this, L.T("Программа ещё выполняет предыдущую команду.\nДождитесь её завершения."),
                    L.T("Подождите"), MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            SetBusy(true, statusText);
            Navigate("log");
            _log.Clear();
            LogLine(statusText, Theme.Text);
            LogLine(new string('─', 58), Theme.TextFaint);

            Process p = new Process();
            try { p.StartInfo = EnginePsi(extra); }
            catch (Exception ex)
            {
                SetBusy(false, L.T("Ошибка."));
                LogLine(L.T("Не удалось подготовить движок: ") + ex.Message, Theme.Err);
                MessageBox.Show(this, ex.Message, L.T("Ошибка"), MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            LogLine(L.T("Запуск: powershell ") + extra, Theme.TextFaint);
            if (_detect != null && !Json.GetBool(_detect, "admin"))
                LogLine(L.T("ВНИМАНИЕ: программа запущена без прав администратора — изменения применить нельзя."), Theme.Err);

            _streamRunning = true;
            p.EnableRaisingEvents = true;
            DataReceivedEventHandler h = delegate(object s, DataReceivedEventArgs e)
            {
                if (e.Data == null) return;
                string line = e.Data;
                if (line.Trim() == "###DONE###") return;
                try { BeginInvoke((MethodInvoker)delegate { LogEngine(line); }); } catch { }
            };
            p.OutputDataReceived += h; p.ErrorDataReceived += h;
            p.Exited += delegate
            {
                int code = -1;
                try { p.WaitForExit(); code = p.ExitCode; } catch { }
                try
                {
                    BeginInvoke((MethodInvoker)delegate
                    {
                        _streamRunning = false;
                        SetBusy(false, code == 0 ? L.T("Готово.") : L.T("Завершено с ошибкой."));
                        LogLine(new string('─', 58), Theme.TextFaint);
                        if (code == 0) LogLine(L.T("Готово."), Theme.Text);
                        else
                        {
                            LogLine(L.T("PowerShell завершился с кодом ") + code + ".", Theme.Err);
                            LogLine(L.T("Если выше нет строк движка — его блокирует антивирус или не хватает прав."), Theme.TextDim);
                        }
                        if (onDone != null) onDone();
                    });
                }
                catch { }
            };
            _proc = p;
            try { p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine(); }
            catch (Exception ex)
            {
                _streamRunning = false;
                SetBusy(false, L.T("Не удалось запустить PowerShell."));
                LogLine(L.T("Не удалось запустить PowerShell: ") + ex.Message, Theme.Err);
                LogLine(L.T("Путь: ") + PowerShellExe(), Theme.TextDim);
                MessageBox.Show(this, L.T("Не удалось запустить PowerShell:\n") + ex.Message,
                    L.T("Ошибка"), MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        // запуск с разбором JSON (для данных) — без переключения на журнал
        private void RunJson(string extra, string statusText, Action<Dictionary<string, object>> onResult)
        {
            SetBusy(true, statusText);
            Process p = new Process();
            try { p.StartInfo = EnginePsi(extra); }
            catch (Exception ex)
            {
                SetBusy(false, L.T("Ошибка."));
                LogLine(L.T("Не удалось подготовить движок: ") + ex.Message, Theme.Err);
                if (onResult != null) onResult(null);
                return;
            }
            p.EnableRaisingEvents = true;
            string jsonLine = null;
            StringBuilder errBuf = new StringBuilder();
            DataReceivedEventHandler h = delegate(object s, DataReceivedEventArgs e)
            {
                if (e.Data == null) return;
                string t = e.Data.TrimStart();
                if (t.StartsWith("###JSON###")) jsonLine = t.Substring(10).Trim();
                else if (t.Length > 0 && errBuf.Length < 2000) errBuf.Append(t).Append("\n");
            };
            p.OutputDataReceived += h; p.ErrorDataReceived += h;
            p.Exited += delegate
            {
                int code = -1;
                try { p.WaitForExit(); code = p.ExitCode; } catch { }
                try
                {
                    BeginInvoke((MethodInvoker)delegate
                    {
                        SetBusy(false, L.T("Готово."));
                        Dictionary<string, object> d = null;
                        if (jsonLine != null) { try { d = Json.ParseObject(jsonLine); } catch { } }
                        if (d == null && errBuf.Length > 0)
                            LogLine(L.T("Движок (") + extra + L.T(") не вернул данные, код ") + code + ":\n" + errBuf, Theme.Err);
                        if (onResult != null) onResult(d);
                    });
                }
                catch { }
            };
            _proc = p;
            try { p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine(); }
            catch (Exception ex)
            {
                SetBusy(false, L.T("PowerShell недоступен."));
                LogLine(L.T("Не удалось запустить PowerShell: ") + ex.Message, Theme.Err);
                if (onResult != null) onResult(null);
            }
        }

        private void SetBusy(bool busy, string status)
        {
            _progress.Visible = busy; _status.Text = status;
            if (_progress.Parent != null) _progress.Parent.PerformLayout();
            _status.Location = new Point(busy ? (int)(Font.Height * 11F) : (int)(Font.Height * 1.2F), _status.Location.Y);
            if (_btnApply != null) _btnApply.Enabled = !busy;
            if (_btnRevert != null) _btnRevert.Enabled = !busy;
            if (_btnGuardInstall != null) _btnGuardInstall.Enabled = !busy;
            if (_monitorToggle != null) _monitorToggle.Enabled = !busy;
        }

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
            if (d.ContainsKey("backup")) _optBackup.Checked = Json.GetBool(d, "backup");
            if (d.ContainsKey("restorePoint")) _optRestore.Checked = Json.GetBool(d, "restorePoint");
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

        private void RenderAudit(Dictionary<string, object> d)
        {
            int ok = Json.GetInt(d, "ok"), total = Json.GetInt(d, "total");
            _ring.SetScore(ok, total);
            _auditHint.Visible = false;
            _auditWhen.Text = L.T("Проверено: ") + Json.GetStr(d, "time");

            _auditTiles.Controls.Clear();
            int fails = total - ok;
            _auditTiles.Controls.Add(Tile(L.T("Применено"), ok + " / " + total, L.T("настроек подтверждено"), fails == 0 ? Theme.Ok : Theme.Accent));
            _auditTiles.Controls.Add(Tile(L.T("Не применено"), fails.ToString(), fails == 0 ? L.T("всё на месте") : L.T("требуют внимания"), fails == 0 ? Theme.Ok : Theme.Warn));
            Dictionary<string, object> buf = Json.GetObj(d, "buffer");
            if (buf != null) { string mb = Json.GetStr(buf, "mb"); _auditTiles.Controls.Add(Tile(L.T("Буфер телеметрии"), (mb == "-1" ? L.T("нет") : mb + L.T(" МБ")), Json.GetInt(buf, "files") + L.T(" файлов ждут отправки"), Theme.Accent)); }
            List<object> dns = Json.GetArr(d, "dns");
            int leaked = 0; foreach (object o in dns) if (!Json.GetBool(Json.Obj(o), "blocked")) leaked++;
            _auditTiles.Controls.Add(Tile(L.T("Обращения к телеметрии"), dns.Count.ToString(), leaked + L.T(" не заблокировано (из кэша DNS)"), leaked == 0 ? Theme.Ok : Theme.Err));

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
            RunStreaming("-InstallGuard -Modules " + string.Join(",", mods.ToArray()), L.T("Установка стража…"), delegate { RunDetect(); });
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

        // ================================================================== //
        //  Detect при старте
        // ================================================================== //
        private bool _spyAutoRan;

        // Список отдельных настроек внутри каждого модуля — приходит из движка
        private void LoadDefs()
        {
            if (_defsLoaded) return;
            _defsLoaded = true;
            RunJson("-ListDefs", L.T("Чтение списка настроек…"), delegate(Dictionary<string, object> d)
            {
                if (d == null || _settingsList == null) return;
                foreach (object go in Json.GetArr(d, "groups"))
                {
                    Dictionary<string, object> g = Json.Obj(go);
                    string mod = Json.GetStr(g, "module");
                    ModuleDef m = null;
                    foreach (ModuleDef mm in _mods) if (mm.Id == mod) { m = mm; break; }
                    if (m == null || m.Row == null) continue;

                    int at = _settingsList.Controls.IndexOf(m.Row);
                    if (at < 0) continue;
                    List<object> items = Json.GetArr(g, "items");
                    int offset = 1;
                    foreach (object io2 in items)
                    {
                        Dictionary<string, object> it = Json.Obj(io2);
                        SubOptionRow r = new SubOptionRow(Json.GetStr(it, "id"), L.T(Json.GetStr(it, "name")));
                        r.Font = Font;
                        m.Subs.Add(r);
                        _settingsList.Controls.Add(r);
                        _settingsList.Controls.SetChildIndex(r, at + offset);
                        offset++;
                        _settingsList.Hidden.Add(r);          // свёрнуто по умолчанию
                    }
                    m.Row.SubCount = m.Subs.Count;
                    ModuleDef captured = m;
                    m.Row.ExpandRequested += delegate { ToggleModule(captured); };
                    m.Row.Invalidate();
                }
                _settingsList.Restack();
            });
        }

        internal void ToggleModule(ModuleDef m)
        {
            m.Expanded = !m.Expanded;
            m.Row.Expanded = m.Expanded;
            foreach (SubOptionRow r in m.Subs)
            {
                if (m.Expanded) _settingsList.Hidden.Remove(r);
                else _settingsList.Hidden.Add(r);
            }
            m.Row.Invalidate();
            _settingsList.Restack();
        }

        // Пункты, которые пользователь снял внутри раскрытых модулей
        private List<string> SkippedItems()
        {
            List<string> skip = new List<string>();
            foreach (ModuleDef m in _mods)
            {
                if (m.Row == null || !m.Row.Checked) continue;
                foreach (SubOptionRow r in m.Subs) if (!r.Checked) skip.Add(r.Id);
            }
            return skip;
        }
        private void RunDetect()
        {
            RunJson("-Detect", L.T("Определение системы…"), delegate(Dictionary<string, object> d)
            {
                _detect = d;
                if (d == null) { if (_sysInfoLabel != null) _sysInfoLabel.Text = L.T("Система не определена\n(PowerShell недоступен)"); return; }
                ApplyDetect(d);
                // журнал датчиков — сразу при старте: бейдж «!» и график на «Обзоре»
                LoadDefs();
                if (!_spyAutoRan && Environment.GetEnvironmentVariable("WIN11_TEST_MOCK") != "1")
                {
                    _spyAutoRan = true;
                    LoadDefs();
                    RunJson("-Spy", L.T("Чтение журнала датчиков…"), delegate(Dictionary<string, object> s)
                    {
                        if (s == null) return;
                        _lastSpy = s;
                        RenderDossier();
                    });
                }
            });
        }

        private void ApplyDetect(Dictionary<string, object> d)
        {
            {
                _editionKind = Json.GetStr(d, "editionKind");
                _guardInstalled = Json.GetBool(d, "guardInstalled");
                _monitorEnabled = Json.GetBool(d, "monitorEnabled");
                _watcherOn = Json.GetBool(d, "watcherInstalled");
                if (_btnWatcher != null) _btnWatcher.Text = _watcherOn ? L.T("Уведомления: вкл") : L.T("Уведомления");
                _sensorOn = Json.GetBool(d, "sensorGuardInstalled");
                if (_btnSensorGuard != null) _btnSensorGuard.Text = _sensorOn ? L.T("Датчики: вкл") : L.T("Датчики");

                // sysinfo
                string os = Json.GetStr(d, "os"); string ed = Json.GetStr(d, "edition");
                if (_sysInfoLabel != null) _sysInfoLabel.Text = os.Replace("Microsoft ", "") + "\n" + ed + L.T("  •  сборка ") + Json.GetStr(d, "build");
                if (_homeSysChip != null) _homeSysChip.SetText(os.Replace("Microsoft ", "") + L.T("  •  сборка ") + Json.GetStr(d, "build"));

                // доступность программных модулей
                Dictionary<string, bool> appFound = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
                foreach (object o in Json.GetArr(d, "apps")) { Dictionary<string, object> a = Json.Obj(o); appFound[Json.GetStr(a, "id")] = Json.GetBool(a, "found"); }
                Dictionary<string, object> oem = Json.GetObj(d, "oem");
                int oemCount = oem != null ? Json.GetArr(oem, "items").Count : 0;

                foreach (ModuleDef m in _mods)
                {
                    if (!m.App || m.Row == null) continue;
                    bool found;
                    if (m.Id == "oem") found = oemCount > 0;
                    else found = appFound.ContainsKey(m.Id) && appFound[m.Id];
                    m.Installed = found;
                    m.Row.Enabled = found;
                    if (!found) m.Row.Checked = false;
                    if (m.Id == "oem" && found) m.Row.Description = L.T("Найдено компонентов: ") + oemCount + " (" + Json.GetStr(oem, "manufacturer") + L.T("). Драйверы не трогаются.");
                    else if (!found) m.Row.Description = L.T("Не установлено на этом компьютере.");
                }
                if (_settingsList != null) _settingsList.Restack();

                // about
                if (_aboutEdition != null)
                {
                    string kindText = _editionKind == "enterprise" ? L.T("Enterprise/Education — доступно полное отключение телеметрии.")
                        : (_editionKind == "pro" ? L.T("Pro — уровень телеметрии ограничен «Обязательными данными».")
                        : (_editionKind == "home" ? L.T("Home — уровень телеметрии ограничен «Обязательными данными».") : "—"));
                    Dictionary<string, object> buf = Json.GetObj(d, "buffer");
                    string bufText = buf != null ? (Json.GetStr(buf, "mb") + L.T(" МБ в буфере")) : "";
                    SetAboutBody(_aboutEdition, os + "\n" + ed + L.T(" (сборка ") + Json.GetStr(d, "build") + ")\n" + kindText +
                        L.T("\nСлужба DiagTrack: ") + Json.GetStr(d, "diagTrack") +
                        L.T("\nБрандмауэр (правил): ") + Json.GetInt(d, "firewallRules") +
                        L.T("\nБлок hosts: ") + (Json.GetBool(d, "hostsBlocked") ? L.T("установлен") : L.T("нет")) +
                        L.T("\nНеотправленная телеметрия: ") + bufText);
                }

                UpdateMonitorButton();
                RenderGuard();
                // бейджи навигации
                foreach (NavItem n in _nav)
                {
                    if ((string)n.Tag == "guard") { n.Badge = _guardInstalled ? L.T("вкл") : ""; n.Invalidate(); }
                    if ((string)n.Tag == "monitor") { n.Badge = _monitorEnabled ? L.T("вкл") : ""; n.Invalidate(); }
                }
            }
        }

        // ================================================================== //
        [STAThread]
        public static void Main(string[] argv)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

#if UITEST
            if (Environment.GetEnvironmentVariable("WIN11_TEST_EN") == "1") L.English = true;
            MainForm f = new MainForm();
            string page = Environment.GetEnvironmentVariable("WIN11_TEST_PAGE"); if (string.IsNullOrEmpty(page)) page = "settings";
            bool mock = Environment.GetEnvironmentVariable("WIN11_TEST_MOCK") == "1";
            string shot = Environment.GetEnvironmentVariable("WIN11_TEST_SHOT");
            int delayMs = shot != null ? 2500 : 13000;
            string delayEnv = Environment.GetEnvironmentVariable("WIN11_TEST_DELAY");
            if (!string.IsNullOrEmpty(delayEnv)) { int dv; if (int.TryParse(delayEnv, out dv) && dv > 500) delayMs = dv; }
            Timer t = new Timer(); t.Interval = delayMs;
            t.Tick += delegate {
                t.Stop();
                if (shot != null) { try { using (Bitmap bmp = new Bitmap(f.Width, f.Height)) { f.DrawToBitmap(bmp, new Rectangle(0, 0, f.Width, f.Height)); bmp.Save(shot); Console.WriteLine("SHOT " + shot); } } catch (Exception ex) { Console.WriteLine("SHOTERR " + ex.Message); } }
                Console.WriteLine("UITEST ok"); f.Close();
            };
            f.Shown += delegate {
                string sz = Environment.GetEnvironmentVariable("WIN11_TEST_SIZE");
                if (!string.IsNullOrEmpty(sz))
                {
                    string[] p2 = sz.Split('x');
                    int tw, th2;
                    if (p2.Length == 2 && int.TryParse(p2[0], out tw) && int.TryParse(p2[1], out th2))
                        f.ClientSize = new Size(tw, th2);
                }
                if (mock) f.InjectMocks();
                if (Environment.GetEnvironmentVariable("WIN11_TEST_EXPAND") == "1")
                {
                    Timer ex = new Timer(); ex.Interval = 7000;
                    ex.Tick += delegate {
                        ex.Stop();
                        foreach (ModuleDef md in f._mods) if (md.Subs.Count > 0) { f.ToggleModule(md); break; }
                    };
                    ex.Start();
                }
                f.Navigate(page);
                string q = Environment.GetEnvironmentVariable("WIN11_TEST_QUERY");
                if (!string.IsNullOrEmpty(q) && f._search != null) f._search.Text = q;
                if (Environment.GetEnvironmentVariable("WIN11_TEST_SCROLL") == "1" && f._dossierList != null)
                {
                    try { f._dossierList.VerticalScroll.Value = f._dossierList.VerticalScroll.Maximum; f._dossierList.Restack(); } catch { }
                }
                t.Start();
            };
            Application.Run(f); return;
#pragma warning disable 0162
#endif
            // тихий режим командной строки
            string profile = null; bool silent = false, audit = false;
            for (int i = 0; i < argv.Length; i++)
            {
                string a = argv[i].ToLowerInvariant();
                if (a == "--profile" && i + 1 < argv.Length) profile = argv[++i];
                else if (a == "--silent" || a == "-silent") silent = true;
                else if (a == "--audit") audit = true;
            }

            if (!IsAdmin())
            {
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo(Application.ExecutablePath);
                    psi.UseShellExecute = true; psi.Verb = "runas";
                    psi.Arguments = string.Join(" ", argv);
                    Process.Start(psi);
                }
                catch
                {
                    if (!silent) MessageBox.Show(L.T("Программа изменяет системные настройки и требует прав администратора."),
                        L.T("Нужны права администратора"), MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
                return;
            }

            if (silent && profile != null) { RunSilentProfile(profile); return; }
            if (audit) { RunCliAudit(); return; }

            Application.Run(new MainForm());
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
                if (d.ContainsKey("backup") && !Json.GetBool(d, "backup")) extra += " -NoBackup";
                if (d.ContainsKey("restorePoint") && !Json.GetBool(d, "restorePoint")) extra += " -NoRestorePoint";
                return RunEngineConsole(extra);
            }
            catch { return 1; }
        }

        private static int RunCliAudit()
        {
            // возвращает число несоответствий как код выхода
            string script = ExtractEngineStatic();
            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe",
                "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -Audit");
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
                "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" " + extra + " -BackupRoot \"" + desktop + "\"");
            psi.UseShellExecute = false; psi.RedirectStandardOutput = true; psi.StandardOutputEncoding = Encoding.UTF8; psi.CreateNoWindow = true;
            Process p = Process.Start(psi);
            while (!p.StandardOutput.EndOfStream) { string l = p.StandardOutput.ReadLine(); if (l != null && !l.TrimStart().StartsWith("###JSON###") && l.Trim() != "###DONE###") Console.WriteLine(l); }
            p.WaitForExit();
            return p.ExitCode;
        }

        private static string ExtractEngineStatic()
        {
            string dir = Path.Combine(Path.GetTempPath(), "Win11Privacy");
            Directory.CreateDirectory(dir);
            string path = Path.Combine(dir, "engine.ps1");
            Assembly asm = Assembly.GetExecutingAssembly();
            using (Stream src = asm.GetManifestResourceStream("engine.ps1"))
            using (FileStream dst = new FileStream(path, FileMode.Create, FileAccess.Write))
            { byte[] buf = new byte[8192]; int n; while ((n = src.Read(buf, 0, buf.Length)) > 0) dst.Write(buf, 0, n); }
            return path;
        }

        private static bool IsAdmin()
        {
            try { return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator); }
            catch { return false; }
        }

#if UITEST
        // Тестовые данные для скриншотов без реального PowerShell
        internal void InjectMocks()
        {
            string audit = "{\"time\":\"2026-08-31 15:20\",\"ok\":58,\"total\":63,\"groups\":[" +
                "{\"module\":\"telemetry\",\"title\":\"Телеметрия и диагностика\",\"ok\":12,\"total\":12,\"items\":[{\"name\":\"уровень телеметрии — минимальный\",\"ok\":true,\"actual\":\"0\"}]}," +
                "{\"module\":\"ads\",\"title\":\"Рекламный ID и реклама\",\"ok\":22,\"total\":22,\"items\":[]}," +
                "{\"module\":\"copilot\",\"title\":\"Copilot и Recall\",\"ok\":6,\"total\":6,\"items\":[]}," +
                "{\"module\":\"ai\",\"title\":\"ИИ-функции Windows\",\"ok\":13,\"total\":15,\"items\":[" +
                    "{\"name\":\"Paint Cocreator — выкл\",\"ok\":false,\"actual\":\"не задано\"},{\"name\":\"Edge: Copilot не читает страницы\",\"ok\":false,\"actual\":\"не задано\"}]}," +
                "{\"module\":\"services\",\"title\":\"Службы и задачи телеметрии\",\"ok\":5,\"total\":11,\"items\":[" +
                    "{\"name\":\"задача Consolidator\",\"ok\":false,\"actual\":\"Ready\"},{\"name\":\"задача ProgramDataUpdater\",\"ok\":false,\"actual\":\"Ready\"}]}" +
                "],\"dns\":[{\"name\":\"v20.events.data.microsoft.com\",\"blocked\":true},{\"name\":\"telemetry.microsoft.com\",\"blocked\":true},{\"name\":\"self.events.data.microsoft.com\",\"blocked\":false}]," +
                "\"buffer\":{\"mb\":\"4.7\",\"files\":9},\"edition\":{\"kind\":\"home\"},\"monitorEnabled\":true,\"hostsBlocked\":true}";
            RenderAudit(Json.ParseObject(audit));

            string mon = "{\"enabled\":true,\"hours\":24,\"total\":146,\"telemetryHits\":23,\"firewallRules\":6,\"blocked\":31,\"byProcess\":[" +
                "{\"name\":\"svchost.exe\",\"count\":54,\"path\":\"C:\\Windows\\System32\\svchost.exe\",\"blocked\":false}," +
                "{\"name\":\"MoUsoCoreWorker.exe\",\"count\":22,\"path\":\"C:\\Windows\\UUS\\amd64\\MoUsoCoreWorker.exe\",\"blocked\":false}," +
                "{\"name\":\"chrome.exe\",\"count\":18,\"path\":\"C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe\",\"blocked\":false}," +
                "{\"name\":\"CompatTelRunner.exe\",\"count\":12,\"path\":\"C:\\Windows\\System32\\CompatTelRunner.exe\",\"blocked\":true}," +
                "{\"name\":\"NvTelemetry.exe\",\"count\":9,\"path\":\"C:\\Program Files\\NVIDIA Corporation\\NvTelemetry\\NvTelemetry.exe\",\"blocked\":true}]," +
                "\"byDest\":[{\"ip\":\"20.42.65.90\",\"domain\":\"v20.events.data.microsoft.com\",\"count\":31,\"port\":\"443\"}," +
                "{\"ip\":\"13.89.178.26\",\"domain\":\"self.events.data.microsoft.com\",\"count\":14,\"port\":\"443\"}," +
                "{\"ip\":\"142.250.150.100\",\"domain\":\"clients4.google.com\",\"count\":11,\"port\":\"443\"}," +
                "{\"ip\":\"20.190.160.14\",\"domain\":\"login.microsoftonline.com\",\"count\":6,\"port\":\"443\"}]}";
            RenderMonitor(Json.ParseObject(mon));

            string det = "{\"os\":\"Windows 11 Домашняя\",\"build\":\"26100\",\"edition\":\"Core\",\"editionKind\":\"home\",\"guardInstalled\":true,\"monitorEnabled\":true," +
                "\"guardModules\":[\"telemetry\",\"ads\",\"copilot\"],\"guardLast\":{\"time\":\"2026-08-31 12:00\",\"drifted\":[\"AllowTelemetry\",\"ShowCopilotButton\"],\"fixed\":2,\"hotfixes\":[\"KB5054321\"]}," +
                "\"firewallRules\":6,\"hostsBlocked\":true,\"diagTrack\":\"Disabled\",\"buffer\":{\"mb\":\"4.7\",\"files\":9}," +
                "\"apps\":[{\"id\":\"app_nvidia\",\"found\":true},{\"id\":\"app_vscode\",\"found\":true},{\"id\":\"app_chrome\",\"found\":true},{\"id\":\"app_firefox\",\"found\":false},{\"id\":\"app_office\",\"found\":false},{\"id\":\"app_devtools\",\"found\":true},{\"id\":\"app_vs\",\"found\":false}]," +
                "\"oem\":{\"manufacturer\":\"HONOR\",\"model\":\"HVY-WXX9\",\"items\":[{\"type\":\"svc\",\"display\":\"HnAnalyticsService\",\"state\":\"Auto\"},{\"type\":\"task\",\"display\":\"HonorUserExperience\",\"state\":\"Ready\"}]}}";
            _detect = Json.ParseObject(det);
            ApplyDetect(_detect);

            string xr = "{\"time\":\"2026-08-31 15:40\",\"hours\":24,\"recording\":true,\"total\":4812,\"distinctNames\":137," +
                "\"mb\":8.4,\"perDay\":4812,\"mbPerDay\":\"8.4\",\"perYear\":1756380,\"mbPerYear\":\"3066\"," +
                "\"baselinePerDay\":4812,\"baselineTime\":\"2026-08-30 11:00\",\"deltaPercent\":0,\"categories\":[" +
                "{\"name\":\"Список установленных программ\",\"count\":1420,\"share\":29.5,\"what\":\"Какие программы стоят на компьютере, их версии и издатели\"," +
                  "\"topNames\":[{\"name\":\"Microsoft.Windows.Inventory.Core.InventoryApplicationAdd\",\"count\":980},{\"name\":\"Microsoft.Windows.Inventory.Core.InventoryApplicationStartup\",\"count\":440}]," +
                  "\"sample\":{\"name\":\"Microsoft.Windows.Inventory.Core.InventoryApplicationAdd\",\"time\":\"2026-08-31 14:22:07\"," +
                  "\"payload\":\"{\\\"data\\\":{\\\"ProgramName\\\":\\\"Google Chrome\\\",\\\"Publisher\\\":\\\"Google LLC\\\",\\\"Version\\\":\\\"131.0.6778.86\\\",\\\"InstallDate\\\":\\\"2026-03-14\\\",\\\"RootDirPath\\\":\\\"c:/program files/google/chrome\\\"},\\\"ext\\\":{\\\"device\\\":{\\\"localId\\\":\\\"m:A1B2C3D4E5F67890\\\",\\\"deviceMake\\\":\\\"HONOR\\\",\\\"deviceModel\\\":\\\"HVY-WXX9\\\"},\\\"user\\\":{\\\"localId\\\":\\\"w:9F8E7D6C5B4A\\\"},\\\"os\\\":{\\\"osVer\\\":\\\"10.0.26100\\\"}}}\"}}," +
                "{\"name\":\"Какие программы ты запускал\",\"count\":1180,\"share\":24.5,\"what\":\"Что открывал, сколько времени провёл, как часто\"," +
                  "\"topNames\":[{\"name\":\"Win32kTraceLogging.AppInteractivitySummary\",\"count\":1180}],\"sample\":null}," +
                "{\"name\":\"Инвентаризация железа\",\"count\":820,\"share\":17.0,\"what\":\"Модель ноутбука, процессор, память, диски, серийные номера\",\"topNames\":[{\"name\":\"Census.Hardware\",\"count\":410}],\"sample\":null}," +
                "{\"name\":\"Подключённые устройства\",\"count\":540,\"share\":11.2,\"what\":\"Флешки, наушники, принтеры, мыши — что и когда подключал\",\"topNames\":[{\"name\":\"Microsoft.Windows.Kernel.PnP.DeviceConfig\",\"count\":540}],\"sample\":null}," +
                "{\"name\":\"Сбои и падения программ\",\"count\":312,\"share\":6.5,\"what\":\"Какие программы падали, с какими ошибками, имена файлов\",\"topNames\":[{\"name\":\"Microsoft.Windows.FaultReporting.AppCrashEvent\",\"count\":312}],\"sample\":null}," +
                "{\"name\":\"Браузер\",\"count\":290,\"share\":6.0,\"what\":\"Активность в браузере, посещения, проверки сайтов\",\"topNames\":[{\"name\":\"Microsoft.Edge.Browser.Navigation\",\"count\":290}],\"sample\":null}," +
                "{\"name\":\"Учётная запись\",\"count\":250,\"share\":5.3,\"what\":\"Входы в систему, привязка к учётной записи Microsoft\",\"topNames\":[],\"sample\":null}]," +
                "\"identifiers\":[{\"key\":\"localId\",\"distinct\":2,\"values\":[{\"value\":\"m:A1B2C3D4E5F67890\",\"count\":4812}]}," +
                "{\"key\":\"deviceMake\",\"distinct\":1,\"values\":[{\"value\":\"HONOR\",\"count\":4812}]}," +
                "{\"key\":\"deviceModel\",\"distinct\":1,\"values\":[{\"value\":\"HVY-WXX9\",\"count\":4812}]}]," +
                "\"apps\":[{\"name\":\"Google Chrome\",\"count\":980},{\"name\":\"Visual Studio Code\",\"count\":610},{\"name\":\"Telegram Desktop\",\"count\":320},{\"name\":\"Steam\",\"count\":180}]," +
                "\"db\":{\"mb\":42.7,\"files\":6}}";
            _lastXray = Json.ParseObject(xr);
            RenderXray(_lastXray);
            _lastAudit = Json.ParseObject(audit);

            string spy = "{\"time\":\"2026-08-31 19:20\",\"activeNow\":1,\"week\":9," +
                "\"days\":[" +
                "{\"date\":\"18.08\",\"cam\":0,\"mic\":1,\"loc\":0,\"other\":0}," +
                "{\"date\":\"19.08\",\"cam\":1,\"mic\":2,\"loc\":1,\"other\":0}," +
                "{\"date\":\"20.08\",\"cam\":0,\"mic\":0,\"loc\":0,\"other\":0}," +
                "{\"date\":\"21.08\",\"cam\":0,\"mic\":3,\"loc\":1,\"other\":0}," +
                "{\"date\":\"22.08\",\"cam\":2,\"mic\":4,\"loc\":0,\"other\":1}," +
                "{\"date\":\"23.08\",\"cam\":0,\"mic\":1,\"loc\":2,\"other\":0}," +
                "{\"date\":\"24.08\",\"cam\":0,\"mic\":0,\"loc\":1,\"other\":0}," +
                "{\"date\":\"25.08\",\"cam\":1,\"mic\":2,\"loc\":0,\"other\":0}," +
                "{\"date\":\"26.08\",\"cam\":0,\"mic\":5,\"loc\":1,\"other\":0}," +
                "{\"date\":\"27.08\",\"cam\":0,\"mic\":1,\"loc\":3,\"other\":0}," +
                "{\"date\":\"28.08\",\"cam\":1,\"mic\":0,\"loc\":0,\"other\":0}," +
                "{\"date\":\"29.08\",\"cam\":2,\"mic\":3,\"loc\":1,\"other\":0}," +
                "{\"date\":\"30.08\",\"cam\":0,\"mic\":6,\"loc\":0,\"other\":1}," +
                "{\"date\":\"31.08\",\"cam\":1,\"mic\":4,\"loc\":2,\"other\":0}]," +
                "\"caps\":[" +
                "{\"id\":\"webcam\",\"title\":\"Камера\",\"global\":\"Allow\",\"count\":2,\"items\":[" +
                  "{\"app\":\"Telegram.exe\",\"last\":\"2026-08-31 18:55\",\"minutes\":0,\"active\":true}," +
                  "{\"app\":\"chrome.exe\",\"last\":\"2026-08-29 21:14\",\"minutes\":41.5,\"active\":false}]}," +
                "{\"id\":\"microphone\",\"title\":\"Микрофон\",\"global\":\"Allow\",\"count\":3,\"items\":[" +
                  "{\"app\":\"cs2.exe\",\"last\":\"2026-08-30 19:43\",\"minutes\":103.6,\"active\":false}," +
                  "{\"app\":\"obs64.exe\",\"last\":\"2026-08-28 13:00\",\"minutes\":85.5,\"active\":false}," +
                  "{\"app\":\"chrome.exe\",\"last\":\"2026-08-27 18:36\",\"minutes\":2.2,\"active\":false}]}," +
                "{\"id\":\"location\",\"title\":\"Местоположение\",\"global\":\"Allow\",\"count\":2,\"items\":[" +
                  "{\"app\":\"Виджеты Windows\",\"last\":\"2026-08-31 19:14\",\"minutes\":0.2,\"active\":false}," +
                  "{\"app\":\"msedge.exe\",\"last\":\"2026-08-04 12:22\",\"minutes\":0,\"active\":false}]}]}";
            _lastSpy = Json.ParseObject(spy);

            string foot = "{\"time\":\"2026-08-31 19:21\",\"totalMb\":37.8,\"wipeable\":7,\"items\":[" +
                "{\"id\":\"adid\",\"title\":\"Рекламный идентификатор\",\"what\":\"Уникальный ID, по которому рекламные сети узнают вас во всех приложениях.\",\"value\":\"a1b2c3d4-e5f6-7890-abcd-ef0123456789\",\"mb\":0,\"count\":1,\"canWipe\":true}," +
                "{\"id\":\"machineid\",\"title\":\"Постоянные метки компьютера\",\"what\":\"MachineGuid и SQM MachineId — метки, которыми помечается телеметрия. Нужны системе, стереть нельзя.\",\"value\":\"cdfc5378-…\",\"mb\":0,\"count\":2,\"canWipe\":false}," +
                "{\"id\":\"networks\",\"title\":\"История сетей Wi-Fi и Ethernet\",\"what\":\"Список всех сетей, к которым подключался компьютер — по ним видно, где вы бывали. Пароли Wi-Fi не трогаются.\",\"value\":\"Home_5G, Cafe_Free, Airport-WiFi …\",\"mb\":0,\"count\":14,\"canWipe\":true}," +
                "{\"id\":\"usb\",\"title\":\"История подключённых флешек\",\"what\":\"Windows помнит каждую флешку и внешний диск. Запись системная, показываем для сведения.\",\"value\":\"Kingston DataTraveler, WD Elements …\",\"mb\":0,\"count\":6,\"canWipe\":false}," +
                "{\"id\":\"activity\",\"title\":\"База истории активности\",\"what\":\"ActivitiesCache.db — какие программы и документы вы открывали, с точным временем.\",\"value\":\"18.2 МБ\",\"mb\":18.2,\"count\":5,\"canWipe\":true}," +
                "{\"id\":\"recent\",\"title\":\"Недавние документы и папки\",\"what\":\"Ярлыки всего, что вы открывали, плюс списки переходов на панели задач.\",\"value\":\"212 записей\",\"mb\":1.4,\"count\":212,\"canWipe\":true}," +
                "{\"id\":\"clipboard\",\"title\":\"История буфера обмена\",\"what\":\"Всё скопированное (Win+V) хранится на диске.\",\"value\":\"включена, 6.1 МБ\",\"mb\":6.1,\"count\":31,\"canWipe\":true}," +
                "{\"id\":\"wer\",\"title\":\"Архив отчётов об ошибках\",\"what\":\"Дампы и отчёты о сбоях: содержат пути файлов, имена программ, куски памяти.\",\"value\":\"144 отчётов, 11.6 МБ\",\"mb\":11.6,\"count\":144,\"canWipe\":true}," +
                "{\"id\":\"dnscache\",\"title\":\"Кэш DNS (следы сайтов)\",\"what\":\"Адреса сайтов и служб, к которым недавно обращался компьютер.\",\"value\":\"103 записей\",\"mb\":0,\"count\":103,\"canWipe\":true}]}";
            string appsJson = "{\"time\":\"2026-09-01 00:30\",\"apps\":[" +
                "{\"name\":\"Microsoft.BingNews\",\"title\":\"Новости MSN\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":true}," +
                "{\"name\":\"Microsoft.BingWeather\",\"title\":\"Погода MSN\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":true}," +
                "{\"name\":\"Clipchamp.Clipchamp\",\"title\":\"Видеоредактор Clipchamp\",\"publisher\":\"CN=Clipchamp Pty Ltd\",\"bloat\":true}," +
                "{\"name\":\"Microsoft.GamingApp\",\"title\":\"Приложение Xbox\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":true}," +
                "{\"name\":\"Microsoft.MicrosoftSolitaireCollection\",\"title\":\"Коллекция пасьянсов\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":true}," +
                "{\"name\":\"MicrosoftTeams\",\"title\":\"Teams (личный)\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":true}," +
                "{\"name\":\"Microsoft.YourPhone\",\"title\":\"Связь с телефоном\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":true}," +
                "{\"name\":\"Microsoft.WindowsFeedbackHub\",\"title\":\"Центр отзывов\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":true}," +
                "{\"name\":\"Microsoft.WindowsCalculator\",\"title\":\"Microsoft.WindowsCalculator\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":false}," +
                "{\"name\":\"Microsoft.WindowsCamera\",\"title\":\"Microsoft.WindowsCamera\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":false}," +
                "{\"name\":\"Microsoft.Windows.Photos\",\"title\":\"Microsoft.Windows.Photos\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":false}]}";
            RenderApps(Json.ParseObject(appsJson));

            string startJson = "{\"time\":\"2026-09-01 12:10\",\"total\":11,\"on\":8,\"advise\":5,\"items\":[" +
                "{\"id\":\"a1\",\"name\":\"GoogleUpdate\",\"publisher\":\"Google LLC\",\"cmd\":\"C:\\\\Program Files (x86)\\\\Google\\\\Update\\\\GoogleUpdate.exe /c\",\"source\":\"реестр, все пользователи\",\"kind\":\"run\",\"enabled\":true,\"advise\":true,\"keep\":false,\"note\":\"обновлятор Google: работает постоянно и шлёт статистику\"}," +
                "{\"id\":\"a2\",\"name\":\"OneDrive\",\"publisher\":\"Microsoft Corporation\",\"cmd\":\"C:\\\\Program Files\\\\Microsoft OneDrive\\\\OneDrive.exe /background\",\"source\":\"реестр, этот пользователь\",\"kind\":\"run\",\"enabled\":true,\"advise\":true,\"keep\":false,\"note\":\"OneDrive: синхронизация в облако\"}," +
                "{\"id\":\"a3\",\"name\":\"NvBackend\",\"publisher\":\"NVIDIA Corporation\",\"cmd\":\"C:\\\\Program Files (x86)\\\\NVIDIA Corporation\\\\Update Core\\\\NvBackend.exe\",\"source\":\"реестр, все пользователи\",\"kind\":\"run\",\"enabled\":true,\"advise\":true,\"keep\":false,\"note\":\"спутник драйвера NVIDIA: телеметрия и вход в аккаунт\"}," +
                "{\"id\":\"a4\",\"name\":\"HonorPCManager\",\"publisher\":\"HONOR Device Co., Ltd.\",\"cmd\":\"C:\\\\Program Files\\\\Honor\\\\PCManager\\\\PCManager.exe -autorun\",\"source\":\"планировщик задач, при входе\",\"kind\":\"task\",\"enabled\":true,\"advise\":true,\"keep\":false,\"note\":\"программа производителя: собирает сведения о ноутбуке\"}," +
                "{\"id\":\"a5\",\"name\":\"Steam\",\"publisher\":\"Valve Corporation\",\"cmd\":\"C:\\\\Program Files (x86)\\\\Steam\\\\steam.exe -silent\",\"source\":\"реестр, этот пользователь\",\"kind\":\"run\",\"enabled\":true,\"advise\":true,\"keep\":false,\"note\":\"программа сама себя запускает при входе\"}," +
                "{\"id\":\"a6\",\"name\":\"SecurityHealth\",\"publisher\":\"Microsoft Corporation\",\"cmd\":\"%windir%\\\\system32\\\\SecurityHealthSystray.exe\",\"source\":\"реестр, все пользователи\",\"kind\":\"run\",\"enabled\":true,\"advise\":false,\"keep\":true,\"note\":\"\"}," +
                "{\"id\":\"a7\",\"name\":\"RtkAudUService\",\"publisher\":\"Realtek Semiconductor\",\"cmd\":\"RtkAudUService64.exe -background\",\"source\":\"реестр, все пользователи\",\"kind\":\"run\",\"enabled\":true,\"advise\":false,\"keep\":true,\"note\":\"\"}," +
                "{\"id\":\"a8\",\"name\":\"vmware-tray\",\"publisher\":\"VMware, Inc.\",\"cmd\":\"C:\\\\Program Files (x86)\\\\VMware\\\\vmware-tray.exe\",\"source\":\"реестр, все пользователи\",\"kind\":\"run\",\"enabled\":true,\"advise\":false,\"keep\":false,\"note\":\"\"}," +
                "{\"id\":\"a9\",\"name\":\"MicrosoftEdgeAutoLaunch\",\"publisher\":\"Microsoft Corporation\",\"cmd\":\"C:\\\\Program Files (x86)\\\\Microsoft\\\\Edge\\\\Application\\\\msedge.exe --no-startup-window\",\"source\":\"реестр, этот пользователь\",\"kind\":\"run\",\"enabled\":false,\"advise\":true,\"keep\":false,\"note\":\"автозапуск и обновлятор Edge\"}," +
                "{\"id\":\"a10\",\"name\":\"Telegram\",\"publisher\":\"Telegram FZ-LLC\",\"cmd\":\"C:\\\\Users\\\\user\\\\AppData\\\\Roaming\\\\Telegram Desktop\\\\Telegram.exe -autostart\",\"source\":\"папка автозагрузки, этот пользователь\",\"kind\":\"folder\",\"enabled\":false,\"advise\":true,\"keep\":false,\"note\":\"программа сама себя запускает при входе\"}," +
                "{\"id\":\"a11\",\"name\":\"AdobeAAMUpdater-1.0\",\"publisher\":\"Adobe Inc.\",\"cmd\":\"C:\\\\Program Files (x86)\\\\Common Files\\\\Adobe\\\\OOBE\\\\PDApp\\\\UWA\\\\UpdaterStartupUtility.exe\",\"source\":\"реестр, все пользователи\",\"kind\":\"run\",\"enabled\":false,\"advise\":true,\"keep\":false,\"note\":\"служба обновлений Adobe\"}]}";
            RenderStartup(Json.ParseObject(startJson));

            _lastFoot = Json.ParseObject(foot);
            if (Environment.GetEnvironmentVariable("WIN11_TEST_ONLYFOOT") == "1") _lastSpy = null;
            RenderDossier();

            RefreshHome();
            _xrayRecording = true;
            _btnXrayRec.Text = "Выключить запись"; _btnXrayRec.Primary = false;
            foreach (Control c in _xrayList.Controls) { if (c is XrayCatRow) { ((XrayCatRow)c).Expand(); break; } }
        }
#endif
    }
}
