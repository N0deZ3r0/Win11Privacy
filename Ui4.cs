using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;

namespace Win11Privacy
{
    // ====================================================================== //
    //  Кликабельная карточка раздела на «Обзоре»: иконка, название, статус
    // ====================================================================== //
    internal class ActionCard : Control
    {
        public string Glyph = "", Title = "", Status = "";
        public Color Accent;
        public Color StatusColor;
        private bool _hover;

        public ActionCard(string title, string glyph, Color accent)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Title = title; Glyph = glyph; Accent = accent;
            StatusColor = Theme.TextDim;
            BackColor = Theme.WindowBg;
            Cursor = Cursors.Hand;
        }

        public void SetStatus(string text, Color color)
        {
            Status = text; StatusColor = color; Invalidate();
        }

        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            using (SolidBrush b = new SolidBrush(Parent != null ? Parent.BackColor : Theme.WindowBg))
                g.FillRectangle(b, ClientRectangle);
            if (Width < 20 || Height < 20) return;
            int u = Font.Height;

            RectangleF r = new RectangleF(0.5F, 0.5F, Width - 1, Height - 1);
            using (GraphicsPath p = Theme.RoundRect(r, 12))
            {
                using (LinearGradientBrush lb = new LinearGradientBrush(new Rectangle(0, 0, Width, Height),
                    Theme.Mix(Theme.CardBg, Accent, _hover ? 0.10F : 0.04F), Theme.CardBg, LinearGradientMode.Vertical))
                    g.FillPath(lb, p);
                using (Pen pen = new Pen(_hover ? Theme.Mix(Theme.CardBorder, Accent, 0.55F) : Theme.CardBorder))
                    g.DrawPath(pen, p);
            }
            using (Pen pen = new Pen(Color.FromArgb(Theme.Dark ? 22 : 40, Color.White)))
                g.DrawLine(pen, 12, 1, Width - 12, 1);

            int pad = (int)(u * 0.85F);
            int chip = (int)(u * 1.95F);
            int cy = (Height - chip) / 2;
            Font icon = Theme.IconFont(Font.Size * 1.25F);
            using (GraphicsPath p = Theme.RoundRect(new RectangleF(pad, cy, chip, chip), chip * 0.32F))
            using (SolidBrush b = new SolidBrush(Theme.Mix(Theme.CardBg, Accent, 0.20F))) g.FillPath(b, p);
            if (icon != null && !string.IsNullOrEmpty(Glyph))
                TextRenderer.DrawText(g, Glyph, icon, new Rectangle(pad, cy, chip, chip), Accent,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

            // стрелка справа
            int chev = (int)(u * 1.4F);
            Font chevF = Theme.IconFont(Font.Size * 0.9F);
            if (chevF != null)
                TextRenderer.DrawText(g, "", chevF, new Rectangle(Width - chev - (int)(u * 0.5F), 0, chev, Height),
                    _hover ? Accent : Theme.TextFaint,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

            int tx = pad + chip + (int)(u * 0.65F);
            int tw = Width - tx - chev - (int)(u * 0.8F);
            TextRenderer.DrawText(g, Title, new Font(Font, FontStyle.Bold),
                new Rectangle(tx, (int)(Height / 2F - u * 1.45F), tw, (int)(u * 1.5F)), Theme.Text,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            TextRenderer.DrawText(g, Status, Font,
                new Rectangle(tx, (int)(Height / 2F + 0), tw, (int)(u * 1.5F)), StatusColor,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
        }
    }

    // ====================================================================== //
    //  Мини-показатель в статусной панели: иконка, число, подпись
    // ====================================================================== //
    internal class MiniStat : Control
    {
        public string Glyph = "", Value = "—", Caption = "";
        public Color Accent;

        public MiniStat(string caption, string glyph, Color accent)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Caption = caption; Glyph = glyph; Accent = accent;
        }

        public void SetValue(string v) { Value = v; Invalidate(); }

        protected override void OnFontChanged(EventArgs e)
        {
            base.OnFontChanged(e);
            Size = new Size((int)(Font.Height * 10.5F), (int)(Font.Height * 2.9F));
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = Font.Height;
            int chip = (int)(u * 2.1F);
            int cy = (Height - chip) / 2;
            Font icon = Theme.IconFont(Font.Size * 1.1F);
            using (GraphicsPath p = Theme.RoundRect(new RectangleF(0, cy, chip, chip), chip * 0.32F))
            using (SolidBrush b = new SolidBrush(Theme.Mix(Theme.CardBg, Accent, 0.20F))) g.FillPath(b, p);
            if (icon != null && !string.IsNullOrEmpty(Glyph))
                TextRenderer.DrawText(g, Glyph, icon, new Rectangle(0, cy, chip, chip), Accent,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            int tx = chip + (int)(u * 0.55F);
            using (Font vf = new Font(Font.FontFamily, Font.Size * 1.2F, FontStyle.Bold))
                TextRenderer.DrawText(g, Value, vf, new Rectangle(tx, (int)(u * 0.1F), Width - tx, (int)(u * 1.6F)),
                    Accent, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            using (Font cf = new Font(Font.FontFamily, Font.Size * 0.85F))
                TextRenderer.DrawText(g, Caption, cf, new Rectangle(tx, (int)(u * 1.6F), Width - tx, (int)(u * 1.3F)),
                    Theme.TextDim, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
        }
    }

    // ====================================================================== //
    //  Небольшой «чип» с текстом (система в шапке «Обзора»)
    // ====================================================================== //
    internal class ChipLabel : Control
    {
        public ChipLabel()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        public void SetText(string text)
        {
            Text = text;
            int u = Font.Height;
            Size sz = TextRenderer.MeasureText(text, Font);
            Size = new Size(sz.Width + (int)(u * 1.4F), (int)(u * 1.7F));
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            if (string.IsNullOrEmpty(Text)) return;
            RectangleF r = new RectangleF(0.5F, 0.5F, Width - 1, Height - 1);
            using (GraphicsPath p = Theme.RoundRect(r, Height / 2F))
            {
                using (SolidBrush b = new SolidBrush(Theme.CardBg)) g.FillPath(b, p);
                using (Pen pen = new Pen(Theme.CardBorder)) g.DrawPath(pen, p);
            }
            TextRenderer.DrawText(g, Text, Font, ClientRectangle, Theme.TextDim,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
        }
    }
    // ====================================================================== //
    //  Адаптивная сетка плиток: сама выбирает число колонок по ширине,
    //  плитки растягиваются на всю ширину поровну
    // ====================================================================== //
    internal class TileGrid : Panel
    {
        public float MinTileWidthU = 13.5F;   // минимальная ширина плитки, в высотах шрифта
        public float TileHeightU = 6.0F;      // высота плитки: хватает на две строки подписи
        public float GapU = 0.55F;            // зазор
        public int MaxCols = 4;
        // Полоса фиксированной высоты вмещает только один ряд: если плитки
        // не влезли по ширине, они должны сузиться, а не уехать во второй ряд,
        // где их просто не видно.
        public bool SingleRow;
        private bool _busy;

        public TileGrid()
        {
            SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
            BackColor = Theme.WindowBg;
        }

        protected override void OnResize(EventArgs e) { base.OnResize(e); Arrange(); }
        protected override void OnControlAdded(ControlEventArgs e) { base.OnControlAdded(e); Arrange(); }
        protected override void OnControlRemoved(ControlEventArgs e) { base.OnControlRemoved(e); Arrange(); }
        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Arrange(); }

        private int CalcCols(int width, int count)
        {
            if (SingleRow) return Math.Max(1, count);
            int u = Font.Height;
            int gap = (int)(u * GapU);
            int minW = Math.Max(40, (int)(u * MinTileWidthU));
            int cols = (width + gap) / (minW + gap);
            if (cols < 1) cols = 1;
            int cap = Math.Min(MaxCols, Math.Max(1, count));
            if (cols > cap) cols = cap;
            return cols;
        }

        private int GridHeight(int width, int count)
        {
            if (count == 0) return 0;
            int u = Font.Height;
            int gap = (int)(u * GapU);
            int th = (int)(u * TileHeightU);
            int cols = CalcCols(width, count);
            int rows = (count + cols - 1) / cols;
            return rows * (th + gap) - gap;
        }

        public override Size GetPreferredSize(Size proposedSize)
        {
            int w = (proposedSize.Width > 0 && proposedSize.Width < 30000) ? proposedSize.Width : ClientSize.Width;
            return new Size(w, GridHeight(w, Controls.Count));
        }

        public void Arrange()
        {
            if (_busy || Controls.Count == 0) return;
            _busy = true;
            try
            {
                int u = Font.Height;
                int gap = (int)(u * GapU);
                int th = (int)(u * TileHeightU);
                int w = ClientSize.Width;
                if (w < 40) return;
                int cols = CalcCols(w, Controls.Count);
                int tw = (w - gap * (cols - 1)) / cols;
                for (int i = 0; i < Controls.Count; i++)
                {
                    int r = i / cols, c = i % cols;
                    Controls[i].SetBounds(c * (tw + gap), r * (th + gap), tw, th);
                }
                if (Dock == DockStyle.None)
                {
                    int need = GridHeight(w, Controls.Count);
                    if (Height != need) Height = need;
                }
            }
            finally { _busy = false; }
        }
    }

    // ====================================================================== //
    //  Панель содержимого с двойной буферизацией — без мерцания
    // ====================================================================== //
    internal class ContentPanel : Panel
    {
        public ContentPanel()
        {
            SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
        }
    }

    // ====================================================================== //
    //  Отдельная настройка внутри модуля: маленькая строка с галочкой
    // ====================================================================== //
    internal class SubOptionRow : Control
    {
        public readonly string Id;
        private readonly string _name;
        private bool _checked = true, _hover;

        public SubOptionRow(string id, string name)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Id = id; _name = name;
            BackColor = Theme.CardBg;
            Cursor = Cursors.Hand;
        }

        public bool Checked { get { return _checked; } set { _checked = value; Invalidate(); } }
        public string Name2 { get { return _name; } }

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Height = (int)(Font.Height * 1.75F); }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; Invalidate(); }
        protected override void OnClick(EventArgs e) { base.OnClick(e); _checked = !_checked; Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = Font.Height;
            int left = (int)(u * 3.4F);              // отступ под уровень модуля

            if (_hover)
            {
                using (GraphicsPath p = Theme.RoundRect(new RectangleF(left - u * 0.4F, 0.5F, Width - left, Height - 1), 5))
                using (SolidBrush b = new SolidBrush(Theme.RowHover)) g.FillPath(b, p);
            }

            int box = (int)(u * 0.95F);
            int by = (Height - box) / 2;
            RectangleF br = new RectangleF(left, by, box, box);
            using (GraphicsPath p = Theme.RoundRect(br, box * 0.28F))
            {
                if (_checked) using (SolidBrush b = new SolidBrush(Theme.Accent)) g.FillPath(b, p);
                using (Pen pen = new Pen(_checked ? Theme.Accent : Theme.TrackOff, 1.3F)) g.DrawPath(pen, p);
            }
            if (_checked)
                using (Pen pen = new Pen(Theme.AccentText, 1.6F))
                {
                    pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
                    g.DrawLine(pen, left + box * 0.24F, by + box * 0.54F, left + box * 0.43F, by + box * 0.73F);
                    g.DrawLine(pen, left + box * 0.43F, by + box * 0.73F, left + box * 0.78F, by + box * 0.28F);
                }

            int tx = left + box + (int)(u * 0.55F);
            TextRenderer.DrawText(g, _name, Font, new Rectangle(tx, 0, Width - tx - (int)(u * 0.5F), Height),
                _checked ? Theme.TextDim : Theme.TextFaint,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
        }
    }

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
            ok.Font = new Font(baseFont, FontStyle.Bold);
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
