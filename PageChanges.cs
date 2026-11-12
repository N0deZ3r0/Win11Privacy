// Часть MainForm: страница «Изменения» — что программа поменяла и как вернуть.

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
        //  Страница: Изменения — что программа поменяла и как вернуть обратно
        // ================================================================== //
        private Control BuildChangesPage()
        {
            ModernButton refresh = new ModernButton(L.T("Обновить"), false);
            refresh.Click += delegate { RefreshChanges(); };
            _btnChangesBack = new ModernButton(L.T("Вернуть выбранные"), true);
            _btnChangesBack.Click += OnRestoreSelected;
            ModernButton all = new ModernButton(L.T("Вернуть всё"), false);
            all.Click += OnRestoreAll;
            ModernButton fromBackup = new ModernButton(L.T("Из резервной копии"), false);
            fromBackup.Click += OnRestoreFromBackup;
            Label state; StackPanel list; TextBox search;
            TableLayoutPanel page = ListPage(L.T("Что программа изменила"),
                L.T("Каждое изменение записано вместе с прежним значением. Любую строку\n") +
                L.T("можно вернуть по отдельности — система станет ровно такой, как была."),
                "changes", out state, out list, out search, refresh, _btnChangesBack, all, fromBackup);
            _changesState = state; _changesList = list;
            if (search != null) search.TextChanged += delegate { FilterList(_changesList, search.Text); };
            return page;
        }

        private void RefreshChanges()
        {
            RunJson("-ChangeLog", L.T("Чтение журнала изменений…"), RenderChanges);
        }

        private void RenderChanges(Dictionary<string, object> d)
        {
            _changesList.Controls.Clear();
            List<object> items = (d != null) ? Json.GetArr(d, "items") : new List<object>();
            // Журнал есть, но верить ему нельзя (подпись не сошлась или ключа
            // нет) — это не «программа ничего не меняла». Раньше страница
            // показывала тут пустой журнал.
            if (d != null && d.ContainsKey("trusted") && !Json.GetBool(d, "trusted"))
            {
                SectionHeader su = new SectionHeader(L.T("Журналу изменений нельзя верить"));
                su.Font = Font; _changesList.Controls.Add(su);
                _changesList.Restack();
                _changesState.Text = L.T("Подпись журнала не сошлась или ключа подписи нет: его могли изменить. По нему ничего не возвращается.\n") +
                                     L.T("Файл не удалён — при следующем изменении он будет отложен рядом. Запасной путь — резервная копия реестра или точка восстановления Windows.");
                if (_btnChangesBack != null) _btnChangesBack.Enabled = false;
                return;
            }
            if (items.Count == 0)
            {
                SectionHeader sh = new SectionHeader(L.T("Программа ещё ничего не меняла"));
                sh.Font = Font; _changesList.Controls.Add(sh);
                _changesList.Restack();
                _changesState.Text = L.T("Журнал пуст: настройки ещё не применялись.\n") +
                                     L.T("После применения здесь появится каждое изменение с прежним значением.");
                if (_btnChangesBack != null) _btnChangesBack.Enabled = false;
                return;
            }
            if (_btnChangesBack != null) _btnChangesBack.Enabled = true;
            SectionHeader head = new SectionHeader(L.T("Свежие изменения сверху"));
            head.Font = Font; _changesList.Controls.Add(head);
            foreach (object o in items)
            {
                Dictionary<string, object> it = Json.Obj(o);
                // движок отдаёт эти поля словами, а не числами: «запускалась»,
                // «не было», «автозагрузка» — их тоже надо переводить
                string was = L.T(Json.GetStr(it, "was")), now = L.T(Json.GetStr(it, "now"));
                string what = L.T("было: ") + was + L.T("   ·   стало: ") + now + "   ·   " + L.T(Json.GetStr(it, "where"));
                WipeRow r = new WipeRow(Json.GetStr(it, "id"), L.T(Json.GetStr(it, "title")), what,
                                        Json.GetStr(it, "time").Replace("T", " "),
                                        Json.GetStr(it, "kind") == "startup" ? GPower : GUndo, true);
                r.Font = Font;
                _changesList.Controls.Add(r);
            }
            _changesList.Restack();
            _changesState.Text = L.T("Записей в журнале: ") + items.Count + L.T(", изменений всего: ") + Json.GetInt(d, "raw") + ".\n" +
                                 L.T("Отметьте строки и нажмите «Вернуть выбранные» — вернётся то значение, что было до программы.");
        }

        private void OnRestoreSelected(object sender, EventArgs e)
        {
            List<string> ids = CheckedIds(_changesList);
            if (ids.Count == 0)
            {
                MessageBox.Show(this, L.T("Отметьте галочками, что вернуть."), L.T("Ничего не выбрано"),
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            if (MessageBox.Show(this, L.T("Будет возвращено изменений: ") + ids.Count + ".\n\n" +
                L.T("Каждый параметр вернётся в то значение, которое было до программы,\n") +
                L.T("и пропадёт из журнала.\n\nПродолжить?"),
                L.T("Возврат изменений"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            RunStreaming("-RestoreItems -ChangeItems \"" + string.Join(",", ids.ToArray()) + "\"",
                L.T("Возврат выбранных изменений…"), delegate { Navigate("changes"); RefreshChanges(); });
        }

        // Копии .reg программа делала и раньше, но импортировать их приходилось
        // руками. Теперь круг замкнут прямо из окна.
        private void OnRestoreFromBackup(object sender, EventArgs e)
        {
            RunJson("-ListBackups", L.T("Поиск резервных копий…"), delegate(Dictionary<string, object> d)
            {
                List<object> items = (d != null) ? Json.GetArr(d, "items") : new List<object>();
                if (items.Count == 0)
                {
                    MessageBox.Show(this, L.T("Резервных копий не найдено.\n\n") +
                        L.T("Программа создаёт их на рабочем столе перед первым изменением\n") +
                        L.T("в каждом запуске. Если папку перенесли — верните её на место."),
                        L.T("Восстановление из копии"), MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                string[] lines = new string[items.Count];
                string[] paths = new string[items.Count];
                for (int i = 0; i < items.Count; i++)
                {
                    Dictionary<string, object> b = Json.Obj(items[i]);
                    paths[i] = Json.GetStr(b, "path");
                    lines[i] = Json.GetStr(b, "when") + "   ·   " + Json.GetInt(b, "branches") + L.T(" веток") +
                               "   ·   " + Json.GetStr(b, "kb") + L.T(" КБ");
                }
                using (ListDialog dlg = new ListDialog(L.T("Восстановление из копии"),
                    L.T("Выберите копию — её значения вернутся в реестр как были на тот момент."),
                    lines, L.T("Восстановить"), Font, true))
                {
                    if (dlg.ShowDialog(this) != DialogResult.OK) return;
                    int idx = dlg.SelectedIndex;
                    if (idx < 0 || idx >= paths.Length) return;
                    if (MessageBox.Show(this, L.T("Из копии будут возвращены все сохранённые ветки реестра:\n\n") +
                        paths[idx] + L.T("\n\nТекущие значения этих параметров будут заменены.\n\nПродолжить?"),
                        L.T("Восстановление из копии"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
                    RunStreaming("-RestoreBackup -BackupPath \"" + paths[idx] + "\"",
                        L.T("Восстановление из копии…"), delegate { Navigate("changes"); RefreshChanges(); });
                }
            });
        }

        private void OnRestoreAll(object sender, EventArgs e)
        {
            if (MessageBox.Show(this, L.T("Программа вернёт все параметры реестра и записи автозапуска\n") +
                L.T("в то состояние, в котором они были до неё, и очистит журнал.\n\nПродолжить?"),
                L.T("Возврат изменений"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming("-RestoreAll", L.T("Возврат всех изменений…"), delegate { Navigate("changes"); RefreshChanges(); });
        }
    }
}
