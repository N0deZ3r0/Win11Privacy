// Базовые элементы: карточки, кнопки, переключатели, вкладки, поиск,
// заголовки разделов, пустое состояние.

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

    // ====================================================================== //
    //  Строгий вид «консоли»: вкладки разделов, переключатель профиля,
    //  строки с действием для «Обзора» и тёмное меню. Никаких цветных
    //  подложек: цвет — только у отметок о состоянии.
    // ====================================================================== //

    // ---------------------------------------------------------------------- //
    //  Полоса вкладок над страницей объединённого раздела
    // ---------------------------------------------------------------------- //
    internal class TabStrip : Control
    {
        public event Action<string> TabClicked;
        private readonly List<string> _keys = new List<string>();
        private readonly List<string> _texts = new List<string>();
        private readonly List<Rectangle> _rects = new List<Rectangle>();
        private readonly Dictionary<string, bool> _dots = new Dictionary<string, bool>();
        private string _sel = "";
        private int _hover = -1;

        public TabStrip()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
            BackColor = Theme.WindowBg;
            TabStop = true;
            AccessibleRole = AccessibleRole.PageTabList;
        }

        public string Selected { get { return _sel; } }

        public void SetTabs(IList<string> keys, IList<string> texts, string selected)
        {
            _keys.Clear(); _keys.AddRange(keys);
            _texts.Clear(); _texts.AddRange(texts);
            _sel = selected ?? "";
            AccessibleName = string.Join(", ", _texts.ToArray());
            Invalidate();
        }

        public void SetDot(string key, bool on) { _dots[key] = on; Invalidate(); }

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Height = (int)(Font.Height * 2.3F); }

        private void Measure(Graphics g)
        {
            _rects.Clear();
            int u = Font.Height;
            int x = 0;
            for (int i = 0; i < _texts.Count; i++)
            {
                int w = TextRenderer.MeasureText(g, _texts[i], Font, new Size(int.MaxValue, Height), TextFormatFlags.NoPadding).Width;
                bool dot = _dots.ContainsKey(_keys[i]) && _dots[_keys[i]];
                if (dot) w += (int)(u * 0.7F);
                _rects.Add(new Rectangle(x, 0, w + (int)(u * 0.2F), Height));
                x += w + (int)(u * 1.6F);
            }
#if UITEST
            if (x - (int)(u * 1.6F) > Width && Width > 0) ClipWatch.Note("TabStrip", string.Join("|", _texts.ToArray()), x, Width);
#endif
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            using (SolidBrush b = new SolidBrush(Theme.WindowBg)) g.FillRectangle(b, ClientRectangle);
            using (Pen line = new Pen(Theme.CardBorder)) g.DrawLine(line, 0, Height - 1, Width, Height - 1);
            Measure(g);
            int u = Font.Height;
            for (int i = 0; i < _texts.Count; i++)
            {
                Rectangle r = _rects[i];
                bool sel = _keys[i] == _sel;
                Color fg = sel || i == _hover ? Theme.Text : Theme.TextDim;
                int textH = (int)(u * 1.6F);
                TextRenderer.DrawText(g, _texts[i], Font, new Rectangle(r.X, 0, r.Width + u, textH), fg,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
                if (_dots.ContainsKey(_keys[i]) && _dots[_keys[i]])
                {
                    float d = u * 0.32F;
                    using (SolidBrush b = new SolidBrush(Theme.Warn))
                        g.FillEllipse(b, r.Right - d - u * 0.1F, (textH - d) / 2F, d, d);
                }
                if (sel)
                    using (SolidBrush b = new SolidBrush(Theme.Accent))
                        g.FillRectangle(b, r.X, Height - 2, r.Width - (int)(u * 0.2F), 2);
                if (sel && Focused)
                    using (Pen p = new Pen(Theme.Accent))
                        g.DrawRectangle(p, r.X - 3, 1, r.Width, textH);
            }
        }

        private int HitTest(Point p) { for (int i = 0; i < _rects.Count; i++) if (_rects[i].Contains(p)) return i; return -1; }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            int h = HitTest(e.Location);
            if (h != _hover) { _hover = h; Cursor = h >= 0 ? Cursors.Hand : Cursors.Default; Invalidate(); }
        }

        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = -1; Invalidate(); }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            int h = HitTest(e.Location);
            if (h >= 0) Pick(h);
        }

        private void Pick(int i)
        {
            if (i < 0 || i >= _keys.Count) return;
            _sel = _keys[i]; Invalidate();
            if (TabClicked != null) TabClicked(_keys[i]);
        }

        protected override bool IsInputKey(Keys keyData)
        { return keyData == Keys.Left || keyData == Keys.Right || base.IsInputKey(keyData); }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            int i = _keys.IndexOf(_sel);
            if (e.KeyCode == Keys.Right && i < _keys.Count - 1) { Pick(i + 1); e.Handled = true; }
            if (e.KeyCode == Keys.Left && i > 0) { Pick(i - 1); e.Handled = true; }
        }

        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }
    }

    // ---------------------------------------------------------------------- //
    //  Переключатель из нескольких вариантов (профиль настроек)
    // ---------------------------------------------------------------------- //
    internal class Segmented : Control
    {
        public event Action<string> Picked;
        private readonly List<string> _keys = new List<string>();
        private readonly List<string> _texts = new List<string>();
        private readonly List<Rectangle> _rects = new List<Rectangle>();
        private string _sel = "";
        private int _hover = -1;

        public Segmented()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
            BackColor = Theme.WindowBg;
            TabStop = true;
            AccessibleRole = AccessibleRole.PageTabList;
        }

        public string Selected { get { return _sel; } set { _sel = value ?? ""; Invalidate(); } }

        public void Add(string key, string text) { _keys.Add(key); _texts.Add(text); Fit(); }

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Fit(); }

        private void Fit()
        {
            int u = Font.Height;
            _rects.Clear();
            int x = 0;
            for (int i = 0; i < _texts.Count; i++)
            {
                int w = TextRenderer.MeasureText(_texts[i], Font).Width + (int)(u * 0.9F);
                _rects.Add(new Rectangle(x, 0, w, (int)(u * 2.0F)));
                x += w;
            }
            Size = new Size(Math.Max(1, x + 1), (int)(u * 2.0F));
            AccessibleName = string.Join(", ", _texts.ToArray());
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            using (SolidBrush b = new SolidBrush(Parent != null ? Parent.BackColor : Theme.WindowBg)) g.FillRectangle(b, ClientRectangle);
            RectangleF outer = new RectangleF(0.5F, 0.5F, Width - 1, Height - 1);
            using (GraphicsPath p = Theme.RoundRect(outer, 6))
            {
                using (SolidBrush b = new SolidBrush(Theme.ButtonBg)) g.FillPath(b, p);
                Region old = g.Clip;
                g.SetClip(p);
                for (int i = 0; i < _rects.Count; i++)
                {
                    Rectangle r = _rects[i];
                    bool sel = _keys[i] == _sel;
                    if (sel) using (SolidBrush b = new SolidBrush(Theme.BadgeBg)) g.FillRectangle(b, r);
                    else if (i == _hover) using (SolidBrush b = new SolidBrush(Theme.ButtonHover)) g.FillRectangle(b, r);
                    if (i > 0) using (Pen pen = new Pen(Theme.ButtonBorder)) g.DrawLine(pen, r.X, 0, r.X, Height);
                    TextRenderer.DrawText(g, _texts[i], Font, r, sel || i == _hover ? Theme.Text : Theme.TextDim,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
                }
                g.Clip = old;
                using (Pen pen = new Pen(Focused ? Theme.Accent : Theme.ButtonBorder)) g.DrawPath(pen, p);
            }
        }

        private int HitTest(Point p) { for (int i = 0; i < _rects.Count; i++) if (_rects[i].Contains(p)) return i; return -1; }

        protected override void OnMouseMove(MouseEventArgs e)
        { base.OnMouseMove(e); int h = HitTest(e.Location); if (h != _hover) { _hover = h; Cursor = h >= 0 ? Cursors.Hand : Cursors.Default; Invalidate(); } }

        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = -1; Invalidate(); }

        protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); if (CanFocus) Focus(); Pick(HitTest(e.Location)); }

        private void Pick(int i)
        {
            if (i < 0 || i >= _keys.Count) return;
            _sel = _keys[i]; Invalidate();
            if (Picked != null) Picked(_keys[i]);
        }

        protected override bool IsInputKey(Keys keyData)
        { return keyData == Keys.Left || keyData == Keys.Right || base.IsInputKey(keyData); }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            int i = _keys.IndexOf(_sel);
            if (e.KeyCode == Keys.Right && i < _keys.Count - 1) { Pick(i + 1); e.Handled = true; }
            if (e.KeyCode == Keys.Left && i > 0) { Pick(i - 1); e.Handled = true; }
        }

        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }
    }

    // ====================================================================== //
    //  Пустое состояние: значок, заголовок и пояснение по центру, шрифтом
    //  интерфейса. Раньше пустой журнал показывал две строки моноширинным
    //  шрифтом с переносом посреди фразы — как будто это уже вывод.
    // ====================================================================== //
    internal class EmptyState : Control
    {
        public string Glyph = "", Title = "", Note = "";

        public EmptyState()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            using (SolidBrush bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);
            int u = Font.Height;
            int w = Math.Max(u * 8, Math.Min(Width - u * 2, (int)(u * 28F)));
            int x = (Width - w) / 2;
            TextFormatFlags f = TextFormatFlags.HorizontalCenter | TextFormatFlags.WordBreak | TextFormatFlags.NoPadding;
            Font bold = Theme.Bold(Font);
            Font icon = string.IsNullOrEmpty(Glyph) ? null : Theme.IconFont(Font.Size * 2.2F);
            int ih = icon != null ? (int)(u * 2.6F) : 0;
            Size ts = TextRenderer.MeasureText(g, Title, bold, new Size(w, int.MaxValue), f);
            Size ns = TextRenderer.MeasureText(g, Note, Font, new Size(w, int.MaxValue), f);
            int gap = (int)(u * 0.45F);
            int total = ih + ts.Height + gap + ns.Height;
            int y = Math.Max(u, (Height - total) / 2 - u);      // чуть выше середины — так глазу ровнее
            if (icon != null)
                TextRenderer.DrawText(g, Glyph, icon, new Rectangle(0, y, Width, ih), Theme.TextFaint,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.Top | TextFormatFlags.NoPadding);
            y += ih;
            TextRenderer.DrawText(g, Title, bold, new Rectangle(x, y, w, ts.Height), Theme.Text, f);
            y += ts.Height + gap;
            TextRenderer.DrawText(g, Note, Font, new Rectangle(x, y, w, ns.Height), Theme.TextDim, f);
        }
    }
}
