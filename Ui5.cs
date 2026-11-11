using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;

namespace Win11Privacy
{
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

    // ---------------------------------------------------------------------- //
    //  Строка «Обзора»: значок, заголовок, пояснение; справа — кнопка
    //  действия или состояние раздела. Текст переносится, а не режется.
    // ---------------------------------------------------------------------- //
    internal class InfoRow : Control
    {
        public string Glyph = "", Title = "", Desc = "", State = "";
        public Color GlyphColor, StateColor;
        public bool GlyphTile;           // крупный значок на подложке — строка состояния
        public bool Large;               // крупный заголовок
        public bool Link;                // вся строка — переход (стрелка справа)
        public bool Divider = true;      // разделитель сверху
        public ModernButton Button;
        private EventHandler _btnClick;
        private bool _hover;

        public InfoRow()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.CardBg;
            GlyphColor = Theme.TextDim; StateColor = Theme.TextFaint;
        }

        public void Set(string glyph, Color glyphColor, string title, string desc)
        {
            Glyph = glyph ?? ""; GlyphColor = glyphColor; Title = title ?? ""; Desc = desc ?? "";
            AccessibleName = Title; AccessibleDescription = Desc;
            Reflow();
        }

        public void SetState(string state, Color color) { State = state ?? ""; StateColor = color; Reflow(); }

        // Кнопка справа; null — убрать
        public void SetButton(string text, EventHandler click)
        {
            if (text == null) { if (Button != null) Button.Visible = false; _btnClick = null; Reflow(); return; }
            if (Button == null)
            {
                Button = new ModernButton(text, false);
                Button.Font = Font;
                Button.Click += delegate(object s, EventArgs e) { if (_btnClick != null) _btnClick(s, e); };
                Controls.Add(Button);
            }
            Button.Text = text; Button.Fit(); Button.Visible = true;
            _btnClick = click;
            Reflow();
        }

        private int U { get { return Font.Height; } }
        private int PadX { get { return (int)(U * 1.0F); } }
        private int PadY { get { return (int)(U * (Large ? 0.95F : 0.7F)); } }
        private int GlyphW { get { return GlyphTile ? (int)(U * 2.4F) : (int)(U * 1.3F); } }
        private Font TitleFont { get { return Large ? Theme.Sized(Font.Name, Font.SizeInPoints * 1.2F, FontStyle.Bold) : Font; } }

        private int RightW(Graphics g)
        {
            int u = U;
            if (Button != null && Button.Visible) return Button.Width + (int)(u * 0.6F);
            int w = 0;
            if (State.Length > 0) w += TextRenderer.MeasureText(g, State, Font).Width + (int)(u * 0.9F);
            if (Link) w += (int)(u * 1.3F);
            return w;
        }

        private int TextLeft { get { return PadX + (Glyph.Length > 0 ? GlyphW + (int)(U * 0.75F) : 0); } }

        // Высота под ширину: заголовок и пояснение переносятся по словам
        public int Measure(int width)
        {
            using (Graphics g = CreateGraphics())
            {
                int tw = Math.Max(U * 6, width - TextLeft - RightW(g) - PadX);
                int th = TextRenderer.MeasureText(g, Title, TitleFont, new Size(tw, 0), TextFormatFlags.WordBreak | TextFormatFlags.NoPadding).Height;
                int dh = Desc.Length == 0 ? 0 : TextRenderer.MeasureText(g, Desc, Font, new Size(tw, 0), TextFormatFlags.WordBreak | TextFormatFlags.NoPadding).Height + (int)(U * 0.2F);
                int inner = Math.Max(th + dh, GlyphTile ? GlyphW : 0);
                int btn = Button != null && Button.Visible ? Button.Height : 0;
                return Math.Max(inner, btn) + PadY * 2;
            }
        }

        private void Reflow() { if (Parent != null) Parent.PerformLayout(); Invalidate(); }

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); if (Button != null) Button.Font = Font; Reflow(); }

        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e);
            if (Button != null && Button.Visible)
                Button.Location = new Point(Width - PadX - Button.Width, (Height - Button.Height) / 2);
        }

        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); if (Link) { _hover = true; Cursor = Cursors.Hand; Invalidate(); } }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = U;
            using (SolidBrush b = new SolidBrush(_hover ? Theme.RowHover : Theme.CardBg)) g.FillRectangle(b, ClientRectangle);
            if (Divider) using (Pen p = new Pen(Theme.CardBorder)) g.DrawLine(p, 0, 0, Width, 0);

            Font icon = Theme.IconFont(Font.Size * (GlyphTile ? 1.35F : 1.05F));
            int left = TextLeft;
            int right = RightW(g);
            int tw = Math.Max(u * 6, Width - left - right - PadX);
            int th = TextRenderer.MeasureText(g, Title, TitleFont, new Size(tw, 0), TextFormatFlags.WordBreak | TextFormatFlags.NoPadding).Height;
            int dh = Desc.Length == 0 ? 0 : TextRenderer.MeasureText(g, Desc, Font, new Size(tw, 0), TextFormatFlags.WordBreak | TextFormatFlags.NoPadding).Height;
            int block = th + (dh > 0 ? dh + (int)(u * 0.2F) : 0);
            int ty = (Height - block) / 2;

            if (Glyph.Length > 0 && icon != null)
            {
                if (GlyphTile)
                {
                    Rectangle tile = new Rectangle(PadX, (Height - GlyphW) / 2, GlyphW, GlyphW);
                    using (GraphicsPath p = Theme.RoundRect(tile, 6))
                    using (SolidBrush b = new SolidBrush(Theme.Mix(Theme.CardBg, GlyphColor, Theme.Dark ? 0.14F : 0.10F))) g.FillPath(b, p);
                    TextRenderer.DrawText(g, Glyph, icon, tile, GlyphColor,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                }
                else
                    TextRenderer.DrawText(g, Glyph, icon, new Rectangle(PadX, ty, GlyphW, (int)(u * 1.3F)), GlyphColor,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            }

            TextRenderer.DrawText(g, Title, TitleFont, new Rectangle(left, ty, tw, th), Theme.Text,
                TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
            if (dh > 0)
                TextRenderer.DrawText(g, Desc, Font, new Rectangle(left, ty + th + (int)(u * 0.2F), tw, dh), Theme.TextDim,
                    TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
#if UITEST
            if (block + PadY * 2 > Height + 1) ClipWatch.Note("InfoRow", Title, block + PadY * 2, Height);
#endif

            if (Button != null && Button.Visible) return;
            int x = Width - PadX;
            if (Link)
            {
                Font chev = Theme.IconFont(Font.Size * 0.8F);
                if (chev != null)
                    TextRenderer.DrawText(g, "", chev, new Rectangle(x - (int)(u * 1.0F), 0, (int)(u * 1.0F), Height), Theme.TextFaint,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                x -= (int)(u * 1.3F);
            }
            if (State.Length > 0)
            {
                int sw = TextRenderer.MeasureText(g, State, Font).Width;
                TextRenderer.DrawText(g, State, Font, new Rectangle(x - sw, 0, sw, Height), Theme.TextDim,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
                float d = u * 0.4F;
                using (SolidBrush b = new SolidBrush(StateColor))
                    g.FillEllipse(b, x - sw - u * 0.45F - d, (Height - d) / 2F, d, d);
            }
        }
    }

    // ---------------------------------------------------------------------- //
    //  Карточка-список строк InfoRow: высота — по содержимому
    // ---------------------------------------------------------------------- //
    internal class RowList : Panel
    {
        public RowList()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.CardBg;
        }

        private int _want = 2;

        // Полоса прокрутки страницы сужает список уже после раскладки строк:
        // без явной перераскладки строки оставались прежней ширины.
        protected override void OnSizeChanged(EventArgs e)
        {
            base.OnSizeChanged(e);
            int w = Math.Max(10, ClientSize.Width - 2);
            foreach (Control c in Controls) if (c.Width != w) c.Width = w;
            PerformLayout();
        }

        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e);
            int y = 1, w = Math.Max(10, ClientSize.Width - 2);
            bool first = true;
            foreach (Control c in Controls)
            {
                if (!c.Visible) continue;
                InfoRow r = c as InfoRow;
                if (r != null) { r.Divider = !first; c.Height = r.Measure(w); }
                c.SetBounds(1, y, w, c.Height);
                y += c.Height;
                first = false;
            }
            int want = y + 1;
            if (want != _want)
            {
                _want = want; Height = want;
                // Мы внутри раскладки родителя: новую высоту он сейчас уже не
                // учтёт, и строка таблицы оставалась прежней (пустой зазор).
                // Перераскладка — следующим шагом цикла сообщений.
                Control p = Parent;
                if (p != null)
                {
                    if (IsHandleCreated) BeginInvoke((MethodInvoker)delegate { p.PerformLayout(); });
                    else p.PerformLayout();
                }
            }
        }

        public override Size GetPreferredSize(Size proposedSize) { return new Size(Width, _want); }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            using (SolidBrush b = new SolidBrush(Parent != null ? Parent.BackColor : Theme.WindowBg)) g.FillRectangle(b, ClientRectangle);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath p = Theme.RoundRect(new RectangleF(0.5F, 0.5F, Width - 1, Height - 1), 8))
            {
                using (SolidBrush b = new SolidBrush(Theme.CardBg)) g.FillPath(b, p);
                using (Pen pen = new Pen(Theme.CardBorder)) g.DrawPath(pen, p);
            }
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
