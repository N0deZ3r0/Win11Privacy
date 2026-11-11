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

    // Окно разложено по нескольким файлам: здесь каркас, навигация, запуск
    // движка и общие действия, рядом — страницы, отчёт и тестовые данные.
    public partial class MainForm : Form
    {
        internal readonly List<ModuleDef> _mods = new List<ModuleDef>();
        private readonly List<NavItem> _nav = new List<NavItem>();
        private readonly List<NavGroup> _navGroups = new List<NavGroup>();
        private readonly List<Control> _navRows = new List<Control>();   // пункты и заголовки в порядке показа

        private Panel _content;
        private RichTextBox _log;
        private Label _status;
        private SlimProgress _progress;
        private ModernButton _btnStop;      // «Прервать» в строке состояния
        // первый пункт «Требует внимания» на «Обзоре» (мусор в реестре, сбитые настройки)
        private string _homeAlertTitle, _homeAlertDesc, _homeAlertBtn;
        private Action _homeAlertGo;
        private int _junkCount;             // параметры под числовыми именами от версий 1.1–1.5
        private string _busyText = "";      // чем занята программа сейчас
        private Icon _appIcon;
        private Image _appImage;

        // страницы по ключу навигации
        private readonly Dictionary<string, Control> _pages = new Dictionary<string, Control>();
        private TileGrid _dossierTiles;
        private StackPanel _dossierList;
        private Label _dossierState;
        private ModernButton _btnDossierRefresh, _btnDossierWipe, _btnDossierAll;
        private bool _spyShowAll;
        private Dictionary<string, object> _lastSpy, _lastFoot, _lastProof;
        private TextBox _search;
        private NavHost _navHost;
        private TitleBar _titleBar;
        // «Обзор»: строка состояния, «Требует внимания», защита по разделам
        private InfoRow _homeStatus;
        private RowList _homeAttention, _homeSections;
        private Label _homeSub;
        private TableLayoutPanel _homePage;
        private Panel _homeScroll;
        private string _homeSys = "";
        private int _homeStartupAdvise = -1;
        private StackPanel _appsList;
        private Label _appsState;
        private ModernButton _btnAppsRemove;
        private TimelineChart _timeline;
        private StackPanel _timelineNotes;
        private Label _timelineState;
        private StackPanel _changesList;
        private Label _changesState;
        private ModernButton _btnChangesBack;
        private readonly Dictionary<string, TextBox> _pageSearch = new Dictionary<string, TextBox>();
        private StackPanel _startupList;
        private Label _startupState;
        private ModernButton _btnStartupOff, _btnStartupOn;
        private bool _defsLoaded;
        private string _current = "";
        private StackPanel _xrayList;
        private TileGrid _xrayTiles;

        // боковая панель: сворачивание
        private SidePanel _side;
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
        private InfoRow _auditStatus;
        private Label _auditWhen;
        private StackPanel _auditGroups;
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
            if (_themeChoice == 1) Theme.Apply(true);
            else if (_themeChoice == 2) Theme.Apply(false);
            else Theme.Detect();
#if LIGHTTEST
            Theme.Apply(false);
#endif
            BuildModules();
            BuildUi();
        }

        private void BuildModules()
        {
            string S1=L.T("Сбор данных Windows"), S2=L.T("Реклама и рекомендации"), S3=L.T("ИИ Windows"),
                         S4=L.T("Расширенная защита"), S5=L.T("Программы"), S6=L.T("Обслуживание");
            Action<string,string,string,string,string,bool,bool,bool> A =
                (sec,id,t,d,g,on,hard,app) => _mods.Add(new ModuleDef(sec,id,t,d,g,on,hard,app));

            A(S1,"telemetry",L.T("Телеметрия и диагностика"),L.T("Диагностические данные, логи и дампы памяти в Microsoft."),GDiag,true,false,false);
            A(S1,"errors",L.T("Отчёты об ошибках"),L.T("Отчёты о сбоях программ и системы."),GError,true,false,false);
            A(S1,"activity",L.T("История активности и буфер обмена"),L.T("Лента активности и синхронизация буфера через облако."),GHistory,true,false,false);
            A(S1,"input",L.T("Персонализация ввода и речь"),L.T("Сбор набранного текста, рукописного ввода, облачная речь."),GKeyboard,true,false,false);
            A(S1,"edge","Microsoft Edge",L.T("Статистика и персонализация Edge; блокировка трекеров."),GGlobe,true,false,false);
            A(S1,"delivery",L.T("Раздача обновлений в интернет"),L.T("Отдача файлов обновлений чужим ПК."),GSync,true,false,false);
            A(S1,"onedrive",L.T("OneDrive: синхронизация и реклама"),L.T("Выгрузка файлов в облако и реклама OneDrive. Файлы на диске остаются."),GSync,false,false,false);
            A(S1,"location",L.T("Геолокация и «Поиск устройства»"),L.T("Служба местоположения целиком и отправка координат в Microsoft."),GPin,false,false,false);
            A(S1,"apppriv",L.T("Разрешения приложений"),L.T("Контакты, календарь, почта, возраст — под запретом политики, обновлением не вернуть."),GShield,true,false,false);
            A(S1,"network",L.T("Фоновые обращения в сеть"),L.T("Что Windows сама скачивает и отправляет: шрифты, карты, модели, Teredo."),GGlobe,true,false,false);
            A(S1,"cloudsync",L.T("Облачная синхронизация и копия"),L.T("Список приложений, Wi-Fi, язык и согласия, которые Windows сама выгружает в облако."),"",false,false,false);

            A(S2,"ads",L.T("Рекламный ID и реклама"),L.T("Реклама в Пуске, на экране блокировки и в Параметрах."),GAds,true,false,false);
            A(S2,"widgets",L.T("Виджеты и лента новостей"),L.T("Лента MSN на панели задач, которая изучает ваши интересы."),GGlobe,false,false,false);
            A(S2,"search",L.T("Поиск: Bing и Cortana"),L.T("Поиск в Пуске без обращения в интернет и к Cortana."),GSearch,true,false,false);

            A(S3,"copilot",L.T("Copilot и Recall"),L.T("ИИ-помощник и запись снимков экрана Recall."),GRobot,true,false,false);
            A(S3,"ai",L.T("Все ИИ-функции"),L.T("Click to Do, Copilot в Блокноте/Paint/Edge, ИИ в Проводнике и поиске."),GChip,true,false,false);

            A(S4,"services",L.T("Службы и задачи телеметрии"),L.T("Останавливает DiagTrack и задачи планировщика."),GShield,false,true,false);
            A(S4,"hosts",L.T("Блокировка доменов (hosts)"),L.T("Адреса телеметрии Microsoft — в файл hosts."),GDoc,false,true,false);
            A(S4,"gdid",L.T("Номер устройства (GDID)"),L.T("Номер, по которому Microsoft узнаёт ПК даже через VPN. Подробно — на своей вкладке."),GBadge,false,true,false);
            A(S4,"firewall",L.T("Блокировка через брандмауэр"),L.T("Исходящие соединения служб телеметрии. Надёжнее hosts."),GFire,false,true,false);
            A(S4,"buffer",L.T("Стереть неотправленную телеметрию"),L.T("Удаляет накопленный буфер C:\\ProgramData\\Microsoft\\Diagnosis."),GBroom,false,true,false);
            A(S4,"defender",L.T("Защитник: облако и образцы"),L.T("Отправка подозрительных файлов и облачная проверка MAPS. Чуть снижает защиту."),GShield,false,true,false);
            A(S4,"fwips",L.T("Блокировка адресов телеметрии"),L.T("Брандмауэр закрывает сами адреса сбора — в обход hosts не пройти."),GFire,false,true,false);
            A(S4,"apphw",L.T("Камера, микрофон и фон приложений"),L.T("Камера, микрофон и фон для приложений Магазина. Браузеры не затрагивает."),GShield,false,true,false);
            A(S4,"doh",L.T("Запретить шифрованный DNS"),L.T("Без DoH браузеры не обойдут блокировку доменов. Запросы снова видит провайдер."),GGlobe,false,true,false);

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
            _titleBar.Logo = LogoFromIco((int)(u * 1.45F)) ?? _appImage;   // размер — как рисует TitleBar
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
            _pages["home"]     = BuildHomePage();
            _pages["settings"] = BuildSettingsPage();
            _pages["xray"]     = BuildXrayPage();
            _pages["dossier"]  = BuildDossierPage();
            _pages["gdid"]     = BuildGdidPage();
            _pages["audit"]    = BuildAuditPage();
            _pages["monitor"]  = BuildMonitorPage();
            _pages["apps"]     = BuildAppsPage();
            _pages["startup"]  = BuildStartupPage();
            _pages["guard"]    = BuildGuardPage();
            _pages["changes"]  = BuildChangesPage();
            _pages["timeline"] = BuildTimelinePage();
            _pages["log"]      = BuildLogPage();
            _pages["about"]    = BuildAboutPage();
            foreach (Control p in _pages.Values)
            {
                p.Dock = DockStyle.Fill; p.Visible = false; _content.Controls.Add(p);
            }

            // Шапка объединённого раздела: название и вкладки. Докуется первой
            // (в конце списка элементов), поэтому встаёт над страницей.
            foreach (string[] grp in NavGroupPages)
                foreach (string k in grp)
                {
                    _groupOf[k] = grp[0];
                    if (grp.Length > 1 && _pages.ContainsKey(k)) HidePageTitle(_pages[k]);
                }
            _groupHead = new Panel();
            _groupHead.Dock = DockStyle.Top;
            _groupHead.BackColor = Theme.WindowBg;
            _groupHead.Visible = false;
            _groupTitle = PageTitle("");
            _groupTitle.Location = new Point(0, 0);
            _groupHead.Controls.Add(_groupTitle);
            _tabs = new TabStrip();
            _tabs.Font = Font;
            _tabs.TabClicked += delegate(string k) { Navigate(k); };
            _groupHead.Controls.Add(_tabs);
            _groupHead.Resize += delegate { LayoutGroupHead(); };
            _content.Controls.Add(_groupHead);
            _groupHead.SendToBack();
            Navigate("home");
        }

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
        //  Страница: Проверка
        // ================================================================== //
        private Control BuildAuditPage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 3;
            page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));   // иначе страница растёт под самую широкую строку
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            TableLayoutPanel head = new TableLayoutPanel();
            head.ColumnCount = 2; head.Dock = DockStyle.Fill; head.AutoSize = true;
            head.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            head.Controls.Add(PageTitle(L.T("Проверка")), 0, 0);
            FlowLayoutPanel auditBtns = new FlowLayoutPanel();
            auditBtns.AutoSize = true; auditBtns.WrapContents = false;
            auditBtns.Anchor = AnchorStyles.Right | AnchorStyles.Bottom;
            auditBtns.Margin = new Padding(0);
            _btnCleanJunk = new ModernButton(L.T("Убрать мусор"), false);
            _btnCleanJunk.Font = Font; _btnCleanJunk.Visible = false;
            _btnCleanJunk.Margin = new Padding(0, 0, (int)(u * 0.5F), (int)(u * 0.45F));
            _btnCleanJunk.Click += OnCleanJunk;
            ModernButton rerun = new ModernButton(L.T("Проверить сейчас"), true); rerun.Font = Theme.Bold(Font);
            rerun.Margin = new Padding(0, 0, 0, (int)(u * 0.45F));
            rerun.Click += delegate { RunAudit(); };
            ModernButton leak = new ModernButton(L.T("Проверить утечки"), false); leak.Font = Font;
            leak.Margin = new Padding(0, 0, (int)(u * 0.5F), (int)(u * 0.45F));
            leak.Click += OnLeakTest;
            auditBtns.Controls.Add(_btnCleanJunk); auditBtns.Controls.Add(leak); auditBtns.Controls.Add(rerun);
            head.Controls.Add(auditBtns, 1, 0);
            WrapHeadButtons(head, auditBtns);
            page.Controls.Add(head, 0, 0);

            // верх: строка-итог вместо кольца и плиток с крупными числами
            RowList summary = new RowList();
            summary.Dock = DockStyle.Fill; summary.Font = Font; summary.AutoSize = false;
            summary.Margin = new Padding(0, (int)(u * 0.5F), 0, (int)(u * 0.8F));
            _auditStatus = new InfoRow();
            _auditStatus.Font = Font;
            _auditStatus.GlyphTile = true; _auditStatus.Large = true;
            _auditStatus.Set(GNav2, Theme.TextDim, L.T("Проверка ещё не запускалась"),
                L.T("Нажмите «Проверить сейчас» — программа прочитает реальное состояние системы и покажет, что сработало, а что нет."));
            summary.Controls.Add(_auditStatus);
            page.Controls.Add(summary, 0, 1);

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
            page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));   // иначе страница растёт под самую широкую строку
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            page.Controls.Add(PageTitle(L.T("Сеть")), 0, 0);

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
            _monitorState.Text = L.T("Наблюдение за сетью фиксирует попытки программ отправить данные наружу и показывает, кто и куда стучится. Использует брандмауэр и журнал безопасности Windows.");
            ctlIn.Controls.Add(_monitorState, 0, 0);
            FlowLayoutPanel mb = new FlowLayoutPanel(); mb.AutoSize = true; mb.WrapContents = false; mb.Anchor = AnchorStyles.Right;
            _monitorToggle = new ModernButton(L.T("Включить наблюдение"), true); _monitorToggle.Font = Theme.Bold(Font);
            _monitorToggle.Click += OnMonitorToggle;
            ModernButton refresh = new ModernButton(L.T("Обновить"), false); refresh.Click += delegate { RefreshMonitor(); };
            refresh.Margin = new Padding((int)(u*0.5F),0,0,0);
            _netGuardToggle = new ModernButton(L.T("Следить за новыми"), false);
            _netGuardToggle.Click += OnNetGuardToggle;
            _netGuardToggle.Margin = new Padding((int)(u*0.5F),0,0,0);
            mb.Controls.Add(_monitorToggle); mb.Controls.Add(_netGuardToggle); mb.Controls.Add(refresh);
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
            ModernButton refresh = new ModernButton(L.T("Обновить список"), false);
            refresh.Click += delegate { RefreshApps(); };
            ModernButton pick = new ModernButton(L.T("Отметить лишнее"), false);
            pick.Click += delegate { SelectBloat(); };
            _btnAppsRemove = new ModernButton(L.T("Удалить выбранные"), true);
            _btnAppsRemove.Click += OnRemoveApps;
            Label state; StackPanel list; TextBox search;
            TableLayoutPanel page = ListPage(L.T("Предустановленные приложения"),
                L.T("Приложения, которые Windows ставит без спроса. Отмеченные «можно убрать» —\n") +
                L.T("проверенный список; системные компоненты в перечень не попадают вовсе."),
                "apps", out state, out list, out search, refresh, pick, _btnAppsRemove);
            _appsState = state; _appsList = list;
            if (search != null) search.TextChanged += delegate { FilterList(_appsList, search.Text); };
            return page;
        }

        private void RefreshApps()
        {
            RunJson("-ListApps", L.T("Чтение списка приложений…"), RenderApps);
        }

        private void RenderApps(Dictionary<string, object> d)
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

        private void SelectBloat() { CheckSection(_appsList, L.T("Можно убрать — ставится без спроса")); }

        private void OnRemoveApps(object sender, EventArgs e)
        {
            List<string> ids = CheckedIds(_appsList);
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
            ModernButton refresh = new ModernButton(L.T("Обновить список"), false);
            refresh.Click += delegate { RefreshStartup(); };
            ModernButton pick = new ModernButton(L.T("Отметить лишнее"), false);
            pick.Click += delegate { SelectStartupBloat(); };
            _btnStartupOff = new ModernButton(L.T("Отключить выбранные"), true);
            _btnStartupOff.Click += delegate { SetStartupSelected(false); };
            _btnStartupOn = new ModernButton(L.T("Вернуть выбранные"), false);
            _btnStartupOn.Click += delegate { SetStartupSelected(true); };
            Label state; StackPanel list; TextBox search;
            TableLayoutPanel page = ListPage(L.T("Что стартует вместе с Windows"),
                L.T("Обновляторы, агенты телеметрии и помощники производителя запускаются при\n") +
                L.T("каждом входе. Отключение обратимо: запись остаётся на месте, просто гасится."),
                "startup", out state, out list, out search, refresh, pick, _btnStartupOff, _btnStartupOn);
            _startupState = state; _startupList = list;
            if (search != null) search.TextChanged += delegate { FilterList(_startupList, search.Text); };
            return page;
        }

        private void RefreshStartup()
        {
            RunJson("-ListStartup", L.T("Чтение автозагрузки…"), RenderStartup);
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

        private void SelectStartupBloat() { CheckSection(_startupList, L.T("Стартует без нужды — можно отключить")); }

        private void SetStartupSelected(bool on)
        {
            List<string> ids = CheckedIds(_startupList);
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
        //  Каркас страницы-списка: заголовок с поиском, карточка с описанием
        //  и кнопками, список в карточке. Пять страниц повторяли его слово
        //  в слово — теперь он один.
        // ================================================================== //
        private TableLayoutPanel ListPage(string title, string hint, string searchKey,
                                          out Label state, out StackPanel list, out TextBox search,
                                          params ModernButton[] buttons)
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 3;
            page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));   // иначе страница растёт под самую широкую строку
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Absolute, (int)(u * 7.6F)));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            TableLayoutPanel head = new TableLayoutPanel();
            head.ColumnCount = 2; head.RowCount = 1; head.Dock = DockStyle.Fill; head.AutoSize = true;
            head.BackColor = Theme.WindowBg;
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            head.Controls.Add(PageTitle(title), 0, 0);
            search = null;
            if (searchKey != null)
            {
                SearchBox sb = new SearchBox(Font, L.T("Поиск по списку…"));
                sb.Width = (int)(u * 14F);
                sb.Anchor = AnchorStyles.Left;
                sb.Margin = new Padding((int)(u * 1.0F), 0, (int)(u * 0.5F), 0);
                head.Controls.Add(sb, 1, 0);
                TextBox tb = sb.Box;
                search = tb;
                _pageSearch[searchKey] = tb;
            }
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
            state = new Label();
            state.AutoSize = false; state.Dock = DockStyle.Fill;
            state.TextAlign = ContentAlignment.MiddleLeft; state.ForeColor = Theme.TextDim;
            state.Text = hint;
            ci.Controls.Add(state, 0, 0);
            FlowLayoutPanel row = new FlowLayoutPanel();
            AttachButtonRow(row, ctl);
            row.Margin = new Padding(0, (int)(u * 0.5F), 0, 0);
            foreach (ModernButton b in buttons)
            {
                b.Font = b.Primary ? Theme.Bold(Font) : Font;
                b.Margin = new Padding((int)(u * 0.4F), 0, 0, (int)(u * 0.3F));
                row.Controls.Add(b);
            }
            ci.Controls.Add(row, 0, 1);
            ctl.Controls.Add(ci);
            page.Controls.Add(ctl, 0, 1);

            Card listCard = new Card();
            listCard.Dock = DockStyle.Fill; listCard.Padding = new Padding((int)(u * 0.6F));
            listCard.Margin = new Padding(0, 0, 0, (int)(u * 0.3F));
            list = new StackPanel();
            list.Dock = DockStyle.Fill; list.Font = Font;
            list.Padding = new Padding((int)(u * 0.4F));
            Dwm.DarkScrollbars(list);
            listCard.Controls.Add(list);
            page.Controls.Add(listCard, 0, 2);
            return page;
        }

        // Шапка страницы: заголовок слева, кнопки справа. Когда в одну строку
        // всё не помещается, кнопки уходят под заголовок и переносятся по
        // ширине — раньше они молча уезжали за край окна.
        private static void WrapHeadButtons(TableLayoutPanel head, FlowLayoutPanel buttons)
        {
            int column = head.GetColumn(buttons);
            AnchorStyles anchor = buttons.Anchor;
            head.RowCount = 2;
            EventHandler reflow = delegate
            {
                int need = buttons.Margin.Horizontal;
                foreach (Control c in buttons.Controls) if (c.Visible) need += c.Width + c.Margin.Horizontal;
                foreach (Control c in head.Controls)
                    if (c != buttons) need += (c is Label ? c.PreferredSize.Width : c.Width) + c.Margin.Horizontal;
                int room = head.ClientSize.Width;
                if (room < 60) return;
                bool below = need > room;
                Size limit = below ? new Size(room, 0) : Size.Empty;
                if (buttons.MaximumSize == limit && (head.GetRow(buttons) == 1) == below) return;
                head.SuspendLayout();
                buttons.WrapContents = below;       // без предела ширины перенос сложил бы кнопки столбиком
                buttons.MaximumSize = limit;
                head.SetCellPosition(buttons, new TableLayoutPanelCellPosition(below ? 0 : column, below ? 1 : 0));
                head.SetColumnSpan(buttons, below ? head.ColumnCount : 1);
                buttons.Anchor = below ? AnchorStyles.Left : anchor;
                head.ResumeLayout(true);
            };
            // События приходят изнутри раскладки, а она перестановку на ходу не
            // подхватывает: шапка оставалась высотой в две строки. Переставляем
            // следующим шагом, когда раскладка закончится.
            EventHandler later = delegate
            {
                if (head.IsHandleCreated) head.BeginInvoke(reflow, head, EventArgs.Empty);
                else reflow(head, EventArgs.Empty);
            };
            head.Resize += later;
            // кнопка могла появиться или сменить подпись — ширина ряда уже другая
            buttons.Layout += delegate { later(buttons, EventArgs.Empty); };
        }

        // Ряд кнопок переносится на новую строку, когда не помещается по ширине хозяина
        private static void WrapToWidth(FlowLayoutPanel row, Control host)
        {
            row.WrapContents = true;
            host.Resize += delegate
            {
                int w = host.ClientSize.Width - host.Padding.Horizontal;
                if (w <= 120 || row.MaximumSize.Width == w) return;
                row.MaximumSize = new Size(w, 0);
                row.PerformLayout();
                if (row.Parent != null) row.Parent.PerformLayout();
            };
        }

        // Высота ряда кнопок, перенесённого по ширине: считается по самим
        // кнопкам и не зависит от того, успела ли пройти раскладка
        private static int WrappedHeight(FlowLayoutPanel row, int width)
        {
            int x = 0, line = 0, total = 0;
            foreach (Control c in row.Controls)
            {
                int w = c.Width + c.Margin.Horizontal;
                if (x > 0 && x + w > width) { total += line; x = 0; line = 0; }
                x += w;
                line = Math.Max(line, c.Height + c.Margin.Vertical);
            }
            return total + line;
        }

        // Идентификаторы отмеченных строк списка
        private static List<string> CheckedIds(StackPanel list)
        {
            List<string> ids = new List<string>();
            foreach (Control c in list.Controls)
            {
                WipeRow r = c as WipeRow;
                if (r != null && r.Checked) ids.Add(r.Id);
            }
            return ids;
        }

        // Отмечает строки одного раздела и снимает отметку с остальных. Раздел
        // ищется по полному заголовку: разделов может не быть вовсе, а сравнение
        // по первому слову держалось на отдельной записи в словаре и молча
        // ломалось от правки.
        private static void CheckSection(StackPanel list, string title)
        {
            string head = title.ToUpperInvariant();
            bool inside = false;
            foreach (Control c in list.Controls)
            {
                SectionHeader sh = c as SectionHeader;
                if (sh != null) { inside = (sh.Text == head); continue; }
                WipeRow r = c as WipeRow;
                if (r != null) r.Checked = inside;
            }
            list.Invalidate(true);
        }

        // Прячет строки, не подходящие под запрос, вместе с пустыми разделами
        private static void FilterList(StackPanel list, string query)
        {
            if (list == null) return;
            string q = (query ?? "").Trim().ToLowerInvariant();
            list.Hidden.Clear();
            if (q.Length > 0)
            {
                SectionHeader head = null; bool any = false;
                foreach (Control c in list.Controls)
                {
                    SectionHeader sh = c as SectionHeader;
                    if (sh != null)
                    {
                        if (head != null && !any) list.Hidden.Add(head);
                        head = sh; any = false; continue;
                    }
                    IFilterable f = c as IFilterable;
                    bool match = (f == null) || f.FilterText.ToLowerInvariant().Contains(q);
                    if (!match) list.Hidden.Add(c); else any = true;
                }
                if (head != null && !any) list.Hidden.Add(head);
            }
            try { list.VerticalScroll.Value = 0; } catch { }
            list.Restack();
        }

        // ================================================================== //
        //  Страница: Изменения — что программа поменяла и как вернуть обратно
        // ================================================================== //
        private Control BuildChangesPage()
        {
            ModernButton refresh = new ModernButton(L.T("Обновить"), false);
            refresh.Click += delegate { RefreshChanges(); };
            _btnChangesBack = new ModernButton(L.T("Вернуть выбранные"), true);
            _btnChangesBack.Click += OnRestoreSelected;
            ModernButton all = new ModernButton(L.T("Вернуть всё"), false);
            all.Click += OnRestoreAll;
            ModernButton fromBackup = new ModernButton(L.T("Из резервной копии"), false);
            fromBackup.Click += OnRestoreFromBackup;
            Label state; StackPanel list; TextBox search;
            TableLayoutPanel page = ListPage(L.T("Что программа изменила"),
                L.T("Каждое изменение записано вместе с прежним значением. Любую строку\n") +
                L.T("можно вернуть по отдельности — система станет ровно такой, как была."),
                "changes", out state, out list, out search, refresh, _btnChangesBack, all, fromBackup);
            _changesState = state; _changesList = list;
            if (search != null) search.TextChanged += delegate { FilterList(_changesList, search.Text); };
            return page;
        }

        private void RefreshChanges()
        {
            RunJson("-ChangeLog", L.T("Чтение журнала изменений…"), RenderChanges);
        }

        private void RenderChanges(Dictionary<string, object> d)
        {
            _changesList.Controls.Clear();
            List<object> items = (d != null) ? Json.GetArr(d, "items") : new List<object>();
            if (items.Count == 0)
            {
                SectionHeader sh = new SectionHeader(L.T("Программа ещё ничего не меняла"));
                sh.Font = Font; _changesList.Controls.Add(sh);
                _changesList.Restack();
                _changesState.Text = L.T("Журнал пуст: настройки ещё не применялись.\n") +
                                     L.T("После применения здесь появится каждое изменение с прежним значением.");
                if (_btnChangesBack != null) _btnChangesBack.Enabled = false;
                return;
            }
            if (_btnChangesBack != null) _btnChangesBack.Enabled = true;
            SectionHeader head = new SectionHeader(L.T("Свежие изменения сверху"));
            head.Font = Font; _changesList.Controls.Add(head);
            foreach (object o in items)
            {
                Dictionary<string, object> it = Json.Obj(o);
                // движок отдаёт эти поля словами, а не числами: «запускалась»,
                // «не было», «автозагрузка» — их тоже надо переводить
                string was = L.T(Json.GetStr(it, "was")), now = L.T(Json.GetStr(it, "now"));
                string what = L.T("было: ") + was + L.T("   ·   стало: ") + now + "   ·   " + L.T(Json.GetStr(it, "where"));
                WipeRow r = new WipeRow(Json.GetStr(it, "id"), L.T(Json.GetStr(it, "title")), what,
                                        Json.GetStr(it, "time").Replace("T", " "),
                                        Json.GetStr(it, "kind") == "startup" ? GPower : GUndo, true);
                r.Font = Font;
                _changesList.Controls.Add(r);
            }
            _changesList.Restack();
            _changesState.Text = L.T("Записей в журнале: ") + items.Count + L.T(", изменений всего: ") + Json.GetInt(d, "raw") + ".\n" +
                                 L.T("Отметьте строки и нажмите «Вернуть выбранные» — вернётся то значение, что было до программы.");
        }

        private void OnRestoreSelected(object sender, EventArgs e)
        {
            List<string> ids = CheckedIds(_changesList);
            if (ids.Count == 0)
            {
                MessageBox.Show(this, L.T("Отметьте галочками, что вернуть."), L.T("Ничего не выбрано"),
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            if (MessageBox.Show(this, L.T("Будет возвращено изменений: ") + ids.Count + ".\n\n" +
                L.T("Каждый параметр вернётся в то значение, которое было до программы,\n") +
                L.T("и пропадёт из журнала.\n\nПродолжить?"),
                L.T("Возврат изменений"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            RunStreaming("-RestoreItems -ChangeItems \"" + string.Join(",", ids.ToArray()) + "\"",
                L.T("Возврат выбранных изменений…"), delegate { Navigate("changes"); RefreshChanges(); });
        }

        // Копии .reg программа делала и раньше, но импортировать их приходилось
        // руками. Теперь круг замкнут прямо из окна.
        private void OnRestoreFromBackup(object sender, EventArgs e)
        {
            RunJson("-ListBackups", L.T("Поиск резервных копий…"), delegate(Dictionary<string, object> d)
            {
                List<object> items = (d != null) ? Json.GetArr(d, "items") : new List<object>();
                if (items.Count == 0)
                {
                    MessageBox.Show(this, L.T("Резервных копий не найдено.\n\n") +
                        L.T("Программа создаёт их на рабочем столе перед первым изменением\n") +
                        L.T("в каждом запуске. Если папку перенесли — верните её на место."),
                        L.T("Восстановление из копии"), MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                string[] lines = new string[items.Count];
                string[] paths = new string[items.Count];
                for (int i = 0; i < items.Count; i++)
                {
                    Dictionary<string, object> b = Json.Obj(items[i]);
                    paths[i] = Json.GetStr(b, "path");
                    lines[i] = Json.GetStr(b, "when") + "   ·   " + Json.GetInt(b, "branches") + L.T(" веток") +
                               "   ·   " + Json.GetStr(b, "kb") + L.T(" КБ");
                }
                using (ListDialog dlg = new ListDialog(L.T("Восстановление из копии"),
                    L.T("Выберите копию — её значения вернутся в реестр как были на тот момент."),
                    lines, L.T("Восстановить"), Font, true))
                {
                    if (dlg.ShowDialog(this) != DialogResult.OK) return;
                    int idx = dlg.SelectedIndex;
                    if (idx < 0 || idx >= paths.Length) return;
                    if (MessageBox.Show(this, L.T("Из копии будут возвращены все сохранённые ветки реестра:\n\n") +
                        paths[idx] + L.T("\n\nТекущие значения этих параметров будут заменены.\n\nПродолжить?"),
                        L.T("Восстановление из копии"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
                    RunStreaming("-RestoreBackup -BackupPath \"" + paths[idx] + "\"",
                        L.T("Восстановление из копии…"), delegate { Navigate("changes"); RefreshChanges(); });
                }
            });
        }

        private void OnRestoreAll(object sender, EventArgs e)
        {
            if (MessageBox.Show(this, L.T("Программа вернёт все параметры реестра и записи автозапуска\n") +
                L.T("в то состояние, в котором они были до неё, и очистит журнал.\n\nПродолжить?"),
                L.T("Возврат изменений"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming("-RestoreAll", L.T("Возврат всех изменений…"), delegate { Navigate("changes"); RefreshChanges(); });
        }

        // ================================================================== //
        //  Страница: Хронология приватности
        //  Один график вместо разрозненных цифр: сколько событий уходило в
        //  день, когда приезжали обновления Windows, что меняла программа и
        //  что возвращал страж. Видно, как система отыгрывает настройки назад.
        // ================================================================== //
        private Control BuildTimelinePage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 4;
            page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));   // иначе страница растёт под самую широкую строку
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Absolute, (int)(u * 7.6F)));
            page.RowStyles.Add(new RowStyle(SizeType.Absolute, (int)(u * 14F)));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            page.Controls.Add(PageTitle(L.T("Хронология")), 0, 0);

            Card ctl = new Card();
            ctl.Dock = DockStyle.Fill;
            ctl.Margin = new Padding(0, (int)(u * 0.5F), 0, (int)(u * 0.5F));
            ctl.Padding = new Padding((int)(u * 0.9F), (int)(u * 0.7F), (int)(u * 0.9F), (int)(u * 0.7F));
            TableLayoutPanel ci = new TableLayoutPanel();
            ci.Dock = DockStyle.Fill; ci.AutoSize = true; ci.ColumnCount = 1; ci.RowCount = 2;
            ci.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            ci.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            ci.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            _timelineState = new Label();
            _timelineState.AutoSize = false; _timelineState.Dock = DockStyle.Fill;
            _timelineState.TextAlign = ContentAlignment.MiddleLeft; _timelineState.ForeColor = Theme.TextDim;
            _timelineState.Text = L.T("Программа копит историю: события телеметрии по дням, обновления Windows,\n") +
                                  L.T("свои правки и возвраты автозащиты. Чем дольше она стоит, тем больше видно.");
            ci.Controls.Add(_timelineState, 0, 0);
            FlowLayoutPanel tb = new FlowLayoutPanel();
            AttachButtonRow(tb, ctl);
            tb.Margin = new Padding(0, (int)(u * 0.4F), 0, 0);
            ModernButton refresh = new ModernButton(L.T("Обновить"), false);
            refresh.Click += delegate { RefreshTimeline(); };
            ModernButton scan = new ModernButton(L.T("Замерить телеметрию"), false);
            scan.Click += delegate { Navigate("xray"); RunXrayScan(false); };
            foreach (ModernButton b in new[] { refresh, scan })
            { b.Font = Font; b.Margin = new Padding((int)(u * 0.4F), 0, 0, (int)(u * 0.3F)); tb.Controls.Add(b); }
            ci.Controls.Add(tb, 0, 1);
            ctl.Controls.Add(ci);
            page.Controls.Add(ctl, 0, 1);

            Card chartCard = new Card();
            chartCard.Dock = DockStyle.Fill;
            chartCard.Margin = new Padding(0, 0, 0, (int)(u * 0.5F));
            chartCard.Padding = new Padding((int)(u * 0.8F), (int)(u * 0.6F), (int)(u * 0.8F), (int)(u * 0.4F));
            _timeline = new TimelineChart();
            _timeline.Dock = DockStyle.Fill; _timeline.Font = Font;
            _timeline.Empty = L.T("Линии телеметрии пока нет: включите запись на вкладке «Сбор данных» и нажмите «Замерить».");
            chartCard.Controls.Add(_timeline);
            page.Controls.Add(chartCard, 0, 2);

            Card notes = new Card();
            notes.Dock = DockStyle.Fill; notes.Padding = new Padding((int)(u * 0.6F));
            notes.Margin = new Padding(0, 0, 0, (int)(u * 0.3F));
            _timelineNotes = new StackPanel();
            _timelineNotes.Dock = DockStyle.Fill; _timelineNotes.Font = Font;
            _timelineNotes.Padding = new Padding((int)(u * 0.4F));
            Dwm.DarkScrollbars(_timelineNotes);
            notes.Controls.Add(_timelineNotes);
            page.Controls.Add(notes, 0, 3);
            return page;
        }

        private void RefreshTimeline()
        {
            RunJson("-Timeline -TimelineDays 30", L.T("Сбор хронологии…"), RenderTimeline);
        }

        private Dictionary<string, object> _lastTimeline;

        private void RenderTimeline(Dictionary<string, object> d)
        {
            if (d == null) { _timelineState.Text = L.T("Не удалось собрать хронологию."); return; }
            _lastTimeline = d;
            List<object> days = Json.GetArr(d, "days");
            _timeline.SetData(days);

            _timelineNotes.Controls.Clear();
            List<object> notes = Json.GetArr(d, "notes");
            SectionHeader sh = new SectionHeader(L.T("Что случилось за это время"));
            sh.Font = Font; _timelineNotes.Controls.Add(sh);
            if (notes.Count == 0)
            {
                _timelineNotes.Controls.Add(new KvRow(L.T("Пока ничего примечательного не происходило"), "", false) { Font = this.Font });
            }
            else
            {
                for (int i = notes.Count - 1; i >= 0; i--)
                {
                    Dictionary<string, object> n = Json.Obj(notes[i]);
                    string kind = Json.GetStr(n, "kind");
                    bool bad = (kind == "grow" || kind == "drift");
                    string text;
                    if (kind == "update") text = L.T("Обновление Windows: ") + Json.GetStr(n, "list");
                    else if (kind == "drift") text = L.T("Автозащита нашла сбитых настроек: ") + Json.GetInt(n, "a") + L.T(", вернул: ") + Json.GetInt(n, "b");
                    else text = L.T("Телеметрия выросла: было ") + Json.GetInt(n, "a") + L.T(" событий в сутки, стало ") + Json.GetInt(n, "b");
                    _timelineNotes.Controls.Add(new KvRow(Json.GetStr(n, "date") + "   ·   " + text, "", bad) { Font = this.Font });
                }
            }
            _timelineNotes.Restack();

            int shown = days.Count;
            _timelineState.Text = L.T("Показано дней: ") + shown +
                (Json.GetBool(d, "hasXray") ? L.T(". Столбики — события телеметрии в сутки.")
                                            : L.T(". Столбики — обращения к датчикам: замера телеметрии ещё не было.")) + "\n" +
                L.T("Красная черта — обновление Windows, зелёная точка — правка программы, жёлтая — возврат автозащиты.");
        }

        // ================================================================== //
        //  Страница: Страж
        // ================================================================== //
        private Control BuildGuardPage()
        {
            _btnGuardInstall = new ModernButton(L.T("Включить автозащиту"), true); _btnGuardInstall.Click += OnGuardInstall;
            _btnGuardNow = new ModernButton(L.T("Проверить"), false); _btnGuardNow.Click += OnGuardNow;
            _btnGuardRemove = new ModernButton(L.T("Отключить"), false); _btnGuardRemove.Click += OnGuardRemove;
            _btnWatcher = new ModernButton(L.T("Уведомления"), false); _btnWatcher.Click += OnWatcherToggle;
            _btnSensorGuard = new ModernButton(L.T("Датчики"), false); _btnSensorGuard.Click += OnSensorToggle;
            _btnSnapshot = new ModernButton(L.T("Снимок"), false); _btnSnapshot.Click += OnSnapshot;
            _btnGuardFreq = new ModernButton(GuardFreqText(), false);
            _btnGuardFreq.Click += delegate
            {
                _guardDaily = !_guardDaily;
                _btnGuardFreq.Text = GuardFreqText();
                _status.Text = _guardDaily ? L.T("Автозащита будет проверять каждый день. Нажмите «Включить автозащиту».")
                                           : L.T("Автозащита будет проверять раз в неделю. Нажмите «Включить автозащиту».");
            };
            Label state; StackPanel list; TextBox search;
            TableLayoutPanel page = ListPage(L.T("Автозащита"),
                L.T("Крупные обновления Windows тихо возвращают часть настроек назад.\n") +
                L.T("Автозащита проверяет систему по расписанию, возвращает сбитое и предупреждает."),
                null, out state, out list, out search,
                _btnGuardInstall, _btnGuardNow, _btnGuardRemove, _btnGuardFreq, _btnWatcher, _btnSensorGuard, _btnSnapshot);
            _guardState = state; _guardBody = list;
            return page;
        }

        private ModernButton _btnGuardInstall, _btnGuardNow, _btnGuardRemove, _btnWatcher, _btnSensorGuard, _btnSnapshot, _btnGuardFreq;
        private bool _watcherOn, _sensorOn, _guardDaily;
        private string GuardFreqText() { return _guardDaily ? L.T("Проверка: каждый день") : L.T("Проверка: раз в неделю"); }

        // ================================================================== //
        //  Страница: Журнал
        // ================================================================== //
        private Control BuildLogPage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 2;
            page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));   // иначе страница растёт под самую широкую строку
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            // Заголовок с кнопкой: по этим журналам находились прошлые ошибки,
            // но выгрузить их можно было только выделением мышью.
            TableLayoutPanel head = new TableLayoutPanel();
            head.ColumnCount = 2; head.RowCount = 1; head.AutoSize = true;
            head.BackColor = Theme.WindowBg; head.Dock = DockStyle.Fill;
            head.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            head.Controls.Add(PageTitle(L.T("Журнал")), 0, 0);

            FlowLayoutPanel logBtns = new FlowLayoutPanel();
            logBtns.AutoSize = true; logBtns.WrapContents = false;
            logBtns.Anchor = AnchorStyles.Right | AnchorStyles.Bottom;
            logBtns.Margin = new Padding(0, 0, 0, (int)(u * 0.45F));
            ModernButton logSave = new ModernButton(L.T("Сохранить журнал"), false);
            logSave.Font = Font; logSave.Margin = new Padding(0, 0, (int)(u * 0.4F), 0);
            logSave.Click += delegate { SaveLogToFile(); };
            ModernButton logClear = new ModernButton(L.T("Очистить"), false);
            logClear.Font = Font; logClear.Margin = new Padding(0);
            logClear.Click += delegate { if (_log != null) { _log.Clear(); UpdateLogEmpty(); } };
            logBtns.Controls.Add(logSave); logBtns.Controls.Add(logClear);
            head.Controls.Add(logBtns, 1, 0);
            WrapHeadButtons(head, logBtns);
            page.Controls.Add(head, 0, 0);

            // Фон карточки — как у самого журнала: раньше тёмное поле сидело
            // в более светлой рамке, и выходила двойная обводка.
            Card card = new Card(); card.Dock = DockStyle.Fill; card.Padding = new Padding((int)(u*0.6F));
            card.Margin = new Padding(0,(int)(u*0.5F),0,(int)(u*0.3F));
            card.BackColor = Theme.LogBg;
            _log = new RichTextBox();
            _log.Dock = DockStyle.Fill; _log.ReadOnly = true; _log.BorderStyle = BorderStyle.None;
            _log.BackColor = Theme.LogBg; _log.ForeColor = Theme.TextDim;
            _log.Font = Theme.PickFont(Theme.MonoFonts, Font.Size * 0.92F, FontStyle.Regular);
            _log.WordWrap = true; _log.ScrollBars = RichTextBoxScrollBars.Vertical; _log.DetectUrls = false;
            _log.TextChanged += delegate { UpdateLogEmpty(); };
            Dwm.DarkScrollbars(_log);
            card.Controls.Add(_log);

            // Пока в журнале ничего нет — пояснение, а не «вывод»: подсказка
            // больше не попадает в сохранённый файл и не мешает понять, что
            // журнал пуст.
            _logEmpty = new EmptyState();
            _logEmpty.Dock = DockStyle.Fill;
            _logEmpty.Font = Font;
            _logEmpty.BackColor = Theme.LogBg;
            _logEmpty.Glyph = "";
            _logEmpty.Title = L.T("Журнал пока пуст");
            _logEmpty.Note = L.T("Здесь по шагам видно, что программа делает: применение и откат настроек, работа автозащиты и наблюдения за сетью. Если что-то пошло не так, сохраните журнал и приложите его к сообщению об ошибке.");
            card.Controls.Add(_logEmpty);
            _logEmpty.BringToFront();
            page.Controls.Add(card, 0, 1);
            return page;
        }

        private EmptyState _logEmpty;

        private void UpdateLogEmpty()
        {
            if (_logEmpty == null || _log == null) return;
            bool empty = _log.TextLength == 0;
            if (_logEmpty.Visible != empty) _logEmpty.Visible = empty;
        }

        // Журнал выгружается в файл целиком: именно по нему разбираются
        // случаи «применилось не то» — присылать снимок экрана неудобно.
        private void SaveLogToFile()
        {
            if (_log == null || _log.TextLength == 0)
            {
                MessageBox.Show(this, L.T("Журнал пока пуст."), L.T("Сохранение журнала"),
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            string path;
            using (SaveFileDialog d = new SaveFileDialog())
            {
                d.Filter = L.T("Текстовый файл (*.txt)|*.txt");
                d.FileName = "win11privacy-log-" + DateTime.Now.ToString("yyyy-MM-dd-HHmm") + ".txt";
                if (d.ShowDialog(this) != DialogResult.OK) return;
                path = d.FileName;
            }
            try
            {
                StringBuilder sb = new StringBuilder();
                sb.AppendLine(L.T("Приватность Windows 11, версия ") + AppInfo.Version);
                sb.AppendLine(Environment.OSVersion.VersionString + (Environment.Is64BitOperatingSystem ? " x64" : " x86"));
                sb.AppendLine(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
                sb.AppendLine(new string('-', 60));
                sb.AppendLine(_log.Text);
                File.WriteAllText(path, sb.ToString(), new UTF8Encoding(true));
                _status.Text = L.T("Журнал сохранён: ") + Path.GetFileName(path);
            }
            catch (Exception ex)
            { MessageBox.Show(this, ex.Message, L.T("Ошибка"), MessageBoxButtons.OK, MessageBoxIcon.Error); }
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
            FlowLayoutPanel aboutBtns = new FlowLayoutPanel();
            aboutBtns.AutoSize = true; aboutBtns.WrapContents = true;    // ширину задаёт FitAboutCards
            aboutBtns.Anchor = AnchorStyles.Left | AnchorStyles.Bottom;
            aboutBtns.Margin = new Padding((int)(u * 1.2F), 0, 0, (int)(u * 0.15F));
            _aboutBtns = aboutBtns;
            // как в Windows → русский → английский → как в Windows
            ModernButton bLang = new ModernButton(LangButtonText(), false);
            bLang.Font = Font;
            bLang.Click += delegate
            {
                _langChoice = (_langChoice + 1) % 3;
                SaveUiState();
                bLang.Text = LangButtonText();
                bool next = _langChoice == 0 ? L.SystemEnglish() : _langChoice == 2;
                if (next != L.English)
                    MessageBox.Show(this,
                        next ? "The language will change after restarting the program."
                             : "Язык интерфейса сменится после перезапуска программы.",
                        L.T("Приватность Windows 11"), MessageBoxButtons.OK, MessageBoxIcon.Information);
            };
            aboutBtns.Controls.Add(bLang);

            ModernButton bTheme = new ModernButton(ThemeButtonText(), false);
            bTheme.Font = Font;
            bTheme.Click += delegate
            {
                _themeChoice = (_themeChoice + 1) % 3;
                SaveUiState();
                bTheme.Text = ThemeButtonText();
                MessageBox.Show(this, L.T("Тема сменится после перезапуска программы."),
                    L.T("Приватность Windows 11"), MessageBoxButtons.OK, MessageBoxIcon.Information);
            };
            aboutBtns.Controls.Add(bTheme);

            ModernButton bUpd = new ModernButton(L.T("Проверить обновление"), false);
            _btnUpdate = bUpd;
            bUpd.Font = Font;
            bUpd.Click += delegate { CheckUpdate(bUpd); };
            aboutBtns.Controls.Add(bUpd);

            ModernButton bPurge = new ModernButton(L.T("Удалить данные программы"), false);
            bPurge.Font = Font;
            bPurge.Click += OnPurgeData;
            aboutBtns.Controls.Add(bPurge);
            foreach (Control b in aboutBtns.Controls) b.Margin = new Padding(0, 0, (int)(u * 0.4F), (int)(u * 0.3F));
            aboutHead.Controls.Add(aboutBtns, 1, 0);
            f.Controls.Add(aboutHead);

            _aboutVersion = AboutCard(L.T("Версия программы"), VersionText());
            f.Controls.Add(_aboutVersion);

            _aboutEdition = AboutCard(L.T("Ваша система"), L.T("Определение…"));
            f.Controls.Add(_aboutEdition);

            _aboutData = AboutCard(L.T("Что программа хранит о вас у себя"), L.T("Чтение…"));
            f.Controls.Add(_aboutData);

            f.Controls.Add(AboutCard(L.T("Что умеет эта программа, чего нет у других"),
                L.T("• Следы на компьютере: кто и когда реально включал камеру, микрофон и геолокацию — с длительностью и меткой «сейчас».\n") +
                L.T("• Слежение за датчиками: уведомление в момент, когда НОВАЯ программа впервые получила доступ; график по дням.\n") +
                L.T("• Цифровой след: рекламный ID, история сетей и флешек, всё, что Windows помнит о вас — с выборочным стиранием.\n") +
                L.T("• Сбор данных: настоящие события, собранные о компьютере, с сырым содержимым.\n") +
                L.T("• Проверка на деле: читает реальное состояние системы и показывает индекс, а не «галочки».\n") +
                L.T("• Сеть: показывает, кто и куда реально отправляет данные.\n") +
                L.T("• Автозащита: возвращает настройки, сбитые обновлениями Windows; машина времени со снимками состояния.\n") +
                L.T("• Телеметрия сторонних программ и слежка производителя ноутбука.\n") +
                L.T("• Блокировка через брандмауэр, а не только hosts; удаление накопленного буфера телеметрии.\n") +
                L.T("• Профили и тихий запуск из командной строки для настройки нескольких ПК.\n") +
                L.T("• Быстрые клавиши: Ctrl+1…9 и Ctrl+0 — страницы, Ctrl+F — поиск по настройкам.")));

            f.Controls.Add(AboutCard(L.T("Командная строка"),
                L.T("Win11Privacy.exe --profile \"C:\\путь\\profile.json\" --silent   тихо применить профиль\n") +
                L.T("Win11Privacy.exe --audit                                     проверка (код возврата = число несоответствий)\n") +
                L.T("Профиль сохраняется кнопкой «Сохранить профиль» на странице «Настройки»."), true));

            f.Controls.Add(AboutCard(L.T("Честно о пределах"),
                L.T("Полностью прекратить обмен данными с Microsoft на Windows нельзя: остаются проверка обновлений,\n") +
                L.T("активация лицензии и проверка сертификатов. На редакциях Home и Pro минимальный уровень телеметрии\n") +
                L.T("система трактует как «Обязательные данные» — это ограничение редакции, а не программы. Всё, что можно\n") +
                L.T("отключить без поломки системы, эта программа отключает, а автозащита не даёт вернуть обратно.")));

            f.Controls.Add(AboutCard(L.T("Запуск без предупреждения SmartScreen"),
                L.T("Синее окно показывается любому неподписанному приложению из интернета. Убрать его можно так:\n") +
                L.T("правый клик по файлу → Свойства → внизу галочка «Разблокировать» → ОК. Запрос прав администратора\n") +
                L.T("(UAC) остаётся — он нужен, потому что программа меняет системные настройки.")));
            page.Controls.Add(f);
            page.Resize += delegate { FitAboutCards(page); };
            _aboutFlow = f;
            return page;
        }
        private Control _aboutEdition, _aboutData, _aboutVersion;
        private ModernButton _btnUpdate;
#pragma warning disable 0649
        private bool _mockMode;             // ставится только в тестовой сборке
#pragma warning restore 0649
        // Переносимый режим: рядом с exe лежит файл portable.txt — тогда все
        // данные программы хранятся там же, а не в ProgramData, и на чужом
        // компьютере после себя ничего не остаётся.
        private static string _portableRoot;
        private static string PortableRoot()
        {
            if (_portableRoot != null) return _portableRoot;
            _portableRoot = "";
            try
            {
                string dir = Path.GetDirectoryName(Application.ExecutablePath);
                if (File.Exists(Path.Combine(dir, "portable.txt")))
                {
                    string data = Path.Combine(dir, "Win11Privacy-Data");
                    if (!Directory.Exists(data)) Directory.CreateDirectory(data);
                    _portableRoot = data;
                }
            }
            catch { }
            return _portableRoot;
        }
        private FlowLayoutPanel _aboutFlow, _aboutBtns;

        // Старый флаг «en» → выбор языка: совпадает с Windows — «как в Windows»
        internal static int LangChoiceFromOld(bool en, bool systemEnglish)
        {
            return en == systemEnglish ? 0 : (en ? 2 : 1);
        }

        private string LangButtonText()
        {
            if (_langChoice == 1) return L.T("Язык: русский");
            if (_langChoice == 2) return L.T("Язык: английский");
            return L.T("Язык: как в Windows");
        }

        private string ThemeButtonText()
        {
            if (_themeChoice == 1) return L.T("Тема: тёмная");
            if (_themeChoice == 2) return L.T("Тема: светлая");
            return L.T("Тема: как в Windows");
        }

        // Что программа накопила у себя — и кнопка это стереть
        private void RefreshDataInfo()
        {
            RunJson("-DataInfo", L.T("Чтение данных программы…"), delegate(Dictionary<string, object> d)
            {
                if (d == null) { SetAboutBody(_aboutData, L.T("Не удалось прочитать папку с данными.")); return; }
                List<object> items = Json.GetArr(d, "items");
                StringBuilder sb = new StringBuilder();
                sb.Append(L.T("Папка: ")).Append(Json.GetStr(d, "folder")).Append("\n");
                if (items.Count == 0) sb.Append(L.T("Программа ничего о вас не хранит."));
                else
                {
                    foreach (object o in items)
                    {
                        Dictionary<string, object> it = Json.Obj(o);
                        sb.Append("• ").Append(L.T(Json.GetStr(it, "title")))
                          .Append(" — ").Append(Json.GetStr(it, "kb")).Append(L.T(" КБ, изменён "))
                          .Append(Json.GetStr(it, "changed")).Append("\n");
                    }
                    sb.Append(L.T("Всего: ")).Append(Json.GetStr(d, "kb")).Append(L.T(" КБ. Наружу ничего из этого не уходит."));
                }
                SetAboutBody(_aboutData, sb.ToString());
            });
        }

        private void OnPurgeData(object sender, EventArgs e)
        {
            if (MessageBox.Show(this,
                L.T("Программа удалит всё, что накопила о вас у себя: историю датчиков,\n") +
                L.T("журнал изменений, снимки и эталоны сбора данных.\n\n") +
                L.T("Вернуть настройки «как было» после этого будет нечем — журнал отката\n") +
                L.T("пропадёт вместе с остальным.\n\nПродолжить?"),
                L.T("Удаление данных программы"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming("-PurgeData", L.T("Удаление данных программы…"), delegate { Navigate("about"); RefreshDataInfo(); });
        }

        // Карточки «О программе» тянутся по ширине окна, но не шире 54 строчных высот
        private void FitAboutCards(Control page)
        {
            if (_aboutFlow == null) return;
            int u = Font.Height;
            int w = Math.Max((int)(u * 24F), Math.Min((int)(u * 54F), page.ClientSize.Width - (int)(u * 1.2F)));
            // кнопки шапки переносятся, а не уезжают за край узкого окна
            Control title = _aboutBtns.Parent.Controls[0];
            int room = page.ClientSize.Width - title.PreferredSize.Width - title.Margin.Horizontal - _aboutBtns.Margin.Horizontal;
            _aboutBtns.MaximumSize = new Size(Math.Max((int)(u * 12F), room), 0);
            foreach (Control c in _aboutFlow.Controls)
            {
                TableLayoutPanel tl = null;
                foreach (Control cc in c.Controls) { tl = cc as TableLayoutPanel; if (tl != null) break; }
                if (tl == null || tl.ColumnStyles.Count == 0) continue;
                int inner = w - c.Padding.Horizontal;
                if ((int)tl.ColumnStyles[0].Width == inner) continue;
                tl.ColumnStyles[0].Width = inner;
                tl.Width = inner;
                foreach (Control lb in tl.Controls)
                    if (lb is Label) lb.MaximumSize = new Size(inner, 0);
            }
        }

        private Control AboutCard(string title, string body) { return AboutCard(title, body, false); }

        // ВАЖНО: шрифт меткам задаём здесь же. Раньше высота карточки считалась
        // до того, как ей доставался шрифт формы, — по системному 8-точечному,
        // и настоящий текст в эту высоту потом не влезал (обрезался снизу).
        private Control AboutCard(string title, string body, bool mono)
        {
            int u = Font.Height;
            int cardW = (int)(u * 54F);
            int padX = (int)(u * 0.9F);
            int innerW = cardW - padX * 2;
            Card c = new Card();
            c.Margin = new Padding(0, 0, 0, (int)(u * 0.6F));
            c.Padding = new Padding(padX, (int)(u * 0.7F), padX, (int)(u * 0.7F));
            c.AutoSize = true;
            c.AutoSizeMode = AutoSizeMode.GrowAndShrink;

            TableLayoutPanel tl = new TableLayoutPanel();
            tl.AutoSize = true; tl.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            tl.ColumnCount = 1; tl.RowCount = 2; tl.BackColor = Theme.CardBg;
            tl.Margin = new Padding(0);
            // обычная панель не двигает недокованных детей на свой Padding —
            // ставим руками, иначе текст прижимается к самому краю карточки
            tl.Location = new Point(padX, (int)(u * 0.7F));
            tl.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, innerW));
            tl.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            tl.RowStyles.Add(new RowStyle(SizeType.AutoSize));

            Label t = new Label(); t.Text = title; t.Font = Theme.Bold(Font); t.ForeColor = Theme.Text;
            t.AutoSize = true; t.MaximumSize = new Size(innerW, 0);
            t.Margin = new Padding(0, 0, 0, (int)(u * 0.4F));
            Label b = new Label(); b.Text = body; b.ForeColor = Theme.TextDim; b.AutoSize = true;
            // моноширинный — для командной строки: только так колонки сходятся
            b.Font = mono ? Theme.PickFont(Theme.MonoFonts, Font.Size * 0.95F, FontStyle.Regular) : Font;
            b.Margin = new Padding(0);
            b.MaximumSize = new Size(innerW, 0); b.Tag = "body";
            tl.Controls.Add(t, 0, 0); tl.Controls.Add(b, 0, 1);
            c.Controls.Add(tl);
            return c;
        }
        // Версия видна не из любви к номерам: в 1.1–1.5 настройки писались под
        // числовыми именами и ничего не меняли, и человеку нужно понимать,
        // относится ли к нему совет «нажмите „Убрать мусор“».
        private string VersionText()
        {
            string s = L.T("Версия ") + AppInfo.Version + "." + "\n" +
                       L.T("Обновления сама программа не проверяет и в сеть не выходит: только по кнопке «Проверить обновление».");
            if (_updateNote != null) s += "\n" + _updateNote;
            string dir = EngineFile.Folder;
            if (dir.Length > 0)
                s += "\n" + L.T("Движок распакован: ") + dir +
                     (EngineFile.Guarded ? L.T(" (папка закрыта для записи без прав администратора)")
                                         : L.T(" (временная папка — прав на защищённую не хватило)"));
            return s;
        }

#if UITEST
        // Нажимает кнопку так же, как это делает человек: проверяется весь путь
        // от щелчка до вердикта, а не одна лишь работа с сетью.
        internal void PressUpdateForTest()
        {
            if (_btnUpdate == null) { Console.WriteLine("UPDATE кнопка не найдена"); return; }
            InvokeOnClick(_btnUpdate, EventArgs.Empty);
        }
#endif

        // Что ответил GitHub в прошлый раз. Хранится, потому что карточку
        // перерисовывает и определение системы — оно заканчивается позже
        // проверки и раньше затирало её ответ.
        private string _updateNote;

        private void CheckUpdate(ModernButton btn)
        {
            btn.Enabled = false;
            _status.Text = L.T("Проверка обновления…");
            System.Threading.Thread th = new System.Threading.Thread(delegate()
            {
                string err;
                string tag = AppInfo.LatestRelease(out err);
                try { BeginInvoke((MethodInvoker)delegate { ShowUpdate(tag, err, btn); }); } catch { }
            });
            th.IsBackground = true;
            th.Start();
        }

        // Что именно сказать про версию — решается отдельно от показа окна.
        // Так вердикт можно проверить, не открывая модальных диалогов, и так
        // видно, что состояний не два, а четыре: своя сборка бывает и новее
        // последнего релиза (промежуточная, собранная из исходников).
        internal enum UpdateState { Failed, Newer, Same, Ahead }

        internal static UpdateState UpdateVerdict(string tag, string err, out string status, out string card)
        {
            if (tag == null || tag.Length == 0)
            {
                status = L.T("Проверить не удалось.");
                card = err;
                return UpdateState.Failed;
            }
            int cmp = AppInfo.Compare(AppInfo.Version, tag);
            if (cmp < 0)
            {
                status = L.T("Есть новая версия: ") + tag;
                card = L.T("На GitHub выложена ") + tag;
                return UpdateState.Newer;
            }
            if (cmp == 0)
            {
                status = L.T("У вас последняя версия.");
                card = L.T("На GitHub та же версия — обновляться не нужно.");
                return UpdateState.Same;
            }
            status = L.T("У вас сборка новее релиза.");
            card = L.T("На GitHub пока ") + tag + L.T(" — ваша сборка новее.");
            return UpdateState.Ahead;
        }

        private void ShowUpdate(string tag, string err, ModernButton btn)
        {
            btn.Enabled = true;
            string status, card;
            UpdateState st = UpdateVerdict(tag, err, out status, out card);
            _status.Text = status;
            if (st != UpdateState.Failed) _updateNote = card;
            if (_aboutVersion != null) SetAboutBody(_aboutVersion, VersionText());
#if UITEST
            // в тестовой сборке модальных окон не открываем — иначе прогон встанет
            Console.WriteLine("UPDATE " + st + " | " + status + " | " + card);
            return;
#pragma warning disable 0162
#endif
            if (st == UpdateState.Failed)
            {
                MessageBox.Show(this, err, L.T("Проверка обновления"), MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            if (st != UpdateState.Newer)
            {
                MessageBox.Show(this, status + "\n\n" + L.T("Версия программы: ") + AppInfo.Version,
                    L.T("Проверка обновления"), MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            if (MessageBox.Show(this, L.T("Вышла версия ") + tag + L.T(", у вас ") + AppInfo.Version + "." + "\n" + "\n" +
                                      L.T("Открыть страницу загрузки в браузере?"),
                                L.T("Проверка обновления"), MessageBoxButtons.YesNo, MessageBoxIcon.Information) == DialogResult.Yes)
            { try { Process.Start(AppInfo.ReleasesUrl); } catch { } }
#if UITEST
#pragma warning restore 0162
#endif
        }

        private void SetAboutBody(Control card, string text)
        {
            foreach (Control c in card.Controls)   // c = TableLayoutPanel
                foreach (Control cc in c.Controls)
                    if (cc is Label && (string)cc.Tag == "body") cc.Text = text;
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
            l.Tag = "pagetitle";
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

            _progress = new SlimProgress();
            _progress.Style = ProgressBarStyle.Marquee;
            _progress.Size = new Size((int)(u * 9F), Math.Max(4, (int)(u * 0.36F)));
            _progress.Location = new Point((int)(u * 1.2F), (int)(u * 1.0F));
            _progress.Visible = false; bar.Controls.Add(_progress);

            _status = new Label();
            _status.Text = L.T("Готово к работе."); _status.ForeColor = Theme.TextDim; _status.AutoSize = true;
            _status.Location = new Point((int)(u * 1.2F), (int)(u * 0.75F)); bar.Controls.Add(_status);

            // Долгая работа больше не выглядит как зависание: её видно и её
            // можно остановить. Чтение обрывается сразу, применение — только
            // после предупреждения.
            _btnStop = new ModernButton(L.T("Прервать"), false);
            _btnStop.Ghost = true; _btnStop.Font = Font; _btnStop.Fit();
            _btnStop.Visible = false;
            _btnStop.Click += delegate { StopEngine(true); };
            bar.Controls.Add(_btnStop);

            bar.Resize += delegate {
                _progress.Location = new Point((int)(u * 1.2F), (bar.Height - _progress.Height)/2 + 1);
                _status.Location = new Point(_progress.Visible ? (int)(u * 11F) : (int)(u * 1.2F), (bar.Height - _status.Height)/2);
                _btnStop.Location = new Point(Math.Max((int)(u * 1.2F), bar.ClientSize.Width - _btnStop.Width - (int)(u * 1.2F)),
                                              (bar.Height - _btnStop.Height) / 2);
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

        // Картинка из app.ico ближайшего размера. В заголовке значок около 24
        // точек, и уменьшенный в десять раз app.png там расплывался; в значке
        // для мелких размеров лежат отдельно нарисованные картинки — они чёткие.
        private Image LogoFromIco(int size)
        {
            try
            {
                byte[] ico;
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("app.ico"))
                {
                    if (s == null) return null;
                    using (MemoryStream ms = new MemoryStream()) { s.CopyTo(ms); ico = ms.ToArray(); }
                }
                int n = BitConverter.ToUInt16(ico, 4), best = -1, bestDiff = int.MaxValue;
                for (int i = 0; i < n; i++)
                {
                    int w = ico[6 + 16 * i]; if (w == 0) w = 256;
                    // предпочитаем чуть крупнее нужного: уменьшение чище увеличения
                    int diff = w >= size ? w - size : (size - w) * 4;
                    if (diff < bestDiff) { bestDiff = diff; best = i; }
                }
                if (best < 0) return null;
                int len = BitConverter.ToInt32(ico, 6 + 16 * best + 8), off = BitConverter.ToInt32(ico, 6 + 16 * best + 12);
                if (ico[off] != 0x89) return null;          // только PNG-картинки, других в app.ico нет
                using (MemoryStream ps = new MemoryStream(ico, off, len))
                using (Image tmp = Image.FromStream(ps)) return new Bitmap(tmp);
            }
            catch { return null; }
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
            ShowWelcomeIfFirstRun();
        }

        // Первый запуск: один вопрос вместо тринадцати разделов сразу.
        // Ничего не применяет — только отмечает набор и открывает страницу,
        // где видно, что именно будет сделано.
        private void ShowWelcomeIfFirstRun()
        {
#if UITEST
            if (Environment.GetEnvironmentVariable("WIN11_TEST_WELCOME") != "1") return;
            using (WelcomeForm wt = new WelcomeForm(Font, _appImage))
            {
                wt.Show(this);
                Application.DoEvents();
                string ws = Environment.GetEnvironmentVariable("WIN11_TEST_SHOT");
                if (ws != null) ws = ws.Replace(".png", "-welcome.png");   // снимок страницы не затираем
                if (ws != null)
                {
                    try { using (Bitmap bmp = new Bitmap(wt.Width, wt.Height)) { wt.DrawToBitmap(bmp, new Rectangle(0, 0, wt.Width, wt.Height)); bmp.Save(ws); } }
                    catch (Exception ex) { Console.WriteLine("SHOTERR " + ex.Message); }
                }
                Console.WriteLine("WELCOME controls=" + CountControls(wt));
                wt.Close();
            }
            return;
#else
            if (_welcomeSeen) return;
#endif
            _welcomeSeen = true;
            SaveUiState();
            WelcomeChoice choice;
            using (WelcomeForm w = new WelcomeForm(Font, _appImage))
            {
                w.ShowDialog(this);
                choice = w.Choice;
            }
            if (choice == WelcomeChoice.Basic || choice == WelcomeChoice.Strict)
            {
                ApplyPreset(choice == WelcomeChoice.Basic ? "base" : "strict");
                Navigate("settings");
                _status.Text = L.T("Набор отмечен. Посмотрите список и нажмите «Применить».");
            }
            else if (choice == WelcomeChoice.LookFirst)
            {
                Navigate("audit");
                RunAudit();
            }
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
            string portable = PortableRoot();
            if (portable.Length > 0) return Path.Combine(portable, "ui.json");
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
                if (d != null && d.ContainsKey("lang")) L.Choice = Json.GetInt(d, "lang");
                else if (d != null && d.ContainsKey("en"))
                {
                    // Прежние версии записывали язык всегда, даже если его никто
                    // не выбирал, и он навсегда застывал на первом запуске.
                    // Выбором считаем только тот, что расходится с языком Windows.
                    L.Choice = LangChoiceFromOld(Json.GetBool(d, "en"), L.SystemEnglish());
                }
                _langChoice = L.Choice;
                if (d != null && d.ContainsKey("theme")) _themeChoice = Json.GetInt(d, "theme");
            }
            catch { }
        }
        // 0 — как в Windows, 1 — тёмная, 2 — светлая
        private int _themeChoice;
        // 0 — как в Windows, 1 — русский, 2 — английский. Меняется кнопкой и
        // действует со следующего запуска: на ходу подписи смешались бы.
        private int _langChoice;
        private bool _welcomeSeen;          // окно первого запуска уже показывали

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
                _welcomeSeen = Json.GetBool(d, "welcome");
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
                             ", \"lang\": " + _langChoice +
                             ", \"welcome\": " + (_welcomeSeen ? "true" : "false") +
                             ", \"theme\": " + _themeChoice + " }";
                File.WriteAllText(p, txt);
            }
            catch { }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            // Раньше закрытое окно ничего не останавливало: движок продолжал
            // менять реестр уже без интерфейса, а распакованный скрипт
            // оставался во временной папке навсегда.
#if UITEST
            StopEngine(false);          // в тестовой сборке спрашивать некого
#else
            if (EngineAlive())
            {
                string ask = EngineWriting()
                    ? L.T("Программа сейчас меняет настройки системы.\n\nЕсли закрыть окно, работа прервётся на середине. Всё уже изменённое останется в журнале — вернуть можно на странице «Изменения».\n\nЗакрыть?")
                    : L.T("Программа сейчас читает состояние системы.\n\nЕсли закрыть окно, чтение прервётся. Ничего изменено не будет.\n\nЗакрыть?");
                if (MessageBox.Show(this, ask, L.T("Идёт работа"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                { e.Cancel = true; return; }
                StopEngine(false);
            }
#endif
            SaveUiState();
            EngineFile.Remove();
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
        //
        // Запусков бывает несколько сразу: определение системы, список настроек
        // и журнал датчиков читаются параллельно, а поверх может идти применение.
        // Раньше окно помнило только последний: «Прервать» и закрытие окна
        // останавливали не тот процесс, а чтение, закончившись первым, снимало
        // занятость с ещё идущего применения. Теперь на учёте каждый.
        private sealed class EngineRun
        {
            public Process Proc;
            public string Status;       // подпись в строке состояния
            public bool Writes;         // команда меняет систему
            public bool Streams;        // действие с выводом в журнал, а не чтение данных
            public bool Cancelled;      // прервано пользователем
        }

        // Меняется только из потока окна
        private readonly List<EngineRun> _runs = new List<EngineRun>();

        private bool EngineWriting() { return _runs.Exists(delegate(EngineRun r) { return r.Writes; }); }
        private bool EngineStreaming() { return _runs.Exists(delegate(EngineRun r) { return r.Streams; }); }

        // Запускает движок и ставит запуск на учёт. Строки вывода приходят из
        // чужого потока, конец работы — уже в потоке окна.
        private void Launch(ProcessStartInfo psi, EngineRun run, Action<string> onLine, Action<int> onExit)
        {
            Process p = new Process();
            p.StartInfo = psi;
            p.EnableRaisingEvents = true;
            DataReceivedEventHandler h = delegate(object s, DataReceivedEventArgs e) { if (e.Data != null) onLine(e.Data); };
            p.OutputDataReceived += h; p.ErrorDataReceived += h;
            p.Exited += delegate
            {
                int code = -1;
                try { p.WaitForExit(); code = p.ExitCode; } catch { }
                try
                {
                    BeginInvoke((MethodInvoker)delegate
                    {
                        _runs.Remove(run);
                        onExit(code);
                        p.Dispose();
                    });
                }
                catch { }
            };
            run.Proc = p;
            p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine();
            _runs.Add(run);
        }

        // Занятость снимается с последним запуском; пока работает другой, в
        // строку состояния возвращается его подпись.
        private void SettleBusy(string doneText)
        {
            if (_runs.Count == 0) SetBusy(false, doneText);
            else SetBusy(true, _runs[_runs.Count - 1].Status);
        }

        private string ExtractEngine() { return EngineFile.Ensure(); }

        // Команды, которые меняют систему. Всё остальное движок только читает,
        // и обрывать его можно без последствий.
        private static readonly string[] WriteFlags = {
            "-Revert", "-RestoreAll", "-RestoreItems", "-RestoreBackup", "-RemoveApps",
            "-StartupSet", "-SensorSet", "-FootprintWipe", "-XrayWipe", "-PurgeBuffer",
            "-PurgeData", "-CleanJunk", "-BlockApp", "-UnblockApp", "-InstallGuard", "-GdidReissue", "-GdidRestore",
            "-InstallNetGuard", "-RemoveNetGuard",
            "-RemoveGuard", "-GuardNow", "-InstallWatcher", "-RemoveWatcher",
            "-InstallSensorGuard", "-RemoveSensorGuard", "-EnableMonitor",
            "-DisableMonitor", "-XrayEnable", "-XrayDisable", "-XrayBaseline"
        };

        internal static bool EngineWrites(string extra)
        {
            if (extra == null) return false;
            // тестовый прогон и проверка только читают, хотя список модулей у них тот же
            if (extra.IndexOf("-DryRun", StringComparison.OrdinalIgnoreCase) >= 0) return false;
            if (extra.IndexOf("-Audit", StringComparison.OrdinalIgnoreCase) >= 0) return false;
            if (extra.IndexOf("-Modules", StringComparison.OrdinalIgnoreCase) >= 0) return true;
            foreach (string f in WriteFlags)
                if (extra.IndexOf(f, StringComparison.OrdinalIgnoreCase) >= 0) return true;
            return false;
        }

        // «###PROGRESS### 15/34 Телеметрия» — движок говорит, сколько проверок
        // из скольких пройдено. Раньше проверка молчала до самого конца, и
        // полминуты было не отличить работу от зависания.
        private bool ShowProgress(string line)
        {
            if (line == null || !line.StartsWith("###PROGRESS###")) return false;
            string rest = line.Substring("###PROGRESS###".Length).Trim();
            int sp = rest.IndexOf(' ');
            string nums = sp > 0 ? rest.Substring(0, sp) : rest;
            string what = sp > 0 ? rest.Substring(sp + 1).Trim() : "";
            string[] parts = nums.Split('/');
            int done, total;
            if (parts.Length != 2 || !int.TryParse(parts[0], out done) || !int.TryParse(parts[1], out total) || total < 1)
                return true;                        // строка наша, но непонятная — просто прячем
            try
            {
                BeginInvoke((MethodInvoker)delegate
                {
                    if (!_progress.Visible) return;
                    _progress.Style = ProgressBarStyle.Continuous;
                    _progress.Maximum = total;
                    _progress.Value = Math.Max(0, Math.Min(done, total));
                    _status.Text = (_busyText.Length > 0 ? _busyText + "  " : "") + done + " / " + total +
                                   (what.Length > 0 ? "  -  " + L.T(what) : "");
                });
            }
            catch { }
            return true;
        }

        private bool EngineAlive()
        {
            foreach (EngineRun r in _runs)
            {
                try { if (!r.Proc.HasExited) return true; } catch { }
            }
            return false;
        }

        // Прервать работу движка. Чтение обрывается сразу; применение — только
        // после предупреждения: часть настроек к этому моменту уже записана.
        private bool StopEngine(bool ask)
        {
            if (!EngineAlive()) return true;
#if UITEST
            ask = false;                // тестовая сборка не открывает окон
#endif
            if (ask && EngineWriting())
            {
                string warn = L.T("Движок сейчас меняет настройки системы.\n\n") +
                              L.T("Если прервать, часть настроек останется применённой. Всё, что он успел изменить, записано в журнал — вернуть можно на странице «Изменения».\n\nВсё равно прервать?");
                if (MessageBox.Show(this, warn, L.T("Прервать работу"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                    return false;
            }
            EngineRun[] live = _runs.ToArray();
            foreach (EngineRun r in live)
            {
                r.Cancelled = true;
                try { r.Proc.Kill(); } catch { }
            }
            foreach (EngineRun r in live)
            {
                try { r.Proc.WaitForExit(4000); } catch { }
            }
            SetBusy(false, L.T("Прервано."));
            return true;
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
            string portable = PortableRoot();
            string backupRoot = (portable.Length > 0)
                ? portable
                : Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
            string args = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\" " + extra +
                          " -BackupRoot \"" + backupRoot + "\"";
            if (portable.Length > 0) args += " -DataRoot \"" + portable + "\"";
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
            if (EngineStreaming())
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

            ProcessStartInfo psi;
            try { psi = EnginePsi(extra); }
            catch (Exception ex)
            {
                SettleBusy(L.T("Ошибка."));
                LogLine(L.T("Не удалось подготовить движок: ") + ex.Message, Theme.Err);
                MessageBox.Show(this, ex.Message, L.T("Ошибка"), MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            LogLine(L.T("Запуск: powershell ") + extra, Theme.TextFaint);
            if (_detect != null && !Json.GetBool(_detect, "admin"))
                LogLine(L.T("ВНИМАНИЕ: программа запущена без прав администратора — изменения применить нельзя."), Theme.Err);

            EngineRun run = new EngineRun();
            run.Status = statusText; run.Streams = true; run.Writes = EngineWrites(extra);
            Action<string> onLine = delegate(string line)
            {
                if (line.Trim() == "###DONE###") return;
                if (ShowProgress(line.TrimStart())) return;
                try { BeginInvoke((MethodInvoker)delegate { LogEngine(line); }); } catch { }
            };
            Action<int> onExit = delegate(int code)
            {
                bool stopped = run.Cancelled;
                SettleBusy(stopped ? L.T("Прервано.") : (code == 0 ? L.T("Готово.") : L.T("Завершено с ошибкой.")));
                LogLine(new string('─', 58), Theme.TextFaint);
                if (stopped)
                {
                    LogLine(L.T("Прервано по вашей команде."), Theme.Err);
                    if (run.Writes) LogLine(L.T("Что движок успел изменить — записано на странице «Изменения»."), Theme.TextDim);
                }
                else if (code == 0) LogLine(L.T("Готово."), Theme.Text);
                else if (code == 3)
                {
                    // движок сам объяснил причину строкой выше
                    LogLine(L.T("Программа не может работать на этом компьютере из-за политики устройства."), Theme.Err);
                }
                else
                {
                    LogLine(L.T("PowerShell завершился с кодом ") + code + ".", Theme.Err);
                    LogLine(L.T("Если выше нет строк движка — его блокирует антивирус или не хватает прав."), Theme.TextDim);
                }
                if (onDone != null) onDone();
            };
            try { Launch(psi, run, onLine, onExit); }
            catch (Exception ex)
            {
                SettleBusy(L.T("Не удалось запустить PowerShell."));
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
            ProcessStartInfo psi;
            try { psi = EnginePsi(extra); }
            catch (Exception ex)
            {
                SettleBusy(L.T("Ошибка."));
                LogLine(L.T("Не удалось подготовить движок: ") + ex.Message, Theme.Err);
                if (onResult != null) onResult(null);
                return;
            }
            EngineRun run = new EngineRun();
            run.Status = statusText; run.Writes = EngineWrites(extra);
            string jsonLine = null;
            StringBuilder errBuf = new StringBuilder();
            object gate = new object();         // вывод и ошибки приходят из разных потоков
            Action<string> onLine = delegate(string line)
            {
                string t = line.TrimStart();
                if (ShowProgress(t)) return;
                lock (gate)
                {
                    if (t.StartsWith("###JSON###")) jsonLine = t.Substring(10).Trim();
                    else if (t.Length > 0 && errBuf.Length < 2000) errBuf.Append(t).Append("\n");
                }
            };
            Action<int> onExit = delegate(int code)
            {
                SettleBusy(run.Cancelled ? L.T("Прервано.") : L.T("Готово."));
                Dictionary<string, object> d = null;
                if (jsonLine != null) { try { d = Json.ParseObject(jsonLine); } catch { } }
                if (d == null && errBuf.Length > 0 && !run.Cancelled)
                    LogLine(L.T("Движок (") + extra + L.T(") не вернул данные, код ") + code + ":\n" + errBuf, Theme.Err);
                if (onResult != null) onResult(d);
            };
            try { Launch(psi, run, onLine, onExit); }
            catch (Exception ex)
            {
                SettleBusy(L.T("PowerShell недоступен."));
                LogLine(L.T("Не удалось запустить PowerShell: ") + ex.Message, Theme.Err);
                if (onResult != null) onResult(null);
            }
        }

        private void SetBusy(bool busy, string status)
        {
            _progress.Visible = busy; _status.Text = status;
            _busyText = busy ? status : "";
            // бегущая полоса — пока движок не сказал, сколько всего работы
            if (busy) { _progress.Style = ProgressBarStyle.Marquee; _progress.Value = 0; }
            if (_btnStop != null)
            {
                _btnStop.Visible = busy;
                if (_btnStop.Parent != null) _btnStop.Parent.PerformLayout();
            }
            if (_progress.Parent != null) _progress.Parent.PerformLayout();
            _status.Location = new Point(busy ? (int)(Font.Height * 11F) : (int)(Font.Height * 1.2F), _status.Location.Y);
            if (_btnApply != null) _btnApply.Enabled = !busy;
            if (_miRevert != null) _miRevert.Enabled = !busy;
            if (_btnGuardInstall != null) _btnGuardInstall.Enabled = !busy;
            if (_monitorToggle != null) _monitorToggle.Enabled = !busy;
        }

        // ================================================================== //
        //  Detect при старте
        // ================================================================== //
        private bool _spyAutoRan;

        // что перестанет работать — по номеру настройки, для «Что изменится»
        private readonly Dictionary<string, string> _defNotes = new Dictionary<string, string>();

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
                        string risk = Json.GetStr(it, "risk");
                        string note = Json.GetStr(it, "note");
                        string riskText = risk == "caution" ? L.T("осторожно") : (risk == "limited" ? L.T("с последствиями") : "");
                        if (note.Length > 0) _defNotes[Json.GetStr(it, "id")] = L.T(note);
                        SubOptionRow r = new SubOptionRow(Json.GetStr(it, "id"), L.T(Json.GetStr(it, "name")), risk, L.T(note), riskText);
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
                ApplyProfileSkip();
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
                    RunJson("-Spy", L.T("Чтение журнала датчиков…"), delegate(Dictionary<string, object> s)
                    {
                        if (s != null) { _lastSpy = s; RenderDossier(); }
                        FillHomeExtras();   // очередью, а не четырьмя процессами разом
                    });
                }
            });
        }

        private void ApplyDetect(Dictionary<string, object> d)
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
            _homeSys = os.Replace("Microsoft ", "") + L.T(" · сборка ") + Json.GetStr(d, "build");

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
            UpdateHomeAlert();
            if (_aboutVersion != null) SetAboutBody(_aboutVersion, VersionText());
            // Отметки «вкл» у разделов убраны: включённое состояние видно на
            // самих страницах, а точка в панели означает только «загляните».
            RefreshHome();
        }

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
