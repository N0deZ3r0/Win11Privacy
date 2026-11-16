// Часть MainForm: страница «Автозащита».

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
        //  Страница: Страж
        // ================================================================== //
        private Control BuildGuardPage()
        {
            _btnGuardInstall = new ModernButton(L.T("Включить автозащиту"), true); _btnGuardInstall.Click += OnGuardInstall;
            _btnGuardNow = new ModernButton(L.T("Проверить"), false); _btnGuardNow.Click += OnGuardNow;
            _btnGuardRemove = new ModernButton(L.T("Отключить"), false); _btnGuardRemove.Click += OnGuardRemove;
            _btnWatcher = new ModernButton(L.T("Уведомления"), false); _btnWatcher.Click += OnWatcherToggle;
            _btnSensorGuard = new ModernButton(L.T("Датчики"), false); _btnSensorGuard.Click += OnSensorToggle;
            _btnSnapshot = new ModernButton(L.T("Снимок"), false); _btnSnapshot.Click += OnSnapshot;
            _btnGuardFreq = new ModernButton(GuardFreqText(), false);
            _btnGuardFreq.Click += delegate
            {
                _guardDaily = !_guardDaily;
                _btnGuardFreq.Text = GuardFreqText();
                _status.Text = _guardDaily ? L.T("Автозащита будет проверять каждый день. Нажмите «Включить автозащиту».")
                                           : L.T("Автозащита будет проверять раз в неделю. Нажмите «Включить автозащиту».");
            };
            Label state; StackPanel list; TextBox search;
            TableLayoutPanel page = ListPage(L.T("Автозащита"),
                L.T("Крупные обновления Windows тихо возвращают часть настроек назад.\n") +
                L.T("Автозащита проверяет систему по расписанию, возвращает сбитое и предупреждает."),
                null, out state, out list, out search,
                _btnGuardInstall, _btnGuardNow, _btnGuardRemove, _btnGuardFreq, _btnWatcher, _btnSensorGuard, _btnSnapshot);
            _guardState = state; _guardBody = list;
            return page;
        }

        private ModernButton _btnGuardInstall, _btnGuardNow, _btnGuardRemove, _btnWatcher, _btnSensorGuard, _btnSnapshot, _btnGuardFreq;
        private bool _watcherOn, _sensorOn, _guardDaily;
        private string GuardFreqText() { return _guardDaily ? L.T("Проверка: каждый день") : L.T("Проверка: раз в неделю"); }
    }
}
