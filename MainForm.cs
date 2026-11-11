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
    }
}
