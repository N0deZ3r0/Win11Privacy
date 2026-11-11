// Часть MainForm: страницы «Приложения» и «Автозагрузка».

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
        //  Страница: Приложения — удаление предустановленного
        // ================================================================== //
        private Control BuildAppsPage()
        {
            ModernButton refresh = new ModernButton(L.T("Обновить список"), false);
            refresh.Click += delegate { RefreshApps(); };
            ModernButton pick = new ModernButton(L.T("Отметить лишнее"), false);
            pick.Click += delegate { SelectBloat(); };
            _btnAppsRemove = new ModernButton(L.T("Удалить выбранные"), true);
            _btnAppsRemove.Click += OnRemoveApps;
            Label state; StackPanel list; TextBox search;
            TableLayoutPanel page = ListPage(L.T("Предустановленные приложения"),
                L.T("Приложения, которые Windows ставит без спроса. Отмеченные «можно убрать» —\n") +
                L.T("проверенный список; системные компоненты в перечень не попадают вовсе."),
                "apps", out state, out list, out search, refresh, pick, _btnAppsRemove);
            _appsState = state; _appsList = list;
            if (search != null) search.TextChanged += delegate { FilterList(_appsList, search.Text); };
            return page;
        }

        private void RefreshApps()
        {
            RunJson("-ListApps", L.T("Чтение списка приложений…"), RenderApps);
        }

        private void RenderApps(Dictionary<string, object> d)
        {
            _appsList.Controls.Clear();
            if (d == null)
            {
                SectionHeader sh = new SectionHeader(L.T("Не удалось получить список")); sh.Font = Font;
                _appsList.Controls.Add(sh); _appsList.Restack(); return;
            }
            _lastApps = d;
            List<object> apps = Json.GetArr(d, "apps");
            int bloat = 0;
            bool headBloat = false, headRest = false;
            foreach (object o in apps)
            {
                Dictionary<string, object> a = Json.Obj(o);
                bool isBloat = Json.GetBool(a, "bloat");
                if (isBloat && !headBloat)
                {
                    SectionHeader sh = new SectionHeader(L.T("Можно убрать — ставится без спроса"));
                    sh.Font = Font; _appsList.Controls.Add(sh); headBloat = true;
                }
                if (!isBloat && !headRest)
                {
                    SectionHeader sh = new SectionHeader(L.T("Остальное — удаляйте, только если знаете, что это"));
                    sh.Font = Font; _appsList.Controls.Add(sh); headRest = true;
                }
                if (isBloat) bloat++;
                WipeRow r = new WipeRow(Json.GetStr(a, "name"), L.T(Json.GetStr(a, "title")),
                    Json.GetStr(a, "name") + "   ·   " + Json.GetStr(a, "publisher"),
                    isBloat ? L.T("можно убрать") : "", GApp, true);
                r.Font = Font;
                _appsList.Controls.Add(r);
            }
            _appsList.Restack();
            _appsState.Text = L.T("Найдено приложений: ") + apps.Count + L.T(", из них лишних: ") + bloat + ".\n" +
                              L.T("Любое удалённое можно вернуть из Microsoft Store.");
        }

        private void SelectBloat() { CheckSection(_appsList, L.T("Можно убрать — ставится без спроса")); }

        private void OnRemoveApps(object sender, EventArgs e)
        {
            List<string> ids = CheckedIds(_appsList);
            if (ids.Count == 0)
            { MessageBox.Show(this, L.T("Отметьте галочками, какие приложения удалить."), L.T("Ничего не выбрано"), MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            if (MessageBox.Show(this, L.T("Будет удалено приложений: ") + ids.Count + ".\n\n" +
                L.T("Любое из них можно вернуть из Microsoft Store. Системные компоненты\n") +
                L.T("программа не трогает.\n\nПродолжить?"),
                L.T("Удаление приложений"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming("-RemoveApps -AppItems " + string.Join(",", ids.ToArray()) + " -AllUsers",
                L.T("Удаление приложений…"), delegate { Navigate("apps"); RefreshApps(); });
        }

        // ================================================================== //
        //  Страница: Автозапуск
        //  Что стартует вместе с Windows. Отключается ровно так же, как в
        //  диспетчере задач — отметкой, а не удалением: включить обратно
        //  можно той же кнопкой, и всё это попадает в журнал отката.
        // ================================================================== //
        private Control BuildStartupPage()
        {
            ModernButton refresh = new ModernButton(L.T("Обновить список"), false);
            refresh.Click += delegate { RefreshStartup(); };
            ModernButton pick = new ModernButton(L.T("Отметить лишнее"), false);
            pick.Click += delegate { SelectStartupBloat(); };
            _btnStartupOff = new ModernButton(L.T("Отключить выбранные"), true);
            _btnStartupOff.Click += delegate { SetStartupSelected(false); };
            _btnStartupOn = new ModernButton(L.T("Вернуть выбранные"), false);
            _btnStartupOn.Click += delegate { SetStartupSelected(true); };
            Label state; StackPanel list; TextBox search;
            TableLayoutPanel page = ListPage(L.T("Что стартует вместе с Windows"),
                L.T("Обновляторы, агенты телеметрии и помощники производителя запускаются при\n") +
                L.T("каждом входе. Отключение обратимо: запись остаётся на месте, просто гасится."),
                "startup", out state, out list, out search, refresh, pick, _btnStartupOff, _btnStartupOn);
            _startupState = state; _startupList = list;
            if (search != null) search.TextChanged += delegate { FilterList(_startupList, search.Text); };
            return page;
        }

        private void RefreshStartup()
        {
            RunJson("-ListStartup", L.T("Чтение автозагрузки…"), RenderStartup);
        }

        private void RenderStartup(Dictionary<string, object> d)
        {
            _lastStartup = d;
            _startupList.Controls.Clear();
            if (d == null)
            {
                SectionHeader sh = new SectionHeader(L.T("Не удалось прочитать автозагрузку")); sh.Font = Font;
                _startupList.Controls.Add(sh); _startupList.Restack(); return;
            }
            List<object> items = Json.GetArr(d, "items");
            // три группы: лишнее, остальное работающее, уже погашенное
            string[] heads = new string[] {
                L.T("Стартует без нужды — можно отключить"),
                L.T("Остальное — отключайте, только если знаете, что это"),
                L.T("Уже отключено")
            };
            for (int pass = 0; pass < 3; pass++)
            {
                bool head = false;
                foreach (object o in items)
                {
                    Dictionary<string, object> a = Json.Obj(o);
                    bool on = Json.GetBool(a, "enabled");
                    bool advise = Json.GetBool(a, "advise");
                    int group = !on ? 2 : (advise ? 0 : 1);
                    if (group != pass) continue;
                    if (!head)
                    {
                        SectionHeader sh = new SectionHeader(heads[pass]);
                        sh.Font = Font; _startupList.Controls.Add(sh); head = true;
                    }
                    string name = Json.GetStr(a, "name");
                    string pub = Json.GetStr(a, "publisher");
                    string note = L.T(Json.GetStr(a, "note"));
                    string cmd = Json.GetStr(a, "cmd");
                    string what = (note.Length > 0 ? note : cmd);
                    if (what.Length == 0) what = cmd;
                    string chip = !on ? L.T("отключено")
                                : (Json.GetBool(a, "keep") ? L.T("лучше не трогать") : (advise ? L.T("лишнее") : ""));
                    WipeRow r = new WipeRow(Json.GetStr(a, "id"),
                        pub.Length > 0 ? name + "   ·   " + pub : name,
                        what + "   ·   " + L.T(Json.GetStr(a, "source")),
                        chip, GPower, true);
                    r.Font = Font;
                    _startupList.Controls.Add(r);
                }
            }
            _startupList.Restack();
            int total = Json.GetInt(d, "total"), onCount = Json.GetInt(d, "on"), bad = Json.GetInt(d, "advise");
            _startupState.Text = L.T("Записей автозапуска: ") + total + L.T(", работает: ") + onCount +
                                 L.T(", лишних: ") + bad + ".\n" +
                                 L.T("Отключённое возвращается кнопкой «Вернуть выбранные» или общим откатом.");
        }

        private void SelectStartupBloat() { CheckSection(_startupList, L.T("Стартует без нужды — можно отключить")); }

        private void SetStartupSelected(bool on)
        {
            List<string> ids = CheckedIds(_startupList);
            if (ids.Count == 0)
            {
                MessageBox.Show(this, L.T("Отметьте галочками, какие записи менять."), L.T("Ничего не выбрано"),
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            if (!on && MessageBox.Show(this, L.T("Будет отключено записей автозапуска: ") + ids.Count + ".\n\n" +
                L.T("Сами программы остаются на месте — они просто перестанут\n") +
                L.T("запускаться при входе. Вернуть можно этой же страницей.\n\nПродолжить?"),
                L.T("Отключение автозапуска"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming("-StartupSet -StartupValue " + (on ? "On" : "Off") + " -StartupItems \"" + string.Join(",", ids.ToArray()) + "\"",
                on ? L.T("Возврат автозапуска…") : L.T("Отключение автозапуска…"),
                delegate { Navigate("startup"); RefreshStartup(); });
        }
    }
}
