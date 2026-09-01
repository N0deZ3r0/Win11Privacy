using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;

namespace Win11Privacy
{
    // ====================================================================== //
    //  Строка досье: какая программа включала камеру / микрофон / геолокацию
    // ====================================================================== //
    internal class SpyRow : Control, IFilterable
    {
        public string FilterText { get { return _app + " " + _cap + " " + _when; } }
        private readonly string _app, _cap, _when, _dur, _glyph;
        private readonly bool _active;
        private readonly Color _capColor;
        private bool _hover, _btnHover;
        private Rectangle _btnRect;

        public readonly string Key;          // ключ в ConsentStore
        public bool Denied;                  // доступ уже запрещён
        public event EventHandler ToggleAccess;

        public SpyRow(string app, string cap, string glyph, Color capColor,
                      string when, string duration, bool active, string key, bool denied)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            _app = app; _cap = cap; _glyph = glyph; _capColor = capColor;
            _when = when; _dur = duration; _active = active;
            Key = key ?? ""; Denied = denied;
            BackColor = Theme.CardBg;
        }

        private bool HasButton { get { return Key.Length > 0; } }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            bool over = HasButton && _btnRect.Contains(e.Location);
            if (over != _btnHover) { _btnHover = over; Cursor = over ? Cursors.Hand : Cursors.Default; Invalidate(); }
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (HasButton && _btnRect.Contains(e.Location) && ToggleAccess != null) ToggleAccess(this, EventArgs.Empty);
        }

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Height = (int)(Font.Height * 3.0F); }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; _btnHover = false; Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = Font.Height;

            if (_hover)
            {
                using (GraphicsPath p = Theme.RoundRect(new RectangleF(0.5F, 0.5F, Width - 1, Height - 1), 6))
                using (SolidBrush b = new SolidBrush(Theme.RowHover)) g.FillPath(b, p);
            }
            if (_active)
            {
                using (GraphicsPath p = Theme.RoundRect(new RectangleF(0.5F, 0.5F, Width - 1, Height - 1), 6))
                using (SolidBrush b = new SolidBrush(Theme.Mix(Theme.CardBg, Theme.Err, 0.12F))) g.FillPath(b, p);
            }

            // значок датчика
            int badge = (int)(u * 2.0F);
            int bx = (int)(u * 0.5F);
            int by = (Height - badge) / 2;
            using (GraphicsPath p = Theme.RoundRect(new RectangleF(bx, by, badge, badge), badge * 0.3F))
            using (SolidBrush b = new SolidBrush(Theme.Mix(Theme.CardBg, _capColor, 0.18F))) g.FillPath(b, p);
            Font icon = Theme.IconFont(Font.Size * 1.1F);
            if (icon != null && !string.IsNullOrEmpty(_glyph))
                TextRenderer.DrawText(g, _glyph, icon, new Rectangle(bx, by, badge, badge), _capColor,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            else
            {
                float d = badge * 0.36F;
                using (SolidBrush b = new SolidBrush(_capColor)) g.FillEllipse(b, bx + (badge - d) / 2, by + (badge - d) / 2, d, d);
            }

            int tx = bx + badge + (int)(u * 0.65F);

            // правая часть: кнопка доступа, затем «СЕЙЧАС» или время
            int rightEdge = Width - (int)(u * 0.5F);
            if (_active)
            {
                string chip = L.T("СЕЙЧАС");
                using (Font cf = new Font(Font.FontFamily, Font.Size * 0.85F, FontStyle.Bold))
                {
                    Size cs = TextRenderer.MeasureText(chip, cf);
                    int cw = cs.Width + (int)(u * 0.9F), ch = (int)(u * 1.35F);
                    RectangleF cr = new RectangleF(rightEdge - cw, (Height - ch) / 2F, cw, ch);
                    using (GraphicsPath p = Theme.RoundRect(cr, ch / 2F))
                    using (SolidBrush b = new SolidBrush(Theme.Err)) g.FillPath(b, p);
                    TextRenderer.DrawText(g, chip, cf, Rectangle.Round(cr), Theme.Dark ? Color.FromArgb(0x20, 0x10, 0x10) : Color.White,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                    rightEdge -= cw + (int)(u * 0.5F);
                }
            }
            else
            {
                Size ws = TextRenderer.MeasureText(_when, Font);
                TextRenderer.DrawText(g, _when, Font, new Rectangle(rightEdge - ws.Width, 0, ws.Width, Height),
                    Theme.TextDim, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
                rightEdge -= ws.Width + (int)(u * 0.5F);
            }

            // кнопка «Запретить» / «Запрещено»
            if (HasButton)
            {
                string cap = Denied ? L.T("Запрещено") : L.T("Запретить");
                using (Font bf = new Font(Font.FontFamily, Font.Size * 0.9F, FontStyle.Regular))
                {
                    Size cs = TextRenderer.MeasureText(g, cap, bf, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
                    int bw = cs.Width + (int)(u * 1.1F), bh = (int)(u * 1.5F);
                    _btnRect = new Rectangle(rightEdge - bw, (Height - bh) / 2, bw, bh);
                    RectangleF br = new RectangleF(_btnRect.X + 0.5F, _btnRect.Y + 0.5F, _btnRect.Width - 1, _btnRect.Height - 1);
                    Color face = Denied ? Theme.Mix(Theme.CardBg, Theme.Ok, 0.22F)
                                        : (_btnHover ? Theme.ButtonHover : Theme.ButtonBg);
                    Color edge = Denied ? Theme.Ok : (_btnHover ? Theme.Mix(Theme.ButtonBorder, _capColor, 0.6F) : Theme.ButtonBorder);
                    using (GraphicsPath p = Theme.RoundRect(br, bh / 2F))
                    {
                        using (SolidBrush b = new SolidBrush(face)) g.FillPath(b, p);
                        using (Pen pen = new Pen(edge)) g.DrawPath(pen, p);
                    }
                    TextRenderer.DrawText(g, cap, bf, _btnRect, Denied ? Theme.Ok : Theme.Text,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                    rightEdge -= bw + (int)(u * 0.5F);
                }
            }
            else _btnRect = Rectangle.Empty;

            // имя программы + датчик и длительность
            int textW = Math.Max(50, rightEdge - tx);
            TextRenderer.DrawText(g, _app, new Font(Font, FontStyle.Bold),
                new Rectangle(tx, (int)(u * 0.35F), textW, (int)(u * 1.4F)),
                _active ? Theme.Err : Theme.Text,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            string sub = _cap + (string.IsNullOrEmpty(_dur) ? "" : "  ·  " + _dur);
            TextRenderer.DrawText(g, sub, Font,
                new Rectangle(tx, (int)(u * 1.5F), textW, (int)(u * 1.4F)), Theme.TextDim,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
        }
    }

    // ====================================================================== //
    //  График обращений к датчикам по дням (Обзор)
    // ====================================================================== //
    internal class SensorChart : Control
    {
        private class Day { public string Label; public int Cam, Mic, Loc, Other;
                            public int Total { get { return Cam + Mic + Loc + Other; } } }
        private readonly List<Day> _days = new List<Day>();
        private readonly Tween _grow = new Tween(0.12F);

        public SensorChart()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            _grow.Changed += delegate { Invalidate(); };
        }

        public void SetData(List<object> days)
        {
            _days.Clear();
            if (days != null)
                foreach (object o in days)
                {
                    Dictionary<string, object> d = Json.Obj(o);
                    if (d == null) continue;
                    Day day = new Day();
                    day.Label = Json.GetStr(d, "date");
                    day.Cam = Json.GetInt(d, "cam"); day.Mic = Json.GetInt(d, "mic");
                    day.Loc = Json.GetInt(d, "loc"); day.Other = Json.GetInt(d, "other");
                    _days.Add(day);
                }
            _grow.To(0F, false);
            _grow.To(1F, IsHandleCreated && Visible);
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = Font.Height;
            if (Width < 60 || Height < 40) return;

            int max = 0; foreach (Day d in _days) if (d.Total > max) max = d.Total;
            if (_days.Count == 0 || max == 0)
            {
                TextRenderer.DrawText(g,
                    L.T("Здесь появится история по дням.\n") +
                    L.T("Включите «Следить за датчиками» на странице «Страж» —\n") +
                    L.T("она будет пополняться сама."),
                    Font, ClientRectangle, Theme.TextDim,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
                return;
            }

            // легенда
            int lx = Width - (int)(u * 0.3F);
            string[] names = { L.T("Другое"), L.T("Гео"), L.T("Микрофон"), L.T("Камера") };
            Color[] cols = { Theme.TextFaint, Theme.Accent, Theme.Warn, Theme.Err };
            using (Font lf = new Font(Font.FontFamily, Font.Size * 0.85F))
            {
                for (int i = 0; i < names.Length; i++)
                {
                    if (i == 0) { bool anyOther = false; foreach (Day d in _days) if (d.Other > 0) anyOther = true; if (!anyOther) continue; }
                    Size ts = TextRenderer.MeasureText(names[i], lf);
                    lx -= ts.Width;
                    TextRenderer.DrawText(g, names[i], lf, new Rectangle(lx, 0, ts.Width, (int)(u * 1.3F)),
                        Theme.TextDim, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                    lx -= (int)(u * 0.75F);
                    using (SolidBrush b = new SolidBrush(cols[i]))
                        g.FillEllipse(b, lx, (int)(u * 0.35F), u * 0.55F, u * 0.55F);
                    lx -= (int)(u * 0.8F);
                }
            }

            int top = (int)(u * 2.7F);
            int labelH = (int)(u * 1.3F);
            int plotH = Height - top - labelH;
            int baseY = top + plotH;
            if (plotH < u) return;

            float slot = (float)Width / _days.Count;
            float barW = Math.Max(4F, slot * 0.58F);
            float grow = _grow.Value;

            using (Pen axis = new Pen(Theme.Mix(Theme.CardBg, Theme.TextFaint, 0.35F)))
                g.DrawLine(axis, 0, baseY, Width, baseY);

            using (Font lf = new Font(Font.FontFamily, Font.Size * 0.8F))
            {
                bool everyOther = slot < TextRenderer.MeasureText("00.00", lf).Width + 4;
                for (int i = 0; i < _days.Count; i++)
                {
                    Day d = _days[i];
                    float cx = slot * i + slot / 2F;
                    float x = cx - barW / 2F;

                    // подпись даты
                    if (!everyOther || i % 2 == 1 || _days.Count - 1 == i)
                        TextRenderer.DrawText(g, d.Label, lf,
                            new Rectangle((int)(cx - slot / 2F), baseY + 2, (int)slot, labelH),
                            Theme.TextFaint, TextFormatFlags.HorizontalCenter | TextFormatFlags.Top | TextFormatFlags.NoPadding);

                    if (d.Total == 0) continue;
                    float totalH = plotH * ((float)d.Total / max) * grow;
                    if (totalH < 2F) totalH = 2F;

                    // сегменты снизу вверх: другое, гео, микрофон, камера
                    int[] vals = { d.Other, d.Loc, d.Mic, d.Cam };
                    float y = baseY;
                    using (GraphicsPath clip = Theme.RoundRect(new RectangleF(x, baseY - totalH, barW, totalH), Math.Min(4F, barW / 2.5F)))
                    {
                        Region old = g.Clip;
                        g.SetClip(clip, CombineMode.Intersect);
                        for (int s = 0; s < vals.Length; s++)
                        {
                            if (vals[s] <= 0) continue;
                            float h = totalH * ((float)vals[s] / d.Total);
                            using (SolidBrush b = new SolidBrush(cols[s]))
                                g.FillRectangle(b, x, y - h, barW, h + 0.8F);
                            y -= h;
                        }
                        g.Clip = old;
                    }

                    // число над баром
                    string t = d.Total.ToString();
                    Size ts = TextRenderer.MeasureText(t, lf);
                    if (ts.Width < slot)
                        TextRenderer.DrawText(g, t, lf,
                            new Rectangle((int)(cx - slot / 2F), (int)(baseY - totalH - u * 1.05F), (int)slot, (int)(u * 1.0F)),
                            Theme.TextDim, TextFormatFlags.HorizontalCenter | TextFormatFlags.Bottom | TextFormatFlags.NoPadding);
                }
            }
        }
    }

    // ====================================================================== //
    //  Строка цифрового следа: чекбокс «стереть», название, описание, значение
    // ====================================================================== //
    internal class WipeRow : Control, IFilterable
    {
        public readonly string Id;
        public readonly bool CanWipe;
        public string FilterText { get { return _title + " " + _what + " " + _value; } }
        private readonly string _title, _what, _value, _glyph;
        private bool _checked, _hover;
        private Font _bold;

        public WipeRow(string id, string title, string what, string value, string glyph, bool canWipe)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Id = id; _title = title; _what = what; _value = value; _glyph = glyph; CanWipe = canWipe;
            BackColor = Theme.CardBg;
            // строку можно отметить и с клавиатуры: Tab доводит до неё, пробел ставит галочку
            SetStyle(ControlStyles.Selectable, canWipe);
            TabStop = canWipe;
            if (canWipe) Cursor = Cursors.Hand;
        }

        public bool Checked { get { return _checked; } set { _checked = value; Invalidate(); } }

        private int U { get { return Font.Height; } }
        private int _textLeft, _textWidth, _titleH, _whatH, _valueW;
        private bool _inLayout;

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); _bold = new Font(Font, FontStyle.Bold); Relayout(); }
        protected override void OnResize(EventArgs e) { base.OnResize(e); Relayout(); }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; Invalidate(); }
        protected override void OnClick(EventArgs e)
        {
            base.OnClick(e);
            if (CanWipe) { Focus(); _checked = !_checked; Invalidate(); }
        }

        protected override void OnEnter(EventArgs e) { base.OnEnter(e); Invalidate(); }
        protected override void OnLeave(EventArgs e) { base.OnLeave(e); Invalidate(); }

        // пробел и Enter переключают галочку — иначе страница только для мыши
        protected override bool IsInputKey(Keys keyData)
        {
            if (keyData == Keys.Space || keyData == Keys.Enter) return true;
            return base.IsInputKey(keyData);
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (!CanWipe) return;
            if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter)
            { _checked = !_checked; Invalidate(); e.Handled = true; }
        }

        private void Relayout()
        {
            if (_inLayout || Width < 60) return;
            _inLayout = true;
            try
            {
                if (_bold == null) _bold = new Font(Font, FontStyle.Bold);
                int u = U;
                int box = (int)(u * 1.15F);
                _textLeft = (int)(u * 0.6F) + box + (int)(u * 0.7F);
                _valueW = Math.Min((int)(Width * 0.36F), TextRenderer.MeasureText(_value, _bold).Width + (int)(u * 0.4F));
                _textWidth = Math.Max(60, Width - _textLeft - _valueW - (int)(u * 1.2F));
                _titleH = TextRenderer.MeasureText(_title, _bold, new Size(_textWidth, 0),
                    TextFormatFlags.WordBreak | TextFormatFlags.NoPadding).Height;
                _whatH = TextRenderer.MeasureText(_what, Font, new Size(_textWidth + _valueW, 0),
                    TextFormatFlags.WordBreak | TextFormatFlags.NoPadding).Height;
                int padY = (int)(u * 0.5F);
                int h = padY + _titleH + (int)(u * 0.15F) + _whatH + padY;
                if (Height != h) Height = h;
            }
            finally { _inLayout = false; }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = U;

            if (_hover && CanWipe)
            {
                using (GraphicsPath p = Theme.RoundRect(new RectangleF(0.5F, 0.5F, Width - 1, Height - 1), 6))
                using (SolidBrush b = new SolidBrush(Theme.RowHover)) g.FillPath(b, p);
            }
            if (Focused && CanWipe)      // видно, на какой строке клавиатура
            {
                using (GraphicsPath p = Theme.RoundRect(new RectangleF(0.5F, 0.5F, Width - 1, Height - 1), 6))
                using (Pen pen = new Pen(Theme.Accent)) g.DrawPath(pen, p);
            }

            int padY = (int)(u * 0.5F);
            int box = (int)(u * 1.15F);
            int bx = (int)(u * 0.6F);
            int by = padY + (_titleH - box) / 2; if (by < padY) by = padY;

            if (CanWipe)
            {
                RectangleF br = new RectangleF(bx, by, box, box);
                using (GraphicsPath p = Theme.RoundRect(br, box * 0.28F))
                {
                    if (_checked) { using (SolidBrush b = new SolidBrush(Theme.Accent)) g.FillPath(b, p); }
                    else { using (SolidBrush b = new SolidBrush(Theme.CardBg)) g.FillPath(b, p); }
                    using (Pen pen = new Pen(_checked ? Theme.Accent : Theme.TrackOff, 1.4F)) g.DrawPath(pen, p);
                }
                if (_checked)
                {
                    using (Pen pen = new Pen(Theme.AccentText, 1.8F))
                    {
                        pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
                        float cx = bx + box * 0.5F, cy = by + box * 0.55F;
                        g.DrawLine(pen, bx + box * 0.24F, cy, bx + box * 0.43F, by + box * 0.72F);
                        g.DrawLine(pen, bx + box * 0.43F, by + box * 0.72F, bx + box * 0.78F, by + box * 0.28F);
                    }
                }
            }
            else
            {
                // информационная строка без стирания — маленький глиф
                Font icon = Theme.IconFont(Font.Size * 0.95F);
                if (icon != null && !string.IsNullOrEmpty(_glyph))
                    TextRenderer.DrawText(g, _glyph, icon, new Rectangle(bx, by, box, box), Theme.TextFaint,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                else using (SolidBrush b = new SolidBrush(Theme.TextFaint))
                    g.FillEllipse(b, bx + box * 0.3F, by + box * 0.3F, box * 0.4F, box * 0.4F);
            }

            Color titleColor = CanWipe ? Theme.Text : Theme.TextDim;
            TextRenderer.DrawText(g, _title, _bold ?? Font,
                new Rectangle(_textLeft, padY, _textWidth, _titleH), titleColor,
                TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, _what, Font,
                new Rectangle(_textLeft, padY + _titleH + (int)(u * 0.15F), _textWidth + _valueW, _whatH),
                Theme.TextFaint, TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);

            TextRenderer.DrawText(g, _value, _bold ?? Font,
                new Rectangle(Width - _valueW - (int)(u * 0.5F), padY, _valueW, _titleH + (int)(u * 0.2F)),
                CanWipe ? Theme.Accent : Theme.TextDim,
                TextFormatFlags.Right | TextFormatFlags.Top | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
        }
    }

    // ================================================================== //
    //  Строка «кто отправляет» на странице «Монитор»: имя программы,
    //  сколько соединений и кнопка запрета выхода в сеть — видно, кто
    //  стучится, и тут же можно закрыть ему дорогу.
    // ================================================================== //
    internal class NetAppRow : Control, IFilterable
    {
        public string FilterText { get { return _name + " " + AppPath; } }
        public readonly string AppPath;
        public bool Blocked;
        public event EventHandler ToggleBlock;

        private readonly string _name, _count;
        private bool _hover, _btnHover;
        private Rectangle _btnRect;
        private Font _bold;

        public NetAppRow(string name, string count, string path, bool blocked)
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            _name = name; _count = count; AppPath = path ?? ""; Blocked = blocked;
            BackColor = Theme.CardBg;
            SetStyle(ControlStyles.Selectable, HasButton);
            TabStop = HasButton;
        }

        private bool HasButton { get { return AppPath.Length > 0; } }

        protected override void OnFontChanged(EventArgs e)
        { base.OnFontChanged(e); _bold = new Font(Font, FontStyle.Bold); Height = (int)(Font.Height * 2.4F); }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; _btnHover = false; Invalidate(); }
        protected override void OnEnter(EventArgs e) { base.OnEnter(e); Invalidate(); }
        protected override void OnLeave(EventArgs e) { base.OnLeave(e); Invalidate(); }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            bool over = HasButton && _btnRect.Contains(e.Location);
            if (over != _btnHover) { _btnHover = over; Cursor = over ? Cursors.Hand : Cursors.Default; Invalidate(); }
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (!HasButton || !_btnRect.Contains(e.Location)) return;
            Focus();
            if (ToggleBlock != null) ToggleBlock(this, EventArgs.Empty);
        }

        // кнопку видно и с клавиатуры: Tab доводит до строки, пробел нажимает
        protected override bool IsInputKey(Keys keyData)
        {
            if (keyData == Keys.Space || keyData == Keys.Enter) return true;
            return base.IsInputKey(keyData);
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (!HasButton) return;
            if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter)
            { if (ToggleBlock != null) ToggleBlock(this, EventArgs.Empty); e.Handled = true; }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = Font.Height;
            if (_bold == null) _bold = new Font(Font, FontStyle.Bold);

            if (_hover)
            {
                using (GraphicsPath p = Theme.RoundRect(new RectangleF(0.5F, 0.5F, Width - 1, Height - 1), 6))
                using (SolidBrush b = new SolidBrush(Theme.RowHover)) g.FillPath(b, p);
            }
            if (Focused && HasButton)
            {
                using (GraphicsPath p = Theme.RoundRect(new RectangleF(0.5F, 0.5F, Width - 1, Height - 1), 6))
                using (Pen pen = new Pen(Theme.Accent)) g.DrawPath(pen, p);
            }

            int rightEdge = Width - (int)(u * 0.6F);

            // рамку под число берём с запасом: при точной ширине правое
            // выравнивание срезает первую цифру
            Size cs = TextRenderer.MeasureText(g, _count, Font, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
            int cw = cs.Width + (int)(u * 0.4F);
            TextRenderer.DrawText(g, _count, Font, new Rectangle(rightEdge - cw, 0, cw, Height),
                Theme.TextDim, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
            rightEdge -= cw + (int)(u * 0.6F);

            if (HasButton)
            {
                string cap = Blocked ? L.T("Заблокировано") : L.T("Запретить сеть");
                using (Font bf = new Font(Font.FontFamily, Font.Size * 0.9F, FontStyle.Regular))
                {
                    Size bs = TextRenderer.MeasureText(g, cap, bf, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
                    int bw = bs.Width + (int)(u * 1.1F), bh = (int)(u * 1.5F);
                    _btnRect = new Rectangle(rightEdge - bw, (Height - bh) / 2, bw, bh);
                    RectangleF br = new RectangleF(_btnRect.X + 0.5F, _btnRect.Y + 0.5F, _btnRect.Width - 1, _btnRect.Height - 1);
                    Color face = Blocked ? Theme.Mix(Theme.CardBg, Theme.Ok, 0.22F)
                                         : (_btnHover ? Theme.ButtonHover : Theme.ButtonBg);
                    Color edge = Blocked ? Theme.Ok : (_btnHover ? Theme.Accent : Theme.ButtonBorder);
                    using (GraphicsPath p = Theme.RoundRect(br, bh / 2F))
                    {
                        using (SolidBrush b = new SolidBrush(face)) g.FillPath(b, p);
                        using (Pen pen = new Pen(edge)) g.DrawPath(pen, p);
                    }
                    TextRenderer.DrawText(g, cap, bf, _btnRect, Blocked ? Theme.Ok : Theme.Text,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                    rightEdge -= bw + (int)(u * 0.5F);
                }
            }
            else _btnRect = Rectangle.Empty;

            int left = (int)(u * 0.6F);
            TextRenderer.DrawText(g, _name, _bold, new Rectangle(left, 0, Math.Max(20, rightEdge - left), Height),
                Theme.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter |
                            TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
        }
    }
}
