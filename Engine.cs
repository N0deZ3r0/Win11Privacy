using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using Microsoft.Win32;

namespace Win11Privacy
{
    // ====================================================================== //
    //  Движок вшит в exe ресурсом, а перед запуском кладётся на диск. Важно,
    //  куда именно: запускает его администратор, и во временной папке
    //  пользователя любой процесс без всяких прав мог бы подменить файл в
    //  промежутке между записью и запуском — подмена выполнилась бы с полными
    //  правами. Поэтому папка лежит в ProgramData и создаётся с явными
    //  правами: система и администраторы пишут, остальные только читают.
    //  Вдобавок перед каждым запуском файл сверяется по SHA-256 с тем, что
    //  вшито в exe: если на диске оказалось не то, скрипт переписывается.
    // ====================================================================== //
    internal static class EngineFile
    {
        private static readonly object Lock = new object();
        private static string _path;
        private static byte[] _want;
        private static bool _guarded;

        // false — папку с правами создать не удалось и скрипт лежит во
        // временной; на странице «О программе» об этом сказано прямо.
        internal static bool Guarded { get { return _guarded; } }

        internal static string Folder { get { return _path == null ? "" : Path.GetDirectoryName(_path); } }

        // --- эталон: SHA-256 ресурса внутри exe ---------------------------- //
        private static byte[] WantHash()
        {
            if (_want != null) return _want;
            using (Stream src = Resource())
            using (SHA256 sha = SHA256.Create())
                _want = sha.ComputeHash(src);
            return _want;
        }

        private static Stream Resource()
        {
            Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("engine.ps1");
            if (s == null) throw new InvalidOperationException(L.T("встроенный скрипт движка не найден в программе"));
            return s;
        }

        private static bool Same(string path)
        {
            try
            {
                if (!File.Exists(path)) return false;
                byte[] want = WantHash();
                using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                using (SHA256 sha = SHA256.Create())
                {
                    byte[] got = sha.ComputeHash(fs);
                    if (got.Length != want.Length) return false;
                    for (int i = 0; i < got.Length; i++) if (got[i] != want[i]) return false;
                    return true;
                }
            }
            catch { return false; }
        }

        // --- права: писать может только администратор ----------------------- //
        private static DirectorySecurity Rules()
        {
            DirectorySecurity sec = new DirectorySecurity();
            sec.SetAccessRuleProtection(true, false);          // наследование выключено
            SecurityIdentifier sys = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
            SecurityIdentifier adm = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
            SecurityIdentifier usr = new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null);
            InheritanceFlags all = InheritanceFlags.ObjectInherit | InheritanceFlags.ContainerInherit;
            sec.AddAccessRule(new FileSystemAccessRule(sys, FileSystemRights.FullControl, all, PropagationFlags.None, AccessControlType.Allow));
            sec.AddAccessRule(new FileSystemAccessRule(adm, FileSystemRights.FullControl, all, PropagationFlags.None, AccessControlType.Allow));
            sec.AddAccessRule(new FileSystemAccessRule(usr, FileSystemRights.ReadAndExecute, all, PropagationFlags.None, AccessControlType.Allow));
            try { sec.SetOwner(adm); } catch { }
            return sec;
        }

        // Папку мог создать заранее кто угодно: в ProgramData обычный
        // пользователь вправе завести свою, а её владелец всегда может вернуть
        // себе права. Чужую папку мы не «чиним», а сносим и делаем заново.
        private static bool OwnedByAdmins(string dir)
        {
            try
            {
                IdentityReference owner = Directory.GetAccessControl(dir, AccessControlSections.Owner)
                                                   .GetOwner(typeof(SecurityIdentifier));
                SecurityIdentifier sid = owner as SecurityIdentifier;
                if (sid == null) return false;
                return sid.IsWellKnown(WellKnownSidType.BuiltinAdministratorsSid) ||
                       sid.IsWellKnown(WellKnownSidType.LocalSystemSid);
            }
            catch { return false; }
        }

        // --- корень ProgramData\Win11Privacy -------------------------------- //
        //  Над bin лежит корень, и он важен не меньше: его владелец может
        //  переименовать bin и подставить свою папку между проверкой и
        //  запуском. А права ProgramData по умолчанию дают обычным
        //  пользователям создавать файлы и папки во всех её подпапках —
        //  подложенный заранее файл (журнал отката, копия движка для стража)
        //  остался бы их собственностью. Поэтому: корень, заведённый не
        //  администратором, откладывается целиком; подложенное внутрь
        //  прежней папки — в карантин рядом; права закрываются на запись для
        //  всех, кроме системы и администраторов. То же делает и движок.
        private static readonly string[] TrustedOwners =
            { "S-1-5-18", "S-1-5-32-544", "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464" };

        private static bool Trusted(FileSystemSecurity sec)
        {
            SecurityIdentifier sid = sec.GetOwner(typeof(SecurityIdentifier)) as SecurityIdentifier;
            return sid != null && Array.IndexOf(TrustedOwners, sid.Value) >= 0;
        }

        private static bool TrustedItem(string path, bool dir)
        {
            try
            {
                if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) return false;
                return dir ? Trusted(Directory.GetAccessControl(path, AccessControlSections.Owner))
                           : Trusted(File.GetAccessControl(path, AccessControlSections.Owner));
            }
            catch { return false; }
        }

        internal static bool IsSecure(string dir)
        {
            try
            {
                if (!TrustedItem(dir, true)) return false;
                DirectorySecurity sec = Directory.GetAccessControl(dir, AccessControlSections.Access);
                if (!sec.AreAccessRulesProtected) return false;
                // запись, удаление, смена прав или владельца — в том числе общими правами
                const long write = 0x2 | 0x4 | 0x10 | 0x40 | 0x100 | 0x10000 | 0x40000 | 0x80000 | 0x40000000 | 0x10000000;
                foreach (FileSystemAccessRule r in sec.GetAccessRules(true, true, typeof(SecurityIdentifier)))
                {
                    if (r.AccessControlType != AccessControlType.Allow) continue;
                    if (Array.IndexOf(TrustedOwners, r.IdentityReference.Value) >= 0) continue;
                    if (((long)r.FileSystemRights & write) != 0) return false;
                }
                return true;
            }
            catch { return false; }
        }

        // Свежая пустая папка карантина со случайным хвостом в имени, которую
        // мы сами создаём. Предсказуемый путь «<корень>.untrusted-<время>»
        // обычный пользователь мог завести заранее папкой или junction, и
        // перенос «чужого» с правами администратора ушёл бы по ссылке.
        private static string FreshQuarantine(string root)
        {
            for (int i = 0; i < 20; i++)
            {
                string cand = root + ".untrusted-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N").Substring(0, 8);
                if (Directory.Exists(cand) || File.Exists(cand)) continue;
                // Сразу с правами (система и администраторы пишут, остальные
                // читают): раньше папка наследовала права ProgramData, где
                // обычный пользователь может заводить свои файлы и папки.
                try { Directory.CreateDirectory(cand, Rules()); } catch { continue; }
                if ((File.GetAttributes(cand) & FileAttributes.ReparsePoint) != 0)
                {
                    try { Directory.Delete(cand, true); } catch { }
                    continue;
                }
                return cand;
            }
            throw new IOException("не удалось завести папку карантина рядом с " + root);
        }

        // Ни одну папку выше корня (ProgramData, корень диска) никто, кроме
        // системы и администраторов, не может удалить, переименовать, сменить
        // ей права или владельца, а у родителя — удалить вложенное. Иначе
        // закрытый корень можно отодвинуть целиком и положить на его место свой
        // (W11P-006). То же проверяет движок (Test-DirChainSecure, Assert-SafeRoot).
        internal static bool ChainSecure(string dir)
        {
            try
            {
                const long self = 0x10000 | 0x40000 | 0x80000 | 0x10000000 | 0x40000000;   // удаление, права, владелец, общие
                const long child = 0x40 | 0x10000000 | 0x40000000;                          // удаление вложенного
                string cur = Path.GetFullPath(dir).TrimEnd('\\');
                while (!string.IsNullOrEmpty(cur))
                {
                    string parent = Path.GetDirectoryName(cur);
                    bool isRoot = string.IsNullOrEmpty(parent);
                    string node = isRoot ? cur.TrimEnd('\\') + "\\" : cur;
                    if (!isRoot && (File.GetAttributes(node) & FileAttributes.ReparsePoint) != 0) return false;
                    DirectorySecurity sec = Directory.GetAccessControl(node, AccessControlSections.Owner | AccessControlSections.Access);
                    if (!Trusted(sec)) return false;
                    long mask = isRoot ? child : (self | child);
                    foreach (FileSystemAccessRule r in sec.GetAccessRules(true, true, typeof(SecurityIdentifier)))
                    {
                        if (r.AccessControlType != AccessControlType.Allow) continue;
                        // «создатель-владелец» и прочие шаблоны для вложенного к самой папке не относятся
                        if ((r.PropagationFlags & PropagationFlags.InheritOnly) != 0) continue;
                        if (Array.IndexOf(TrustedOwners, r.IdentityReference.Value) >= 0) continue;
                        if (((long)r.FileSystemRights & mask) != 0) return false;
                    }
                    if (isRoot) break;
                    cur = parent;
                }
                return true;
            }
            catch { return false; }
        }

        internal static void SecureRoot(string root)
        {
            if (!ChainSecure(Path.GetDirectoryName(root)))
                throw new UnauthorizedAccessException(L.T("папку выше папки данных может переименовать не администратор: ") + Path.GetDirectoryName(root));
            if (Directory.Exists(root) && !TrustedItem(root, true))
            {
                string aside = FreshQuarantine(root);
                // Move не идёт в уже существующую папку — кладём внутрь свежей
                Directory.Move(root, Path.Combine(aside, Path.GetFileName(root)));
            }
            if (!Directory.Exists(root)) { Directory.CreateDirectory(root, Rules()); return; }
            if (IsSecure(root)) return;
            // Прежняя папка: права наследовались от ProgramData, и обычный
            // пользователь мог завести файлы и папки на любой глубине, а не
            // только прямо в корне. Раньше проверялся только корень — и после
            // того как окно закрывало его, движок считал папку чистой.
            // Унаследованные от ProgramData права тут не в счёт: их сейчас же
            // заменят права нового корня.
            Quarantine(root, "", FreshQuarantine(root), false);
            Directory.SetAccessControl(root, Rules());
            if (!IsSecure(root)) throw new UnauthorizedAccessException(root);
            // Права корня разошлись по вложенному — теперь проверяется всё,
            // с унаследованным (W11P-006, так же делает движок). Обычно пусто.
            if (HasUntrusted(root)) Quarantine(root, "", FreshQuarantine(root), true);
        }

        // Может ли кто-то, кроме системы и администраторов, менять объект
        // (запись, удаление своё и вложенного, права, владелец, атрибуты) —
        // как Get-UntrustedRights в движке (W11P-006):
        //  * к самому объекту — всё, кроме «только для вложенного»; у папки ещё
        //    и то, что она передаст вложенному (кроме создателя-владельца и
        //    создателя-группы — ими станет тот, кто создаст вложенное);
        //  * запрет вычитается, только если он явный, для «Все», в обычном
        //    порядке и относится к самому объекту — он идёт раньше любых
        //    разрешений; для вложенного запреты не вычитаются;
        //  * withInherited = false — только явные записи: так при переносе
        //    старой папки данных, где унаследованное тут же заменит новый корень.
        private static bool OpenToOthers(FileSystemSecurity sec, bool dir, bool withInherited)
        {
            const long write = 0x2 | 0x4 | 0x10 | 0x40 | 0x100 | 0x10000 | 0x40000 | 0x80000 | 0x40000000 | 0x10000000;
            long self = 0, child = 0, deny = 0;
            bool canonical = sec.AreAccessRulesCanonical;
            foreach (FileSystemAccessRule r in sec.GetAccessRules(true, withInherited, typeof(SecurityIdentifier)))
            {
                string sid = r.IdentityReference.Value;
                long rights = (long)r.FileSystemRights;
                bool inheritOnly = (r.PropagationFlags & PropagationFlags.InheritOnly) != 0;
                bool toChildren = dir && (r.InheritanceFlags & (InheritanceFlags.ObjectInherit | InheritanceFlags.ContainerInherit)) != 0;
                if (r.AccessControlType == AccessControlType.Deny)
                {
                    if (canonical && !r.IsInherited && !inheritOnly && sid == "S-1-1-0") deny |= rights;
                    continue;
                }
                if (Array.IndexOf(TrustedOwners, sid) >= 0) continue;
                if (sid == "S-1-3-4") continue;                      // права владельца — владелец проверен
                if (!inheritOnly) self |= rights;
                if (toChildren && sid != "S-1-3-0" && sid != "S-1-3-1") child |= rights;
            }
            return (((self & ~deny) | child) & write) != 0;
        }

        private static bool TrustedDeep(string path, bool dir, bool withInherited)
        {
            if (!TrustedItem(path, dir)) return false;
            try
            {
                FileSystemSecurity sec = dir ? (FileSystemSecurity)Directory.GetAccessControl(path, AccessControlSections.Access)
                                             : File.GetAccessControl(path, AccessControlSections.Access);
                return !OpenToOthers(sec, dir, withInherited);
            }
            catch { return false; }
        }

        // Есть ли внутри хоть что-то недоверенное (полная проверка)
        private static bool HasUntrusted(string dir)
        {
            foreach (string d in Directory.GetDirectories(dir))
            {
                if (!TrustedDeep(d, true, true)) return true;
                if (HasUntrusted(d)) return true;
            }
            foreach (string f in Directory.GetFiles(dir))
                if (!TrustedDeep(f, false, true)) return true;
            return false;
        }

        // Путь внутри собирается из имён: у временной папки бывает короткое
        // имя 8.3, и отрезать начало полного пути нельзя. Внутрь ссылок и
        // чужих папок не заходим — они уходят в карантин целиком.
        private static void Quarantine(string dir, string rel, string aside, bool withInherited)
        {
            foreach (string d in Directory.GetDirectories(dir))
            {
                string r = rel.Length > 0 ? Path.Combine(rel, Path.GetFileName(d)) : Path.GetFileName(d);
                if (!TrustedDeep(d, true, withInherited)) { MoveAside(d, Path.Combine(aside, r), true); continue; }
                Quarantine(d, r, aside, withInherited);
            }
            foreach (string f in Directory.GetFiles(dir))
            {
                string r = rel.Length > 0 ? Path.Combine(rel, Path.GetFileName(f)) : Path.GetFileName(f);
                if (!TrustedDeep(f, false, withInherited)) MoveAside(f, Path.Combine(aside, r), false);
            }
        }

        private static void MoveAside(string from, string to, bool dir)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(to));
            if (dir) Directory.Move(from, to); else File.Move(from, to);
        }

        // Раньше, если защищённую папку подготовить не удавалось, движок
        // клался во временную папку пользователя. Сверка по SHA-256 там не
        // спасала: между сверкой и чтением файла PowerShell'ом любая
        // программа пользователя без прав могла его подменить, и подмена
        // выполнилась бы с правами администратора. Программа всегда запущена
        // с этими правами (так требует манифест), так что неудача здесь — не
        // «нет прав», а что-то не так с папкой. Тогда движок не запускается.
        private static string Dir()
        {
            string root = Path.Combine(ProgramDataDir(), "Win11Privacy");
            string safe = Path.Combine(root, "bin");
            try
            {
                SecureRoot(root);
                if (Directory.Exists(safe) && !OwnedByAdmins(safe)) Directory.Delete(safe, true);
                DirectorySecurity sec = Rules();
                if (!Directory.Exists(safe)) Directory.CreateDirectory(safe, sec);
                else Directory.SetAccessControl(safe, sec);   // права выставляем каждый раз: папка могла остаться от прошлой версии
                if (!OwnedByAdmins(safe) || !IsSecure(safe)) throw new UnauthorizedAccessException(safe);
                _guarded = true;
                return safe;
            }
            catch (Exception ex)
            {
                _guarded = false;
                throw new InvalidOperationException(L.T("Не удалось подготовить защищённую папку для движка:\n") + safe + "\n\n" + ex.Message +
                                                    L.T("\n\nБез неё движок не запускается: из незащищённой папки его могла бы подменить любая программа. Перезапустите компьютер и попробуйте снова; если не поможет — проверьте, не блокирует ли антивирус папку ProgramData\\Win11Privacy."), ex);
            }
        }

        // --- окружение: из системы, а не из переменных среды -------------- //
        //  Переменные среды повышенного процесса складываются и из
        //  HKCU\Environment, а туда пишет любая программа пользователя без
        //  прав администратора. ProgramData, указанная там на свою папку,
        //  увела бы защищённую папку движка туда, где его можно подменить;
        //  PSModulePath — модули PowerShell, которые движок загружает с
        //  правами администратора. Пути берутся у Windows и из HKLM.
        internal static string SystemDrive() { return Path.GetPathRoot(Environment.SystemDirectory).TrimEnd('\\'); }

        private static string ReplaceNoCase(string s, string what, string with)
        {
            int i;
            while ((i = s.IndexOf(what, StringComparison.OrdinalIgnoreCase)) >= 0)
                s = s.Substring(0, i) + with + s.Substring(i + what.Length);
            return s;
        }

        // Путь из HKLM; %SystemDrive% и %SystemRoot% раскрываются по самой
        // системе, другие переменные не годятся — тогда запасной путь.
        internal static string MachinePath(string key, string name, string fallback)
        {
            try
            {
                using (RegistryKey b = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                using (RegistryKey k = b.OpenSubKey(key, false))
                {
                    string v = k == null ? null : k.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
                    if (!string.IsNullOrEmpty(v))
                    {
                        v = ReplaceNoCase(v, "%SystemDrive%", SystemDrive());
                        v = ReplaceNoCase(v, "%SystemRoot%", Path.GetDirectoryName(Environment.SystemDirectory));
                        if (v.IndexOf('%') < 0 && Path.IsPathRooted(v)) return v.TrimEnd('\\');
                    }
                }
            }
            catch { }
            return fallback;
        }

        internal static string ProgramDataDir()
        {
            return MachinePath(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList", "ProgramData", SystemDrive() + "\\ProgramData");
        }

        // Окружение запуска движка. Движок первой же строкой переустанавливает
        // всё это сам (у задач стража окна нет), здесь — для самого PowerShell
        // с первого мгновения и для рабочей папки, которая была во временной
        // папке пользователя.
        internal static void Harden(ProcessStartInfo psi)
        {
            string sys = Environment.SystemDirectory;
            string win = Path.GetDirectoryName(sys);
            string pf = MachinePath(@"SOFTWARE\Microsoft\Windows\CurrentVersion", "ProgramFilesDir", SystemDrive() + "\\Program Files");
            string pshome = Path.Combine(sys, "WindowsPowerShell\\v1.0");
            psi.EnvironmentVariables["PSModulePath"] = Path.Combine(pshome, "Modules") + ";" + Path.Combine(pf, "WindowsPowerShell\\Modules");
            psi.EnvironmentVariables["SystemRoot"] = win;
            psi.EnvironmentVariables["windir"] = win;
            psi.EnvironmentVariables["SystemDrive"] = SystemDrive();
            psi.EnvironmentVariables["ProgramData"] = ProgramDataDir();
            psi.EnvironmentVariables["ComSpec"] = Path.Combine(sys, "cmd.exe");
            psi.EnvironmentVariables["PATH"] = sys + ";" + win + ";" + Path.Combine(sys, "Wbem") + ";" + pshome + "\\";
            // Переменные, через которые .NET грузит в процесс чужой код
            // (профайлер CLR, стартовые перехватчики, слой совместимости):
            // убираем до запуска, чтобы PowerShell движка стартовал чистым.
            foreach (string bad in new[] {
                "COR_ENABLE_PROFILING", "COR_PROFILER", "COR_PROFILER_PATH", "COR_PROFILER_PATH_32", "COR_PROFILER_PATH_64",
                "CORECLR_ENABLE_PROFILING", "CORECLR_PROFILER", "CORECLR_PROFILER_PATH", "CORECLR_PROFILER_PATH_32", "CORECLR_PROFILER_PATH_64",
                "DOTNET_STARTUP_HOOKS", "DOTNET_ADDITIONAL_DEPS", "DOTNET_EnableDiagnostics", "__COMPAT_LAYER",
                // тестовый режим движка (только принять запрос и выйти): из
                // HKCU\Environment его не должна включать посторонняя программа
                "WIN11_ENGINE_TRACE" })
                psi.EnvironmentVariables.Remove(bad);
            psi.WorkingDirectory = sys;
        }

        // --- PowerShell: только системный, по полному пути ------------------ //
        //  Раньше, если файла на своём месте не оказывалось, запускался просто
        //  «powershell.exe». По имени без пути Windows ищет программу и в
        //  папке самого exe, и в текущей: подложенный туда powershell.exe
        //  выполнился бы с правами администратора. Теперь — ошибка.
        internal static string PowerShellPath()
        {
            string full = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                                       "WindowsPowerShell\\v1.0\\powershell.exe");
            if (!File.Exists(full))
                throw new FileNotFoundException(L.T("Не найден системный PowerShell:\n") + full, full);
            return full;
        }

        // --- путь к готовому к запуску скрипту ------------------------------ //
        internal static string Ensure()
        {
            lock (Lock)
            {
                if (_path != null && Same(_path)) return _path;
                string dir = Dir();
                string path = Path.Combine(dir, "engine-" + Process.GetCurrentProcess().Id + ".ps1");
                using (Stream src = Resource())
                using (FileStream dst = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.Read))
                { byte[] buf = new byte[8192]; int n; while ((n = src.Read(buf, 0, buf.Length)) > 0) dst.Write(buf, 0, n); }

                if (!Same(path))
                    throw new InvalidOperationException(L.T("не удалось распаковать движок:\n") + path +
                                                        L.T("\n\nФайл на диске не совпадает с тем, что внутри программы. Обычно так делает антивирус."));
                _path = path;
                Sweep(dir);
                return path;
            }
        }

        // --- уборка за прошлыми запусками ----------------------------------- //
        //  Раньше файлы engine-<номер>.ps1 копились без предела: программу
        //  закрывали, а за собой она не убирала.
        private static void Sweep(string dir)
        {
            int mine = Process.GetCurrentProcess().Id;
            try
            {
                foreach (string f in Directory.GetFiles(dir, "engine-*.ps1"))
                {
                    string name = Path.GetFileNameWithoutExtension(f);
                    int pid;
                    if (!int.TryParse(name.Substring("engine-".Length), out pid)) continue;
                    if (pid == mine) continue;
                    bool alive = true;
                    try { Process.GetProcessById(pid); } catch { alive = false; }
                    if (alive) continue;                       // чужой запуск ещё работает
                    try { File.Delete(f); } catch { }
                }
                string old = Path.Combine(dir, "engine.ps1");   // файл версий до 1.9 — без номера процесса
                if (File.Exists(old)) { try { File.Delete(old); } catch { } }
            }
            catch { }
        }

        // Вызывается при закрытии программы: свой файл после себя не оставляем.
        internal static void Remove()
        {
            lock (Lock)
            {
                if (_path == null) return;
                try { File.Delete(_path); } catch { }
                _path = null;
            }
        }
    }
}
