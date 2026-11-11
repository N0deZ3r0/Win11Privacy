// Часть MainForm: общий каркас страниц-списков (поиск, карточка, кнопки) и помощники для них.

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
    }
}
