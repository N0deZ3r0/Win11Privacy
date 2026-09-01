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
    // ====================================================================== //
    //  Тема: цвета, шрифты, определение тёмного режима Windows
    // ====================================================================== //
    internal static class Theme
    {
        public static bool Dark = true;

        public static Color WindowBg, CardBg, CardBorder, RowHover, LogBg;
        public static Color Text, TextDim, TextFaint, Accent, Accent2, AccentHover, AccentText;
        public static Color Warn, Ok, Err, ButtonBg, ButtonHover, ButtonBorder, BadgeBg, TrackOff, Knob;
        public static Color SideTop, SideBottom;

        public static void Detect()
        {
            bool dark = true;
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                {
                    if (k != null)
                    {
                        object v = k.GetValue("AppsUseLightTheme");
                        if (v != null && Convert.ToInt32(v) == 1) dark = false;
                    }
                }
            }
            catch { }
            Apply(dark);
        }

        public static void Apply(bool dark)
        {
            Dark = dark;
            if (dark)
            {
                WindowBg   = Color.FromArgb(0x15, 0x17, 0x1C);
                CardBg     = Color.FromArgb(0x1E, 0x22, 0x2A);
                CardBorder = Color.FromArgb(0x2B, 0x30, 0x3B);
                RowHover   = Color.FromArgb(0x27, 0x2C, 0x37);
                LogBg      = Color.FromArgb(0x12, 0x14, 0x19);
                Text       = Color.FromArgb(0xF2, 0xF4, 0xF8);
                TextDim    = Color.FromArgb(0xA9, 0xB1, 0xBF);
                TextFaint  = Color.FromArgb(0x74, 0x7C, 0x8B);
                Accent     = Color.FromArgb(0x4C, 0xC2, 0xFF);
                Accent2    = Color.FromArgb(0x47, 0x83, 0xFF);
                AccentHover= Color.FromArgb(0x7E, 0xD3, 0xFF);
                AccentText = Color.FromArgb(0x0A, 0x18, 0x28);
                Warn       = Color.FromArgb(0xF6, 0xB1, 0x5C);
                Ok         = Color.FromArgb(0x74, 0xD9, 0x8C);
                Err        = Color.FromArgb(0xFF, 0x82, 0x78);
                ButtonBg   = Color.FromArgb(0x28, 0x2D, 0x38);
                ButtonHover= Color.FromArgb(0x31, 0x37, 0x44);
                ButtonBorder=Color.FromArgb(0x3C, 0x43, 0x52);
                BadgeBg    = Color.FromArgb(0x1D, 0x3A, 0x55);
                TrackOff   = Color.FromArgb(0x8E, 0x96, 0xA5);
                Knob       = Color.FromArgb(0xE8, 0xEC, 0xF2);
                SideTop    = Color.FromArgb(0x11, 0x13, 0x19);
                SideBottom = Color.FromArgb(0x0D, 0x0F, 0x14);
            }
            else
            {
                WindowBg   = Color.FromArgb(0xF4, 0xF6, 0xFA);
                CardBg     = Color.White;
                CardBorder = Color.FromArgb(0xE3, 0xE7, 0xEF);
                RowHover   = Color.FromArgb(0xF0, 0xF3, 0xF8);
                LogBg      = Color.FromArgb(0xFA, 0xFB, 0xFD);
                Text       = Color.FromArgb(0x1A, 0x1D, 0x23);
                TextDim    = Color.FromArgb(0x5B, 0x63, 0x6F);
                TextFaint  = Color.FromArgb(0x8A, 0x93, 0xA1);
                Accent     = Color.FromArgb(0x0F, 0x6C, 0xBD);
                Accent2    = Color.FromArgb(0x4F, 0x6B, 0xED);
                AccentHover= Color.FromArgb(0x2B, 0x84, 0xD6);
                AccentText = Color.White;
                Warn       = Color.FromArgb(0xB4, 0x53, 0x09);
                Ok         = Color.FromArgb(0x1E, 0x8E, 0x3E);
                Err        = Color.FromArgb(0xC4, 0x2B, 0x1C);
                ButtonBg   = Color.FromArgb(0xFB, 0xFC, 0xFE);
                ButtonHover= Color.FromArgb(0xF0, 0xF3, 0xF8);
                ButtonBorder=Color.FromArgb(0xD5, 0xDA, 0xE4);
                BadgeBg    = Color.FromArgb(0xE1, 0xEF, 0xFB);
                TrackOff   = Color.FromArgb(0x84, 0x8D, 0x9B);
                Knob       = Color.FromArgb(0x56, 0x60, 0x70);
                SideTop    = Color.FromArgb(0xFB, 0xFC, 0xFE);
                SideBottom = Color.FromArgb(0xED, 0xF1, 0xF7);
            }
        }

        // Первый существующий шрифт из списка
        public static Font PickFont(string[] names, float size, FontStyle style)
        {
            foreach (string n in names)
            {
                try
                {
                    using (FontFamily ff = new FontFamily(n))
                    {
                        if (ff.IsStyleAvailable(style)) return new Font(n, size, style, GraphicsUnit.Point);
                    }
                }
                catch { }
            }
            return new Font(FontFamily.GenericSansSerif, size, style, GraphicsUnit.Point);
        }

        public static readonly string[] UiFonts   = { "Segoe UI Variable Text", "Segoe UI", "Tahoma" };
        public static readonly string[] MonoFonts = { "Cascadia Mono", "Cascadia Code", "Consolas", "Courier New" };
        public static readonly string[] IconFonts = { "Segoe Fluent Icons", "Segoe MDL2 Assets" };

        private static Font _iconFont;
        private static bool _iconChecked;
        public static Font IconFont(float size)
        {
            if (!_iconChecked)
            {
                _iconChecked = true;
                foreach (string n in IconFonts)
                {
                    try
                    {
                        using (FontFamily ff = new FontFamily(n)) { _iconFont = new Font(n, size, GraphicsUnit.Point); break; }
                    }
                    catch { }
                }
            }
            if (_iconFont == null) return null;
            if (Math.Abs(_iconFont.Size - size) > 0.1F) _iconFont = new Font(_iconFont.FontFamily, size, GraphicsUnit.Point);
            return _iconFont;
        }

        public static GraphicsPath RoundRect(RectangleF r, float radius)
        {
            GraphicsPath p = new GraphicsPath();
            float d = radius * 2;
            if (d <= 0 || r.Width < d || r.Height < d) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        public static Color Mix(Color a, Color b, float t)
        {
            return Color.FromArgb(
                (int)(a.R + (b.R - a.R) * t),
                (int)(a.G + (b.G - a.G) * t),
                (int)(a.B + (b.B - a.B) * t));
        }
    }

    // ====================================================================== //
    //  Интеграция с DWM: тёмный заголовок и скруглённые углы окна (Win11)
    // ====================================================================== //
    internal static class Dwm
    {
        [DllImport("dwmapi.dll", PreserveSig = true)]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int SetWindowTheme(IntPtr hWnd, string subApp, string subIdList);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam);

        // Серая подсказка внутри пустого поля ввода (EM_SETCUEBANNER)
        public static void Placeholder(TextBox t, string text)
        {
            EventHandler apply = delegate { try { SendMessage(t.Handle, 0x1501, (IntPtr)1, text); } catch { } };
            if (t.IsHandleCreated) apply(null, EventArgs.Empty);
            t.HandleCreated += apply;
        }

        // Тёмные системные полосы прокрутки (Windows 10 1809+ / 11)
        public static void DarkScrollbars(Control c)
        {
            if (Environment.OSVersion.Platform != PlatformID.Win32NT) return;
            EventHandler apply = delegate
            {
                try { SetWindowTheme(c.Handle, Theme.Dark ? "DarkMode_Explorer" : "Explorer", null); } catch { }
            };
            if (c.IsHandleCreated) apply(null, EventArgs.Empty);
            c.HandleCreated += apply;
        }

        public static void Style(IntPtr hwnd, bool dark)
        {
            if (Environment.OSVersion.Platform != PlatformID.Win32NT) return;
            try
            {
                int on = dark ? 1 : 0;
                if (DwmSetWindowAttribute(hwnd, 20, ref on, 4) != 0)   // DWMWA_USE_IMMERSIVE_DARK_MODE
                    DwmSetWindowAttribute(hwnd, 19, ref on, 4);          // старый номер атрибута (Win10 1809)
                int round = 2;                                            // DWMWCP_ROUND
                DwmSetWindowAttribute(hwnd, 33, ref round, 4);           // DWMWA_WINDOW_CORNER_PREFERENCE
            }
            catch { }
        }
    }

    // ====================================================================== //
    //  Карточка со скруглёнными углами
    // ====================================================================== //
    // Строка списка, которую можно отфильтровать поиском по странице
    internal interface IFilterable { string FilterText { get; } }

    internal class Card : Panel
    {
        public Card()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.CardBg;
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            using (SolidBrush b = new SolidBrush(Parent != null ? Parent.BackColor : Theme.WindowBg))
                g.FillRectangle(b, ClientRectangle);
            if (Width < 6 || Height < 6) return;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5F, 0.5F, Width - 1, Height - 1);
            using (GraphicsPath p = Theme.RoundRect(r, 12))
            {
                using (SolidBrush b = new SolidBrush(Theme.CardBg)) g.FillPath(b, p);
                using (Pen pen = new Pen(Theme.CardBorder)) g.DrawPath(pen, p);
            }
            // тонкий блик по верхней кромке — как в Fluent
            using (Pen pen = new Pen(Color.FromArgb(Theme.Dark ? 22 : 40, Color.White)))
                g.DrawLine(pen, 12, 1, Width - 12, 1);
        }
    }

    // ====================================================================== //
    //  Переключатель в стиле Windows 11 с плавной анимацией
    // ====================================================================== //
    internal class ToggleSwitch : Control
    {
        private bool _checked;
        private float _pos;            // 0 = выкл, 1 = вкл
        private bool _hover;
        private readonly Timer _anim = new Timer();

        public event EventHandler CheckedChanged;

        public ToggleSwitch()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor | ControlStyles.Selectable, true);
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
            TabStop = true;
            _anim.Interval = 15;
            _anim.Tick += delegate
            {
                float target = _checked ? 1F : 0F;
                _pos += (target - _pos) * 0.35F;
                if (Math.Abs(target - _pos) < 0.02F) { _pos = target; _anim.Stop(); }
                Invalidate();
            };
            FitToFont();
        }

        public bool Checked
        {
            get { return _checked; }
            set
            {
                if (_checked == value) return;
                _checked = value;
                if (IsHandleCreated && Visible) _anim.Start(); else _pos = value ? 1F : 0F;
                Invalidate();
                if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty);
            }
        }

        private void FitToFont()
        {
            int u = Font.Height;
            Size = new Size((int)(u * 2.7F), (int)(u * 1.35F));
        }

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); FitToFont(); }
        protected override void OnClick(EventArgs e) { base.OnClick(e); Checked = !Checked; }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; Invalidate(); }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (e.KeyCode == Keys.Space) { Checked = !Checked; e.Handled = true; }
        }
        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            float h = Height - 2;
            RectangleF track = new RectangleF(1, 1, Width - 2, h);
            float t = _pos;

            Color trackFill = Theme.Mix(Theme.CardBg, Enabled ? Theme.Accent : Theme.TextFaint, t);
            if (_hover && t > 0.5F && Enabled) trackFill = Theme.AccentHover;
            Color trackBorder = Theme.Mix(Theme.TrackOff, Enabled ? Theme.Accent : Theme.TextFaint, t);

            using (GraphicsPath p = Theme.RoundRect(track, h / 2))
            {
                using (SolidBrush b = new SolidBrush(trackFill)) g.FillPath(b, p);
                using (Pen pen = new Pen(trackBorder, 1.2F)) g.DrawPath(pen, p);
            }

            float knobD = h * (0.62F + (_hover ? 0.06F : 0F));
            float x0 = 1 + (h - knobD) / 2;
            float x1 = Width - 1 - (h - knobD) / 2 - knobD;
            float kx = x0 + (x1 - x0) * t;
            float ky = 1 + (h - knobD) / 2;
            Color knob = Theme.Mix(Theme.Knob, Theme.AccentText, t);
            if (!Enabled) knob = Theme.TextFaint;
            using (SolidBrush b = new SolidBrush(knob)) g.FillEllipse(b, kx, ky, knobD, knobD);

            if (Focused)
            {
                using (Pen pen = new Pen(Theme.TextDim, 1F))
                {
                    pen.DashStyle = DashStyle.Dot;
                    using (GraphicsPath p = Theme.RoundRect(new RectangleF(-1, -1, Width + 1, Height + 1), Height / 2))
                        g.DrawPath(pen, p);
                }
            }
        }
    }

    // ====================================================================== //
    //  Кнопка со скруглением: основная (акцентная) и обычная
    // ====================================================================== //
    internal class ModernButton : Control
    {
        private bool _hover, _down;
        public bool Primary;
        public bool Ghost;         // без рамки, текст акцентным цветом

        public ModernButton(string text, bool primary)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor | ControlStyles.Selectable, true);
            BackColor = Color.Transparent;
            Text = text;
            Primary = primary;
            Cursor = Cursors.Hand;
            TabStop = true;
        }

        public void Fit()
        {
            int u = Font.Height;
            Size sz = TextRenderer.MeasureText(Text, Font);
            int padX = Ghost ? (int)(u * 0.55F) : (int)(u * 1.05F);
            Size = new Size(sz.Width + padX * 2, (int)(u * 2.0F));
        }

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Fit(); }
        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Fit(); }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; _down = false; Invalidate(); }
        protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); _down = true; Focus(); Invalidate(); }
        protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); _down = false; Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) { OnClick(EventArgs.Empty); e.Handled = true; }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

            RectangleF r = new RectangleF(0.5F, 0.5F, Width - 1, Height - 1);
            if (Primary)
            {
                // акцентный градиент — как у топовых панелей
                Color c1 = Theme.Accent, c2 = Theme.Accent2;
                if (_hover) { c1 = Theme.Mix(c1, Color.White, 0.15F); c2 = Theme.Mix(c2, Color.White, 0.15F); }
                if (_down)  { c1 = Theme.Mix(c1, Color.Black, 0.12F); c2 = Theme.Mix(c2, Color.Black, 0.12F); }
                Color fg = Theme.AccentText;
                if (!Enabled)
                {
                    c1 = Theme.Mix(Theme.CardBg, Theme.Accent, 0.30F);
                    c2 = Theme.Mix(Theme.CardBg, Theme.Accent2, 0.30F);
                    fg = Theme.Mix(Theme.AccentText, Theme.CardBg, 0.45F);
                }
                using (GraphicsPath p = Theme.RoundRect(r, 8))
                using (LinearGradientBrush lb = new LinearGradientBrush(
                    new RectangleF(0, 0, Math.Max(1, Width), Math.Max(1, Height)), c1, c2, LinearGradientMode.Horizontal))
                    g.FillPath(lb, p);
                TextRenderer.DrawText(g, Text, Font, ClientRectangle, fg,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
                return;
            }

            Color bg, tfg, border;
            if (Ghost)
            {
                bg = _hover ? Theme.RowHover : Color.Transparent;
                tfg = Enabled ? Theme.Accent : Theme.TextFaint;
                border = Color.Transparent;
            }
            else
            {
                bg = _hover ? Theme.ButtonHover : Theme.ButtonBg;
                if (_down) bg = Theme.Mix(Theme.ButtonBg, Theme.Text, 0.08F);
                tfg = Enabled ? Theme.Text : Theme.TextFaint;
                border = Theme.ButtonBorder;
            }

            using (GraphicsPath p = Theme.RoundRect(r, 8))
            {
                if (bg.A > 0) using (SolidBrush b = new SolidBrush(bg)) g.FillPath(b, p);
                if (border.A > 0) using (Pen pen = new Pen(border)) g.DrawPath(pen, p);
            }
            TextRenderer.DrawText(g, Text, Font, ClientRectangle, tfg,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
        }
    }

    // ====================================================================== //
    //  Заголовок раздела в списке
    // ====================================================================== //
    internal class SectionHeader : Control
    {
        public SectionHeader(string text)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Text = text.ToUpperInvariant();
            BackColor = Theme.CardBg;
            TabStop = false;
        }

        protected override void OnFontChanged(EventArgs e)
        {
            base.OnFontChanged(e);
            Height = (int)(Font.Height * 2.0F);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = Font.Height;
            // акцентная чёрточка перед заголовком секции
            float barW = u * 0.26F, barH = u * 0.85F;
            using (GraphicsPath p = Theme.RoundRect(new RectangleF(1, Height - barH - u * 0.12F, barW, barH), barW / 2F))
            using (LinearGradientBrush lb = new LinearGradientBrush(
                new RectangleF(0, Height - barH - u * 0.2F, Math.Max(1F, barW), barH + 1), Theme.Accent, Theme.Accent2, LinearGradientMode.Vertical))
                g.FillPath(lb, p);
            using (Font f = new Font(Font.FontFamily, Font.Size * 0.82F, FontStyle.Bold))
            {
                Rectangle r = new Rectangle((int)(barW + u * 0.45F), 0, Width - (int)(barW + u * 0.45F), Height);
                TextRenderer.DrawText(g, Text, f, r, Theme.TextDim,
                    TextFormatFlags.Left | TextFormatFlags.Bottom | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
            }
        }
    }

    // ====================================================================== //
    //  Строка-опция: иконка, название, описание, переключатель справа
    // ====================================================================== //
    internal class OptionRow : Control
    {
        public readonly ToggleSwitch Toggle = new ToggleSwitch();
        public string Glyph;
        public string Title;
        public string Description;
        public bool Hard;
        private bool _hover;
        private Font _bold;

        public OptionRow(string title, string description, string glyph, bool on, bool hard)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Title = title; Description = description; Glyph = glyph; Hard = hard;
            BackColor = Theme.CardBg;
            Cursor = Cursors.Hand;
            Toggle.Checked = on;
            Toggle.CheckedChanged += delegate { Invalidate(); };
            Toggle.MouseEnter += delegate { _hover = true; Invalidate(); };
            Toggle.MouseLeave += delegate { _hover = false; Invalidate(); };
            Controls.Add(Toggle);
        }

        public bool Checked
        {
            get { return Toggle.Checked; }
            set { Toggle.Checked = value; }
        }

        // Чип «N настроек» справа: по нему модуль раскрывается в список пунктов
        public int SubCount;
        public bool Expanded;
        public event EventHandler ExpandRequested;
        private Rectangle _chipRect;

        private int U { get { return Font.Height; } }

        protected override void OnFontChanged(EventArgs e)
        {
            base.OnFontChanged(e);
            _bold = new Font(Font, FontStyle.Bold);
            Toggle.Font = Font;
            Relayout();
        }

        protected override void OnResize(EventArgs e) { base.OnResize(e); Relayout(); }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (SubCount > 0 && _chipRect.Contains(e.Location))
            {
                _suppressClick = true;
                if (ExpandRequested != null) ExpandRequested(this, EventArgs.Empty);
            }
        }
        private bool _suppressClick;

        protected override void OnClick(EventArgs e)
        {
            base.OnClick(e);
            if (_suppressClick) { _suppressClick = false; return; }
            Toggle.Checked = !Toggle.Checked;
        }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Toggle.Enabled = Enabled; Invalidate(); }

        private int _textLeft, _textWidth, _titleH, _descH;
        private bool _inLayout;

        private void Relayout()
        {
            if (_inLayout || Width < 40) return;
            _inLayout = true;
            try
            {
                if (_bold == null) _bold = new Font(Font, FontStyle.Bold);
                int u = U;
                int badge = (int)(u * 2.2F);
                _textLeft = (int)(u * 0.8F) + badge + (int)(u * 0.75F);
                int right = Width - Toggle.Width - (int)(u * 1.0F);
                _textWidth = Math.Max(60, right - _textLeft - (int)(u * 0.6F));

                _titleH = TextRenderer.MeasureText(Title, _bold, new Size(_textWidth, 0),
                    TextFormatFlags.WordBreak | TextFormatFlags.NoPadding).Height;
                _descH = TextRenderer.MeasureText(Description, Font, new Size(_textWidth, 0),
                    TextFormatFlags.WordBreak | TextFormatFlags.NoPadding).Height;

                int padY = (int)(u * 0.6F);
                int h = padY + _titleH + (int)(u * 0.2F) + _descH + padY;
                h = Math.Max(h, badge + padY * 2);
                if (Height != h) Height = h;

                Toggle.Location = new Point(Width - Toggle.Width - (int)(u * 0.8F), padY + (_titleH - Toggle.Height) / 2 + (int)(u * 0.1F));
            }
            finally { _inLayout = false; }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = U;

            if (_hover && Enabled)
            {
                using (GraphicsPath p = Theme.RoundRect(new RectangleF(0.5F, 0.5F, Width - 1, Height - 1), 6))
                using (SolidBrush b = new SolidBrush(Theme.RowHover)) g.FillPath(b, p);
            }

            // бейдж с иконкой
            int badge = (int)(u * 2.2F);
            int bx = (int)(u * 0.8F);
            int by = (Height - badge) / 2;
            bool on = Toggle.Checked;
            Color badgeBg = on ? Theme.BadgeBg : Theme.Mix(Theme.CardBg, Theme.TextFaint, 0.18F);
            Color glyphColor = !Enabled ? Theme.TextFaint : (Hard ? Theme.Warn : (on ? Theme.Accent : Theme.TextDim));
            using (GraphicsPath p = Theme.RoundRect(new RectangleF(bx, by, badge, badge), badge * 0.3F))
            using (SolidBrush b = new SolidBrush(badgeBg)) g.FillPath(b, p);

            Font iconFont = Theme.IconFont(Font.Size * 1.25F);
            Rectangle badgeRect = new Rectangle(bx, by, badge, badge);
            if (iconFont != null && !string.IsNullOrEmpty(Glyph))
            {
                TextRenderer.DrawText(g, Glyph, iconFont, badgeRect, glyphColor,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            }
            else
            {
                // запасной вариант без шрифта иконок — маркер
                float d = badge * 0.38F;
                using (SolidBrush b = new SolidBrush(glyphColor))
                    g.FillEllipse(b, bx + (badge - d) / 2, by + (badge - d) / 2, d, d);
            }

            int padY = (int)(u * 0.6F);
            Color titleColor = !Enabled ? Theme.TextFaint : (Hard ? Theme.Warn : Theme.Text);
            TextRenderer.DrawText(g, Title, _bold ?? Font, new Rectangle(_textLeft, padY, _textWidth, _titleH), titleColor,
                TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, Description, Font,
                new Rectangle(_textLeft, padY + _titleH + (int)(u * 0.2F), _textWidth, _descH),
                Enabled ? Theme.TextDim : Theme.TextFaint, TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);

            // чип с числом настроек внутри модуля
            if (SubCount > 0)
            {
                string chip = (Expanded ? "\u25B4 " : "\u25BE ") + SubCount + L.T(" настроек");
                using (Font cf = new Font(Font.FontFamily, Font.Size * 0.85F))
                {
                    Size cs = TextRenderer.MeasureText(g, chip, cf, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
                    int cw = cs.Width + (int)(u * 0.9F), ch = (int)(u * 1.4F);
                    int cx = Width - Toggle.Width - (int)(u * 1.6F) - cw;
                    _chipRect = new Rectangle(cx, padY + (_titleH - ch) / 2, cw, ch);
                    using (GraphicsPath p = Theme.RoundRect(new RectangleF(_chipRect.X + 0.5F, _chipRect.Y + 0.5F, cw - 1, ch - 1), ch / 2F))
                    {
                        using (SolidBrush b = new SolidBrush(Expanded ? Theme.Mix(Theme.CardBg, Theme.Accent, 0.22F) : Theme.ButtonBg)) g.FillPath(b, p);
                        using (Pen pen = new Pen(Expanded ? Theme.Accent : Theme.ButtonBorder)) g.DrawPath(pen, p);
                    }
                    TextRenderer.DrawText(g, chip, cf, _chipRect, Expanded ? Theme.Accent : Theme.TextDim,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                }
            }
            else _chipRect = Rectangle.Empty;
        }
    }

    // ====================================================================== //
    //  Список строк с прокруткой; сам укладывает детей по вертикали
    // ====================================================================== //
    internal class StackPanel : Panel
    {
        private bool _busy;

        // Строки, скрытые фильтром поиска: не участвуют в укладке и не рисуются
        public readonly HashSet<Control> Hidden = new HashSet<Control>();

        public StackPanel()
        {
            SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
            AutoScroll = true;
            BackColor = Theme.CardBg;
        }

        protected override void OnResize(EventArgs e) { base.OnResize(e); Restack(); }
        protected override void OnControlAdded(ControlEventArgs e) { base.OnControlAdded(e); Restack(); }

        public void Restack()
        {
            if (_busy) return;
            _busy = true;
            try
            {
                SuspendLayout();
                int u = Font.Height;
                int gap = (int)(u * 0.25F);
                for (int pass = 0; pass < 2; pass++)
                {
                    int w = Width - Padding.Horizontal - SystemInformation.VerticalScrollBarWidth - 2;
                    int y = Padding.Top - VerticalScroll.Value;
                    foreach (Control c in Controls)
                    {
                        if (Hidden.Contains(c)) { c.Visible = false; continue; }
                        if (!c.Visible) c.Visible = true;
                        c.Left = Padding.Left;
                        c.Width = w;
                        c.Top = y;
                        y += c.Height + gap;
                    }
                }
                ResumeLayout(true);
            }
            finally { _busy = false; }
        }
    }

    // ====================================================================== //
    //  Кольцо индекса приватности с анимацией
    // ====================================================================== //
    internal class IndexRing : Control
    {
        private float _value;      // 0..1 отрисованное
        private float _target;
        private int _ok, _total;
        private readonly Timer _anim = new Timer();

        public IndexRing()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            _anim.Interval = 15;
            _anim.Tick += delegate
            {
                _value += (_target - _value) * 0.12F;
                if (Math.Abs(_target - _value) < 0.003F) { _value = _target; _anim.Stop(); }
                Invalidate();
            };
        }

        public void SetScore(int ok, int total)
        {
            _ok = ok; _total = total;
            _target = total > 0 ? (float)ok / total : 0F;
            if (IsHandleCreated && Visible) _anim.Start(); else { _value = _target; Invalidate(); }
        }

        private Color Grade(float t)
        {
            if (t >= 0.85F) return Theme.Ok;
            if (t >= 0.5F) return Theme.Warn;
            return Theme.Err;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

            int side = (int)(Math.Min(Width, Height) * 0.84F);
            if (side < 20) return;
            float thick = side * 0.11F;
            RectangleF r = new RectangleF((Width - side) / 2F, (Height - side) / 2F, side, side);

            using (Pen bg = new Pen(Theme.Mix(Theme.CardBg, Theme.TextFaint, 0.25F), thick))
            {
                bg.StartCap = LineCap.Round; bg.EndCap = LineCap.Round;
                g.DrawArc(bg, r, 0, 360);
            }
            Color c = Grade(_value);
            if (_value > 0.001F)
            {
                using (Pen p = new Pen(c, thick))
                {
                    p.StartCap = LineCap.Round; p.EndCap = LineCap.Round;
                    g.DrawArc(p, r, -90, 360 * _value);
                }
            }

            // две строки внутри кольца: размер подбирается под отверстие,
            // а весь блок целиком центруется по высоте
            float hole = side - thick * 2F - Font.Height * 0.5F;

            string pct = _total > 0 ? ((int)Math.Round(_value * 100)).ToString() + "%" : "—";
            float fs = side * 0.145F;
            Font bf = new Font(Font.FontFamily, fs, FontStyle.Bold);
            SizeF psz = g.MeasureString(pct, bf);
            while (psz.Width > hole && fs > Font.Size * 0.85F)
            {
                fs *= 0.92F;
                bf.Dispose();
                bf = new Font(Font.FontFamily, fs, FontStyle.Bold);
                psz = g.MeasureString(pct, bf);
            }

            string sub = _total > 0 ? (_ok + L.T(" из ") + _total) : L.T("нет данных");
            float ss = side * 0.065F;
            Font sf2 = new Font(Font.FontFamily, ss, FontStyle.Regular);
            SizeF ssz = g.MeasureString(sub, sf2);
            while (ssz.Width > hole && ss > Font.Size * 0.7F)
            {
                ss *= 0.92F;
                sf2.Dispose();
                sf2 = new Font(Font.FontFamily, ss, FontStyle.Regular);
                ssz = g.MeasureString(sub, sf2);
            }

            float gap = -psz.Height * 0.12F;
            float blockH = psz.Height + gap + ssz.Height;
            float y = (Height - blockH) / 2F;
            using (SolidBrush b = new SolidBrush(Theme.Text))
                g.DrawString(pct, bf, b, (Width - psz.Width) / 2F, y);
            using (SolidBrush b = new SolidBrush(Theme.TextDim))
                g.DrawString(sub, sf2, b, (Width - ssz.Width) / 2F, y + psz.Height + gap);
            bf.Dispose();
            sf2.Dispose();
        }
    }

    // ====================================================================== //
    //  Пункт боковой навигации
    // ====================================================================== //
    internal class NavItem : Control
    {
        public string Glyph;
        public bool Selected;
        private bool _hover;
        public string Badge = "";

        public NavItem(string text, string glyph)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            Text = text; Glyph = glyph;
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
        }

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Height = (int)(Font.Height * 2.5F); }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; Invalidate(); }

        // Узкий пункт (свёрнутая боковая панель) — только иконка и точка-бейдж
        public bool Compact { get { return Width < Font.Height * 6; } }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = Font.Height;

            RectangleF r = new RectangleF(4, 2, Width - 8, Height - 4);
            if (_hover && !Selected)
            {
                using (GraphicsPath p = Theme.RoundRect(r, 7))
                using (SolidBrush b = new SolidBrush(Color.FromArgb(Theme.Dark ? 26 : 22, Theme.Text)))
                    g.FillPath(b, p);
            }

            Color fg = Selected ? Theme.AccentText : Theme.TextDim;
            Font icon = Theme.IconFont(Font.Size * 1.15F);

            if (Compact)
            {
                if (icon != null && !string.IsNullOrEmpty(Glyph))
                    TextRenderer.DrawText(g, Glyph, icon, new Rectangle(0, 0, Width, Height), fg,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                else
                    TextRenderer.DrawText(g, Text.Length > 0 ? Text.Substring(0, 1) : "", new Font(Font, FontStyle.Bold),
                        new Rectangle(0, 0, Width, Height), fg,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                if (!string.IsNullOrEmpty(Badge))
                {
                    float d = u * 0.5F;
                    using (SolidBrush b = new SolidBrush(Selected ? Theme.AccentText : Theme.Accent))
                        g.FillEllipse(b, Width / 2F + u * 0.55F, Height / 2F - u * 0.95F, d, d);
                }
                return;
            }

            int gx = (int)(u * 1.0F);
            if (icon != null && !string.IsNullOrEmpty(Glyph))
                TextRenderer.DrawText(g, Glyph, icon, new Rectangle(gx, 0, (int)(u * 1.6F), Height), fg,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

            int tx = gx + (int)(u * 2.0F);
            TextRenderer.DrawText(g, Text, Selected ? new Font(Font, FontStyle.Bold) : Font,
                new Rectangle(tx, 0, Width - tx - (int)(u * 1.6F), Height), fg,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);

            if (!string.IsNullOrEmpty(Badge))
            {
                using (Font bf = new Font(Font.FontFamily, Font.Size * 0.8F, FontStyle.Bold))
                {
                    Size bs = TextRenderer.MeasureText(Badge, bf);
                    int bw = bs.Width + (int)(u * 0.8F);
                    int bh = (int)(u * 1.25F);
                    RectangleF br = new RectangleF(Width - bw - (int)(u * 0.6F), (Height - bh) / 2F, bw, bh);
                    Color bBg = Selected ? Color.FromArgb(70, Theme.AccentText) : Theme.Accent;
                    Color bFg = Theme.AccentText;
                    using (GraphicsPath p = Theme.RoundRect(br, bh / 2F))
                    using (SolidBrush b = new SolidBrush(bBg)) g.FillPath(b, p);
                    TextRenderer.DrawText(g, Badge, bf, Rectangle.Round(br), bFg,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                }
            }
        }
    }

    // ====================================================================== //
    //  Плитка со значением (для страниц Проверка / Монитор)
    // ====================================================================== //
    internal class StatTile : Control
    {
        public string Caption = "";
        public string Value = "";
        public string Sub = "";
        public Color Accent;

        public StatTile()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.CardBg;
            Accent = Theme.Accent;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            using (SolidBrush b = new SolidBrush(Parent != null ? Parent.BackColor : Theme.WindowBg))
                g.FillRectangle(b, ClientRectangle);
            if (Width < 12 || Height < 12) return;
            RectangleF r = new RectangleF(0.5F, 0.5F, Width - 1, Height - 1);
            using (GraphicsPath p = Theme.RoundRect(r, 8))
            using (SolidBrush b = new SolidBrush(Theme.CardBg)) g.FillPath(b, p);
            using (GraphicsPath p = Theme.RoundRect(new RectangleF(0.5F, 0.5F, 3.5F, Height - 1), 2))
            using (SolidBrush b = new SolidBrush(Accent)) g.FillPath(b, p);

            int u = Font.Height;
            TextRenderer.DrawText(g, Caption.ToUpperInvariant(), new Font(Font.FontFamily, Font.Size * 0.8F, FontStyle.Bold),
                new Rectangle((int)(u * 0.9F), (int)(u * 0.5F), Width - (int)(u * 1.5F), u * 2), Theme.TextFaint,
                TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            using (Font vf = new Font(Font.FontFamily, Font.Size * 1.45F, FontStyle.Bold))
                TextRenderer.DrawText(g, Value, vf,
                    new Rectangle((int)(u * 0.85F), (int)(u * 1.55F), Width - (int)(u * 1.4F), (int)(u * 2.2F)),
                    Accent, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            if (!string.IsNullOrEmpty(Sub))
                TextRenderer.DrawText(g, Sub, Font,
                    new Rectangle((int)(u * 0.9F), Height - (int)(u * 1.7F), Width - (int)(u * 1.5F), (int)(u * 1.6F)),
                    Theme.TextDim, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
        }
    }

    // ====================================================================== //
    //  Строка «ключ — значение» (Монитор, Страж)
    // ====================================================================== //
    internal class KvRow : Control
    {
        private readonly string _key, _val;
        private readonly bool _flag;   // подсветить как телеметрию
        public KvRow(string key, string val, bool flag)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            _key = key; _val = val; _flag = flag; BackColor = Theme.CardBg;
        }
        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Height = (int)(Font.Height * 1.9F); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = Font.Height;
            if (_flag)
            {
                using (GraphicsPath p = Theme.RoundRect(new RectangleF(0.5F, 1.5F, Width - 1, Height - 3), 5))
                using (SolidBrush b = new SolidBrush(Theme.Mix(Theme.CardBg, Theme.Err, 0.14F))) g.FillPath(b, p);
                using (SolidBrush b = new SolidBrush(Theme.Err)) g.FillEllipse(b, u * 0.5F, (Height - u * 0.5F) / 2F, u * 0.5F, u * 0.5F);
            }
            int lx = _flag ? (int)(u * 1.5F) : (int)(u * 0.4F);
            Size vs = TextRenderer.MeasureText(_val, new Font(Font, FontStyle.Bold));
            TextRenderer.DrawText(g, _key, Font, new Rectangle(lx, 0, Width - lx - vs.Width - (int)(u * 0.8F), Height),
                _flag ? Theme.Err : Theme.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            TextRenderer.DrawText(g, _val, new Font(Font, FontStyle.Bold), new Rectangle(0, 0, Width - (int)(u * 0.4F), Height),
                _flag ? Theme.Err : Theme.TextDim, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
        }
    }

    // ====================================================================== //
    //  Строка домена в кэше DNS (Проверка)
    // ====================================================================== //
    internal class DnsRow : Control
    {
        private readonly string _name; private readonly bool _blocked;
        public DnsRow(string name, bool blocked)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            _name = name; _blocked = blocked; BackColor = Theme.CardBg;
        }
        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Height = (int)(Font.Height * 1.9F); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = Font.Height;
            Color dot = _blocked ? Theme.Ok : Theme.Err;
            using (SolidBrush b = new SolidBrush(dot)) g.FillEllipse(b, u * 0.4F, (Height - u * 0.55F) / 2F, u * 0.55F, u * 0.55F);
            int lx = (int)(u * 1.5F);
            string tag = _blocked ? L.T("заблокировано") : L.T("проходит");
            Size ts = TextRenderer.MeasureText(tag, Font);
            TextRenderer.DrawText(g, _name, Font, new Rectangle(lx, 0, Width - lx - ts.Width - (int)(u * 0.8F), Height),
                Theme.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            TextRenderer.DrawText(g, tag, Font, new Rectangle(0, 0, Width - (int)(u * 0.4F), Height),
                dot, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
        }
    }

    // ====================================================================== //
    //  Строка категории рентгена: что собрано, сколько, доля, сырой образец
    // ====================================================================== //
    internal class XrayCatRow : Control
    {
        private readonly string _name, _what;
        private readonly int _count;
        private readonly double _share;
        private readonly List<object> _topNames;
        private readonly string _sampleName, _samplePayload, _sampleTime;
        private bool _open, _hover;

        public XrayCatRow(string name, int count, double share, string what,
                          List<object> topNames, string sampleName, string sampleTime, string samplePayload)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            _name = name; _count = count; _share = share; _what = what;
            _topNames = topNames ?? new List<object>();
            _sampleName = sampleName ?? ""; _sampleTime = sampleTime ?? ""; _samplePayload = samplePayload ?? "";
            BackColor = Theme.CardBg; Cursor = Cursors.Hand;
        }

        private int U { get { return Font.Height; } }
        private int HeadH { get { return (int)(U * 3.6F); } }

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Recalc(); }
        protected override void OnResize(EventArgs e) { base.OnResize(e); Recalc(); }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; Invalidate(); }
        protected override void OnClick(EventArgs e)
        {
            base.OnClick(e); _open = !_open; Recalc();
            if (Parent is StackPanel) ((StackPanel)Parent).Restack();
        }

        public void Expand()
        {
            _open = true; Recalc();
            if (Parent is StackPanel) ((StackPanel)Parent).Restack();
            Invalidate();
        }

        private int _payloadH;
        private void Recalc()
        {
            if (Width < 60) return;
            if (!_open) { Height = HeadH; return; }
            int h = HeadH + (int)(U * 0.4F);
            h += _topNames.Count * (int)(U * 1.5F);
            if (_samplePayload.Length > 0)
            {
                h += (int)(U * 2.2F);   // подпись «сырое событие»
                using (Font mono = Theme.PickFont(Theme.MonoFonts, Font.Size * 0.85F, FontStyle.Regular))
                    _payloadH = TextRenderer.MeasureText(_samplePayload, mono,
                        new Size(Math.Max(80, Width - (int)(U * 3.2F)), 0), TextFormatFlags.WordBreak).Height;
                h += _payloadH + (int)(U * 1.0F);
            }
            Height = h + (int)(U * 0.5F);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = U;

            if (_hover)
            {
                using (GraphicsPath p = Theme.RoundRect(new RectangleF(0.5F, 0.5F, Width - 1, HeadH - 1), 6))
                using (SolidBrush b = new SolidBrush(Theme.RowHover)) g.FillPath(b, p);
            }

            Font icon = Theme.IconFont(Font.Size * 0.85F);
            if (icon != null)
                TextRenderer.DrawText(g, _open ? "" : "", icon,
                    new Rectangle((int)(u * 0.3F), 0, (int)(u * 1.4F), (int)(u * 2.2F)), Theme.TextDim,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

            int tx = (int)(u * 1.9F);
            string chip = _count.ToString() + "  ·  " + _share.ToString("0.#") + "%";
            Size cs = TextRenderer.MeasureText(chip, new Font(Font, FontStyle.Bold));
            int chipW = cs.Width + (int)(u * 1.0F), chipH = (int)(u * 1.35F);
            RectangleF cr = new RectangleF(Width - chipW - (int)(u * 0.5F), (int)(u * 0.45F), chipW, chipH);
            using (GraphicsPath p = Theme.RoundRect(cr, chipH / 2F))
            using (SolidBrush b = new SolidBrush(Theme.Mix(Theme.CardBg, Theme.Accent, 0.25F))) g.FillPath(b, p);
            TextRenderer.DrawText(g, chip, new Font(Font, FontStyle.Bold), Rectangle.Round(cr), Theme.Accent,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

            TextRenderer.DrawText(g, _name, new Font(Font, FontStyle.Bold),
                new Rectangle(tx, (int)(u * 0.3F), Width - tx - chipW - (int)(u * 1.2F), (int)(u * 1.5F)),
                Theme.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            TextRenderer.DrawText(g, _what, Font,
                new Rectangle(tx, (int)(u * 1.7F), Width - tx - (int)(u * 1.0F), (int)(u * 1.4F)),
                Theme.TextDim, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);

            // полоса доли
            float barW = Width - tx - (int)(u * 1.0F);
            float barY = (int)(u * 3.05F);
            using (GraphicsPath p = Theme.RoundRect(new RectangleF(tx, barY, barW, u * 0.28F), u * 0.14F))
            using (SolidBrush b = new SolidBrush(Theme.Mix(Theme.CardBg, Theme.TextFaint, 0.3F))) g.FillPath(b, p);
            float fill = (float)Math.Max(0.01, Math.Min(1.0, _share / 100.0)) * barW;
            using (GraphicsPath p = Theme.RoundRect(new RectangleF(tx, barY, fill, u * 0.28F), u * 0.14F))
            using (SolidBrush b = new SolidBrush(Theme.Accent)) g.FillPath(b, p);

            if (!_open) return;

            int y = HeadH + (int)(u * 0.3F);
            foreach (object o in _topNames)
            {
                Dictionary<string, object> n = Json.Obj(o);
                string nm = Json.GetStr(n, "name");
                string ct = Json.GetInt(n, "count").ToString() + "×";
                Size ns = TextRenderer.MeasureText(ct, Font);
                TextRenderer.DrawText(g, nm, Font, new Rectangle(tx, y, Width - tx - ns.Width - (int)(u * 1.2F), (int)(u * 1.5F)),
                    Theme.TextDim, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
                TextRenderer.DrawText(g, ct, Font, new Rectangle(0, y, Width - (int)(u * 0.6F), (int)(u * 1.5F)),
                    Theme.TextFaint, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
                y += (int)(u * 1.5F);
            }

            if (_samplePayload.Length > 0)
            {
                y += (int)(u * 0.4F);
                TextRenderer.DrawText(g, L.T("Настоящее событие, отправленное в Microsoft — ") + _sampleTime, Font,
                    new Rectangle(tx, y, Width - tx, (int)(u * 1.5F)), Theme.Warn,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
                y += (int)(u * 1.6F);
                RectangleF box = new RectangleF(tx, y, Width - tx - (int)(u * 0.6F), _payloadH + u * 0.8F);
                using (GraphicsPath p = Theme.RoundRect(box, 5))
                using (SolidBrush b = new SolidBrush(Theme.LogBg)) g.FillPath(b, p);
                using (Font mono = Theme.PickFont(Theme.MonoFonts, Font.Size * 0.85F, FontStyle.Regular))
                    TextRenderer.DrawText(g, _samplePayload, mono,
                        new Rectangle((int)box.X + (int)(u * 0.4F), (int)box.Y + (int)(u * 0.4F),
                                      (int)box.Width - (int)(u * 0.8F), _payloadH), Theme.TextDim, TextFormatFlags.WordBreak);
            }
        }
    }

    // ====================================================================== //
    //  Группа результата проверки: заголовок со счётом + раскрытие деталей
    // ====================================================================== //
    internal class AuditGroupRow : Control
    {
        private readonly string _title; private readonly int _ok, _total;
        private readonly List<object> _items; private bool _open, _hover;
        public AuditGroupRow(string title, int ok, int total, List<object> items)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            _title = title; _ok = ok; _total = total; _items = items; BackColor = Theme.CardBg;
            Cursor = Cursors.Hand;
        }
        private int HeadH { get { return (int)(Font.Height * 2.2F); } }
        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Recalc(); }
        protected override void OnResize(EventArgs e) { base.OnResize(e); }
        private void Recalc() { Height = _open ? HeadH + RowsH() : HeadH; }
        private int RowsH()
        {
            int fails = 0; foreach (object o in _items) if (!Json.GetBool(Json.Obj(o), "ok")) fails++;
            int shown = _total == _ok ? _items.Count : fails;   // если всё ок — показываем все; иначе только несоответствия
            if (shown == 0) shown = _items.Count;
            return shown * (int)(Font.Height * 1.7F) + (int)(Font.Height * 0.4F);
        }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; Invalidate(); }
        protected override void OnClick(EventArgs e)
        {
            base.OnClick(e); _open = !_open; Recalc();
            if (Parent is StackPanel) ((StackPanel)Parent).Restack();
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = Font.Height;
            if (_hover) { using (GraphicsPath p = Theme.RoundRect(new RectangleF(0.5F, 0.5F, Width - 1, HeadH - 1), 6)) using (SolidBrush b = new SolidBrush(Theme.RowHover)) g.FillPath(b, p); }

            bool all = _ok == _total;
            Color badge = all ? Theme.Ok : (_ok == 0 ? Theme.Err : Theme.Warn);
            Font icon = Theme.IconFont(Font.Size * 1.1F);
            string glyph = _open ? "" : "";
            if (icon != null) TextRenderer.DrawText(g, glyph, Theme.IconFont(Font.Size * 0.85F), new Rectangle((int)(u * 0.3F), 0, (int)(u * 1.4F), HeadH), Theme.TextDim, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

            int tx = (int)(u * 1.9F);
            string score = _ok + "/" + _total;
            Size ss = TextRenderer.MeasureText(score, new Font(Font, FontStyle.Bold));
            TextRenderer.DrawText(g, _title, new Font(Font, FontStyle.Bold), new Rectangle(tx, 0, Width - tx - ss.Width - (int)(u * 2.2F), HeadH),
                Theme.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);

            int chipW = ss.Width + (int)(u * 1.0F); int chipH = (int)(u * 1.35F);
            RectangleF chip = new RectangleF(Width - chipW - (int)(u * 0.5F), (HeadH - chipH) / 2F, chipW, chipH);
            using (GraphicsPath p = Theme.RoundRect(chip, chipH / 2F)) using (SolidBrush b = new SolidBrush(Theme.Mix(Theme.CardBg, badge, 0.22F))) g.FillPath(b, p);
            TextRenderer.DrawText(g, score, new Font(Font, FontStyle.Bold), Rectangle.Round(chip), badge, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

            if (_open)
            {
                int y = HeadH + (int)(u * 0.2F);
                foreach (object o in _items)
                {
                    Dictionary<string, object> it = Json.Obj(o);
                    bool ok = Json.GetBool(it, "ok");
                    if (!all && ok) continue;   // при несоответствиях показываем только их
                    Color dot = ok ? Theme.Ok : Theme.Err;
                    using (SolidBrush b = new SolidBrush(dot)) g.FillEllipse(b, u * 1.9F, y + (u * 1.7F - u * 0.45F) / 2F, u * 0.45F, u * 0.45F);
                    string nm = L.T(Json.GetStr(it, "name")); string act = L.T(Json.GetStr(it, "actual"));
                    Size acs = TextRenderer.MeasureText(act, Font);
                    TextRenderer.DrawText(g, nm, Font, new Rectangle((int)(u * 2.9F), y, Width - (int)(u * 2.9F) - acs.Width - (int)(u * 1.0F), (int)(u * 1.7F)),
                        Theme.TextDim, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
                    TextRenderer.DrawText(g, act, Font, new Rectangle(0, y, Width - (int)(u * 0.6F), (int)(u * 1.7F)),
                        Theme.TextFaint, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
                    y += (int)(u * 1.7F);
                }
            }
        }
    }
}
