// Часть MainForm: страница «Сеть» (монитор соединений).

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
            // Высоту карточки задаёт AttachButtonRow — по описанию и ряду кнопок.
            // Раньше строка была AutoSize, карточка оставалась стандартной высоты
            // Panel (100 пикселей без учёта масштаба), а описание стояло слева от
            // трёх кнопок узкой колонкой: при 150 % или в небольшом окне из него
            // была видна пара строк, остальное обрезалось.
            page.RowStyles.Add(new RowStyle(SizeType.Absolute, (int)(u * 7.6F)));
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            page.Controls.Add(PageTitle(L.T("Сеть")), 0, 0);

            Card ctl = new Card();
            ctl.Dock = DockStyle.Fill;
            ctl.Margin = new Padding(0, (int)(u * 0.5F), 0, (int)(u * 0.5F));
            ctl.Padding = new Padding((int)(u * 0.9F), (int)(u * 0.7F), (int)(u * 0.9F), (int)(u * 0.7F));
            TableLayoutPanel ci = new TableLayoutPanel();
            ci.Dock = DockStyle.Fill; ci.AutoSize = true; ci.ColumnCount = 1; ci.RowCount = 2;
            ci.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            ci.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            ci.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            _monitorState = new Label();
            _monitorState.AutoSize = false; _monitorState.Dock = DockStyle.Fill;
            _monitorState.TextAlign = ContentAlignment.MiddleLeft; _monitorState.ForeColor = Theme.TextDim;
            _monitorState.Text = L.T("Наблюдение за сетью фиксирует попытки программ отправить данные наружу и показывает, кто и куда стучится. Использует брандмауэр и журнал безопасности Windows.");
            ci.Controls.Add(_monitorState, 0, 0);
            FlowLayoutPanel mb = new FlowLayoutPanel();
            AttachButtonRow(mb, ctl);
            mb.Margin = new Padding(0, (int)(u * 0.5F), 0, 0);
            _monitorToggle = new ModernButton(L.T("Включить наблюдение"), true);
            _monitorToggle.Click += OnMonitorToggle;
            _netGuardToggle = new ModernButton(L.T("Следить за новыми"), false);
            _netGuardToggle.Click += OnNetGuardToggle;
            ModernButton refresh = new ModernButton(L.T("Обновить"), false); refresh.Click += delegate { RefreshMonitor(); };
            foreach (ModernButton b in new[] { _monitorToggle, _netGuardToggle, refresh })
            { b.Font = b.Primary ? Theme.Bold(Font) : Font; b.Margin = new Padding((int)(u * 0.4F), 0, 0, (int)(u * 0.3F)); mb.Controls.Add(b); }
            ci.Controls.Add(mb, 0, 1);
            ctl.Controls.Add(ci);
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
    }
}
