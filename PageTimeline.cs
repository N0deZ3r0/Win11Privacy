// Часть MainForm: страница «Хронология приватности».

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
    }
}
