// Тема и системное оформление: цвета, шрифты, тёмные полосы прокрутки,
// рамка фокуса только с клавиатуры, плавные переходы, тёмное меню.

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

    // ---------------------------------------------------------------------- //
    //  Тёмное оформление выпадающих меню
    // ---------------------------------------------------------------------- //
    internal class ConsoleMenuColors : ProfessionalColorTable
    {
        public override Color ToolStripDropDownBackground { get { return Theme.CardBg; } }
        public override Color ImageMarginGradientBegin { get { return Theme.CardBg; } }
        public override Color ImageMarginGradientMiddle { get { return Theme.CardBg; } }
        public override Color ImageMarginGradientEnd { get { return Theme.CardBg; } }
        public override Color MenuBorder { get { return Theme.CardBorder; } }
        public override Color MenuItemBorder { get { return Theme.RowHover; } }
        public override Color MenuItemSelected { get { return Theme.RowHover; } }
        public override Color MenuItemSelectedGradientBegin { get { return Theme.RowHover; } }
        public override Color MenuItemSelectedGradientEnd { get { return Theme.RowHover; } }
        public override Color SeparatorDark { get { return Theme.CardBorder; } }
        public override Color SeparatorLight { get { return Theme.CardBorder; } }
    }

    internal class ConsoleMenuRenderer : ToolStripProfessionalRenderer
    {
        public ConsoleMenuRenderer() : base(new ConsoleMenuColors()) { RoundedEdges = false; }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = e.Item.Enabled ? Theme.Text : Theme.TextFaint;
            base.OnRenderItemText(e);
        }
    }
}
