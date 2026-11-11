// Окно со списком и галочками — «Что изменится» и похожие вопросы.

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace Win11Privacy
{
    // ================================================================== //
    //  Простой модальный список: выбрать копию для восстановления или
    //  посмотреть, что именно изменится, до того как нажать «Применить».
    // ================================================================== //
    internal class ListDialog : Form
    {
        private readonly ListBox _list = new ListBox();
        public int SelectedIndex { get { return _list.SelectedIndex; } }

        public ListDialog(string title, string hint, string[] items, string okText, Font baseFont, bool pick)
        {
            int u = baseFont.Height;
            Font = baseFont;
            Text = title;
            StartPosition = FormStartPosition.CenterParent;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false; ShowInTaskbar = false;
            BackColor = Theme.WindowBg; ForeColor = Theme.Text;
            ClientSize = new Size((int)(u * 46), (int)(u * 26));

            Label h = new Label();
            h.Text = hint; h.ForeColor = Theme.TextDim; h.AutoSize = false;
            h.Dock = DockStyle.Top; h.Height = (int)(u * 2.6F);
            h.Padding = new Padding((int)(u * 0.2F), (int)(u * 0.4F), 0, 0);
            Controls.Add(h);

            _list.Dock = DockStyle.Fill;
            _list.BorderStyle = BorderStyle.FixedSingle;
            _list.BackColor = Theme.CardBg; _list.ForeColor = Theme.Text;
            _list.Font = baseFont;
            _list.IntegralHeight = false;
            _list.SelectionMode = pick ? SelectionMode.One : SelectionMode.None;
            foreach (string s in items) _list.Items.Add(s);
            if (pick && _list.Items.Count > 0) _list.SelectedIndex = 0;
            Controls.Add(_list);
            _list.BringToFront();

            FlowLayoutPanel row = new FlowLayoutPanel();
            row.Dock = DockStyle.Bottom; row.Height = (int)(u * 2.9F);
            row.FlowDirection = FlowDirection.RightToLeft;
            row.BackColor = Theme.WindowBg;
            ModernButton ok = new ModernButton(okText, true);
            ok.Font = Theme.Bold(baseFont);
            ok.Margin = new Padding((int)(u * 0.4F), (int)(u * 0.3F), 0, 0);
            ok.Click += delegate { DialogResult = DialogResult.OK; Close(); };
            ModernButton cancel = new ModernButton(L.T("Отмена"), false);
            cancel.Font = baseFont;
            cancel.Margin = new Padding((int)(u * 0.4F), (int)(u * 0.3F), 0, 0);
            cancel.Click += delegate { DialogResult = DialogResult.Cancel; Close(); };
            row.Controls.Add(ok); row.Controls.Add(cancel);
            Controls.Add(row);
            row.BringToFront();

            Padding = new Padding((int)(u * 0.8F), (int)(u * 0.4F), (int)(u * 0.8F), (int)(u * 0.5F));
            AcceptButton = null; CancelButton = null;
        }
    }
}
