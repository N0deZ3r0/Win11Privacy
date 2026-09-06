using System;
using System.Drawing;
using System.Windows.Forms;

namespace Win11Privacy
{
    // ====================================================================== //
    //  Первый запуск. Раньше человек сразу получал тринадцать разделов и сам
    //  догадывался, с чего начать. Теперь — один вопрос и три ответа; всё
    //  остальное никуда не делось и доступно сразу после.
    //
    //  Мастер ничего не применяет сам: он только отмечает нужный набор и
    //  открывает страницу, где видно, что именно будет сделано. Программа,
    //  которая правит систему, не должна что-то менять до нажатия «Применить».
    // ====================================================================== //
    internal enum WelcomeChoice { Skip, Basic, Strict, LookFirst }

    internal sealed class WelcomeForm : Form
    {
        internal WelcomeChoice Choice = WelcomeChoice.Skip;

        internal WelcomeForm(Font baseFont, Image logo)
        {
            Font = baseFont;
            int u = Font.Height;
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterParent;
            BackColor = Theme.WindowBg;
            ForeColor = Theme.Text;
            ShowInTaskbar = false;
            KeyPreview = true;
            ClientSize = new Size((int)(u * 40), (int)(u * 27));
            DoubleBuffered = true;

            TableLayoutPanel root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.BackColor = Theme.WindowBg;
            root.ColumnCount = 1; root.RowCount = 3;
            root.Padding = new Padding((int)(u * 1.6F), (int)(u * 1.4F), (int)(u * 1.6F), (int)(u * 1.1F));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.AutoSize = true; root.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            _root = root;
            Controls.Add(root);

            // --- заголовок ---------------------------------------------------
            FlowLayoutPanel head = new FlowLayoutPanel();
            head.FlowDirection = FlowDirection.TopDown; head.WrapContents = false;
            head.AutoSize = true; head.Margin = new Padding(0, 0, 0, (int)(u * 0.9F));
            head.BackColor = Theme.WindowBg;

            Label title = new Label();
            title.Text = L.T("С чего начнём?");
            title.Font = Theme.PickFont(new[] { "Segoe UI Variable Display", "Segoe UI", "Tahoma" }, Font.Size * 1.8F, FontStyle.Bold);
            title.ForeColor = Theme.Text; title.AutoSize = true; title.Margin = new Padding(0, 0, 0, (int)(u * 0.2F));

            Label sub = new Label();
            sub.Text = L.T("Программа отключает сбор данных Microsoft и показывает, что о вас уже собрано.\n") +
                       L.T("Выбор ниже ничего не меняет сразу — он только отмечает нужное и показывает, что будет сделано.");
            sub.ForeColor = Theme.TextDim; sub.AutoSize = true; sub.Margin = new Padding(1, 0, 0, 0);

            head.Controls.Add(title); head.Controls.Add(sub);
            root.Controls.Add(head, 0, 0);

            // --- три ответа --------------------------------------------------
            FlowLayoutPanel list = new FlowLayoutPanel();
            list.FlowDirection = FlowDirection.TopDown; list.WrapContents = false;
            list.Dock = DockStyle.Fill;
            list.AutoSize = true; list.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            list.BackColor = Theme.WindowBg;
            list.Margin = new Padding(0);

            int cardW = ClientSize.Width - (int)(u * 3.4F);
            list.Controls.Add(MakeChoice(cardW, WelcomeChoice.Basic,
                L.T("Базовая приватность"),
                L.T("Телеметрия, рекламный идентификатор, история действий, реклама в системе, Copilot.\n") +
                L.T("Ничего из того, чем вы пользуетесь, не ломает. Подходит большинству.")));
            list.Controls.Add(MakeChoice(cardW, WelcomeChoice.Strict,
                L.T("Строгая настройка"),
                L.T("То же плюс службы сбора данных, домены телеметрии, геолокация, виджеты и OneDrive.\n") +
                L.T("Некоторые удобства Windows перестанут работать — это осознанный размен.")));
            list.Controls.Add(MakeChoice(cardW, WelcomeChoice.LookFirst,
                L.T("Сначала посмотреть, что обо мне собрано"),
                L.T("Ничего не меняем: программа прочитает реальное состояние системы и покажет индекс,\n") +
                L.T("а на «Досье» и «Рентгене» — что Windows уже знает об этом компьютере.")));
            root.Controls.Add(list, 0, 1);

            // --- пропустить ---------------------------------------------------
            FlowLayoutPanel foot = new FlowLayoutPanel();
            foot.FlowDirection = FlowDirection.RightToLeft; foot.WrapContents = false;
            foot.AutoSize = true; foot.Dock = DockStyle.Fill;
            foot.BackColor = Theme.WindowBg;
            foot.Margin = new Padding(0, (int)(u * 0.7F), 0, 0);
            ModernButton skip = new ModernButton(L.T("Разберусь сам"), false);
            skip.Ghost = true; skip.Font = Font; skip.Fit();
            skip.Click += delegate { Choice = WelcomeChoice.Skip; DialogResult = DialogResult.Cancel; Close(); };
            foot.Controls.Add(skip);
            root.Controls.Add(foot, 0, 2);

            KeyDown += delegate(object s, KeyEventArgs e)
            { if (e.KeyCode == Keys.Escape) { Choice = WelcomeChoice.Skip; DialogResult = DialogResult.Cancel; Close(); } };
        }

        private TableLayoutPanel _root;

        // Высота — по содержимому: при 150 % масштабе и в английском переводе
        // текст занимает больше строк, и заранее заданное окно резало третий
        // вариант ответа.
        protected override void OnLoad(EventArgs e)
        {
            base.OnLoad(e);
            try
            {
                int need = _root.PreferredSize.Height;
                int max = (int)(Screen.PrimaryScreen.WorkingArea.Height * 0.92F);
                ClientSize = new Size(ClientSize.Width, Math.Min(max, Math.Max((int)(Font.Height * 20), need)));
                CenterToParent();
            }
            catch { }
        }

        private Control MakeChoice(int width, WelcomeChoice choice, string title, string body)
        {
            int u = Font.Height;
            Card c = new Card();
            // ширину держим сами, автоподбор оставляем только высоте: иначе
            // карточки получаются разной длины — по длине своего текста
            c.MinimumSize = new Size(width, 0);
            c.MaximumSize = new Size(width, 0);
            c.AutoSize = true; c.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            c.Margin = new Padding(0, 0, 0, (int)(u * 0.6F));
            // нижний отступ карточка добирает сама: содержимое смещено на
            // Padding.Top, и автоподбор высоты прибавляет его ещё раз
            c.Padding = new Padding((int)(u * 0.9F), (int)(u * 0.7F), (int)(u * 0.9F), 0);
            c.Cursor = Cursors.Hand;

            FlowLayoutPanel col = new FlowLayoutPanel();
            col.FlowDirection = FlowDirection.TopDown; col.WrapContents = false;
            col.AutoSize = true; col.BackColor = Theme.CardBg;
            col.Location = new Point((int)(u * 0.9F), (int)(u * 0.7F));
            col.Margin = new Padding(0);

            Label t = new Label();
            t.Text = title; t.Font = new Font(Font, FontStyle.Bold); t.ForeColor = Theme.Text;
            t.AutoSize = true; t.Margin = new Padding(0, 0, 0, (int)(u * 0.25F));
            Label b = new Label();
            b.Text = body; b.ForeColor = Theme.TextDim; b.AutoSize = true; b.Margin = new Padding(0);
            b.MaximumSize = new Size(width - (int)(u * 2.0F), 0);      // длинная строка переносится, а не режется
            col.Controls.Add(t); col.Controls.Add(b);
            c.Controls.Add(col);

            EventHandler pick = delegate { Choice = choice; DialogResult = DialogResult.OK; Close(); };
            c.Click += pick; t.Click += pick; b.Click += pick; col.Click += pick;
            foreach (Control cc in new Control[] { t, b, col }) cc.Cursor = Cursors.Hand;
            return c;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            using (Pen p = new Pen(Theme.CardBorder))
                e.Graphics.DrawRectangle(p, 0, 0, ClientSize.Width - 1, ClientSize.Height - 1);
        }
    }
}
