using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace Win11Privacy
{
    // Страница «Обзор»: что с защитой, что требует внимания и как обстоят дела
    // по разделам. Без счётчиков и диаграмм — только состояние и действия.
    public partial class MainForm : Form
    {
        private const string GSignWarn = "", GSignInfo = "", GSignOk = "";

        private Control BuildHomePage()
        {
            int u = Font.Height;
            // страница прокручивается, если окну не хватает высоты
            Panel scroll = new Panel();
            scroll.AutoScroll = true;
            scroll.BackColor = Theme.WindowBg;
            Dwm.DarkScrollbars(scroll);
            _homeScroll = scroll;

            TableLayoutPanel page = new TableLayoutPanel();
            _homePage = page;
            page.ColumnCount = 1; page.RowCount = 6;
            page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            page.BackColor = Theme.WindowBg;
            page.Dock = DockStyle.Top;
            page.AutoSize = true; page.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            for (int i = 0; i < 6; i++) page.RowStyles.Add(new RowStyle(SizeType.AutoSize));

            // --- шапка: заголовок, система и время проверки, действия ----------
            TableLayoutPanel head = new TableLayoutPanel();
            head.Dock = DockStyle.Fill; head.AutoSize = true;
            head.ColumnCount = 2; head.RowCount = 1;
            head.BackColor = Theme.WindowBg;
            head.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            head.Margin = new Padding(0);

            FlowLayoutPanel titles = new FlowLayoutPanel();
            titles.FlowDirection = FlowDirection.TopDown; titles.WrapContents = false;
            titles.AutoSize = true; titles.Margin = new Padding(0);
            Label big = PageTitle(L.T("Обзор"));
            big.Margin = new Padding(0, 0, 0, (int)(u * 0.1F));
            _homeSub = new Label();
            _homeSub.ForeColor = Theme.TextDim; _homeSub.AutoSize = true;
            _homeSub.Margin = new Padding(1, 0, 0, 0);
            _homeSub.Text = L.T("Определение системы…");
            titles.Controls.Add(big); titles.Controls.Add(_homeSub);
            head.Controls.Add(titles, 0, 0);

            FlowLayoutPanel actions = new FlowLayoutPanel();
            actions.AutoSize = true; actions.WrapContents = false;
            actions.Anchor = AnchorStyles.Right | AnchorStyles.Top;
            actions.Margin = new Padding(0, (int)(u * 0.2F), 0, 0);
            ModernButton bAudit = new ModernButton(L.T("Проверить"), false);
            bAudit.Font = Font;
            bAudit.Click += delegate { Navigate("audit"); RunAudit(); };
            ModernButton bApply = new ModernButton(L.T("Применить настройки"), true);
            bApply.Font = Theme.Bold(Font);
            bApply.Click += delegate { Navigate("settings"); };
            bAudit.Margin = new Padding(0, 0, (int)(u * 0.5F), 0);
            bApply.Margin = new Padding(0);
            actions.Controls.Add(bAudit); actions.Controls.Add(bApply);
            head.Controls.Add(actions, 1, 0);
            WrapHeadButtons(head, actions);
            page.Controls.Add(head, 0, 0);

            // --- строка состояния ------------------------------------------------
            RowList status = MakeRowList();
            status.Margin = new Padding(0, (int)(u * 1.2F), 0, 0);
            _homeStatus = new InfoRow();
            _homeStatus.Font = Font;
            _homeStatus.GlyphTile = true; _homeStatus.Large = true;
            _homeStatus.Set(GShield, Theme.TextDim, L.T("Идёт проверка системы…"),
                L.T("Программа читает настройки — это займёт несколько секунд."));
            _homeStatus.SetButton(L.T("Изменить настройки"), delegate { Navigate("settings"); });
            status.Controls.Add(_homeStatus);
            page.Controls.Add(status, 0, 1);

            // --- требует внимания -------------------------------------------------
            page.Controls.Add(HomeLabel(L.T("Требует внимания")), 0, 2);
            _homeAttention = MakeRowList();
            page.Controls.Add(_homeAttention, 0, 3);

            // --- защита по разделам ---------------------------------------------
            page.Controls.Add(HomeLabel(L.T("Защита по разделам")), 0, 4);
            _homeSections = MakeRowList();
            _homeSections.Margin = new Padding(0, 0, 0, (int)(u * 1.0F));
            page.Controls.Add(_homeSections, 0, 5);

            scroll.Controls.Add(page);
            RefreshHome();
            return scroll;
        }

        // Карточка управления: описание сверху, ряд кнопок снизу. Ряд выровнен
        // вправо и переносится, когда не хватает ширины, а карточка подрастает:
        // на узком окне кнопки наезжали на описание.
        private void AttachButtonRow(FlowLayoutPanel row, Control card)
        {
            row.FlowDirection = FlowDirection.LeftToRight;
            row.AutoSize = true;
            row.Anchor = AnchorStyles.Right;
            WrapToWidth(row, card);
            Label hint = null;
            EventHandler grow = delegate
            {
                TableLayoutPanel page = card.Parent as TableLayoutPanel;
                int w = card.ClientSize.Width - card.Padding.Horizontal;
                int at = page == null ? -1 : page.GetRow(card);     // пока карточку добавляют, строки у неё ещё нет
                if (at < 0 || at >= page.RowStyles.Count || hint == null || w <= 120) return;
                int u = Font.Height;
                int text = TextRenderer.MeasureText(hint.Text, hint.Font, new Size(w, 0), TextFormatFlags.WordBreak).Height;
                int need = text + WrappedHeight(row, w) + row.Margin.Vertical +
                           card.Padding.Vertical + card.Margin.Vertical + (int)(u * 0.3F);
                RowStyle style = page.RowStyles[at];
                int h = Math.Max((int)(u * 7.6F), need);
                if (style.SizeType != SizeType.Absolute || (int)style.Height == h) return;
                // Мы внутри раскладки страницы: высоту строки, изменённую сейчас,
                // она уже не учтёт. Меняем следующим шагом, когда раскладка закончится.
                if (IsHandleCreated) BeginInvoke((MethodInvoker)delegate { style.Height = h; });
                else style.Height = h;
            };
            card.Resize += delegate
            {
                if (hint == null && row.Parent != null)
                {
                    foreach (Control c in row.Parent.Controls) if (c is Label) hint = (Label)c;
                    if (hint != null) hint.TextChanged += grow;     // описание меняется по ходу работы
                }
                grow(card, EventArgs.Empty);
            };
        }

        private RowList MakeRowList()
        {
            RowList r = new RowList();
            r.Dock = DockStyle.Fill;
            r.Font = Font;
            // Высоту список ставит себе сам. С AutoSize он только рос: когда
            // появлялась полоса прокрутки, строки оставались шире окна.
            r.AutoSize = false;
            r.Margin = new Padding(0);
            return r;
        }

        private Label HomeLabel(string text)
        {
            Label l = new Label();
            l.Text = text; l.AutoSize = true;
            l.Font = Theme.Sized(Font.Name, Font.SizeInPoints * 0.92F, FontStyle.Bold);
            l.ForeColor = Theme.TextDim;
            l.Margin = new Padding(1, (int)(Font.Height * 1.4F), 0, (int)(Font.Height * 0.5F));
            return l;
        }

        // После стартовых чтений: автозагрузка (пункт «лишние программы») и
        // проверка настроек. Раньше проверка сама не запускалась, и «Обзор»
        // показывал «Идёт проверка…» и «Нет данных», пока не откроешь
        // «Проверку». Всё — очередью, а не несколькими процессами разом.
        private bool _homeExtraAsked;
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
                if (d != null)
                {
                    _lastStartup = d;
                    _homeStartupAdvise = Json.GetInt(d, "advise");
                    RefreshHome();
                }
                if (_lastAudit == null) RunAudit();
            });
        }

        // Строки перестраиваются, только когда меняется содержание: обновления
        // данных приходят часто, а пересоздание строк мигало бы.
        private string _homeAttentionSig = null, _homeSectionsSig = null;

        private sealed class HomeItem
        {
            public string Glyph, Title, Desc, Button, State;
            public Color Color, StateColor;
            public Action Go;
        }

        private void RefreshHome()
        {
            if (_homeStatus == null) return;

            // подзаголовок: система и время последней проверки
            string when = _lastAudit != null ? Json.GetStr(_lastAudit, "time") : "";
            string sys = _homeSys.Length > 0 ? _homeSys : L.T("Определение системы…");
            _homeSub.Text = sys + (when.Length > 0 ? L.T(" · проверено ") + when : "");

            // строка состояния
            int ok = 0, total = 0;
            if (_lastAudit == null)
                _homeStatus.Set(GShield, Theme.TextDim, L.T("Идёт проверка системы…"),
                    L.T("Программа читает настройки — это займёт несколько секунд."));
            else
            {
                ok = Json.GetInt(_lastAudit, "ok"); total = Json.GetInt(_lastAudit, "total");
                double share = total > 0 ? (double)ok / total : 0;
                string guard = _guardInstalled
                    ? L.T("Автозащита следит, чтобы обновления Windows не вернули отключённое.")
                    : L.T("Автозащита выключена: после обновлений Windows настройки могут вернуться.");
                if (share >= 0.85) _homeStatus.Set(GShield, Theme.Ok, L.T("Защита включена"), guard);
                else if (share >= 0.5) _homeStatus.Set(GShield, Theme.Warn, L.T("Защита включена частично"),
                    L.T("Не все выбранные настройки действуют. Что исправить — ниже."));
                else _homeStatus.Set(GShield, Theme.Err, L.T("Защита почти не настроена"),
                    L.T("Выберите профиль в «Настройках» и нажмите «Применить»."));
            }

            // требует внимания — от важного к справочному, не больше пяти
            List<HomeItem> att = new List<HomeItem>();
            if (_homeAlertTitle != null)
                att.Add(Item(GSignWarn, Theme.Warn, _homeAlertTitle, _homeAlertDesc, _homeAlertBtn, _homeAlertGo));
            if (_lastSpy != null && Json.GetInt(_lastSpy, "activeNow") > 0)
                att.Add(Item(GSignWarn, Theme.Warn, L.T("Камера или микрофон используются прямо сейчас"),
                    L.T("Посмотрите, какая программа к ним обратилась."), L.T("Подробнее"), delegate { Navigate("dossier"); }));
            if (_lastAudit != null && total > ok)
                att.Add(Item(GSignWarn, Theme.Warn, L.T("Часть настроек не действует"),
                    L.T("Windows могла вернуть их после обновления. Список — на странице «Проверка»."), L.T("Посмотреть"),
                    delegate { Navigate("audit"); }));
            if (_lastAudit != null)
            {
                string pass = null;
                foreach (object o in Json.GetArr(_lastAudit, "dns"))
                {
                    Dictionary<string, object> dd = Json.Obj(o);
                    if (!Json.GetBool(dd, "blocked")) { pass = Json.GetStr(dd, "name"); break; }
                }
                if (!string.IsNullOrEmpty(pass))
                    att.Add(Item(GSignWarn, Theme.Warn, L.T("Телеметрия проходит мимо блокировки"),
                        L.T("Отвечает адрес ") + pass + L.T(". Включите блокировку доменов в «Настройках»."), L.T("Настроить"),
                        delegate { Navigate("settings"); }));
            }
            if (_detect != null && !_guardInstalled)
                att.Add(Item(GSignInfo, Theme.TextDim, L.T("Автозащита выключена"),
                    L.T("Без неё обновления Windows могут вернуть отключённое."), L.T("Включить"), delegate { Navigate("guard"); }));
            if (_detect != null && !_monitorEnabled)
                att.Add(Item(GSignInfo, Theme.TextDim, L.T("Наблюдение за сетью выключено"),
                    L.T("Программа не видит, какие приложения выходят в интернет."), L.T("Включить"), delegate { Navigate("monitor"); }));
            if (_homeStartupAdvise > 0)
                att.Add(Item(GSignInfo, Theme.TextDim, L.T("Лишние программы в автозагрузке"),
                    L.T("Их можно отключить: Windows работает и без них."), L.T("Показать"), delegate { Navigate("startup"); }));
            if (att.Count > 5) att.RemoveRange(5, att.Count - 5);
            if (att.Count == 0)
                att.Add(Item(GSignOk, Theme.Ok, L.T("Ничего не требует внимания"),
                    L.T("Если что-то изменится, программа сообщит об этом здесь."), null, null));
            FillRows(_homeAttention, att, ref _homeAttentionSig, false);

            // защита по разделам: по итогам проверки модулей каждого раздела
            Dictionary<string, int[]> byModule = new Dictionary<string, int[]>();
            if (_lastAudit != null)
                foreach (object o in Json.GetArr(_lastAudit, "groups"))
                {
                    Dictionary<string, object> gr = Json.Obj(o);
                    byModule[Json.GetStr(gr, "module")] = new[] { Json.GetInt(gr, "ok"), Json.GetInt(gr, "total") };
                }
            List<HomeItem> secs = new List<HomeItem>();
            List<string> order = new List<string>();
            foreach (ModuleDef m in _mods) if (!order.Contains(m.Section)) order.Add(m.Section);
            foreach (string sec in order)
            {
                int sOk = 0, sTotal = 0;
                List<string> names = new List<string>();
                string glyph = null;
                foreach (ModuleDef m in _mods)
                {
                    if (m.Section != sec || (m.App && !m.Installed)) continue;
                    if (glyph == null) glyph = m.Glyph;
                    if (names.Count < 3) names.Add(m.Title);
                    int[] r;
                    if (byModule.TryGetValue(m.Id, out r)) { sOk += r[0]; sTotal += r[1]; }
                }
                if (names.Count == 0 || (_lastAudit != null && sTotal == 0)) continue;
                HomeItem it = Item(glyph ?? GShield, Theme.TextDim, sec, string.Join("  ·  ", names.ToArray()), null,
                    delegate { Navigate("settings"); });
                if (_lastAudit == null) { it.State = L.T("Нет данных"); it.StateColor = Theme.TextFaint; }
                else if (sOk >= sTotal) { it.State = L.T("Включено"); it.StateColor = Theme.Ok; }
                else if (sOk == 0) { it.State = L.T("Выключено"); it.StateColor = Theme.TextFaint; }
                else { it.State = L.T("Частично"); it.StateColor = Theme.Warn; }
                secs.Add(it);
            }
            FillRows(_homeSections, secs, ref _homeSectionsSig, true);
        }

        private static HomeItem Item(string glyph, Color color, string title, string desc, string button, Action go)
        {
            HomeItem i = new HomeItem();
            i.Glyph = glyph; i.Color = color; i.Title = title ?? ""; i.Desc = desc ?? ""; i.Button = button; i.Go = go;
            i.State = ""; i.StateColor = Theme.TextFaint;
            return i;
        }

        private void FillRows(RowList list, List<HomeItem> items, ref string sig, bool links)
        {
            System.Text.StringBuilder sb = new System.Text.StringBuilder();
            foreach (HomeItem i in items) sb.Append(i.Title).Append('|').Append(i.Desc).Append('|').Append(i.State).Append('|').Append(i.Button).Append('\n');
            string now = sb.ToString();
            if (now == sig) return;
            sig = now;
            list.SuspendLayout();
            while (list.Controls.Count > 0) list.Controls[0].Dispose();
            foreach (HomeItem i in items)
            {
                InfoRow r = new InfoRow();
                r.Font = Font;
                r.Link = links;
                r.Set(i.Glyph, i.Color, i.Title, i.Desc);
                if (i.State.Length > 0) r.SetState(i.State, i.StateColor);
                Action go = i.Go;
                if (i.Button != null) r.SetButton(i.Button, delegate { if (go != null) go(); });
                else if (links && go != null) r.Click += delegate { go(); };
                list.Controls.Add(r);
            }
            list.ResumeLayout(true);
        }
    }
}
