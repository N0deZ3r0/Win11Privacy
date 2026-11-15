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
        private void Launch(ProcessStartInfo psi, string request, EngineRun run, Action<string> onLine, Action<int> onExit)
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
            SendRequest(p, request);
        }

        // Занятость снимается с последним запуском; пока работает другой, в
        // строку состояния возвращается его подпись.
        private void SettleBusy(string doneText)
        {
            if (_runs.Count == 0) SetBusy(false, doneText);
            else SetBusy(true, _runs[_runs.Count - 1].Status);
        }

        private string ExtractEngine() { return EngineFile.Ensure(); }

        // Меняет ли запрос систему — решает сам запрос (EngineRequest.Writes)
        internal static bool EngineWrites(EngineRequest req) { return req != null && req.Writes; }

        // Действие удалось, только если движок сказал «ok» И завершился с
        // кодом 0 (W11P-003). Расхождение — неудача: раньше «ok:false» с
        // кодом 0 и наоборот могли выглядеть по-разному в разных местах.
        internal static bool EngineSucceeded(Dictionary<string, object> d)
        {
            if (d == null || !Json.GetBool(d, "ok")) return false;
            object code;
            if (d.TryGetValue("_exitCode", out code) && !(code is int && (int)code == 0)) return false;
            return true;
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

        // Командная строка движка постоянная (F-08): путь к движку в защищённой
        // папке и ключ -Request. Ни одного значения из данных в ней нет —
        // операция и её данные идут на стандартный ввод (SendRequest).
        internal static ProcessStartInfo EngineProcess(string script)
        {
            // путь собран из ProgramData по HKLM; кавычка в нём означала бы подмену
            if (string.IsNullOrEmpty(script) || script.IndexOf('"') >= 0)
                throw new InvalidOperationException("engine path");
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = PowerShellExe();
            psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\" -Request";
            psi.UseShellExecute = false; psi.CreateNoWindow = true;
            EngineFile.Harden(psi);             // модули, ProgramData, PATH — из системы
            psi.RedirectStandardInput = true;
            psi.RedirectStandardOutput = true; psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = Encoding.UTF8; psi.StandardErrorEncoding = Encoding.UTF8;
            return psi;
        }

        // Запрос — на стандартный ввод, и сразу закрыть: движок читает его один
        // раз и до конца. Пишем в фоне: запрос больше буфера канала ждал бы,
        // пока PowerShell запустится, и окно бы стояло. Не дошёл (процесс уже
        // закрылся) — движок без полного запроса ничего не делает.
        internal static void SendRequest(Process p, string request)
        {
            System.IO.StreamWriter w = p.StandardInput;
            System.Threading.ThreadPool.QueueUserWorkItem(delegate
            {
                try { w.Write(request); w.Flush(); }
                catch { }
                finally { try { w.Close(); } catch { } }
            });
        }

        private ProcessStartInfo EnginePsi(EngineRequest req, out string json)
        {
            string script = ExtractEngine();
            string portable = PortableRoot();
            string backupRoot = (portable.Length > 0)
                ? portable
                : Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
            json = req.WithCommon(backupRoot, portable).ToJson();
            return EngineProcess(script);
        }

        // потоковый запуск (для действий) — вывод в журнал
        private void RunStreaming(EngineRequest req, string statusText, Action onDone)
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
            // Заголовок — название действия; полоса из «─» в полширины окна
            // выглядела обрывком, вместо неё — шрифт и пустые строки.
            LogLine(statusText.TrimEnd('…', '.', ' '), Theme.Text, LogTitleFont);

            ProcessStartInfo psi;
            string request;
            try { psi = EnginePsi(req, out request); }
            catch (Exception ex)
            {
                SettleBusy(L.T("Ошибка."));
                LogLine(L.T("Не удалось подготовить движок: ") + ex.Message, Theme.Err);
                MessageBox.Show(this, ex.Message, L.T("Ошибка"), MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            LogLine(L.T("Команда движка: ") + req.Describe(), Theme.TextFaint);
            if (_detect != null && !Json.GetBool(_detect, "admin"))
                LogLine(L.T("ВНИМАНИЕ: программа запущена без прав администратора — изменения применить нельзя."), Theme.Err);

            EngineRun run = new EngineRun();
            run.Status = statusText; run.Streams = true; run.Writes = EngineWrites(req);
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
                LogGap();
                if (stopped)
                {
                    LogLine(L.T("Прервано по вашей команде."), Theme.Err, LogSectionFont);
                    if (run.Writes) LogLine(L.T("Что движок успел изменить — записано на странице «Изменения»."), Theme.TextDim);
                }
                else if (code == 0) LogLine(L.T("Готово."), Theme.Ok, LogSectionFont);
                else if (code == 2)
                {
                    // движок дошёл до конца, но что-то не удалось — сказано выше
                    LogLine(L.T("Готово, но не всё прошло: что именно — в строках [!] выше."), Theme.Err, LogSectionFont);
                }
                else if (code == 3)
                {
                    // движок сам объяснил причину строкой выше
                    LogLine(L.T("Программа не может работать на этом компьютере из-за политики устройства."), Theme.Err, LogSectionFont);
                }
                else
                {
                    LogLine(L.T("PowerShell завершился с кодом ") + code + ".", Theme.Err, LogSectionFont);
                    LogLine(L.T("Если выше нет строк движка — его блокирует антивирус или не хватает прав."), Theme.TextDim);
                }
                if (onDone != null) onDone();
            };
            try { Launch(psi, request, run, onLine, onExit); }
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
        private void RunJson(EngineRequest req, string statusText, Action<Dictionary<string, object>> onResult)
        {
            SetBusy(true, statusText);
            ProcessStartInfo psi;
            string request;
            try { psi = EnginePsi(req, out request); }
            catch (Exception ex)
            {
#if UITEST
                // Тестовая сборка, запущенная без прав администратора (снимки
                // страниц на своём компьютере): движок здесь и не должен
                // запускаться — данные тестовые. Красная «ошибка» в журнале и
                // в строке состояния только сбивала с толку.
                if (!IsAdmin())
                {
                    SettleBusy(L.T("Готово."));
                    if (onResult != null) onResult(null);
                    return;
                }
#endif
                SettleBusy(L.T("Ошибка."));
                LogLine(L.T("Не удалось подготовить движок: ") + ex.Message, Theme.Err);
                if (onResult != null) onResult(null);
                return;
            }
            EngineRun run = new EngineRun();
            run.Status = statusText; run.Writes = EngineWrites(req);
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
                // Код выхода — рядом с ответом: «ok» в JSON и код процесса
                // обязаны сходиться, и тот, кому важен успех, проверяет оба
                // (EngineSucceeded). Ключ с подчёркиванием движок не пишет.
                if (d != null) d["_exitCode"] = code;
                if (d == null && errBuf.Length > 0 && !run.Cancelled)
                    LogLine(L.T("Движок (") + req.Describe() + L.T(") не вернул данные, код ") + code + ":\n" + errBuf, Theme.Err);
                if (onResult != null) onResult(d);
            };
            try { Launch(psi, request, run, onLine, onExit); }
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
