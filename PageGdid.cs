using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace Win11Privacy
{
    // Страница «Номер устройства»: GDID — номер, который Microsoft выдаёт
    // компьютеру и по которому узнаёт его при любом IP. Здесь видно, есть ли
    // он, уходит ли он наружу, и собраны три действия: не передавать, сменить,
    // запретить выдачу — и возврат как было.
    public partial class MainForm : Form
    {
        private const string GBadge = "";
        private Dictionary<string, object> _lastGdid;
        private Label _gdidState;
        private TileGrid _gdidTiles;
        private StackPanel _gdidList;
        private ModernButton _btnGdidSend, _btnGdidReissue, _btnGdidLock, _btnGdidRestore, _btnGdidRefresh;

        private Control BuildGdidPage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 4;
            page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Absolute, (int)(u * 7.6F)));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            TableLayoutPanel head = new TableLayoutPanel();
            head.ColumnCount = 1; head.Dock = DockStyle.Fill; head.AutoSize = true;
            head.BackColor = Theme.WindowBg;
            head.Controls.Add(PageTitle(L.T("Номер устройства")), 0, 0);
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
            _gdidState = new Label();
            _gdidState.AutoSize = false; _gdidState.Dock = DockStyle.Fill;
            _gdidState.TextAlign = ContentAlignment.MiddleLeft; _gdidState.ForeColor = Theme.TextDim;
            _gdidState.Text = L.T("Microsoft выдаёт компьютеру номер (GDID) и узнаёт его по нему при любом IP, даже через VPN.\n") +
                              L.T("Отключённая телеметрия его не останавливает: номер уходит через другие службы.");
            ci.Controls.Add(_gdidState, 0, 0);

            FlowLayoutPanel row = new FlowLayoutPanel();
            AttachButtonRow(row, ctl);
            row.Margin = new Padding(0, (int)(u * 0.5F), 0, 0);
            _btnGdidSend = new ModernButton(L.T("Не передавать"), true);
            _btnGdidSend.Click += OnGdidSend;
            _btnGdidReissue = new ModernButton(L.T("Сменить номер"), false);
            _btnGdidReissue.Click += OnGdidReissue;
            _btnGdidLock = new ModernButton(L.T("Запретить выдачу"), false);
            _btnGdidLock.Click += OnGdidLock;
            _btnGdidRestore = new ModernButton(L.T("Вернуть как было"), false);
            _btnGdidRestore.Click += OnGdidRestore;
            _btnGdidRefresh = new ModernButton(L.T("Обновить"), false);
            _btnGdidRefresh.Click += delegate { RefreshGdid(); };
            foreach (ModernButton b in new[] { _btnGdidSend, _btnGdidReissue, _btnGdidLock, _btnGdidRestore, _btnGdidRefresh })
            { b.Font = b.Primary ? Theme.Bold(Font) : Font; b.Margin = new Padding((int)(u * 0.4F), 0, 0, (int)(u * 0.3F)); row.Controls.Add(b); }
            ci.Controls.Add(row, 0, 1);
            ctl.Controls.Add(ci);
            page.Controls.Add(ctl, 0, 1);

            _gdidTiles = new TileGrid();
            _gdidTiles.Dock = DockStyle.Fill; _gdidTiles.AutoSize = true; _gdidTiles.Font = Font;
            _gdidTiles.Margin = new Padding(0, 0, 0, (int)(u * 0.4F));
            page.Controls.Add(_gdidTiles, 0, 2);

            Card list = new Card();
            list.Dock = DockStyle.Fill; list.Padding = new Padding((int)(u * 0.6F));
            list.Margin = new Padding(0, 0, 0, (int)(u * 0.3F));
            _gdidList = new StackPanel();
            _gdidList.Dock = DockStyle.Fill; _gdidList.Font = Font;
            _gdidList.Padding = new Padding((int)(u * 0.4F));
            Dwm.DarkScrollbars(_gdidList);
            list.Controls.Add(_gdidList);
            page.Controls.Add(list, 0, 3);
            return page;
        }

        private void RefreshGdid()
        {
            RunJson("-GdidStatus", L.T("Чтение номера устройства…"), delegate(Dictionary<string, object> d)
            {
                if (d != null) _lastGdid = d;
                RenderGdid();
            });
        }

        // «g:6755487812206045» -> «g:6755…6045»: в плитке целиком не нужен
        private static string ShortGdid(string g)
        {
            if (string.IsNullOrEmpty(g) || g.Length <= 12) return g;
            return g.Substring(0, 6) + "…" + g.Substring(g.Length - 4);
        }

        private string StartName(int start)
        {
            switch (start)
            {
                case 2: return L.T("запуск автоматически");
                case 3: return L.T("запуск по требованию");
                case 4: return L.T("отключена");
                case -1: return L.T("нет на этой системе");
                default: return L.T("запуск при загрузке");
            }
        }

        private void RenderGdid()
        {
            if (_gdidList == null) return;
            _gdidTiles.Controls.Clear();
            _gdidList.Controls.Clear();
            Dictionary<string, object> d = _lastGdid;
            if (d == null)
            {
                SectionHeader sh0 = new SectionHeader(L.T("Нажмите «Обновить», чтобы прочитать состояние"));
                sh0.Font = Font; _gdidList.Controls.Add(sh0); _gdidList.Restack();
                return;
            }
            string gdid = Json.GetStr(d, "gdid");
            bool sendOff = Json.GetBool(d, "transmitOff");
            bool dds = Json.GetBool(d, "ddsBlocked");
            bool locked = Json.GetBool(d, "locked");
            bool msa = Json.GetBool(d, "msaLogon");
            string managed = Json.GetStr(d, "managed");
            int copies = Json.GetInt(d, "copies");

            _gdidTiles.Controls.Add(Tile(L.T("Номер"), string.IsNullOrEmpty(gdid) ? L.T("нет") : ShortGdid(gdid),
                string.IsNullOrEmpty(gdid) ? L.T("Windows его сейчас не хранит") : L.T("выдан серверами Microsoft"),
                string.IsNullOrEmpty(gdid) ? Theme.Ok : Theme.Accent));
            string sendVal = sendOff && dds ? L.T("закрыта") : (sendOff || dds ? L.T("частично") : L.T("идёт"));
            _gdidTiles.Controls.Add(Tile(L.T("Передача"), sendVal, L.T("службы CDPSvc, DoSvc и их серверы"),
                sendOff && dds ? Theme.Ok : (sendOff || dds ? Theme.Warn : Theme.Err)));
            _gdidTiles.Controls.Add(Tile(L.T("Выдача нового"), locked ? L.T("закрыта") : L.T("открыта"),
                L.T("сервер login.live.com"), locked ? Theme.Ok : Theme.Warn));
            _gdidTiles.Controls.Add(Tile(L.T("Копий на диске"), copies.ToString(), L.T("в реестре и учётных данных"), Theme.Accent));

            SectionHeader sh = new SectionHeader(L.T("Сейчас")); sh.Font = Font; _gdidList.Controls.Add(sh);
            _gdidList.Controls.Add(new WipeRow("gdid", L.T("Номер устройства"),
                L.T("Выдаётся при входе в Windows и привязан к установке Windows, а не к железу. По нему Microsoft связывает ваши действия с этим компьютером при любом IP."),
                string.IsNullOrEmpty(gdid) ? "—" : gdid, GBadge, false) { Font = this.Font });
            _gdidList.Controls.Add(new WipeRow("send", L.T("Передача номера"),
                L.T("CDPSvc регистрирует компьютер в каталоге устройств Microsoft, DoSvc сообщает номер. DiagTrack тут ни при чём."),
                sendVal, GSync, false) { Font = this.Font });
            _gdidList.Controls.Add(new WipeRow("lock", L.T("Выдача нового номера"),
                locked ? L.T("Сервер выдачи закрыт: стёртый номер Windows заменить нечем.")
                       : L.T("Сервер выдачи открыт: стёртый номер Windows сразу заменит новым."),
                locked ? L.T("закрыта") : L.T("открыта"), GShield, false) { Font = this.Font });
            _gdidList.Controls.Add(new WipeRow("logon", L.T("Вход в Windows"),
                !string.IsNullOrEmpty(managed) ? L.T(managed)
                : (msa ? L.T("Через учётную запись Microsoft: запретить выдачу номера нельзя — без сервера выдачи она не работает.")
                       : L.T("Локальная учётная запись: доступны все три действия.")),
                msa ? L.T("учётная запись Microsoft") : L.T("локальная"), GContact, false) { Font = this.Font });

            SectionHeader sh2 = new SectionHeader(L.T("Что можно сделать")); sh2.Font = Font; _gdidList.Controls.Add(sh2);
            _gdidList.Controls.Add(new WipeRow("a1", L.T("Не передавать"),
                L.T("Отключает CDPSvc, CDPUserSvc и DoSvc и закрывает серверы каталога устройств. Вход в учётную запись остаётся; «Связь с телефоном» и обмен с устройствами поблизости перестанут работать."),
                sendOff && dds ? L.T("сделано") : "", GSync, false) { Font = this.Font });
            _gdidList.Controls.Add(new WipeRow("a2", L.T("Сменить номер"),
                L.T("Стирает «личность» устройства — Windows получит новый номер. Магазин, Xbox и OneDrive попросят войти заново. Старый номер у Microsoft останется, а войдя той же учётной записью, вы привяжете к ней и новый."),
                "", GBadge, false) { Font = this.Font });
            _gdidList.Controls.Add(new WipeRow("a3", L.T("Запретить выдачу"),
                L.T("Закрывает сервер выдачи и стирает номер: нового Windows не получит. Только для входа без учётной записи Microsoft — Магазин, Xbox и OneDrive перестанут работать."),
                locked ? L.T("сделано") : (msa || !string.IsNullOrEmpty(managed) ? L.T("недоступно") : ""), GShield, false) { Font = this.Font });
            _gdidList.Controls.Add(new WipeRow("a4", L.T("Вернуть как было"),
                L.T("Службы и серверы — как до программы. Стёртый номер не вернётся: Windows получит новый."),
                "", GUndo, false) { Font = this.Font });

            SectionHeader sh3 = new SectionHeader(L.T("Службы")); sh3.Font = Font; _gdidList.Controls.Add(sh3);
            foreach (object o in Json.GetArr(d, "services"))
            {
                Dictionary<string, object> s = Json.Obj(o);
                int start = Json.GetInt(s, "start");
                string val = StartName(start) + (Json.GetBool(s, "running") ? L.T(", работает") : "");
                _gdidList.Controls.Add(new KvRow(Json.GetStr(s, "name"), val, false) { Font = this.Font });
            }

            _btnGdidLock.Enabled = !msa && string.IsNullOrEmpty(managed);
            _btnGdidReissue.Enabled = string.IsNullOrEmpty(managed);
            _gdidState.Text = L.T("Прочитано ") + Json.GetStr(d, "time") + L.T(". Номер виден только вам — наружу программа ничего не отправляет.\n") +
                L.T("Старые записи Microsoft не стереть ничем: всё здесь меняет только то, что будет дальше.");
            try { _gdidList.AutoScrollPosition = Point.Empty; } catch { }
            _gdidList.Restack();
        }

        // Флаги применения — как на странице «Настройки»: копия реестра и
        // точка восстановления по выбору человека, снятые пункты не трогаются.
        private string GdidApplyArgs(string modules)
        {
            string a = "-Modules " + modules;
            List<string> skip = SkippedItems();
            if (skip.Count > 0) a += " -SkipItems " + string.Join(",", skip.ToArray());
            if (_optBackup != null && !_optBackup.Checked) a += " -NoBackup";
            if (_optRestore != null && !_optRestore.Checked) a += " -NoRestorePoint";
            return a;
        }

        private void OnGdidSend(object sender, EventArgs e)
        {
            if (MessageBox.Show(this,
                L.T("Будут отключены службы CDPSvc, CDPUserSvc и DoSvc, а серверы каталога устройств Microsoft закрыты в hosts.\n\n") +
                L.T("Вход в учётную запись Microsoft останется. Перестанут работать «Связь с телефоном» и обмен с устройствами поблизости. ") +
                L.T("Если Магазин перестанет скачивать приложения, верните DoSvc на странице «Изменения».\n\nПродолжить?"),
                L.T("Не передавать номер"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            RunStreaming(GdidApplyArgs("gdid"), L.T("Применение настроек…"), delegate { RefreshGdid(); });
        }

        private void OnGdidReissue(object sender, EventArgs e)
        {
            bool locked = _lastGdid != null && Json.GetBool(_lastGdid, "locked");
            string text = locked
                ? L.T("Номер будет стёрт вместе с «личностью» устройства. Сервер выдачи закрыт — нового номера Windows не получит.\n\nПродолжить?")
                : L.T("Номер будет стёрт вместе с «личностью» устройства, и Windows получит новый при следующем обращении к учётной записи Microsoft.\n\n") +
                  L.T("• Магазин, Xbox и OneDrive могут попросить войти заново.\n") +
                  L.T("• Старый номер у Microsoft останется — стереть чужие записи нельзя.\n") +
                  L.T("• Войдя той же учётной записью, вы привяжете к ней и новый номер.\n\nПродолжить?");
            if (MessageBox.Show(this, text, L.T("Сменить номер устройства"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming("-GdidReissue", L.T("Смена номера устройства…"), delegate { RefreshGdid(); });
        }

        private void OnGdidLock(object sender, EventArgs e)
        {
            if (_lastGdid != null && Json.GetBool(_lastGdid, "msaLogon"))
            {
                MessageBox.Show(this,
                    L.T("Вы входите в Windows через учётную запись Microsoft. Без сервера выдачи номера она перестанет работать, поэтому запрет недоступен.\n\n") +
                    L.T("Чтобы им воспользоваться, сначала перейдите на локальную учётную запись: Параметры → Учётные записи → Ваши данные."),
                    L.T("Запретить выдачу номера"), MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            if (MessageBox.Show(this,
                L.T("Сервер, который выдаёт номер (login.live.com), будет закрыт в hosts и брандмауэре, передача номера отключена, а сам номер стёрт отовсюду.\n\n") +
                L.T("Нового номера Windows не получит. Вход в учётную запись Microsoft, Магазин, Xbox и OneDrive перестанут работать, пока запрет стоит. ") +
                L.T("Снять его — «Вернуть как было» здесь или общий откат.\n\nПродолжить?"),
                L.T("Запретить выдачу номера"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming(GdidApplyArgs("gdid,gdidlock"), L.T("Применение настроек…"), delegate { RefreshGdid(); });
        }

        private void OnGdidRestore(object sender, EventArgs e)
        {
            if (MessageBox.Show(this,
                L.T("Службы получат тот тип запуска, что был до программы, а блоки серверов номера будут убраны из hosts и брандмауэра.\n\n") +
                L.T("Стёртый раньше номер не вернётся: Windows получит новый.\n\nПродолжить?"),
                L.T("Вернуть как было"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            RunStreaming("-GdidRestore", L.T("Возврат…"), delegate { RefreshGdid(); });
        }
    }
}
