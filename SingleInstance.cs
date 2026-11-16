using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Threading;

namespace Win11Privacy
{
    // ====================================================================== //
    //  Программа должна быть одна. Два окна с правами администратора
    //  применяли бы настройки одновременно и переписывали журнал отката
    //  каждое по-своему — а журнал единственный путь назад. Второй запуск
    //  теперь просто показывает уже открытое окно.
    //
    //  Тихий режим командной строки под это правило не подпадает: он для
    //  автоматической настройки нескольких машин, и там окна нет вовсе;
    //  журнал же защищён от одновременной записи замком внутри движка.
    //
    //  Имя Global\Win11Privacy-App может заранее занять любая программа
    //  (T-1). Раньше окно тогда считало, что уже запущено, и молча
    //  закрывалось: человек не мог открыть программу, пока та держала имя.
    //  Теперь «уже запущено» — только если под именем лежит замок самой
    //  программы: владелец — система или администраторы, и ждать (взять и
    //  держать), менять права и владельца, удалить его могут только они.
    //  Чужой объект под этим именем — не «уже запущено»: окно открывается,
    //  но без этого замка (Squatted). Это не ослабляет защиту данных — её
    //  держат замки движка (журнал отката, policies.json, рабочие папки),
    //  которые и так рассчитаны на несколько одновременных запусков (тихий
    //  режим, страж). Отказ запуститься здесь был бы отказом в работе по
    //  воле любой программы пользователя.
    // ====================================================================== //
    internal static class SingleInstance
    {
        internal const string Name = "Global\\Win11Privacy-App";
        private static Mutex _mutex;
        // Почему имя занято не замком программы; пусто — всё в порядке
        internal static string Squatted = "";

        private const int ReadControl = 0x20000;
        private const int QueryState = 0x1;

        internal static bool Take() { return Take(Name); }

        // name — имя замка (проверки SelfTest берут своё, чтобы не мешать окну)
        internal static bool Take(string name)
        {
            bool elevated = IsElevated();
            string self = SelfSid();
            Squatted = "";
            try
            {
                bool created;
                Mutex m;
                try { m = new Mutex(true, name, out created, NewSecurity(elevated, self, elevated)); }
                catch (IOException)
                {
                    // «этот SID нельзя назначить владельцем» — владелец по умолчанию
                    if (!elevated) throw;
                    m = new Mutex(true, name, out created, NewSecurity(elevated, self, false));
                }
                if (created) { _mutex = m; return true; }
                MutexSecurity sec = null;
                try { sec = m.GetAccessControl(); } catch { sec = null; }
                string why = Problem(sec, TrustedSids(elevated, self));
                m.Close();
                if (why.Length == 0) return false;      // открыто другое окно программы
                Squatted = why;
                return true;
            }
            catch (UnauthorizedAccessException)
            {
                // Замок программы открывает любой администратор (права —
                // администраторам и системе). Нет доступа — под именем чужой
                // объект, это не другое окно программы.
                Squatted = "нет доступа к объекту с именем замка";
                return true;
            }
            catch (WaitHandleCannotBeOpenedException)
            {
                Squatted = "имя замка занято объектом другого вида";
                return true;
            }
            catch
            {
                return true;    // не смогли проверить — лучше запуститься, чем не запуститься
            }
        }

        internal static void Release()
        {
            if (_mutex == null) return;
            try { _mutex.ReleaseMutex(); } catch { }
            try { _mutex.Close(); } catch { }
            _mutex = null;
        }

        // Кому можно верить как владельцу замка: системе и администраторам.
        // Сама учётная запись — только без повышения: у повышенного окна тот
        // же SID пользователя есть и у любой его обычной программы.
        internal static string[] TrustedSids(bool elevated, string self)
        {
            if (elevated || string.IsNullOrEmpty(self)) return new string[] { "S-1-5-18", "S-1-5-32-544" };
            return new string[] { "S-1-5-18", "S-1-5-32-544", self };
        }

        internal static MutexSecurity NewSecurity(bool elevated, string self, bool ownerAdmins)
        {
            MutexSecurity sec = new MutexSecurity();
            sec.SetAccessRuleProtection(true, false);
            foreach (string s in TrustedSids(elevated, self))
                sec.AddAccessRule(new MutexAccessRule(new SecurityIdentifier(s), MutexRights.FullControl, AccessControlType.Allow));
            if (ownerAdmins) sec.SetOwner(new SecurityIdentifier("S-1-5-32-544"));
            return sec;
        }

        // Пусто — замок свой; иначе — почему нет (как Get-MutexSecurityProblem
        // в движке). Пустой список прав (NULL DACL) .NET показывает как
        // «Все: полный доступ» — тоже отказ.
        internal static string Problem(MutexSecurity sec, string[] trusted)
        {
            if (sec == null) return "права замка не читаются";
            string owner = "";
            try
            {
                SecurityIdentifier o = (SecurityIdentifier)sec.GetOwner(typeof(SecurityIdentifier));
                if (o != null) owner = o.Value;
            }
            catch { owner = ""; }
            if (owner.Length == 0) return "владелец замка не читается";
            if (Array.IndexOf(trusted, owner) < 0) return "замок заведён чужой учётной записью (" + owner + ")";
            AuthorizationRuleCollection rules;
            try { rules = sec.GetAccessRules(true, true, typeof(SecurityIdentifier)); }
            catch { return "права замка не читаются"; }
            foreach (AuthorizationRule ar in rules)
            {
                MutexAccessRule r = ar as MutexAccessRule;
                if (r == null || r.AccessControlType != AccessControlType.Allow) continue;
                string sid = r.IdentityReference.Value;
                if (Array.IndexOf(trusted, sid) >= 0) continue;
                if (((int)r.MutexRights & ~(ReadControl | QueryState)) != 0) return "замок открыт не только системе и администраторам (" + sid + ")";
            }
            return "";
        }

        private static bool IsElevated()
        {
            try { return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator); }
            catch { return false; }
        }

        private static string SelfSid()
        {
            try { return WindowsIdentity.GetCurrent().User.Value; }
            catch { return ""; }
        }

        // --- показать окно, которое уже открыто ----------------------------- //
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hWnd);
        private const int SW_RESTORE = 9;

        internal static void ShowRunning()
        {
            try
            {
                Process me = Process.GetCurrentProcess();
                foreach (Process p in Process.GetProcessesByName(me.ProcessName))
                {
                    if (p.Id == me.Id) continue;
                    IntPtr h = p.MainWindowHandle;
                    if (h == IntPtr.Zero) continue;
                    if (IsIconic(h)) ShowWindow(h, SW_RESTORE);
                    SetForegroundWindow(h);
                    return;
                }
            }
            catch { }
        }
    }
}
