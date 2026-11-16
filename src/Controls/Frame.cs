// Каркас окна: заголовок, боковая панель, пункты навигации и подсветка выбранного.

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
}
