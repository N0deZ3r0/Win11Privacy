using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;

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

        internal static void SecureRoot(string root)
        {
            string stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss");
            if (Directory.Exists(root) && !TrustedItem(root, true))
                Directory.Move(root, root + ".untrusted-" + stamp);
            if (!Directory.Exists(root)) { Directory.CreateDirectory(root, Rules()); return; }
            if (IsSecure(root)) return;
            // Прежняя папка: права наследовались от ProgramData, и обычный
            // пользователь мог завести файлы и папки на любой глубине, а не
            // только прямо в корне. Раньше проверялся только корень — и после
            // того как окно закрывало его, движок считал папку чистой.
            Quarantine(root, "", root + ".untrusted-" + stamp);
            Directory.SetAccessControl(root, Rules());
            if (!IsSecure(root)) throw new UnauthorizedAccessException(root);
        }

        // Явное право на запись для чужого (унаследованные заменит новый корень)
        private static bool OpenToOthers(FileSystemSecurity sec)
        {
            const long write = 0x2 | 0x4 | 0x10 | 0x40 | 0x100 | 0x10000 | 0x40000 | 0x80000 | 0x40000000 | 0x10000000;
            foreach (FileSystemAccessRule r in sec.GetAccessRules(true, false, typeof(SecurityIdentifier)))
            {
                if (r.AccessControlType != AccessControlType.Allow) continue;
                if (Array.IndexOf(TrustedOwners, r.IdentityReference.Value) >= 0) continue;
                if (((long)r.FileSystemRights & write) != 0) return true;
            }
            return false;
        }

        private static bool TrustedDeep(string path, bool dir)
        {
            if (!TrustedItem(path, dir)) return false;
            try
            {
                FileSystemSecurity sec = dir ? (FileSystemSecurity)Directory.GetAccessControl(path, AccessControlSections.Access)
                                             : File.GetAccessControl(path, AccessControlSections.Access);
                return !OpenToOthers(sec);
            }
            catch { return false; }
        }

        // Путь внутри собирается из имён: у временной папки бывает короткое
        // имя 8.3, и отрезать начало полного пути нельзя. Внутрь ссылок и
        // чужих папок не заходим — они уходят в карантин целиком.
        private static void Quarantine(string dir, string rel, string aside)
        {
            foreach (string d in Directory.GetDirectories(dir))
            {
                string r = rel.Length > 0 ? Path.Combine(rel, Path.GetFileName(d)) : Path.GetFileName(d);
                if (!TrustedDeep(d, true)) { MoveAside(d, Path.Combine(aside, r), true); continue; }
                Quarantine(d, r, aside);
            }
            foreach (string f in Directory.GetFiles(dir))
            {
                string r = rel.Length > 0 ? Path.Combine(rel, Path.GetFileName(f)) : Path.GetFileName(f);
                if (!TrustedDeep(f, false)) MoveAside(f, Path.Combine(aside, r), false);
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
            string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Win11Privacy");
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
