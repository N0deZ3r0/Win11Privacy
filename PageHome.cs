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
    // Страница «Обзор»: индекс, полоса внимания, карточки разделов, диаграммы.
    public partial class MainForm : Form
    {
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
            page.ColumnCount = 1; page.RowCount = 5;
            page.BackColor = Theme.WindowBg;
            page.Dock = DockStyle.Top;
            page.AutoSize = true; page.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));                       // шапка
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));                       // полоса внимания
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

            // --- полоса внимания -----------------------------------------------
            //  Появляется, только когда есть что сказать: страж вернул сбитые
            //  обновлением настройки или в реестре остался мусор от версий,
            //  писавших параметры под числовыми именами. Раньше об этом можно
            //  было узнать, лишь зайдя на нужную страницу.
            _homeAlert = new Card();
            _homeAlert.Dock = DockStyle.Fill; _homeAlert.Visible = false;
            _homeAlert.AutoSize = true; _homeAlert.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            _homeAlert.Margin = new Padding(0, 0, 0, (int)(u * 0.7F));
            _homeAlert.Padding = new Padding((int)(u * 0.9F), (int)(u * 0.6F), (int)(u * 0.9F), (int)(u * 0.6F));
            TableLayoutPanel alert = new TableLayoutPanel();
            alert.Dock = DockStyle.Fill; alert.BackColor = Theme.CardBg;
            alert.ColumnCount = 2; alert.RowCount = 1; alert.AutoSize = true;
            alert.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            alert.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            _homeAlertText = new Label();
            _homeAlertText.AutoSize = true; _homeAlertText.ForeColor = Theme.Text; _homeAlertText.Font = Font;
            _homeAlertText.Margin = new Padding(0, (int)(u * 0.3F), (int)(u * 0.8F), 0);
            _homeAlertBtn = new ModernButton("", false);
            _homeAlertBtn.Font = Font; _homeAlertBtn.Anchor = AnchorStyles.Right;
            _homeAlertBtn.Margin = new Padding(0);
            _homeAlertBtn.Click += delegate { if (_homeAlertGo != null) _homeAlertGo(); };
            alert.Controls.Add(_homeAlertText, 0, 0);
            alert.Controls.Add(_homeAlertBtn, 1, 0);
            _homeAlert.Controls.Add(alert);
            page.Controls.Add(_homeAlert, 0, 1);

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
            page.Controls.Add(band, 0, 2);

            // --- карточки разделов с живыми статусами --------------------------
            TileGrid quick = new TileGrid();
            quick.Dock = DockStyle.Fill; quick.AutoSize = true; quick.Font = Font;
            quick.MinTileWidthU = 13.0F; quick.TileHeightU = 4.0F; quick.MaxCols = 3;
            quick.Margin = new Padding(0, 0, 0, (int)(u * 0.7F));
            quick.Resize += delegate { FitHomeHeight(); };
            _qcXray    = new ActionCard(L.T("Рентген"), GXray, Theme.Warn);
            _qcDossier = new ActionCard(L.T("Досье"), GFinger, Theme.Err);
            _qcMonitor = new ActionCard(L.T("Монитор"), GNav3, Theme.Accent);
            _qcGuard   = new ActionCard(L.T("Страж"), GShield, Theme.Ok);
            _qcStartup = new ActionCard(L.T("Автозапуск"), GPower, Theme.Warn);
            _qcTimeline= new ActionCard(L.T("Хронология"), GHistory, Theme.Accent);
            _qcXray.Click    += delegate { Navigate("xray"); };
            _qcDossier.Click += delegate { Navigate("dossier"); };
            _qcMonitor.Click += delegate { Navigate("monitor"); };
            _qcGuard.Click   += delegate { Navigate("guard"); };
            _qcStartup.Click += delegate { Navigate("startup"); };
            _qcTimeline.Click+= delegate { Navigate("timeline"); };
            foreach (ActionCard c in new[] { _qcXray, _qcDossier, _qcMonitor, _qcGuard, _qcStartup, _qcTimeline })
            { c.Font = Font; c.SetStatus(L.T("ожидание данных…"), Theme.TextFaint); quick.Controls.Add(c); }
            page.Controls.Add(quick, 0, 3);

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
            page.Controls.Add(mid, 0, 4);

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
            if (Math.Abs(_homePage.RowStyles[4].Height - h) > 2)
                _homePage.RowStyles[4].Height = h;
        }

        // Заполняет главный экран по уже полученным данным
        private bool _homeExtraAsked;

        // Автозапуск и хронология подтягиваются один раз при первом показе
        // «Обзора»: держать их в стартовой очереди незачем, а карточка без
        // цифры бесполезна.
        private void FillHomeExtras()
        {
            if (_homeExtraAsked || _mockMode) return;
#if UITEST
            return;
#pragma warning disable 0162
#endif
            _homeExtraAsked = true;
            RunJson("-ListStartup", L.T("Чтение автозагрузки…"), delegate(Dictionary<string, object> d)
            {
                if (d == null) return;
                _lastStartup = d;
                int bad = Json.GetInt(d, "advise"), on = Json.GetInt(d, "on");
                if (_qcStartup != null)
                    _qcStartup.SetStatus(bad > 0 ? bad + L.T(" лишних из ") + on
                                                 : on + L.T(" записей, лишних нет"),
                                         bad > 0 ? Theme.Warn : Theme.Ok);
                RunJson("-Timeline -TimelineDays 30", L.T("Сбор хронологии…"), delegate(Dictionary<string, object> t)
                {
                    if (t == null) return;
                    _lastTimeline = t;
                    List<object> notes = Json.GetArr(t, "notes");
                    if (_qcTimeline == null) return;
                    if (notes.Count == 0) { _qcTimeline.SetStatus(L.T("пока без событий"), Theme.TextFaint); return; }
                    Dictionary<string, object> last = Json.Obj(notes[notes.Count - 1]);
                    string kind = Json.GetStr(last, "kind");
                    string what = kind == "update" ? L.T("обновление Windows") :
                                  kind == "drift" ? L.T("Windows сбила настройки") : L.T("телеметрия выросла");
                    _qcTimeline.SetStatus(Json.GetStr(last, "date") + " — " + what,
                                          kind == "update" ? Theme.Accent : Theme.Warn);
                });
            });
        }

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
                int blockedN = Json.GetInt(_lastAudit, "blocked");
                _verdictSub.Text = ok + L.T(" из ") + total + L.T(" применено") +
                    (fails > 0 ? "  ·  " + fails + L.T(" требуют внимания") : L.T("  ·  всё на месте")) +
                    (blockedN > 0 ? "  ·  " + blockedN + L.T(" Windows не отдаёт") : "");
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
    }
}
