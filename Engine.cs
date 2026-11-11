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
            string aside = root + ".untrusted-" + stamp;
            foreach (string d in Directory.GetDirectories(root))
                if (!TrustedItem(d, true)) { Directory.CreateDirectory(aside); Directory.Move(d, Path.Combine(aside, Path.GetFileName(d))); }
            foreach (string f in Directory.GetFiles(root))
                if (!TrustedItem(f, false)) { Directory.CreateDirectory(aside); File.Move(f, Path.Combine(aside, Path.GetFileName(f))); }
            Directory.SetAccessControl(root, Rules());
            if (!IsSecure(root)) throw new UnauthorizedAccessException(root);
        }

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
                if (!OwnedByAdmins(safe)) throw new UnauthorizedAccessException(safe);
                _guarded = true;
                return safe;
            }
            catch { }
            // Прав не хватило — программа запущена обычным пользователем и
            // системные настройки всё равно не изменит. Работаем из временной
            // папки, но сверку по SHA-256 никто не отменял.
            _guarded = false;
            string tmp = Path.Combine(Path.GetTempPath(), "Win11Privacy");
            Directory.CreateDirectory(tmp);
            return tmp;
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
