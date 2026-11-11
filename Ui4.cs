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
            AccessibleRole = AccessibleRole.PushButton;
            AccessibleName = title;
        }

        public void SetStatus(string text, Color color)
        {
            AccessibleDescription = text;
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
            TextRenderer.DrawText(g, Title, Theme.Bold(Font),
                new Rectangle(tx, (int)(Height / 2F - u * 1.45F), tw, (int)(u * 1.5F)), Theme.Text,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            TextRenderer.DrawText(g, Status, Font,
                new Rectangle(tx, (int)(Height / 2F + 0), tw, (int)(u * 1.5F)), StatusColor,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
#if UITEST
            int need = TextRenderer.MeasureText(g, Status, Font).Width;
            if (need > tw) ClipWatch.Note("ActionCard.Status", Status, need, tw);
#endif
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

        public void SetValue(string v) { Value = v; Fit(); Invalidate(); }

        private Font ValueFont { get { return Theme.Sized(Font.Name, Font.SizeInPoints * 1.2F, FontStyle.Bold); } }
        private Font CaptionFont { get { return Theme.Sized(Font.Name, Font.SizeInPoints * 0.85F, FontStyle.Regular); } }
        private int TextLeft { get { return (int)(Font.Height * 2.1F) + (int)(Font.Height * 0.55F); } }

        // Ширина — по тексту, а не с запасом на глаз: три показателя в ряд
        // обязаны поместиться и в самом узком окне.
        private void Fit()
        {
            int text = Math.Max(TextRenderer.MeasureText(Value, ValueFont).Width,
                                TextRenderer.MeasureText(Caption, CaptionFont).Width);
            Size = new Size(TextLeft + text, (int)(Font.Height * 2.9F));
        }

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Fit(); }

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
            int tx = TextLeft;
            TextRenderer.DrawText(g, Value, ValueFont, new Rectangle(tx, (int)(u * 0.1F), Width - tx, (int)(u * 1.6F)),
                Accent, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            TextRenderer.DrawText(g, Caption, CaptionFont, new Rectangle(tx, (int)(u * 1.6F), Width - tx, (int)(u * 1.3F)),
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

        // Цена пункта: safe — ничего заметного, limited — какая-то функция
        // перестанет работать, caution — может задеть нужное. Note — что именно.
        public readonly string Risk, Note, RiskText;

        public SubOptionRow(string id, string name) : this(id, name, "safe", "", "") { }

        public SubOptionRow(string id, string name, string risk, string note, string riskText)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Id = id; _name = name;
            Risk = risk ?? "safe"; Note = note ?? ""; RiskText = riskText ?? "";
            BackColor = Theme.CardBg;
            Cursor = Cursors.Hand;
            AccessibleRole = AccessibleRole.CheckButton;
            AccessibleName = name;
            AccessibleDescription = (RiskText + (Note.Length > 0 ? ". " + Note : "")).Trim('.', ' ');
        }

        public bool Checked { get { return _checked; } set { _checked = value; Invalidate(); } }
        public string Name2 { get { return _name; } }

        private Color RiskColor { get { return Risk == "caution" ? Theme.Err : Theme.Warn; } }

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Height = (int)(Font.Height * (Note.Length > 0 ? 2.85F : 1.75F)); }
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
            int right = Width - (int)(u * 0.5F);

            // метка цены справа — только когда что-то перестанет работать
            if (Risk != "safe" && RiskText.Length > 0)
            {
                using (Font cf = new Font(Font.FontFamily, Font.Size * 0.8F, FontStyle.Bold))
                {
                    Size cs = TextRenderer.MeasureText(RiskText, cf);
                    int cw = cs.Width + (int)(u * 0.7F), ch = (int)(u * 1.15F);
                    RectangleF cr = new RectangleF(right - cw, (Note.Length > 0 ? u * 0.3F : (Height - ch) / 2F), cw, ch);
                    using (GraphicsPath p = Theme.RoundRect(cr, ch / 2F))
                    using (SolidBrush b = new SolidBrush(Theme.Mix(Theme.CardBg, RiskColor, 0.16F))) g.FillPath(b, p);
                    TextRenderer.DrawText(g, RiskText, cf, Rectangle.Round(cr), RiskColor,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
                    right -= cw + (int)(u * 0.5F);
                }
            }

            Color fg = _checked ? Theme.TextDim : Theme.TextFaint;
            if (Note.Length == 0)
            {
                TextRenderer.DrawText(g, _name, Font, new Rectangle(tx, 0, right - tx, Height), fg,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
                return;
            }
            // с пояснением: название сверху, что перестанет работать — строкой ниже
            int line = (int)(u * 1.3F);
            TextRenderer.DrawText(g, _name, Font, new Rectangle(tx, (int)(u * 0.25F), right - tx, line), fg,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            using (Font nf = new Font(Font.FontFamily, Font.Size * 0.88F))
                TextRenderer.DrawText(g, Note, nf, new Rectangle(tx, (int)(u * 0.25F) + line, Width - tx - (int)(u * 0.5F), line),
                    Risk == "safe" ? Theme.TextFaint : Theme.Mix(Theme.TextFaint, RiskColor, 0.55F),
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

    // ====================================================================== //
    //  Полоска хода работы в строке состояния. Системный ProgressBar рисовался
    //  в стиле Windows 7 — зелёным по светло-серому, чужеродно в тёмной теме.
    //  Эта — тонкая и скруглённая, в цветах темы. Пока объём неизвестен, по ней
    //  бежит мягкий отрезок; когда движок сообщает «15 / 34», она плавно
    //  заполняется. Свойства те же, что у ProgressBar, — менять вызовы не нужно.
    // ====================================================================== //
    internal class SlimProgress : Control
    {
        private ProgressBarStyle _style = ProgressBarStyle.Marquee;
        private int _max = 100, _value;
        private float _shown, _phase;
        private readonly Timer _timer = new Timer();

        public SlimProgress()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            _timer.Interval = 16;
            _timer.Tick += delegate
            {
                if (_style == ProgressBarStyle.Marquee) { _phase += 0.011F; if (_phase > 1F) _phase -= 1F; }
                else
                {
                    float target = _max > 0 ? (float)_value / _max : 0F;
                    _shown += (target - _shown) * 0.18F;
                    if (Math.Abs(target - _shown) < 0.002F) _shown = target;
                }
                Invalidate();
            };
        }

        public ProgressBarStyle Style
        {
            get { return _style; }
            set { if (_style == value) return; _style = value; _phase = 0F; if (value != ProgressBarStyle.Marquee) _shown = 0F; UpdateTimer(); Invalidate(); }
        }
        public int Maximum { get { return _max; } set { _max = Math.Max(1, value); Invalidate(); } }
        public int Value { get { return _value; } set { _value = Math.Max(0, Math.Min(value, _max)); } }

        private void UpdateTimer() { _timer.Enabled = Visible && Parent != null; }
        protected override void OnVisibleChanged(EventArgs e) { base.OnVisibleChanged(e); UpdateTimer(); }
        protected override void OnParentChanged(EventArgs e) { base.OnParentChanged(e); UpdateTimer(); }
        protected override void Dispose(bool disposing) { if (disposing) _timer.Dispose(); base.Dispose(disposing); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Color bg = Parent != null ? Parent.BackColor : Theme.WindowBg;
            using (SolidBrush b = new SolidBrush(bg)) g.FillRectangle(b, ClientRectangle);
            if (Width < 4 || Height < 2) return;

            RectangleF track = new RectangleF(0.5F, 0.5F, Width - 1F, Height - 1F);
            float r = track.Height / 2F;
            using (GraphicsPath tp = Theme.RoundRect(track, r))
            {
                using (SolidBrush b = new SolidBrush(Theme.Mix(bg, Theme.TextFaint, Theme.Dark ? 0.22F : 0.28F))) g.FillPath(b, tp);
                GraphicsState st = g.Save();
                g.SetClip(tp, CombineMode.Intersect);
                if (_style == ProgressBarStyle.Marquee)
                {
                    // отрезок в треть ширины ускоряется к середине и замедляется у краёв
                    float seg = track.Width * 0.34F;
                    float t = (float)(0.5 - 0.5 * Math.Cos(_phase * Math.PI));
                    float x = track.X - seg + (track.Width + seg) * t;
                    RectangleF sr = new RectangleF(x, track.Y, seg, track.Height);
                    using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(sr.X - 1, sr.Y, sr.Width + 2, sr.Height), Theme.Accent, Theme.Accent2, LinearGradientMode.Horizontal))
                    {
                        ColorBlend cb = new ColorBlend();
                        cb.Colors = new[] { Color.FromArgb(0, Theme.Accent), Theme.Accent, Theme.Accent2, Color.FromArgb(0, Theme.Accent2) };
                        cb.Positions = new[] { 0F, 0.3F, 0.7F, 1F };
                        lb.InterpolationColors = cb;
                        g.FillRectangle(lb, sr);
                    }
                }
                else if (_shown > 0.001F)
                {
                    RectangleF fr = new RectangleF(track.X, track.Y, Math.Max(track.Height, track.Width * _shown), track.Height);
                    using (GraphicsPath fp = Theme.RoundRect(fr, r))
                    using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(track.X - 1, track.Y, track.Width + 2, track.Height), Theme.Accent, Theme.Accent2, LinearGradientMode.Horizontal))
                        g.FillPath(lb, fp);
                }
                g.Restore(st);
            }
        }
    }

    // ====================================================================== //
    //  Поле поиска. Голый TextBox с одинарной рамкой прижимал подсказку
    //  вплотную к краю и выглядел чужим среди скруглённых карточек и кнопок.
    //  Теперь: скруглённая рамка, значок лупы, отступы, подсветка рамки при
    //  вводе. Сам TextBox остаётся внутри (Box) — фильтры, Ctrl+F и проверки
    //  работают с ним как раньше.
    // ====================================================================== //
    internal class SearchBox : Control
    {
        public readonly TextBox Box;
        private const string SearchGlyph = "";

        public SearchBox(Font font, string placeholder)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Font = font;
            Cursor = Cursors.IBeam;
            Box = new TextBox();
            Box.BorderStyle = BorderStyle.None;
            Box.Font = font;
            Box.BackColor = Theme.CardBg;
            Box.ForeColor = Theme.Text;
            Box.AccessibleName = placeholder;
            Box.GotFocus += delegate { Invalidate(); };
            Box.LostFocus += delegate { Invalidate(); };
            Controls.Add(Box);
            Dwm.Placeholder(Box, placeholder);
            Height = (int)(font.Height * 2.05F);
            LayoutBox();
        }

        protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); Box.Focus(); }
        protected override void OnResize(EventArgs e) { base.OnResize(e); LayoutBox(); }
        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); if (Box != null) { Box.Font = Font; LayoutBox(); } }

        private void LayoutBox()
        {
            if (Box == null) return;
            int u = Font.Height;
            int left = (int)(u * 1.95F);
            int right = (int)(u * 0.7F);
            Box.SetBounds(left, Math.Max(0, (Height - Box.Height) / 2), Math.Max(10, Width - left - right), Box.Height);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush b = new SolidBrush(Parent != null ? Parent.BackColor : Theme.WindowBg))
                g.FillRectangle(b, ClientRectangle);
            int u = Font.Height;
            bool focused = Box.Focused;
            RectangleF r = new RectangleF(0.5F, 0.5F, Width - 1.5F, Height - 1.5F);
            using (GraphicsPath p = Theme.RoundRect(r, u * 0.45F))
            {
                using (SolidBrush b = new SolidBrush(Theme.CardBg)) g.FillPath(b, p);
                Color edge = focused ? Theme.Accent : Theme.Mix(Theme.CardBorder, Theme.TextFaint, Theme.Dark ? 0.25F : 0.35F);
                using (Pen pen = new Pen(edge, focused ? 1.6F : 1F)) g.DrawPath(pen, p);
            }
            Font icon = Theme.IconFont(Font.Size * 0.95F);
            if (icon != null)
                TextRenderer.DrawText(g, SearchGlyph, icon, new Rectangle((int)(u * 0.55F), 0, (int)(u * 1.2F), Height),
                    focused ? Theme.Accent : Theme.TextFaint,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }
    }
}
