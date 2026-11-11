// Строки списков и сами списки: настройки, проверка, досье, сеть, обзор.

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
    // Строка списка, которую можно отфильтровать поиском по странице
    internal interface IFilterable { string FilterText { get; } }

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
            TextRenderer.DrawText(g, _app, Theme.Bold(Font),
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

        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); _bold = Theme.Bold(Font); Relayout(); }
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
                if (_bold == null) _bold = Theme.Bold(Font);
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
                        float cy = by + box * 0.55F;
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
        { base.OnFontChanged(e); _bold = Theme.Bold(Font); Height = (int)(Font.Height * 2.4F); }
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
            if (_bold == null) _bold = Theme.Bold(Font);

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
}
