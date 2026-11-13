// Часть MainForm: запуск движка, потоковый вывод и ответы JSON, занятость и «Прервать».

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
        //  Запуск движка
        // ================================================================== //
        // Движок распаковывается один раз за сеанс и в файл со своим именем:
        // параллельные запуски (проверка, досье, применение) больше не затирают
        // скрипт друг у друга прямо во время чтения.
        //
        // Запусков бывает несколько сразу: определение системы, список настроек
        // и журнал датчиков читаются параллельно, а поверх может идти применение.
        // Раньше окно помнило только последний: «Прервать» и закрытие окна
        // останавливали не тот процесс, а чтение, закончившись первым, снимало
        // занятость с ещё идущего применения. Теперь на учёте каждый.
        private sealed class EngineRun
        {
            public Process Proc;
            public string Status;       // подпись в строке состояния
            public bool Writes;         // команда меняет систему
            public bool Streams;        // действие с выводом в журнал, а не чтение данных
            public bool Cancelled;      // прервано пользователем
        }

        // Меняется только из потока окна
        private readonly List<EngineRun> _runs = new List<EngineRun>();

        private bool EngineWriting() { return _runs.Exists(delegate(EngineRun r) { return r.Writes; }); }
        private bool EngineStreaming() { return _runs.Exists(delegate(EngineRun r) { return r.Streams; }); }

        // Запускает движок и ставит запуск на учёт. Строки вывода приходят из
        // чужого потока, конец работы — уже в потоке окна.
        private void Launch(ProcessStartInfo psi, EngineRun run, Action<string> onLine, Action<int> onExit)
        {
            Process p = new Process();
            p.StartInfo = psi;
            p.EnableRaisingEvents = true;
            DataReceivedEventHandler h = delegate(object s, DataReceivedEventArgs e) { if (e.Data != null) onLine(e.Data); };
            p.OutputDataReceived += h; p.ErrorDataReceived += h;
            p.Exited += delegate
            {
                int code = -1;
                try { p.WaitForExit(); code = p.ExitCode; } catch { }
                try
                {
                    BeginInvoke((MethodInvoker)delegate
                    {
                        _runs.Remove(run);
                        onExit(code);
                        p.Dispose();
                    });
                }
                catch { }
            };
            run.Proc = p;
            p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine();
            _runs.Add(run);
        }

        // Занятость снимается с последним запуском; пока работает другой, в
        // строку состояния возвращается его подпись.
        private void SettleBusy(string doneText)
        {
            if (_runs.Count == 0) SetBusy(false, doneText);
            else SetBusy(true, _runs[_runs.Count - 1].Status);
        }

        private string ExtractEngine() { return EngineFile.Ensure(); }

        // Команды, которые меняют систему. Всё остальное движок только читает,
        // и обрывать его можно без последствий.
        private static readonly string[] WriteFlags = {
            "-Revert", "-RestoreAll", "-RestoreItems", "-RestoreBackup", "-RemoveApps",
            "-StartupSet", "-SensorSet", "-FootprintWipe", "-XrayWipe", "-PurgeBuffer",
            "-PurgeData", "-CleanJunk", "-BlockApp", "-UnblockApp", "-InstallGuard", "-GdidReissue", "-GdidRestore",
            "-InstallNetGuard", "-RemoveNetGuard",
            "-RemoveGuard", "-GuardNow", "-InstallWatcher", "-RemoveWatcher",
            "-InstallSensorGuard", "-RemoveSensorGuard", "-EnableMonitor",
            "-DisableMonitor", "-XrayEnable", "-XrayDisable", "-XrayBaseline"
        };

        internal static bool EngineWrites(string extra)
        {
            if (extra == null) return false;
            // тестовый прогон и проверка только читают, хотя список модулей у них тот же
            if (extra.IndexOf("-DryRun", StringComparison.OrdinalIgnoreCase) >= 0) return false;
            if (extra.IndexOf("-Audit", StringComparison.OrdinalIgnoreCase) >= 0) return false;
            if (extra.IndexOf("-Modules", StringComparison.OrdinalIgnoreCase) >= 0) return true;
            foreach (string f in WriteFlags)
                if (extra.IndexOf(f, StringComparison.OrdinalIgnoreCase) >= 0) return true;
            return false;
        }

        // «###PROGRESS### 15/34 Телеметрия» — движок говорит, сколько проверок
        // из скольких пройдено. Раньше проверка молчала до самого конца, и
        // полминуты было не отличить работу от зависания.
        private bool ShowProgress(string line)
        {
            if (line == null || !line.StartsWith("###PROGRESS###")) return false;
            string rest = line.Substring("###PROGRESS###".Length).Trim();
            int sp = rest.IndexOf(' ');
            string nums = sp > 0 ? rest.Substring(0, sp) : rest;
            string what = sp > 0 ? rest.Substring(sp + 1).Trim() : "";
            string[] parts = nums.Split('/');
            int done, total;
            if (parts.Length != 2 || !int.TryParse(parts[0], out done) || !int.TryParse(parts[1], out total) || total < 1)
                return true;                        // строка наша, но непонятная — просто прячем
            try
            {
                BeginInvoke((MethodInvoker)delegate
                {
                    if (!_progress.Visible) return;
                    _progress.Style = ProgressBarStyle.Continuous;
                    _progress.Maximum = total;
                    _progress.Value = Math.Max(0, Math.Min(done, total));
                    _status.Text = (_busyText.Length > 0 ? _busyText + "  " : "") + done + " / " + total +
                                   (what.Length > 0 ? "  -  " + L.T(what) : "");
                });
            }
            catch { }
            return true;
        }

        private bool EngineAlive()
        {
            foreach (EngineRun r in _runs)
            {
                try { if (!r.Proc.HasExited) return true; } catch { }
            }
            return false;
        }

        // Прервать работу движка. Чтение обрывается сразу; применение — только
        // после предупреждения: часть настроек к этому моменту уже записана.
        private bool StopEngine(bool ask)
        {
            if (!EngineAlive()) return true;
#if UITEST
            ask = false;                // тестовая сборка не открывает окон
#endif
            if (ask && EngineWriting())
            {
                string warn = L.T("Движок сейчас меняет настройки системы.\n\n") +
                              L.T("Если прервать, часть настроек останется применённой. Всё, что он успел изменить, записано в журнал — вернуть можно на странице «Изменения».\n\nВсё равно прервать?");
                if (MessageBox.Show(this, warn, L.T("Прервать работу"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                    return false;
            }
            EngineRun[] live = _runs.ToArray();
            foreach (EngineRun r in live)
            {
                r.Cancelled = true;
                try { r.Proc.Kill(); } catch { }
            }
            foreach (EngineRun r in live)
            {
                try { r.Proc.WaitForExit(4000); } catch { }
            }
            SetBusy(false, L.T("Прервано."));
            return true;
        }

        // Только системный PowerShell по полному пути (см. EngineFile.PowerShellPath)
        private static string PowerShellExe() { return EngineFile.PowerShellPath(); }

        private ProcessStartInfo EnginePsi(string extra)
        {
            string script = ExtractEngine();
            string portable = PortableRoot();
            string backupRoot = (portable.Length > 0)
                ? portable
                : Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
            string args = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\" " + extra +
                          " -BackupRoot \"" + backupRoot + "\"";
            if (portable.Length > 0) args += " -DataRoot \"" + portable + "\"";
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = PowerShellExe(); psi.Arguments = args;
            psi.UseShellExecute = false; psi.CreateNoWindow = true;
            EngineFile.Harden(psi);             // модули, ProgramData, PATH — из системы
            psi.RedirectStandardOutput = true; psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = Encoding.UTF8; psi.StandardErrorEncoding = Encoding.UTF8;
            return psi;
        }

        // потоковый запуск (для действий) — вывод в журнал
        private void RunStreaming(string extra, string statusText, Action onDone)
        {
            if (EngineStreaming())
            {
                MessageBox.Show(this, L.T("Программа ещё выполняет предыдущую команду.\nДождитесь её завершения."),
                    L.T("Подождите"), MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            SetBusy(true, statusText);
            Navigate("log");
            _log.Clear();
            LogLine(statusText, Theme.Text);
            LogLine(new string('─', 58), Theme.TextFaint);

            ProcessStartInfo psi;
            try { psi = EnginePsi(extra); }
            catch (Exception ex)
            {
                SettleBusy(L.T("Ошибка."));
                LogLine(L.T("Не удалось подготовить движок: ") + ex.Message, Theme.Err);
                MessageBox.Show(this, ex.Message, L.T("Ошибка"), MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            LogLine(L.T("Запуск: powershell ") + extra, Theme.TextFaint);
            if (_detect != null && !Json.GetBool(_detect, "admin"))
                LogLine(L.T("ВНИМАНИЕ: программа запущена без прав администратора — изменения применить нельзя."), Theme.Err);

            EngineRun run = new EngineRun();
            run.Status = statusText; run.Streams = true; run.Writes = EngineWrites(extra);
            Action<string> onLine = delegate(string line)
            {
                if (line.Trim() == "###DONE###") return;
                if (ShowProgress(line.TrimStart())) return;
                try { BeginInvoke((MethodInvoker)delegate { LogEngine(line); }); } catch { }
            };
            Action<int> onExit = delegate(int code)
            {
                bool stopped = run.Cancelled;
                SettleBusy(stopped ? L.T("Прервано.") : (code == 0 ? L.T("Готово.") :
                           code == 2 ? L.T("Готово, с ошибками.") : L.T("Завершено с ошибкой.")));
                LogLine(new string('─', 58), Theme.TextFaint);
                if (stopped)
                {
                    LogLine(L.T("Прервано по вашей команде."), Theme.Err);
                    if (run.Writes) LogLine(L.T("Что движок успел изменить — записано на странице «Изменения»."), Theme.TextDim);
                }
                else if (code == 0) LogLine(L.T("Готово."), Theme.Text);
                else if (code == 2)
                {
                    // движок дошёл до конца, но что-то не удалось — сказано выше
                    LogLine(L.T("Готово, но не всё прошло: что именно — в строках [!] выше."), Theme.Err);
                }
                else if (code == 3)
                {
                    // движок сам объяснил причину строкой выше
                    LogLine(L.T("Программа не может работать на этом компьютере из-за политики устройства."), Theme.Err);
                }
                else
                {
                    LogLine(L.T("PowerShell завершился с кодом ") + code + ".", Theme.Err);
                    LogLine(L.T("Если выше нет строк движка — его блокирует антивирус или не хватает прав."), Theme.TextDim);
                }
                if (onDone != null) onDone();
            };
            try { Launch(psi, run, onLine, onExit); }
            catch (Exception ex)
            {
                SettleBusy(L.T("Не удалось запустить PowerShell."));
                LogLine(L.T("Не удалось запустить PowerShell: ") + ex.Message, Theme.Err);
                LogLine(L.T("Путь: ") + psi.FileName, Theme.TextDim);
                MessageBox.Show(this, L.T("Не удалось запустить PowerShell:\n") + ex.Message,
                    L.T("Ошибка"), MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        // запуск с разбором JSON (для данных) — без переключения на журнал
        private void RunJson(string extra, string statusText, Action<Dictionary<string, object>> onResult)
        {
            SetBusy(true, statusText);
            ProcessStartInfo psi;
            try { psi = EnginePsi(extra); }
            catch (Exception ex)
            {
                SettleBusy(L.T("Ошибка."));
                LogLine(L.T("Не удалось подготовить движок: ") + ex.Message, Theme.Err);
                if (onResult != null) onResult(null);
                return;
            }
            EngineRun run = new EngineRun();
            run.Status = statusText; run.Writes = EngineWrites(extra);
            string jsonLine = null;
            StringBuilder errBuf = new StringBuilder();
            object gate = new object();         // вывод и ошибки приходят из разных потоков
            Action<string> onLine = delegate(string line)
            {
                string t = line.TrimStart();
                if (ShowProgress(t)) return;
                lock (gate)
                {
                    if (t.StartsWith("###JSON###")) jsonLine = t.Substring(10).Trim();
                    else if (t.Length > 0 && errBuf.Length < 2000) errBuf.Append(t).Append("\n");
                }
            };
            Action<int> onExit = delegate(int code)
            {
                SettleBusy(run.Cancelled ? L.T("Прервано.") : L.T("Готово."));
                Dictionary<string, object> d = null;
                if (jsonLine != null) { try { d = Json.ParseObject(jsonLine); } catch { } }
                if (d == null && errBuf.Length > 0 && !run.Cancelled)
                    LogLine(L.T("Движок (") + extra + L.T(") не вернул данные, код ") + code + ":\n" + errBuf, Theme.Err);
                if (onResult != null) onResult(d);
            };
            try { Launch(psi, run, onLine, onExit); }
            catch (Exception ex)
            {
                SettleBusy(L.T("PowerShell недоступен."));
                LogLine(L.T("Не удалось запустить PowerShell: ") + ex.Message, Theme.Err);
                if (onResult != null) onResult(null);
            }
        }

        private void SetBusy(bool busy, string status)
        {
            _progress.Visible = busy; _status.Text = status;
            _busyText = busy ? status : "";
            // бегущая полоса — пока движок не сказал, сколько всего работы
            if (busy) { _progress.Style = ProgressBarStyle.Marquee; _progress.Value = 0; }
            if (_btnStop != null)
            {
                _btnStop.Visible = busy;
                if (_btnStop.Parent != null) _btnStop.Parent.PerformLayout();
            }
            if (_progress.Parent != null) _progress.Parent.PerformLayout();
            _status.Location = new Point(busy ? (int)(Font.Height * 11F) : (int)(Font.Height * 1.2F), _status.Location.Y);
            if (_btnApply != null) _btnApply.Enabled = !busy;
            if (_miRevert != null) _miRevert.Enabled = !busy;
            if (_btnGuardInstall != null) _btnGuardInstall.Enabled = !busy;
            if (_monitorToggle != null) _monitorToggle.Enabled = !busy;
        }
    }
}
