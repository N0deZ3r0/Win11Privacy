// Графики и плитки: кольцо индекса, диаграммы, датчики, хронология.

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
                    L.T("Включите «Следить за датчиками» на странице «Автозащита» —\n") +
                    L.T("она будет пополняться сама."),
                    Font, ClientRectangle, Theme.TextDim,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
                return;
            }

            // легенда
            int lx = Width - (int)(u * 0.3F);
            string[] names = { L.T("Другое"), L.T("Гео"), L.T("Микрофон"), L.T("Камера") };
            // оттенки одного акцента: камера — самый насыщенный, «другое» — серый
            Color[] cols = { Theme.Mix(Theme.TextFaint, Theme.CardBg, 0.35F), Theme.Mix(Theme.Accent, Theme.CardBg, 0.62F),
                             Theme.Mix(Theme.Accent, Theme.CardBg, 0.32F), Theme.Accent };
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

    // ================================================================== //
    //  График хронологии: столбики событий телеметрии по дням, отметки
    //  обновлений Windows, правок программы и срабатываний стража.
    //  Здесь видно то, чего не видно в моменте: как система отыгрывает
    //  настройки назад после очередного обновления.
    // ================================================================== //
    internal class TimelineChart : Control
    {
        private class Day
        {
            public string Label, Date;
            public int Events, Sensors, Changes, Drifted, Fixed;
            public string Updates = "";
        }
        private readonly List<Day> _days = new List<Day>();
        private readonly Tween _grow = new Tween(0.12F);
        private int _hover = -1;

        public TimelineChart()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            _grow.Changed += delegate { Invalidate(); };
        }

        public string Empty = "";

        public void SetData(List<object> days)
        {
            _days.Clear();
            if (days != null)
                foreach (object o in days)
                {
                    Dictionary<string, object> d = Json.Obj(o);
                    if (d == null) continue;
                    Day day = new Day();
                    day.Label = Json.GetStr(d, "label");
                    day.Date = Json.GetStr(d, "date");
                    day.Events = Json.GetInt(d, "events");
                    day.Sensors = Json.GetInt(d, "sensors");
                    day.Changes = Json.GetInt(d, "changes");
                    day.Drifted = Json.GetInt(d, "drifted");
                    day.Fixed = Json.GetInt(d, "fixed");
                    List<object> ups = Json.GetArr(d, "updates");
                    string[] arr = new string[ups.Count];
                    for (int i = 0; i < ups.Count; i++) arr[i] = ups[i] == null ? "" : ups[i].ToString();
                    day.Updates = string.Join(", ", arr);
                    _days.Add(day);
                }
            _grow.To(0F, false);
            _grow.To(1F, IsHandleCreated && Visible);
            Invalidate();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            int idx = IndexAt(e.X);
            if (idx != _hover) { _hover = idx; Invalidate(); }
        }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = -1; Invalidate(); }

        private int _plotLeft, _plotWidth;
        private int IndexAt(int x)
        {
            if (_days.Count == 0 || _plotWidth <= 0) return -1;
            float step = (float)_plotWidth / _days.Count;
            int i = (int)((x - _plotLeft) / step);
            return (i >= 0 && i < _days.Count) ? i : -1;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            int u = Font.Height;
            if (Width < 80 || Height < 60) return;

            int maxEv = 0, maxSens = 0;
            foreach (Day d in _days) { if (d.Events > maxEv) maxEv = d.Events; if (d.Sensors > maxSens) maxSens = d.Sensors; }
            bool useEvents = maxEv > 0;
            int max = useEvents ? maxEv : maxSens;

            if (_days.Count == 0 || max == 0)
            {
                TextRenderer.DrawText(g, Empty.Length > 0 ? Empty : L.T("Данных пока нет"), Font, ClientRectangle,
                    Theme.TextFaint, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
                                     TextFormatFlags.WordBreak);
                return;
            }

            int padL = (int)(u * 2.6F), padR = (int)(u * 0.6F);
            int padT = (int)(u * 1.4F), padB = (int)(u * 2.2F);
            _plotLeft = padL; _plotWidth = Math.Max(10, Width - padL - padR);
            int plotH = Math.Max(10, Height - padT - padB);
            float step = (float)_plotWidth / _days.Count;
            float barW = Math.Max(2F, step * 0.62F);

            // сетка и подписи шкалы
            using (Pen grid = new Pen(Theme.Mix(Theme.CardBg, Theme.Text, 0.10F)))
            using (Font small = new Font(Font.FontFamily, Font.Size * 0.82F))
            {
                for (int s = 0; s <= 2; s++)
                {
                    int y = padT + plotH - (int)(plotH * s / 2.0);
                    g.DrawLine(grid, padL, y, padL + _plotWidth, y);
                    string lbl = FormatShort((int)Math.Round(max * s / 2.0));
                    TextRenderer.DrawText(g, lbl, small, new Rectangle(0, y - u / 2, padL - (int)(u * 0.3F), u),
                        Theme.TextFaint, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                }
            }

            Color barColor = useEvents ? Theme.Accent : Theme.Warn;
            for (int i = 0; i < _days.Count; i++)
            {
                Day d = _days[i];
                int val = useEvents ? d.Events : d.Sensors;
                float x = padL + step * i + (step - barW) / 2F;
                if (val > 0)
                {
                    float h = plotH * (val / (float)max) * _grow.Value;
                    if (h < 2) h = 2;
                    RectangleF r = new RectangleF(x, padT + plotH - h, barW, h);
                    using (GraphicsPath p = Theme.RoundRect(r, Math.Min(3F, barW / 2F)))
                    using (SolidBrush b = new SolidBrush(i == _hover ? Theme.AccentHover : barColor))
                        g.FillPath(b, p);
                }
                // отметка обновления Windows — вертикальная черта во всю высоту
                if (d.Updates.Length > 0)
                {
                    using (Pen up = new Pen(Theme.Mix(Theme.CardBg, Theme.Err, 0.75F), 1.5F))
                        g.DrawLine(up, x + barW / 2F, padT - (int)(u * 0.4F), x + barW / 2F, padT + plotH);
                    using (SolidBrush b = new SolidBrush(Theme.Err))
                        g.FillEllipse(b, x + barW / 2F - 3F, padT - (int)(u * 0.7F), 6F, 6F);
                }
                // программа что-то меняла / страж что-то возвращал
                if (d.Changes > 0)
                    using (SolidBrush b = new SolidBrush(Theme.Ok))
                        g.FillEllipse(b, x + barW / 2F - 3F, padT + plotH + (int)(u * 0.25F), 6F, 6F);
                if (d.Drifted > 0)
                    using (SolidBrush b = new SolidBrush(Theme.Warn))
                        g.FillEllipse(b, x + barW / 2F - 3F, padT + plotH + (int)(u * 0.95F), 6F, 6F);
            }

            // подписи дат — только те, что помещаются
            using (Font small = new Font(Font.FontFamily, Font.Size * 0.8F))
            {
                int everyN = Math.Max(1, (int)Math.Ceiling((u * 2.6F) / Math.Max(1F, step)));
                for (int i = 0; i < _days.Count; i += everyN)
                {
                    float x = padL + step * i;
                    TextRenderer.DrawText(g, _days[i].Label, small,
                        new Rectangle((int)x - (int)(step / 2), Height - (int)(u * 1.1F), (int)(step * 2), u),
                        Theme.TextFaint, TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding);
                }
            }

            // всплывающая подсказка по дню под курсором
            if (_hover >= 0 && _hover < _days.Count)
            {
                Day d = _days[_hover];
                List<string> parts = new List<string>();
                parts.Add(d.Date);
                if (d.Events > 0) parts.Add(L.T("событий: ") + d.Events);
                if (d.Sensors > 0) parts.Add(L.T("датчики: ") + d.Sensors);
                if (d.Changes > 0) parts.Add(L.T("правок: ") + d.Changes);
                if (d.Drifted > 0) parts.Add(L.T("сбито: ") + d.Drifted);
                if (d.Updates.Length > 0) parts.Add(L.T("обновление ") + d.Updates);
                string tip = string.Join("   ·   ", parts.ToArray());
                using (Font small = new Font(Font.FontFamily, Font.Size * 0.85F))
                {
                    Size ts = TextRenderer.MeasureText(g, tip, small, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
                    int tw = ts.Width + (int)(u * 0.8F), th = (int)(u * 1.5F);
                    int tx = Math.Max(2, Math.Min(Width - tw - 2, (int)(padL + step * _hover) - tw / 2));
                    RectangleF tr = new RectangleF(tx, 0, tw, th);
                    using (GraphicsPath p = Theme.RoundRect(tr, 6))
                    using (SolidBrush b = new SolidBrush(Theme.Mix(Theme.CardBg, Theme.Text, 0.14F))) g.FillPath(b, p);
                    TextRenderer.DrawText(g, tip, small, Rectangle.Round(tr), Theme.Text,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                }
            }
        }

        private static string FormatShort(int v)
        {
            if (v >= 1000000) return (v / 1000000.0).ToString("0.#") + L.T(" млн");
            if (v >= 1000) return (v / 1000.0).ToString("0.#") + L.T(" тыс");
            return v.ToString();
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
}
