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
            // Строгая палитра «консоли»: графит, один синий акцент. Зелёный,
            // жёлтый и красный — только там, где они значат состояние. Второй
            // акцент равен первому: градиенты, где они ещё остались, плоские.
            if (dark)
            {
                WindowBg   = Color.FromArgb(0x0E, 0x10, 0x13);
                CardBg     = Color.FromArgb(0x15, 0x18, 0x1D);
                CardBorder = Color.FromArgb(0x26, 0x2B, 0x33);
                RowHover   = Color.FromArgb(0x1C, 0x20, 0x27);
                LogBg      = Color.FromArgb(0x0B, 0x0D, 0x10);
                Text       = Color.FromArgb(0xE6, 0xE9, 0xEE);
                TextDim    = Color.FromArgb(0x9A, 0xA3, 0xAF);
                TextFaint  = Color.FromArgb(0x69, 0x71, 0x7D);
                Accent     = Color.FromArgb(0x2F, 0x74, 0xE8);
                Accent2    = Accent;
                AccentHover= Color.FromArgb(0x4A, 0x88, 0xEE);
                AccentText = Color.White;
                Warn       = Color.FromArgb(0xD9, 0xA2, 0x3B);
                Ok         = Color.FromArgb(0x3F, 0xB2, 0x7F);
                Err        = Color.FromArgb(0xE5, 0x53, 0x4B);
                ButtonBg   = Color.FromArgb(0x1A, 0x1E, 0x24);
                ButtonHover= Color.FromArgb(0x22, 0x27, 0x30);
                ButtonBorder=Color.FromArgb(0x2E, 0x34, 0x3D);
                BadgeBg    = Color.FromArgb(0x16, 0x24, 0x3D);
                TrackOff   = Color.FromArgb(0x6B, 0x73, 0x7F);
                Knob       = Color.FromArgb(0xE6, 0xE9, 0xEE);
                SideTop    = Color.FromArgb(0x0B, 0x0D, 0x10);
                SideBottom = SideTop;
            }
            else
            {
                WindowBg   = Color.FromArgb(0xF3, 0xF4, 0xF6);
                CardBg     = Color.White;
                CardBorder = Color.FromArgb(0xDC, 0xE0, 0xE5);
                RowHover   = Color.FromArgb(0xEE, 0xF0, 0xF3);
                LogBg      = Color.FromArgb(0xF8, 0xF9, 0xFA);
                Text       = Color.FromArgb(0x1C, 0x20, 0x26);
                TextDim    = Color.FromArgb(0x57, 0x60, 0x6A);
                TextFaint  = Color.FromArgb(0x86, 0x8E, 0x98);
                Accent     = Color.FromArgb(0x1F, 0x6F, 0xEB);
                Accent2    = Accent;
                AccentHover= Color.FromArgb(0x1A, 0x5F, 0xD0);
                AccentText = Color.White;
                Warn       = Color.FromArgb(0x9A, 0x67, 0x00);
                Ok         = Color.FromArgb(0x1A, 0x7F, 0x37);
                Err        = Color.FromArgb(0xCF, 0x22, 0x2E);
                ButtonBg   = Color.White;
                ButtonHover= Color.FromArgb(0xF2, 0xF4, 0xF7);
                ButtonBorder=Color.FromArgb(0xD0, 0xD5, 0xDC);
                BadgeBg    = Color.FromArgb(0xE3, 0xED, 0xFD);
                TrackOff   = Color.FromArgb(0x8C, 0x94, 0x9E);
                Knob       = Color.FromArgb(0x57, 0x60, 0x6A);
                SideTop    = Color.FromArgb(0xEB, 0xED, 0xF0);
                SideBottom = SideTop;
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

        // Производные шрифты — жирный, мельче, крупнее — нужны при каждой
        // перерисовке. Раньше они создавались прямо в OnPaint и не
        // освобождались: по дескриптору GDI на кадр, пока не вмешается сборщик
        // мусора. Теперь каждый создаётся один раз и живёт до конца программы.
        private static readonly Dictionary<string, Font> _fonts = new Dictionary<string, Font>();

        public static Font Sized(string family, float points, FontStyle style)
        {
            string key = family + "|" + (int)Math.Round(points * 100F) + "|" + (int)style;
            Font f;
            if (!_fonts.TryGetValue(key, out f))
            {
                f = new Font(family, points, style, GraphicsUnit.Point);
                _fonts[key] = f;
            }
            return f;
        }

        public static Font Bold(Font f) { return Sized(f.Name, f.SizeInPoints, FontStyle.Bold); }

        private static string _iconFamily;
        private static bool _iconChecked;
        public static Font IconFont(float size)
        {
            if (!_iconChecked)
            {
                _iconChecked = true;
                foreach (string n in IconFonts)
                {
                    try { using (FontFamily ff = new FontFamily(n)) { _iconFamily = n; break; } }
                    catch { }
                }
            }
            return _iconFamily == null ? null : Sized(_iconFamily, size, FontStyle.Regular);
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

        // Цвет означает состояние (норма / внимание / проблема)? Только такие
        // цвета и красят числа и значки; всё остальное — нейтральный текст.
        public static bool IsStatus(Color c)
        {
            int v = c.ToArgb();
            return v == Warn.ToArgb() || v == Err.ToArgb() || v == Ok.ToArgb();
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

    // Строка списка, которую можно отфильтровать поиском по странице
    internal interface IFilterable { string FilterText { get; } }

#if UITEST
    // Обрезанный текст глазами ловил пользователь: подпись плитки уезжала в
    // многоточие. Теперь элементы сами сообщают о таком, а сборка падает.
    internal static class ClipWatch
    {
        public static readonly List<string> Clipped = new List<string>();
        public static void Note(string where, string text, int need, int have)
        {
            Clipped.Add("ОБРЕЗАНО " + where + ": «" + text + "» нужно " + need + ", есть " + have);
        }
    }
#endif

    // ====================================================================== //
    //  Карточка со скруглёнными углами
    // ====================================================================== //
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
            using (GraphicsPath p = Theme.RoundRect(r, 8))
            {
                using (SolidBrush b = new SolidBrush(Theme.CardBg)) g.FillPath(b, p);
                using (Pen pen = new Pen(Theme.CardBorder)) g.DrawPath(pen, p);
            }
        }
    }

    // ====================================================================== //
    //  Рамка фокуса — только для того, кто ходит клавиатурой. После щелчка
    //  мышью она висела вокруг элемента, пока фокус не уйдёт.
    // ====================================================================== //
    internal static class FocusCue
    {
        [DllImport("user32.dll")]
        private static extern short GetKeyState(int key);

        // Фокус пришёл с клавиатуры: в этот момент нажат Tab или стрелка
        public static bool FromKeyboard()
        {
            foreach (int k in new int[] { 0x09, 0x25, 0x26, 0x27, 0x28 })
                if ((GetKeyState(k) & 0x8000) != 0) return true;
            return false;
        }
    }

    // ====================================================================== //
    //  Переключатель. Дорожка-«пилюля» с пропорциями Windows 11 (2:1),
    //  выключенный — спокойная серая заливка, включённый — акцент с лёгким
    //  бликом сверху. Ручка с мягкой тенью, на нажатии вытягивается, ход —
    //  150 мс с плавным торможением. Рамка фокуса — только с клавиатуры.
    // ====================================================================== //
    internal class ToggleSwitch : Control
    {
        private bool _checked;
        private float _pos;            // 0 = выкл, 1 = вкл (то, что нарисовано)
        private float _from;
        private int _t0;
        private bool _hover, _down, _keyFocus;
        private const int AnimMs = 150;
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
            _anim.Interval = 10;
            _anim.Tick += delegate
            {
                float target = _checked ? 1F : 0F;
                float k = (Environment.TickCount - _t0) / (float)AnimMs;
                if (k >= 1F) { _pos = target; _anim.Stop(); }
                else
                {
                    float e = 1F - (1F - k) * (1F - k) * (1F - k);
                    _pos = _from + (target - _from) * e;
                }
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
                if (IsHandleCreated && Visible) { _from = _pos; _t0 = Environment.TickCount; _anim.Start(); }
                else _pos = value ? 1F : 0F;
                Invalidate();
                if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty);
            }
        }

        private void FitToFont()
        {
            int u = Font.Height;
            Size = new Size((int)(u * 2.6F), (int)(u * 1.45F));
        }

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); FitToFont(); }
        protected override void OnClick(EventArgs e) { base.OnClick(e); Checked = !Checked; }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; _down = false; Invalidate(); }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Left) { _down = true; _keyFocus = false; Invalidate(); }
        }
        protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); _down = false; Invalidate(); }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (e.KeyCode == Keys.Space) { Checked = !Checked; e.Handled = true; }
        }
        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); _keyFocus = FocusCue.FromKeyboard(); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); _keyFocus = false; Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Draw(e.Graphics, Focused && _keyFocus);
        }

        private void Draw(Graphics g, bool focusRing)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            int u = Font.Height;
            bool dark = Theme.Dark;
            float t = _pos;

            // по краям — место под рамку фокуса
            int inset = Math.Max(2, (int)Math.Round(u * 0.12F));
            float h = Height - inset * 2;
            float w = Math.Min(Width - inset * 2, h * 2F);
            RectangleF track = new RectangleF(Width - inset - w, inset, w, h);

            Color offFill = dark ? (_hover ? Color.FromArgb(0x34, 0x3C, 0x48) : Color.FromArgb(0x29, 0x30, 0x3A))
                                 : (_hover ? Color.FromArgb(0xCF, 0xD5, 0xDD) : Color.FromArgb(0xDC, 0xE1, 0xE7));
            Color offEdge = dark ? Color.FromArgb(0x4A, 0x54, 0x63) : Color.FromArgb(0xC4, 0xCB, 0xD4);
            Color onFill = _hover ? Theme.AccentHover : Theme.Accent;
            Color knobOff = dark ? (_hover ? Color.FromArgb(0xD5, 0xDA, 0xE1) : Color.FromArgb(0xB4, 0xBC, 0xC7)) : Color.White;
            Color knobOn = Color.White;
            if (!Enabled)
            {
                offFill = dark ? Color.FromArgb(0x22, 0x27, 0x2E) : Color.FromArgb(0xE6, 0xE9, 0xED);
                offEdge = offFill;
                onFill = Theme.Mix(Theme.CardBg, Theme.Accent, 0.4F);
                knobOff = dark ? Color.FromArgb(0x55, 0x5C, 0x67) : Color.FromArgb(0xF4, 0xF5, 0xF7);
                knobOn = Theme.Mix(Color.White, onFill, 0.35F);
            }

            Color fill = Theme.Mix(offFill, onFill, t);
            Color edge = Theme.Mix(offEdge, onFill, t);
            using (GraphicsPath p = Theme.RoundRect(track, h / 2))
            {
                using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
                // лёгкий блик сверху на включённом
                if (t > 0.01F && Enabled)
                {
                    RectangleF hl = new RectangleF(track.X, track.Y - 1, track.Width, track.Height + 2);
                    using (LinearGradientBrush lb = new LinearGradientBrush(hl,
                        Color.FromArgb((int)(34 * t), Color.White), Color.FromArgb(0, Color.White), LinearGradientMode.Vertical))
                    {
                        Blend bl = new Blend();
                        bl.Positions = new float[] { 0F, 0.55F, 1F };
                        bl.Factors = new float[] { 0F, 1F, 1F };      // к середине блик сходит на нет
                        lb.Blend = bl;
                        g.FillPath(lb, p);
                    }
                }
                using (Pen pen = new Pen(edge, 1F)) g.DrawPath(pen, p);
            }

            // ручка: на нажатии вытягивается к середине
            float pad = Math.Max(2F, h * 0.15F);
            float kd = h - pad * 2;
            float kw = kd + (_down && Enabled ? h * 0.24F : 0F);
            float x0 = track.X + pad;
            float x1 = track.Right - pad - kw;
            float kx = x0 + (x1 - x0) * t;
            float ky = track.Y + pad;
            if (Enabled)
            {
                float sy = Math.Max(1F, u * 0.05F);
                using (GraphicsPath sp = Theme.RoundRect(new RectangleF(kx, ky + sy, kw, kd), kd / 2))
                using (SolidBrush sb = new SolidBrush(Color.FromArgb(dark ? 90 : 45, Color.Black)))
                    g.FillPath(sb, sp);
            }
            using (GraphicsPath kp = Theme.RoundRect(new RectangleF(kx, ky, kw, kd), kd / 2))
            {
                using (SolidBrush kb = new SolidBrush(Theme.Mix(knobOff, knobOn, t)))
                    g.FillPath(kb, kp);
                // белая ручка на светло-серой дорожке без контура теряется
                if (!dark && Enabled && t < 0.99F)
                    using (Pen kpen = new Pen(Color.FromArgb((int)(55 * (1F - t)), 0x1C, 0x20, 0x26), 1F))
                        g.DrawPath(kpen, kp);
            }

            if (focusRing)
            {
                float o = inset - 0.75F;
                RectangleF fr = new RectangleF(track.X - o, track.Y - o, track.Width + o * 2, track.Height + o * 2);
                using (GraphicsPath fp = Theme.RoundRect(fr, fr.Height / 2))
                using (Pen pen = new Pen(Theme.Accent, 1.5F))
                    g.DrawPath(pen, fp);
            }
        }

#if UITEST
        // WIN11_TEST_TOGGLES=путь.png: все состояния переключателя в обеих
        // темах — в натуральную величину и увеличенные втрое
        internal static void RenderSheet(string path, Font font)
        {
            bool wasDark = Theme.Dark;
            string[] names = { "off", "off+hover", "on", "on+hover", "pressed", "focus", "half", "disabled off", "disabled on" };
            float[] pos = { 0F, 0F, 1F, 1F, 1F, 1F, 0.5F, 0F, 1F };
            ToggleSwitch ts = new ToggleSwitch();
            ts.Font = font;
            int cw = ts.Width + 16, ch = ts.Height + 12, zoom = 3;
            using (Bitmap sheet = new Bitmap(cw * names.Length * zoom, (ch + ch * zoom) * 2))
            using (Graphics sg = Graphics.FromImage(sheet))
            {
                sg.InterpolationMode = InterpolationMode.NearestNeighbor;
                sg.PixelOffsetMode = PixelOffsetMode.Half;
                for (int row = 0; row < 2; row++)
                {
                    Theme.Apply(row == 0);
                    int y0 = row * (ch + ch * zoom);
                    using (SolidBrush bg = new SolidBrush(Theme.CardBg))
                        sg.FillRectangle(bg, 0, y0, sheet.Width, ch + ch * zoom);
                    for (int i = 0; i < names.Length; i++)
                    {
                        ts._pos = pos[i];
                        ts._hover = names[i].Contains("hover") || names[i] == "pressed";
                        ts._down = names[i] == "pressed";
                        ts.Enabled = !names[i].StartsWith("disabled");
                        using (Bitmap cell = new Bitmap(cw, ch))
                        using (Graphics g = Graphics.FromImage(cell))
                        {
                            g.Clear(Theme.CardBg);
                            g.TranslateTransform(8, 6);
                            ts.Draw(g, names[i] == "focus");
                            sg.DrawImage(cell, i * cw * zoom + (cw * zoom - cw) / 2, y0);
                            sg.DrawImage(cell, new Rectangle(i * cw * zoom, y0 + ch, cw * zoom, ch * zoom));
                        }
                    }
                }
                sheet.Save(path);
            }
            Theme.Apply(wasDark);
        }
#endif
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
            AccessibleRole = AccessibleRole.PushButton;
            AccessibleName = text;
        }

        public void Fit()
        {
            int u = Font.Height;
            Size sz = TextRenderer.MeasureText(Text, Font);
            int padX = Ghost ? (int)(u * 0.55F) : (int)(u * 1.05F);
            Size = new Size(sz.Width + padX * 2, (int)(u * 2.0F));
        }

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Fit(); }
        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); AccessibleName = Text; Fit(); }
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
                // ровная заливка акцентом, без градиента
                Color c1 = Theme.Accent;
                if (_hover) c1 = Theme.AccentHover;
                if (_down)  c1 = Theme.Mix(c1, Color.Black, 0.12F);
                Color fg = Theme.AccentText;
                if (!Enabled)
                {
                    c1 = Theme.Mix(Theme.CardBg, Theme.Accent, 0.30F);
                    fg = Theme.Mix(Theme.AccentText, Theme.CardBg, 0.45F);
                }
                using (GraphicsPath p = Theme.RoundRect(r, 6))
                using (SolidBrush lb = new SolidBrush(c1))
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

            using (GraphicsPath p = Theme.RoundRect(r, 6))
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
            Text = text;
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
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = Font.Height;
            // заголовок раздела списка — обычным регистром, приглушённым
            // цветом, без цветных полосок
            Font f = Theme.Sized(Font.Name, Font.SizeInPoints * 0.9F, FontStyle.Bold);
            Rectangle r = new Rectangle((int)(u * 0.55F), 0, Width - (int)(u * 0.55F), Height - (int)(u * 0.15F));
            TextRenderer.DrawText(g, Text, f, r, Theme.TextDim,
                TextFormatFlags.Left | TextFormatFlags.Bottom | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
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
            AccessibleRole = AccessibleRole.CheckButton;
            AccessibleName = title;
            AccessibleDescription = description;
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
            _bold = Theme.Bold(Font);
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

        // правый край чипа: чуть левее переключателя
        private int ChipRight { get { return Width - Toggle.Width - (int)(U * 1.6F); } }

        // ширина колонки чипа — по самому длинному варианту, одна на все строки
        private int ChipColumnWidth()
        {
            using (Font cf = new Font(Font.FontFamily, Font.Size * 0.85F))
                return TextRenderer.MeasureText("▾ 88" + SettingsWord(88), cf, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding).Width + (int)(U * 0.9F);
        }

        // «1 настройка», «4 настройки», «16 настроек»; по-английски — setting / settings
        internal static string SettingsWord(int n)
        {
            if (L.English) return n == 1 ? " setting" : " settings";
            int m10 = n % 10, m100 = n % 100;
            if (m10 == 1 && m100 != 11) return " настройка";
            if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return " настройки";
            return " настроек";
        }

        private void Relayout()
        {
            if (_inLayout || Width < 40) return;
            _inLayout = true;
            try
            {
                if (_bold == null) _bold = Theme.Bold(Font);
                int u = U;
                int badge = (int)(u * 2.2F);
                _textLeft = (int)(u * 0.8F) + badge + (int)(u * 0.75F);
                // Текст кончается до колонки чипа «N настроек» во всех строках —
                // и с чипом, и без. Раньше описание уходило под чип, а строки с
                // чипом и без переносились в разных местах: колонка «гуляла».
                int right = ChipRight - ChipColumnWidth() - (int)(u * 0.8F);
                _textWidth = Math.Max(60, right - _textLeft);

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
            // одноцветный значок без подложки: включённое и так видно по переключателю
            Color glyphColor = !Enabled ? Theme.TextFaint : (on ? Theme.TextDim : Theme.TextFaint);

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
            Color titleColor = !Enabled ? Theme.TextFaint : Theme.Text;
            TextRenderer.DrawText(g, Title, _bold ?? Font, new Rectangle(_textLeft, padY, _textWidth, _titleH), titleColor,
                TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, Description, Font,
                new Rectangle(_textLeft, padY + _titleH + (int)(u * 0.2F), _textWidth, _descH),
                Enabled ? Theme.TextDim : Theme.TextFaint, TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);

            // чип с числом настроек внутри модуля
            if (SubCount > 0)
            {
                string chip = (Expanded ? "\u25B4 " : "\u25BE ") + SubCount + SettingsWord(SubCount);
                using (Font cf = new Font(Font.FontFamily, Font.Size * 0.85F))
                {
                    Size cs = TextRenderer.MeasureText(g, chip, cf, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
                    int cw = cs.Width + (int)(u * 0.9F), ch = (int)(u * 1.4F);
                    int cx = ChipRight - cw;
                    _chipRect = new Rectangle(cx, padY + (_titleH - ch) / 2, cw, ch);
                    using (GraphicsPath p = Theme.RoundRect(new RectangleF(_chipRect.X + 0.5F, _chipRect.Y + 0.5F, cw - 1, ch - 1), 4))
                    {
                        using (SolidBrush b = new SolidBrush(Expanded ? Theme.BadgeBg : Theme.CardBg)) g.FillPath(b, p);
                        using (Pen pen = new Pen(Expanded ? Theme.Mix(Theme.CardBorder, Theme.Accent, 0.6F) : Theme.CardBorder)) g.DrawPath(pen, p);
                    }
                    TextRenderer.DrawText(g, chip, cf, _chipRect, Expanded ? Theme.Text : Theme.TextDim,
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

        // Строки подгоняем под новую ширину ДО того, как прокрутка пересчитает
        // свой диапазон. Иначе при резком сужении (панель разделов развернулась
        // за один шаг) диапазон считался по строкам старой ширины, появлялась
        // горизонтальная полоса и так и оставалась, хотя строки уже влезали.
        protected override void OnResize(EventArgs e) { Restack(); base.OnResize(e); }
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
                     ControlStyles.SupportsTransparentBackColor | ControlStyles.Selectable, true);
            Text = text; Glyph = glyph;
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
            TabStop = true;                       // по разделам можно пройти табуляцией
            AccessibleRole = AccessibleRole.PageTab;
            AccessibleName = text;
        }

        protected override void OnTextChanged(EventArgs e)
        { base.OnTextChanged(e); AccessibleName = Text; }

        // Рамка фокуса нужна тому, кто идёт по разделам клавиатурой. После
        // щелчка мышью она оставалась вокруг кнопки сворачивания и висела,
        // пока фокус не уйдёт. Теперь рамка — только если фокус пришёл с
        // клавиатуры (Tab или стрелка нажаты в этот момент).
        private bool _keyFocus;

        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); _keyFocus = FocusCue.FromKeyboard(); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); _keyFocus = false; Invalidate(); }

        protected override void OnMouseDown(MouseEventArgs e)
        { base.OnMouseDown(e); _keyFocus = false; if (CanFocus) Focus(); Invalidate(); }

        // Enter и пробел открывают раздел — как щелчок мышью
        protected override bool IsInputKey(Keys keyData)
        { return keyData == Keys.Enter || keyData == Keys.Space || base.IsInputKey(keyData); }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space)
            { OnClick(EventArgs.Empty); e.Handled = true; }
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
                using (GraphicsPath p = Theme.RoundRect(r, 6))
                using (SolidBrush b = new SolidBrush(Color.FromArgb(Theme.Dark ? 14 : 12, Theme.Text)))
                    g.FillPath(b, p);
            }
            // Идущему по разделам табуляцией нужно видеть, где он сейчас
            if (Focused && _keyFocus && !Selected)
            {
                using (GraphicsPath p = Theme.RoundRect(r, 6))
                using (Pen pen = new Pen(Theme.Accent, 1.4F))
                    g.DrawPath(pen, p);
            }

            Color fg = Selected ? Theme.Text : Theme.TextDim;
            if (_hover && !Selected) fg = Theme.Text;
            Font icon = Theme.IconFont(Font.Size * 1.1F);
            // Отметка у раздела — одна неброская точка «загляните сюда».
            // Подписи «вкл» и «!» в цветных пилюлях пестрили панель.
            float dot = u * 0.36F;

            // Значок стоит на одном месте при любой ширине пункта: в свёрнутой
            // панели это ровно её середина. Раньше в свёрнутом виде он
            // центрировался по текущей ширине, а в развёрнутом прижимался
            // влево — на середине анимации все значки перепрыгивали, и
            // пункты дёргались.
            int gx = (int)(u * 1.0F), gw = (int)(u * 1.4F);
            Rectangle gr = new Rectangle(gx, 0, gw, Height);
            if (icon != null && !string.IsNullOrEmpty(Glyph))
                TextRenderer.DrawText(g, Glyph, icon, gr, fg,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            else if (Compact)
                TextRenderer.DrawText(g, Text.Length > 0 ? Text.Substring(0, 1) : "", Theme.Bold(Font), gr, fg,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

            if (Compact)
            {
                if (!string.IsNullOrEmpty(Badge))
                    using (SolidBrush b = new SolidBrush(Theme.Warn))
                        g.FillEllipse(b, gx + gw / 2F + u * 0.55F, Height / 2F - u * 0.75F, dot, dot);
                return;
            }

            // Строка раскладывается по ширине развёрнутого пункта, а не по
            // текущей: при сворачивании её просто срезает край и она гаснет,
            // а не пересокращается многоточием на каждом кадре.
            int full = Math.Max(Width, FullWidth);
            int tx = gx + (int)(u * 1.9F);
            float fade = Math.Max(0F, Math.Min(1F, (Width - u * 6F) / (u * 3F)));
            Color tc = fade >= 1F ? fg : Theme.Mix(Theme.SideTop, fg, fade);
            TextRenderer.DrawText(g, Text, Font,
                new Rectangle(tx, 0, full - tx - (int)(u * 1.4F), Height), tc,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);

            if (!string.IsNullOrEmpty(Badge))
                using (SolidBrush b = new SolidBrush(Theme.Warn))
                    g.FillEllipse(b, full - u * 0.9F - dot, (Height - dot) / 2F, dot, dot);
        }

        // Ширина пункта в развёрнутой панели (0 — текущая)
        public int FullWidth;
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
            bool status = Theme.IsStatus(Accent);
            using (GraphicsPath p = Theme.RoundRect(r, 8))
            {
                using (SolidBrush b = new SolidBrush(Theme.CardBg)) g.FillPath(b, p);
                using (Pen pen = new Pen(Theme.CardBorder)) g.DrawPath(pen, p);
            }
            // цветная кромка — только у плитки о состоянии (внимание, проблема)
            if (status)
                using (SolidBrush b = new SolidBrush(Accent)) g.FillRectangle(b, 1, (int)(Height * 0.22F), 2, Height - 2 * (int)(Height * 0.22F));

            int u = Font.Height;
            int left = (int)(u * 0.9F);
            int textW = Math.Max(20, Width - (int)(u * 1.5F));

            // Заголовок плитки — в одну строку, а на узкой плитке в две. Раньше
            // он обрывался многоточием («ОБРАЩЕНИЯ К ТЕЛЕ…»), и понять, что
            // означает число под ним, было нельзя. Всё, что ниже, сдвигается.
            string cap = Caption;
            Font cf = Theme.Sized(Font.Name, Font.SizeInPoints * 0.9F, FontStyle.Regular);
            int line = TextRenderer.MeasureText(g, "X", cf).Height;
            Size capNeed = TextRenderer.MeasureText(g, cap, cf, new Size(textW, 0), TextFormatFlags.WordBreak);
            int capH = capNeed.Height > line ? line * 2 : line;
            int shift = capH - line;
            TextRenderer.DrawText(g, cap, cf, new Rectangle(left, (int)(u * 0.5F), textW, capH), Theme.TextDim,
                TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis);
#if UITEST
            if (capNeed.Height > capH || capNeed.Width > textW) ClipWatch.Note("StatTile.Caption", Caption, capNeed.Width, textW);
#endif
            TextRenderer.DrawText(g, Value, Theme.Sized(Font.Name, Font.SizeInPoints * 1.45F, FontStyle.Bold),
                new Rectangle((int)(u * 0.85F), (int)(u * 1.55F) + shift, Width - (int)(u * 1.4F), (int)(u * 2.2F)),
                status ? Accent : Theme.Text, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            if (!string.IsNullOrEmpty(Sub))
            {
                // Подпись переносится на вторую строку, а если и так не влезает —
                // печатается шрифтом поменьше. Раньше она была в одну строку с
                // обрезкой и на узкой плитке рвалась на полуслове:
                // «1 не заблокировано (из кэ…».
                int subT = (int)(u * 3.9F) + shift;
                if (shift > 0) subT -= (int)(u * 0.3F);      // под двухстрочным заголовком зазор над подписью поджат
                int subH = Height - subT - (int)(u * 0.25F);
                if (subH < u) { subT = Height - (int)(u * 1.7F); subH = (int)(u * 1.6F); }
                // меряем теми же флагами, какими рисуем: иначе длинное слово
                // считалось влезшим и всё равно обрывалось многоточием
                Font sf = Font;
                Size need = TextRenderer.MeasureText(g, Sub, sf, new Size(textW, 0), TextFormatFlags.WordBreak);
                foreach (float scale in new[] { 0.85F, 0.72F })
                {
                    if ((need.Height <= subH && need.Width <= textW) || Font.Size * scale < 6.5F) break;
                    sf = Theme.Sized(Font.Name, Font.SizeInPoints * scale, FontStyle.Regular);
                    need = TextRenderer.MeasureText(g, Sub, sf, new Size(textW, 0), TextFormatFlags.WordBreak);
                }
                TextRenderer.DrawText(g, Sub, sf, new Rectangle(left, subT, textW, subH), Theme.TextDim,
                    TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis);
#if UITEST
                if (need.Height > subH) ClipWatch.Note("StatTile.Sub", Sub, need.Height, subH);
                else if (need.Width > textW) ClipWatch.Note("StatTile.Sub", Sub, need.Width, textW);
#endif
            }
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
            // отмеченная строка — только точка и цвет значения, без красной заливки
            if (_flag)
                using (SolidBrush b = new SolidBrush(Theme.Err)) g.FillEllipse(b, u * 0.45F, (Height - u * 0.4F) / 2F, u * 0.4F, u * 0.4F);
            int lx = _flag ? (int)(u * 1.3F) : (int)(u * 0.4F);
            Size vs = TextRenderer.MeasureText(_val, Font);
            TextRenderer.DrawText(g, _key, Font, new Rectangle(lx, 0, Width - lx - vs.Width - (int)(u * 0.8F), Height),
                Theme.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            TextRenderer.DrawText(g, _val, Font, new Rectangle(0, 0, Width - (int)(u * 0.4F), Height),
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
            Size cs = TextRenderer.MeasureText(chip, Theme.Bold(Font));
            int chipW = cs.Width + (int)(u * 1.0F), chipH = (int)(u * 1.35F);
            RectangleF cr = new RectangleF(Width - chipW - (int)(u * 0.5F), (int)(u * 0.45F), chipW, chipH);
            using (GraphicsPath p = Theme.RoundRect(cr, chipH / 2F))
            using (SolidBrush b = new SolidBrush(Theme.Mix(Theme.CardBg, Theme.Accent, 0.25F))) g.FillPath(b, p);
            TextRenderer.DrawText(g, chip, Theme.Bold(Font), Rectangle.Round(cr), Theme.Accent,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

            TextRenderer.DrawText(g, _name, Theme.Bold(Font),
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
        private readonly List<Dictionary<string, object>> _rows = new List<Dictionary<string, object>>();
        private bool _open, _hover;

        // В раскрытой группе видны несоответствия, а если их нет — все пункты.
        // Список один и для высоты, и для отрисовки: раньше каждая решала это
        // по-своему, и под строками оставалось пустое место.
        public AuditGroupRow(string title, int ok, int total, List<object> items)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            _title = title; _ok = ok; _total = total; BackColor = Theme.CardBg;
            Cursor = Cursors.Hand;
            List<Dictionary<string, object>> all = new List<Dictionary<string, object>>();
            foreach (object o in items)
            {
                Dictionary<string, object> it = Json.Obj(o);
                if (it == null) continue;
                all.Add(it);
                if (!Json.GetBool(it, "ok")) _rows.Add(it);
            }
            if (_rows.Count == 0) _rows = all;
        }
        private int HeadH { get { return (int)(Font.Height * 2.2F); } }
        private int RowH { get { return (int)(Font.Height * 1.7F); } }
        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Recalc(); }
        private void Recalc() { Height = _open ? HeadH + _rows.Count * RowH + (int)(Font.Height * 0.4F) : HeadH; }
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
            Font icon = Theme.IconFont(Font.Size * 0.85F);
            string glyph = _open ? "" : "";
            if (icon != null) TextRenderer.DrawText(g, glyph, icon, new Rectangle((int)(u * 0.3F), 0, (int)(u * 1.4F), HeadH), Theme.TextDim, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

            int tx = (int)(u * 1.9F);
            // справа — точка состояния и «17 из 17» обычным текстом, без цветной пилюли
            string score = _ok + " " + L.T("из") + " " + _total;
            Size ss = TextRenderer.MeasureText(score, Font);
            TextRenderer.DrawText(g, _title, Font, new Rectangle(tx, 0, Width - tx - ss.Width - (int)(u * 2.4F), HeadH),
                Theme.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            int sx = Width - ss.Width - (int)(u * 0.6F);
            TextRenderer.DrawText(g, score, Font, new Rectangle(sx, 0, ss.Width, HeadH), Theme.TextDim,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
            float dd = u * 0.4F;
            using (SolidBrush b = new SolidBrush(badge)) g.FillEllipse(b, sx - u * 0.45F - dd, (HeadH - dd) / 2F, dd, dd);

            if (_open)
            {
                int y = HeadH + (int)(u * 0.2F);
                foreach (Dictionary<string, object> it in _rows)
                {
                    bool ok = Json.GetBool(it, "ok");
                    bool blocked = Json.GetBool(it, "blocked");
                    // «Windows не разрешает» — не наша вина и не красное: серым
                    Color dot = ok ? Theme.Ok : (blocked ? Theme.TextFaint : Theme.Err);
                    using (SolidBrush b = new SolidBrush(dot)) g.FillEllipse(b, u * 1.9F, y + (RowH - u * 0.45F) / 2F, u * 0.45F, u * 0.45F);
                    string nm = L.T(Json.GetStr(it, "name")); string act = L.T(Json.GetStr(it, "actual"));
                    Size acs = TextRenderer.MeasureText(act, Font);
                    TextRenderer.DrawText(g, nm, Font, new Rectangle((int)(u * 2.9F), y, Width - (int)(u * 2.9F) - acs.Width - (int)(u * 1.0F), RowH),
                        Theme.TextDim, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
                    TextRenderer.DrawText(g, act, Font, new Rectangle(0, y, Width - (int)(u * 0.6F), RowH),
                        Theme.TextFaint, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
                    y += RowH;
                }
            }
        }
    }
}
