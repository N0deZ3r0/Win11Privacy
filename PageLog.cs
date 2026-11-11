// Часть MainForm: страница «Журнал» и вывод в него.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Windows.Forms;

namespace Win11Privacy
{
    public partial class MainForm : Form
    {
        // ================================================================== //
        //  Страница: Журнал
        // ================================================================== //
        private Control BuildLogPage()
        {
            int u = Font.Height;
            TableLayoutPanel page = new TableLayoutPanel();
            page.ColumnCount = 1; page.RowCount = 2;
            page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));   // иначе страница растёт под самую широкую строку
            page.BackColor = Theme.WindowBg;
            page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            page.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            // Заголовок с кнопкой: по этим журналам находились прошлые ошибки,
            // но выгрузить их можно было только выделением мышью.
            TableLayoutPanel head = new TableLayoutPanel();
            head.ColumnCount = 2; head.RowCount = 1; head.AutoSize = true;
            head.BackColor = Theme.WindowBg; head.Dock = DockStyle.Fill;
            head.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            head.Controls.Add(PageTitle(L.T("Журнал")), 0, 0);

            FlowLayoutPanel logBtns = new FlowLayoutPanel();
            logBtns.AutoSize = true; logBtns.WrapContents = false;
            logBtns.Anchor = AnchorStyles.Right | AnchorStyles.Bottom;
            logBtns.Margin = new Padding(0, 0, 0, (int)(u * 0.45F));
            ModernButton logSave = new ModernButton(L.T("Сохранить журнал"), false);
            logSave.Font = Font; logSave.Margin = new Padding(0, 0, (int)(u * 0.4F), 0);
            logSave.Click += delegate { SaveLogToFile(); };
            ModernButton logClear = new ModernButton(L.T("Очистить"), false);
            logClear.Font = Font; logClear.Margin = new Padding(0);
            logClear.Click += delegate { if (_log != null) { _log.Clear(); UpdateLogEmpty(); } };
            logBtns.Controls.Add(logSave); logBtns.Controls.Add(logClear);
            head.Controls.Add(logBtns, 1, 0);
            WrapHeadButtons(head, logBtns);
            page.Controls.Add(head, 0, 0);

            // Фон карточки — как у самого журнала: раньше тёмное поле сидело
            // в более светлой рамке, и выходила двойная обводка.
            Card card = new Card(); card.Dock = DockStyle.Fill; card.Padding = new Padding((int)(u*0.6F));
            card.Margin = new Padding(0,(int)(u*0.5F),0,(int)(u*0.3F));
            card.BackColor = Theme.LogBg;
            _log = new RichTextBox();
            _log.Dock = DockStyle.Fill; _log.ReadOnly = true; _log.BorderStyle = BorderStyle.None;
            _log.BackColor = Theme.LogBg; _log.ForeColor = Theme.TextDim;
            _log.Font = Theme.PickFont(Theme.MonoFonts, Font.Size * 0.92F, FontStyle.Regular);
            _log.WordWrap = true; _log.ScrollBars = RichTextBoxScrollBars.Vertical; _log.DetectUrls = false;
            _log.TextChanged += delegate { UpdateLogEmpty(); };
            Dwm.DarkScrollbars(_log);
            card.Controls.Add(_log);

            // Пока в журнале ничего нет — пояснение, а не «вывод»: подсказка
            // больше не попадает в сохранённый файл и не мешает понять, что
            // журнал пуст.
            _logEmpty = new EmptyState();
            _logEmpty.Dock = DockStyle.Fill;
            _logEmpty.Font = Font;
            _logEmpty.BackColor = Theme.LogBg;
            _logEmpty.Glyph = "";
            _logEmpty.Title = L.T("Журнал пока пуст");
            _logEmpty.Note = L.T("Здесь по шагам видно, что программа делает: применение и откат настроек, работа автозащиты и наблюдения за сетью. Если что-то пошло не так, сохраните журнал и приложите его к сообщению об ошибке.");
            card.Controls.Add(_logEmpty);
            _logEmpty.BringToFront();
            page.Controls.Add(card, 0, 1);
            return page;
        }

        private EmptyState _logEmpty;

        private void UpdateLogEmpty()
        {
            if (_logEmpty == null || _log == null) return;
            bool empty = _log.TextLength == 0;
            if (_logEmpty.Visible != empty) _logEmpty.Visible = empty;
        }

        // Журнал выгружается в файл целиком: именно по нему разбираются
        // случаи «применилось не то» — присылать снимок экрана неудобно.
        private void SaveLogToFile()
        {
            if (_log == null || _log.TextLength == 0)
            {
                MessageBox.Show(this, L.T("Журнал пока пуст."), L.T("Сохранение журнала"),
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            string path;
            using (SaveFileDialog d = new SaveFileDialog())
            {
                d.Filter = L.T("Текстовый файл (*.txt)|*.txt");
                d.FileName = "win11privacy-log-" + DateTime.Now.ToString("yyyy-MM-dd-HHmm") + ".txt";
                if (d.ShowDialog(this) != DialogResult.OK) return;
                path = d.FileName;
            }
            try
            {
                StringBuilder sb = new StringBuilder();
                sb.AppendLine(L.T("Приватность Windows 11, версия ") + AppInfo.Version);
                sb.AppendLine(Environment.OSVersion.VersionString + (Environment.Is64BitOperatingSystem ? " x64" : " x86"));
                sb.AppendLine(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
                sb.AppendLine(new string('-', 60));
                sb.AppendLine(_log.Text);
                File.WriteAllText(path, sb.ToString(), new UTF8Encoding(true));
                _status.Text = L.T("Журнал сохранён: ") + Path.GetFileName(path);
            }
            catch (Exception ex)
            { MessageBox.Show(this, ex.Message, L.T("Ошибка"), MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }

        // ================================================================== //
        //  Журнал
        // ================================================================== //
        private void LogLine(string s, Color c)
        {
            if (_log == null) return;
            _log.SelectionStart = _log.TextLength; _log.SelectionLength = 0; _log.SelectionColor = c;
            _log.AppendText(s + Environment.NewLine); _log.SelectionColor = _log.ForeColor;
        }
        private void LogEngine(string s)
        {
            string t = s.TrimStart();
            if (t.StartsWith("###JSON###")) return;
            Color c = Theme.TextDim;
            if (t.StartsWith("[+]")) c = Theme.Ok;
            else if (t.StartsWith("[!]")) c = Theme.Err;
            else if (t.StartsWith("[-]")) c = Theme.TextFaint;
            else if (t.StartsWith("---")) c = Theme.Accent;
            else if (t.StartsWith(L.T("Система")) || t.StartsWith(L.T("ИТОГО")) || t.StartsWith(L.T("Изменений")) || t.StartsWith(L.T("Ошибок")) || t.StartsWith(L.T("Модули"))) c = Theme.Text;
            LogLine(s, c);
            _log.SelectionStart = _log.TextLength; _log.ScrollToCaret();
        }
    }
}
