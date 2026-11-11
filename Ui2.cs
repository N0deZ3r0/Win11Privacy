using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Win11Privacy
{
    // ====================================================================== //
    //  Плавная анимация значения (для счётчиков и полос)
    // ====================================================================== //
    internal class Tween
    {
        private readonly Timer _t = new Timer();
        private float _cur, _target;
        private readonly float _speed;
        public event EventHandler Changed;

        public Tween(float speed = 0.14F)
        {
            _speed = speed;
            _t.Interval = 16;
            _t.Tick += delegate
            {
                _cur += (_target - _cur) * _speed;
                if (Math.Abs(_target - _cur) < 0.002F * Math.Max(1F, Math.Abs(_target))) { _cur = _target; _t.Stop(); }
                if (Changed != null) Changed(this, EventArgs.Empty);
            };
        }

        public float Value { get { return _cur; } }
        public float Target { get { return _target; } }

        public void To(float v, bool animate)
        {
            _target = v;
            if (!animate) { _cur = v; _t.Stop(); if (Changed != null) Changed(this, EventArgs.Empty); return; }
            _t.Start();
        }
    }

    // ====================================================================== //
    //  Свой заголовок окна: иконка, название, кнопки, перетаскивание
    // ====================================================================== //
    internal class TitleBar : Control
    {
        [DllImport("user32.dll")] private static extern bool ReleaseCapture();
        [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr hWnd, int msg, int wParam, int lParam);

        private const int WM_NCLBUTTONDOWN = 0xA1;
        private const int HTCAPTION = 0x2;

        public Image Logo;
        public string Caption = "";
        private int _hoverBtn = -1;     // 0 свернуть, 1 развернуть, 2 закрыть
        private readonly Form _form;

        public TitleBar(Form form)
        {
            _form = form;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.SideTop;
        }

        private int BtnW { get { return (int)(Font.Height * 2.35F); } }

        private int HitButton(int x)
        {
            int w = BtnW;
            if (x >= Width - w) return 2;
            if (x >= Width - w * 2) return 1;
            if (x >= Width - w * 3) return 0;
            return -1;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            int h = HitButton(e.X);
            if (h != _hoverBtn) { _hoverBtn = h; Invalidate(); }
        }

        protected override void OnMouseLeave(EventArgs e)
        { base.OnMouseLeave(e); if (_hoverBtn != -1) { _hoverBtn = -1; Invalidate(); } }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            int h = HitButton(e.X);
            if (h == 2) { _form.Close(); return; }
            if (h == 1) { _form.WindowState = _form.WindowState == FormWindowState.Maximized ? FormWindowState.Normal : FormWindowState.Maximized; Invalidate(); return; }
            if (h == 0) { _form.WindowState = FormWindowState.Minimized; return; }
            // перетаскивание окна
            if (e.Button == MouseButtons.Left)
            {
                try { ReleaseCapture(); SendMessage(_form.Handle, WM_NCLBUTTONDOWN, HTCAPTION, 0); } catch { }
            }
        }

        protected override void OnDoubleClick(EventArgs e)
        {
            base.OnDoubleClick(e);
            if (_hoverBtn == -1)
                _form.WindowState = _form.WindowState == FormWindowState.Maximized ? FormWindowState.Normal : FormWindowState.Maximized;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = Font.Height;

            using (SolidBrush b = new SolidBrush(Theme.SideTop)) g.FillRectangle(b, ClientRectangle);

            int x = (int)(u * 1.1F);
            if (Logo != null)
            {
                int s = (int)(u * 1.45F);
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(Logo, x, (Height - s) / 2, s, s);
                x += s + (int)(u * 0.6F);
            }
            TextRenderer.DrawText(g, Caption, Font, new Rectangle(x, 0, Width - x - BtnW * 3, Height),
                Theme.TextDim, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);

            // кнопки окна
            for (int i = 0; i < 3; i++)
            {
                int bx = Width - BtnW * (3 - i);
                Rectangle r = new Rectangle(bx, 0, BtnW, Height);
                if (_hoverBtn == i)
                    using (SolidBrush b = new SolidBrush(i == 2 ? Color.FromArgb(232, 17, 35) : Theme.RowHover))
                        g.FillRectangle(b, new Rectangle(r.X, 1, r.Width, r.Height - 2));
                Color fg = (_hoverBtn == 2 && i == 2) ? Color.White : Theme.TextDim;
                float cx = bx + BtnW / 2F, cy = Height / 2F, s = u * 0.28F;
                using (Pen p = new Pen(fg, 1.1F))
                {
                    if (i == 0) g.DrawLine(p, cx - s, cy, cx + s, cy);
                    else if (i == 1)
                    {
                        if (_form.WindowState == FormWindowState.Maximized)
                        {
                            g.DrawRectangle(p, cx - s + 2, cy - s, s * 2 - 2, s * 2 - 2);
                            g.DrawLine(p, cx - s + 2, cy - s + 1, cx - s + 2, cy - s - 1);
                        }
                        else g.DrawRectangle(p, cx - s, cy - s, s * 2, s * 2);
                    }
                    else { g.DrawLine(p, cx - s, cy - s, cx + s, cy + s); g.DrawLine(p, cx + s, cy - s, cx - s, cy + s); }
                }
            }
        }
    }

    // ====================================================================== //
    //  Боковая панель: градиент, свечение, скользящая подсветка выбора
    // ====================================================================== //
    // ====================================================================== //
    //  Заголовок группы в боковой панели. Тринадцать пунктов подряд читаются
    //  как сплошной список: глаз каждый раз проходит его целиком. С подписями
    //  «Действия», «Разведка», «Контроль» нужное находится сразу, а в свёрнутой
    //  панели вместо подписи остаётся тонкая черта — она делит список так же.
    // ====================================================================== //
    internal class NavGroup : Control
    {
        public NavGroup(string text)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            Text = text;
            BackColor = Color.Transparent;
        }

        public bool Compact { get { return Width < Font.Height * 6; } }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            float u = Font.Height;
            if (Compact)
            {
                using (Pen p = new Pen(Theme.Mix(Theme.SideBottom, Theme.TextFaint, 0.5F)))
                    g.DrawLine(p, u * 0.6F, Height / 2F, Width - u * 0.6F, Height / 2F);
                return;
            }
            using (Font f = new Font(Font.FontFamily, Font.Size * 0.78F, FontStyle.Bold))
            using (SolidBrush b = new SolidBrush(Theme.TextFaint))
                g.DrawString(Text, f, b, u * 0.6F, (Height - f.Height) / 2F);
        }
    }

    internal class NavHost : Panel
    {
        private readonly Tween _y = new Tween(0.22F);
        private readonly Tween _h = new Tween(0.22F);
        private bool _has;

        public NavHost()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Color.Transparent;
            _y.Changed += delegate { Invalidate(); };
            _h.Changed += delegate { Invalidate(); };
        }

        public void MoveTo(Control item, bool animate)
        {
            if (item == null) { _has = false; Invalidate(); return; }
            bool first = !_has;
            _has = true;
            _y.To(item.Top, animate && !first);
            _h.To(item.Height, animate && !first);
            Invalidate();
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            // Под списком — тот же градиент со свечением, что у всей боковой
            // панели. Раньше здесь была сплошная заливка цветом панели, и поверх
            // градиента проступал прямоугольник: в светлой теме он читался как
            // рамка вокруг разделов с зазубринами у каждого пункта.
            if (Parent != null)
            {
                GraphicsState st = g.Save();
                g.TranslateTransform(-Left, -Top);
                Rectangle clip = e.ClipRectangle;
                clip.Offset(Left, Top);
                using (PaintEventArgs pe = new PaintEventArgs(g, clip)) InvokePaintBackground(Parent, pe);
                g.Restore(st);
            }
            else using (SolidBrush b = new SolidBrush(Theme.SideTop)) g.FillRectangle(b, ClientRectangle);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            if (!_has || Width < 10) return;
            RectangleF r = new RectangleF(4, _y.Value + 2, Width - 8, _h.Value - 4);
            if (r.Height < 2) return;
            // выбранный пункт — едва заметная подложка и тонкая акцентная
            // полоса слева, как в строгих консолях
            using (GraphicsPath p = Theme.RoundRect(r, 6))
            using (SolidBrush b = new SolidBrush(Color.FromArgb(Theme.Dark ? 22 : 18, Theme.Text)))
                g.FillPath(b, p);
            float bar = Math.Max(2F, Font.Height * 0.16F);
            float inset = r.Height * 0.26F;
            using (GraphicsPath p = Theme.RoundRect(new RectangleF(r.X, r.Y + inset, bar, r.Height - inset * 2), bar / 2F))
            using (SolidBrush b = new SolidBrush(Theme.Accent))
                g.FillPath(b, p);
        }
    }

    // ====================================================================== //
    //  Фон боковой панели: вертикальный градиент + мягкое свечение
    // ====================================================================== //
    internal class SidePanel : Panel
    {
        public SidePanel()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            if (Width < 2 || Height < 2) return;
            // ровный фон без градиента и свечения
            using (SolidBrush b = new SolidBrush(Theme.SideTop)) g.FillRectangle(b, ClientRectangle);
            // правая разделительная линия
            using (Pen pen = new Pen(Theme.CardBorder)) g.DrawLine(pen, Width - 1, 0, Width - 1, Height);
        }
    }

    // ====================================================================== //
    //  Кольцевая диаграмма категорий
    // ====================================================================== //
    internal class DonutChart : Control
    {
        private readonly List<KeyValuePair<string, float>> _data = new List<KeyValuePair<string, float>>();
        private readonly Tween _grow = new Tween(0.10F);
        public string CenterTitle = "";
        public string CenterSub = "";
        public string EmptyHint = "";

        // Оттенки одного акцента вместо радуги: категории различимы, а
        // диаграмма не спорит по цвету с пометками о состоянии.
        private static Color[] Palette
        {
            get
            {
                float[] t = { 0F, 0.28F, 0.46F, 0.60F, 0.71F, 0.80F, 0.87F, 0.92F };
                Color[] c = new Color[t.Length];
                for (int i = 0; i < t.Length; i++) c[i] = Theme.Mix(Theme.Accent, Theme.CardBg, t[i]);
                return c;
            }
        }

        public DonutChart()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            _grow.Changed += delegate { Invalidate(); };
        }

        public void SetData(List<KeyValuePair<string, float>> items, string centerTitle, string centerSub)
        {
            _data.Clear();
            if (items != null) _data.AddRange(items);
            CenterTitle = centerTitle; CenterSub = centerSub;
            _grow.To(1F, IsHandleCreated && Visible);
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            if (Width < 60 || Height < 60) return;
            if (_data.Count == 0)
            {
                if (!string.IsNullOrEmpty(EmptyHint))
                    TextRenderer.DrawText(g, EmptyHint, Font, ClientRectangle, Theme.TextDim,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
                return;
            }

            int u = Font.Height;
            int legendW = Math.Min((int)(u * 19F), (int)(Width * 0.52F));
            int side = Math.Min(Height, Width - legendW - (int)(u * 0.8F)) - 6;
            if (side < u * 5) { side = Math.Min(Width, Height) - 6; legendW = 0; }
            RectangleF r = new RectangleF(2, (Height - side) / 2F, side, side);
            float thick = side * 0.19F;

            float total = 0; foreach (var kv in _data) total += kv.Value;
            if (total <= 0) return;

            using (Pen bg = new Pen(Theme.Mix(Theme.CardBg, Theme.TextFaint, 0.22F), thick))
                g.DrawArc(bg, RectangleF.Inflate(r, -thick / 2, -thick / 2), 0, 360);

            float start = -90F;
            for (int i = 0; i < _data.Count; i++)
            {
                float sweep = 360F * (_data[i].Value / total) * _grow.Value;
                using (Pen p = new Pen(Palette[i % Palette.Length], thick))
                {
                    p.StartCap = LineCap.Flat; p.EndCap = LineCap.Flat;
                    if (sweep > 0.6F) g.DrawArc(p, RectangleF.Inflate(r, -thick / 2, -thick / 2), start, sweep - 0.6F);
                }
                start += sweep;
            }

            if (!string.IsNullOrEmpty(CenterTitle))
            {
                // текст в центре не должен выезжать на кольцо — подбираем размер под отверстие
                float hole = side - thick * 2F - u * 0.5F;
                float fs = side * 0.13F;
                SizeF sz;
                Font bf = new Font(Font.FontFamily, fs, FontStyle.Bold);
                while (true)
                {
                    sz = g.MeasureString(CenterTitle, bf);
                    if (sz.Width <= hole || fs <= Font.Size * 0.85F) break;
                    fs *= 0.92F;
                    bf.Dispose();
                    bf = new Font(Font.FontFamily, fs, FontStyle.Bold);
                }
                using (SolidBrush b = new SolidBrush(Theme.Text))
                    g.DrawString(CenterTitle, bf, b, r.X + (side - sz.Width) / 2F, r.Y + side / 2F - sz.Height * 0.85F);
                bf.Dispose();

                float ss = side * 0.068F;
                Font sf = new Font(Font.FontFamily, ss);
                SizeF s2;
                while (true)
                {
                    s2 = g.MeasureString(CenterSub, sf);
                    if (s2.Width <= hole || ss <= Font.Size * 0.75F) break;
                    ss *= 0.92F;
                    sf.Dispose();
                    sf = new Font(Font.FontFamily, ss);
                }
                using (SolidBrush b = new SolidBrush(Theme.TextDim))
                    g.DrawString(CenterSub, sf, b, r.X + (side - s2.Width) / 2F, r.Y + side / 2F + s2.Height * 0.15F);
                sf.Dispose();
            }

            if (legendW < u * 6) return;
            int lx = (int)(r.Right + u * 1.2F);
            int ly = (int)((Height - _data.Count * u * 1.55F) / 2F);
            if (ly < 2) ly = 2;
            for (int i = 0; i < _data.Count; i++)
            {
                using (SolidBrush b = new SolidBrush(Palette[i % Palette.Length]))
                using (GraphicsPath p = Theme.RoundRect(new RectangleF(lx, ly + u * 0.42F, u * 0.6F, u * 0.6F), u * 0.2F))
                    g.FillPath(b, p);
                string pct = (100F * _data[i].Value / total).ToString("0") + "%";
                Size ps = TextRenderer.MeasureText(pct, Font);
                TextRenderer.DrawText(g, _data[i].Key, Font,
                    new Rectangle(lx + (int)(u * 1.1F), ly, Width - lx - (int)(u * 1.1F) - ps.Width - (int)(u * 0.6F), (int)(u * 1.5F)),
                    Theme.TextDim, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
                TextRenderer.DrawText(g, pct, Theme.Bold(Font),
                    new Rectangle(0, ly, Width - (int)(u * 0.3F), (int)(u * 1.5F)),
                    Theme.Text, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
                ly += (int)(u * 1.55F);
            }
        }
    }

    // ====================================================================== //
    //  Крупная плитка показателя с анимацией числа
    // ====================================================================== //
    internal class HeroTile : Control
    {
        private readonly Tween _v = new Tween(0.12F);
        public string Caption = "", Sub = "", Suffix = "", Glyph = "";
        public Color Accent;
        private float _final;
        private bool _numeric = true;
        private string _rawText = "";
        private bool _hover;

        public HeroTile()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.CardBg;
            Accent = Theme.Accent;
            _v.Changed += delegate { Invalidate(); };
        }

        public void SetNumber(float value, string suffix, bool animate)
        { _numeric = true; _final = value; Suffix = suffix ?? ""; _v.To(value, animate); Invalidate(); }

        public void SetText(string text)
        { _numeric = false; _rawText = text ?? ""; Invalidate(); }

        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; Invalidate(); }

        private string Display()
        {
            if (!_numeric) return _rawText;
            float v = _v.Value;
            if (_final >= 1000000) return (v / 1000000F).ToString("0.#") + L.T(" млн");
            if (_final >= 10000) return (v / 1000F).ToString("0.#") + L.T(" тыс");
            if (_final != Math.Floor(_final)) return v.ToString("0.#");
            return ((int)Math.Round(v)).ToString();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            using (SolidBrush b = new SolidBrush(Parent != null ? Parent.BackColor : Theme.WindowBg))
                g.FillRectangle(b, ClientRectangle);
            if (Width < 20 || Height < 20) return;
            int u = Font.Height;

            bool status = Theme.IsStatus(Accent);
            RectangleF r = new RectangleF(0.5F, 0.5F, Width - 1, Height - 1);
            using (GraphicsPath p = Theme.RoundRect(r, 8))
            {
                using (SolidBrush b = new SolidBrush(_hover ? Theme.RowHover : Theme.CardBg)) g.FillPath(b, p);
                using (Pen pen = new Pen(Theme.CardBorder)) g.DrawPath(pen, p);
            }

            int pad = (int)(u * 0.95F);
            Font icon = Theme.IconFont(Font.Size * 1.05F);
            int capX = pad;
            // одноцветный значок без подложки
            int chip = (int)(u * 1.85F);
            if (icon != null && !string.IsNullOrEmpty(Glyph))
            {
                TextRenderer.DrawText(g, Glyph, icon, new Rectangle(pad, (int)(u * 0.55F), (int)(u * 1.3F), chip),
                    status ? Accent : Theme.TextDim, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                capX = pad + (int)(u * 1.3F) + (int)(u * 0.5F);
            }
            TextRenderer.DrawText(g, Caption, Font,
                new Rectangle(capX, (int)(u * 0.55F), Width - capX - pad, chip), Theme.TextDim,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);

            string val = Display();
            using (Font vf = Theme.PickFont(new[] { "Segoe UI Variable Display", "Segoe UI Semibold", "Segoe UI", "Tahoma" },
                                            Font.Size * 2.0F, FontStyle.Bold))
            {
                Size vs = TextRenderer.MeasureText(g, val, vf, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
                TextRenderer.DrawText(g, val, vf, new Rectangle(pad, (int)(u * 2.55F), Width - pad * 2, (int)(u * 1.95F)),
                    status ? Accent : Theme.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                if (!string.IsNullOrEmpty(Suffix))
                    TextRenderer.DrawText(g, Suffix, Font,
                        new Rectangle(pad + vs.Width + (int)(u * 0.15F), (int)(u * 2.55F), Width - pad, (int)(u * 1.95F)),
                        Theme.TextDim, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            }
            if (!string.IsNullOrEmpty(Sub))
            {
                // подпись до двух строк, прижата к низу — длинный текст переносится, а не режется
                int maxW = Width - pad * 2;
                int sh = TextRenderer.MeasureText(Sub, Font, new Size(maxW, 0),
                    TextFormatFlags.WordBreak | TextFormatFlags.NoPadding).Height;
                int maxH = (int)(u * 2.15F);
                if (sh > maxH) sh = maxH;
                Rectangle sr = new Rectangle(pad, Height - (int)(u * 0.5F) - sh, maxW, sh);
                TextRenderer.DrawText(g, Sub, Font, sr, Theme.TextDim,
                    TextFormatFlags.Left | TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
            }
        }
    }
}
