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
    }
}
