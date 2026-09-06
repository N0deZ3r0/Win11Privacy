#if SELFTEST
using System;
using System.Collections.Generic;

namespace Win11Privacy
{
    // ====================================================================== //
    //  Проверки для той части программы, где ошибка тихая. Движок покрыт
    //  своими тестами, страницы — открытием в тестовой сборке, а вот чистые
    //  функции интерфейса не проверял никто: сравнение версий, разбор ответов
    //  движка, решение «эта команда меняет систему или только читает» — от
    //  последнего зависит, спросят ли человека перед тем, как оборвать
    //  применение настроек.
    //
    //  Собирается отдельным exe:
    //      csc /define:SELFTEST /main:Win11Privacy.SelfTest ... *.cs
    // ====================================================================== //
    internal static class SelfTest
    {
        private static int _failed;
        private static int _passed;

        private static void Check(string name, bool ok, string detail)
        {
            if (ok) { Console.WriteLine("  [ok]   " + name); _passed++; }
            else
            {
                Console.WriteLine("  [FAIL] " + name + (detail.Length > 0 ? "  --  " + detail : ""));
                Console.WriteLine("::error::" + name + " " + detail);
                _failed++;
            }
        }

        private static void Check(string name, bool ok) { Check(name, ok, ""); }

        public static int Main()
        {
            try { Console.OutputEncoding = System.Text.Encoding.UTF8; } catch { }

            Versions();
            Commands();
            Verdict();
            Answers();

            Console.WriteLine();
            Console.WriteLine("Пройдено: " + _passed + ", провалено: " + _failed);
            return _failed > 0 ? 1 : 0;
        }

        // --- сравнение версий ------------------------------------------------ //
        private static void Versions()
        {
            Console.WriteLine("Сравнение версий");
            Check("1.9.0 старше 1.10.0", AppInfo.Compare("1.9.0", "1.10.0") < 0,
                  "получено: " + AppInfo.Compare("1.9.0", "1.10.0"));
            Check("1.9.1 новее 1.9.0", AppInfo.Compare("1.9.1", "1.9.0") > 0);
            Check("приставка v не мешает", AppInfo.Compare("1.9.0", "v1.9.0") == 0);
            Check("2.0 новее 1.99.99", AppInfo.Compare("2.0", "1.99.99") > 0);
            Check("недостающие части считаются нулями", AppInfo.Compare("1.9", "1.9.0") == 0);
            Check("мусор не роняет сравнение", AppInfo.Compare("", "1.9.0") < 0);
            Check("хвост после дефиса отбрасывается", AppInfo.Compare("1.9.0-beta", "1.9.0") == 0);
        }

        // --- какие команды движка меняют систему ----------------------------- //
        private static void Commands()
        {
            Console.WriteLine();
            Console.WriteLine("Что считается изменением системы");
            Check("применение модулей меняет", MainForm.EngineWrites("-Modules telemetry,ads"));
            Check("тестовый прогон не меняет", !MainForm.EngineWrites("-Modules telemetry -DryRun"));
            Check("проверка не меняет", !MainForm.EngineWrites("-Audit -Modules telemetry"));
            Check("проверка с доказательством не меняет", !MainForm.EngineWrites("-Audit -WithProof"));
            Check("откат меняет", MainForm.EngineWrites("-Revert"));
            Check("возврат записей меняет", MainForm.EngineWrites("-RestoreItems -ChangeItems abc"));
            Check("удаление приложений меняет", MainForm.EngineWrites("-RemoveApps -AppItems a,b -AllUsers"));
            Check("стирание следа меняет", MainForm.EngineWrites("-FootprintWipe -WipeItems ads"));
            Check("чтение следа не меняет", !MainForm.EngineWrites("-Footprint"));
            Check("досье не меняет", !MainForm.EngineWrites("-Spy"));
            Check("список настроек не меняет", !MainForm.EngineWrites("-ListDefs"));
            Check("хронология не меняет", !MainForm.EngineWrites("-Timeline -TimelineDays 30"));
            Check("сканирование рентгена не меняет", !MainForm.EngineWrites("-XrayScan -XrayHours 24"));
            Check("включение записи рентгена меняет", MainForm.EngineWrites("-XrayEnable"));
            Check("пустая строка ничего не меняет", !MainForm.EngineWrites(""));
        }

        // --- вердикт о версии на GitHub -------------------------------------- //
        private static void Verdict()
        {
            Console.WriteLine();
            Console.WriteLine("Ответ о новой версии");
            string status, card;

            MainForm.UpdateState st = MainForm.UpdateVerdict("v99.0.0", "", out status, out card);
            Check("релиз новее — предлагаем обновиться", st == MainForm.UpdateState.Newer, "получено: " + st);

            st = MainForm.UpdateVerdict("v" + AppInfo.Version, "", out status, out card);
            Check("та же версия — обновляться нечего", st == MainForm.UpdateState.Same, "получено: " + st);

            st = MainForm.UpdateVerdict("v0.0.1", "", out status, out card);
            Check("своя сборка новее релиза", st == MainForm.UpdateState.Ahead, "получено: " + st);

            st = MainForm.UpdateVerdict("", "сеть недоступна", out status, out card);
            Check("без ответа — это неудача", st == MainForm.UpdateState.Failed, "получено: " + st);
            Check("причина неудачи показывается", card == "сеть недоступна");

            st = MainForm.UpdateVerdict(null, "нет сети", out status, out card);
            Check("пустой ответ не роняет разбор", st == MainForm.UpdateState.Failed);
        }

        // --- разбор ответов движка ------------------------------------------- //
        private static void Answers()
        {
            Console.WriteLine();
            Console.WriteLine("Разбор ответов движка");
            string src = "{\"ok\":58,\"total\":63,\"time\":\"2026-09-06 12:00\",\"hostsBlocked\":true," +
                         "\"groups\":[{\"module\":\"telemetry\",\"items\":[{\"name\":\"уровень\",\"ok\":false}]}]," +
                         "\"buffer\":{\"mb\":\"4.7\"},\"empty\":null}";
            Dictionary<string, object> d = Json.ParseObject(src);
            Check("ответ разобран", d != null);
            if (d == null) return;
            Check("число читается", Json.GetInt(d, "ok") == 58);
            Check("строка читается", Json.GetStr(d, "time") == "2026-09-06 12:00");
            Check("да/нет читается", Json.GetBool(d, "hostsBlocked"));
            Check("вложенный объект читается", Json.GetStr(Json.GetObj(d, "buffer"), "mb") == "4.7");
            List<object> groups = Json.GetArr(d, "groups");
            Check("список читается", groups.Count == 1);
            Dictionary<string, object> g = Json.Obj(groups[0]);
            Check("вложенный список читается", Json.GetArr(g, "items").Count == 1);
            Check("кириллица не теряется", Json.GetStr(Json.Obj(Json.GetArr(g, "items")[0]), "name") == "уровень");
            Check("отсутствующий ключ — пусто, а не падение", Json.GetStr(d, "нет такого") == "");
            Check("null не роняет разбор", Json.GetStr(d, "empty") == "");
            Check("обрезанный ответ не роняет разбор", Json.ParseObject("{\"ok\":1,") == null ||
                                                       Json.GetInt(Json.ParseObject("{\"ok\":1,"), "ok") == 1);
        }
    }
}
#endif
