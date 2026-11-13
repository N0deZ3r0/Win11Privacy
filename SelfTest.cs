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
            Arguments();
            Profiles();
            Verdict();
            Answers();
            Language();

            Console.WriteLine();
            Console.WriteLine("Пройдено: " + _passed + ", провалено: " + _failed);
            return _failed > 0 ? 1 : 0;
        }

        // --- язык интерфейса ------------------------------------------------- //
        private static void Language()
        {
            Console.WriteLine("Язык интерфейса");
            L.Choice = 1;
            Check("закреплён русский", !L.English && L.Choice == 1);
            L.Choice = 2;
            Check("закреплён английский", L.English && L.Choice == 2);
            L.Choice = 0;
            Check("как в Windows — язык системы", L.English == L.SystemEnglish());
            L.Choice = 7;
            Check("неизвестный выбор — как в Windows", L.Choice == 0);
            Check("старый флаг совпадает с Windows (рус.) — как в Windows", MainForm.LangChoiceFromOld(false, false) == 0);
            Check("старый флаг совпадает с Windows (англ.) — как в Windows", MainForm.LangChoiceFromOld(true, true) == 0);
            Check("английский на русской Windows — закреплён", MainForm.LangChoiceFromOld(true, false) == 2);
            Check("русский на английской Windows — закреплён", MainForm.LangChoiceFromOld(false, true) == 1);
            L.Choice = 1;
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
            Check("смена номера устройства меняет", MainForm.EngineWrites("-GdidReissue"));
            Check("возврат номера устройства меняет", MainForm.EngineWrites("-GdidRestore"));
            Check("чтение номера устройства не меняет", !MainForm.EngineWrites("-GdidStatus"));
            Check("досье не меняет", !MainForm.EngineWrites("-Spy"));
            Check("список настроек не меняет", !MainForm.EngineWrites("-ListDefs"));
            Check("хронология не меняет", !MainForm.EngineWrites("-Timeline -TimelineDays 30"));
            Check("сканирование рентгена не меняет", !MainForm.EngineWrites("-XrayScan -XrayHours 24"));
            Check("включение записи рентгена меняет", MainForm.EngineWrites("-XrayEnable"));
            Check("пустая строка ничего не меняет", !MainForm.EngineWrites(""));
        }

        // --- аргументы при перезапуске с правами администратора -------------- //
        private static void Arguments()
        {
            Console.WriteLine();
            Console.WriteLine("Командная строка при перезапуске");
            Check("простые ключи остаются как есть",
                  MainForm.QuoteArgs(new[] { "--audit", "--silent" }) == "--audit --silent");
            string q = MainForm.QuoteArgs(new[] { "--profile", @"C:\My Files\p.json", "--silent" });
            Check("путь с пробелом берётся в кавычки", q == @"--profile ""C:\My Files\p.json"" --silent", "получено: " + q);
            Check("пустой аргумент не пропадает", MainForm.QuoteArgs(new[] { "a", "", "b" }) == "a \"\" b");
            Check("без аргументов — пустая строка", MainForm.QuoteArgs(new string[0]) == "");
        }

        // --- тихий режим: что из файла профиля попадёт в командную строку ---- //
        //  Имена модулей и пунктов шли в неё как есть: «telemetry -Revert» в
        //  подложенном файле добавил бы к запуску другой ключ движка.
        private static string SilentArgs(string json)
        {
            string why;
            return MainForm.SilentProfileArgs(Json.ParseObject(json), out why);
        }

        private static void Profiles()
        {
            Console.WriteLine();
            Console.WriteLine("Профиль тихого режима");
            Check("обычный профиль собирается",
                  SilentArgs("{\"modules\":[\"telemetry\",\"app_vscode\"],\"skip\":[\"telemetry#3\"]}") ==
                  "-Modules telemetry,app_vscode -SkipItems telemetry#3");
            Check("ключ движка в имени модуля — отказ", SilentArgs("{\"modules\":[\"telemetry -Revert\"]}") == null);
            Check("ключ движка в номере пункта — отказ",
                  SilentArgs("{\"modules\":[\"telemetry\"],\"skip\":[\"a#1 -PurgeData\"]}") == null);
            Check("кавычка в имени модуля — отказ", SilentArgs("{\"modules\":[\"tele\\\"metry\"]}") == null);
            Check("пустой список модулей — отказ", SilentArgs("{\"modules\":[]}") == null);
            Check("повтор модуля не удваивается",
                  SilentArgs("{\"modules\":[\"ads\",\"ads\"]}") == "-Modules ads");
            Check("выключенная копия даёт -NoBackup",
                  SilentArgs("{\"modules\":[\"ads\"],\"backup\":false}") == "-Modules ads -NoBackup");
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
            Check("битый код символа не роняет разбор", Json.GetStr(Json.ParseObject(@"{""a"":""x\uZZZZy""}"), "a").StartsWith("x"));
            Check("код символа читается", Json.GetStr(Json.ParseObject(@"{""a"":""\u0416""}"), "a") == "Ж");
            Check("пустой ответ не роняет разбор", Json.ParseObject(null) == null && Json.ParseObject("") == null);
        }
    }
}
#endif
