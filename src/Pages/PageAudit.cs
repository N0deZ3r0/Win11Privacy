// Часть MainForm: страница «Проверка».

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
    }
}
