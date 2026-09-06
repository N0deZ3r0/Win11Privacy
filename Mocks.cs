using System;
using System.Collections.Generic;
using System.Drawing;
using System.Text;
using System.Windows.Forms;

namespace Win11Privacy
{
    // Тестовые данные для снимков интерфейса. В обычной сборке этого файла
    // как будто нет: весь он под #if UITEST.
    public partial class MainForm : Form
    {
#if UITEST
        // Тестовые данные для скриншотов без реального PowerShell
        internal void InjectMocks()
        {
            _mockMode = true;
            string audit = "{\"time\":\"2026-08-31 15:20\",\"ok\":58,\"total\":63,\"groups\":[" +
                "{\"module\":\"telemetry\",\"title\":\"Телеметрия и диагностика\",\"ok\":12,\"total\":12,\"items\":[{\"name\":\"уровень телеметрии — минимальный\",\"ok\":true,\"actual\":\"0\"}]}," +
                "{\"module\":\"ads\",\"title\":\"Рекламный ID и реклама\",\"ok\":22,\"total\":22,\"items\":[]}," +
                "{\"module\":\"copilot\",\"title\":\"Copilot и Recall\",\"ok\":6,\"total\":6,\"items\":[]}," +
                "{\"module\":\"ai\",\"title\":\"ИИ-функции Windows\",\"ok\":13,\"total\":15,\"items\":[" +
                    "{\"name\":\"Paint Cocreator — выкл\",\"ok\":false,\"actual\":\"не задано\"},{\"name\":\"Edge: Copilot не читает страницы\",\"ok\":false,\"actual\":\"не задано\"}]}," +
                "{\"module\":\"services\",\"title\":\"Службы и задачи телеметрии\",\"ok\":5,\"total\":11,\"items\":[" +
                    "{\"name\":\"задача Consolidator\",\"ok\":false,\"actual\":\"Ready\"},{\"name\":\"задача ProgramDataUpdater\",\"ok\":false,\"actual\":\"Ready\"}]}" +
                "],\"dns\":[{\"name\":\"v20.events.data.microsoft.com\",\"blocked\":true},{\"name\":\"telemetry.microsoft.com\",\"blocked\":true},{\"name\":\"self.events.data.microsoft.com\",\"blocked\":false}]," +
                "\"buffer\":{\"mb\":\"4.7\",\"files\":9},\"edition\":{\"kind\":\"home\"},\"monitorEnabled\":true,\"hostsBlocked\":true}";
            RenderAudit(Json.ParseObject(audit));

            string mon = "{\"enabled\":true,\"hours\":24,\"total\":146,\"telemetryHits\":23,\"firewallRules\":6,\"blocked\":31,\"byProcess\":[" +
                "{\"name\":\"svchost.exe\",\"count\":54,\"path\":\"C:\\Windows\\System32\\svchost.exe\",\"blocked\":false}," +
                "{\"name\":\"MoUsoCoreWorker.exe\",\"count\":22,\"path\":\"C:\\Windows\\UUS\\amd64\\MoUsoCoreWorker.exe\",\"blocked\":false}," +
                "{\"name\":\"chrome.exe\",\"count\":18,\"path\":\"C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe\",\"blocked\":false}," +
                "{\"name\":\"CompatTelRunner.exe\",\"count\":12,\"path\":\"C:\\Windows\\System32\\CompatTelRunner.exe\",\"blocked\":true}," +
                "{\"name\":\"NvTelemetry.exe\",\"count\":9,\"path\":\"C:\\Program Files\\NVIDIA Corporation\\NvTelemetry\\NvTelemetry.exe\",\"blocked\":true}]," +
                "\"byDest\":[{\"ip\":\"20.42.65.90\",\"domain\":\"v20.events.data.microsoft.com\",\"count\":31,\"port\":\"443\"}," +
                "{\"ip\":\"13.89.178.26\",\"domain\":\"self.events.data.microsoft.com\",\"count\":14,\"port\":\"443\"}," +
                "{\"ip\":\"142.250.150.100\",\"domain\":\"clients4.google.com\",\"count\":11,\"port\":\"443\"}," +
                "{\"ip\":\"20.190.160.14\",\"domain\":\"login.microsoftonline.com\",\"count\":6,\"port\":\"443\"}]}";
            RenderMonitor(Json.ParseObject(mon));

            string det = "{\"os\":\"" + (L.English ? "Windows 11 Home" : "Windows 11 Домашняя") + "\",\"build\":\"26100\",\"edition\":\"Core\",\"editionKind\":\"home\",\"guardInstalled\":true,\"monitorEnabled\":true," +
                "\"guardModules\":[\"telemetry\",\"ads\",\"copilot\"],\"guardLast\":{\"time\":\"2026-08-31 12:00\",\"drifted\":[\"AllowTelemetry\",\"ShowCopilotButton\"],\"fixed\":2,\"hotfixes\":[\"KB5054321\"]}," +
                "\"firewallRules\":6,\"hostsBlocked\":true,\"diagTrack\":\"Disabled\",\"buffer\":{\"mb\":\"4.7\",\"files\":9}," +
                "\"apps\":[{\"id\":\"app_nvidia\",\"found\":true},{\"id\":\"app_vscode\",\"found\":true},{\"id\":\"app_chrome\",\"found\":true},{\"id\":\"app_firefox\",\"found\":false},{\"id\":\"app_office\",\"found\":false},{\"id\":\"app_devtools\",\"found\":true},{\"id\":\"app_vs\",\"found\":false}]," +
                "\"oem\":{\"manufacturer\":\"HONOR\",\"model\":\"HVY-WXX9\",\"items\":[{\"type\":\"svc\",\"display\":\"HnAnalyticsService\",\"state\":\"Auto\"},{\"type\":\"task\",\"display\":\"HonorUserExperience\",\"state\":\"Ready\"}]}}";
            _detect = Json.ParseObject(det);
            ApplyDetect(_detect);

            string xr = "{\"time\":\"2026-08-31 15:40\",\"hours\":24,\"recording\":true,\"total\":4812,\"distinctNames\":137," +
                "\"mb\":8.4,\"perDay\":4812,\"mbPerDay\":\"8.4\",\"perYear\":1756380,\"mbPerYear\":\"3066\"," +
                "\"baselinePerDay\":4812,\"baselineTime\":\"2026-08-30 11:00\",\"deltaPercent\":0,\"categories\":[" +
                "{\"name\":\"Список установленных программ\",\"count\":1420,\"share\":29.5,\"what\":\"Какие программы стоят на компьютере, их версии и издатели\"," +
                  "\"topNames\":[{\"name\":\"Microsoft.Windows.Inventory.Core.InventoryApplicationAdd\",\"count\":980},{\"name\":\"Microsoft.Windows.Inventory.Core.InventoryApplicationStartup\",\"count\":440}]," +
                  "\"sample\":{\"name\":\"Microsoft.Windows.Inventory.Core.InventoryApplicationAdd\",\"time\":\"2026-08-31 14:22:07\"," +
                  "\"payload\":\"{\\\"data\\\":{\\\"ProgramName\\\":\\\"Google Chrome\\\",\\\"Publisher\\\":\\\"Google LLC\\\",\\\"Version\\\":\\\"131.0.6778.86\\\",\\\"InstallDate\\\":\\\"2026-03-14\\\",\\\"RootDirPath\\\":\\\"c:/program files/google/chrome\\\"},\\\"ext\\\":{\\\"device\\\":{\\\"localId\\\":\\\"m:A1B2C3D4E5F67890\\\",\\\"deviceMake\\\":\\\"HONOR\\\",\\\"deviceModel\\\":\\\"HVY-WXX9\\\"},\\\"user\\\":{\\\"localId\\\":\\\"w:9F8E7D6C5B4A\\\"},\\\"os\\\":{\\\"osVer\\\":\\\"10.0.26100\\\"}}}\"}}," +
                "{\"name\":\"Какие программы ты запускал\",\"count\":1180,\"share\":24.5,\"what\":\"Что открывал, сколько времени провёл, как часто\"," +
                  "\"topNames\":[{\"name\":\"Win32kTraceLogging.AppInteractivitySummary\",\"count\":1180}],\"sample\":null}," +
                "{\"name\":\"Инвентаризация железа\",\"count\":820,\"share\":17.0,\"what\":\"Модель ноутбука, процессор, память, диски, серийные номера\",\"topNames\":[{\"name\":\"Census.Hardware\",\"count\":410}],\"sample\":null}," +
                "{\"name\":\"Подключённые устройства\",\"count\":540,\"share\":11.2,\"what\":\"Флешки, наушники, принтеры, мыши — что и когда подключал\",\"topNames\":[{\"name\":\"Microsoft.Windows.Kernel.PnP.DeviceConfig\",\"count\":540}],\"sample\":null}," +
                "{\"name\":\"Сбои и падения программ\",\"count\":312,\"share\":6.5,\"what\":\"Какие программы падали, с какими ошибками, имена файлов\",\"topNames\":[{\"name\":\"Microsoft.Windows.FaultReporting.AppCrashEvent\",\"count\":312}],\"sample\":null}," +
                "{\"name\":\"Браузер\",\"count\":290,\"share\":6.0,\"what\":\"Активность в браузере, посещения, проверки сайтов\",\"topNames\":[{\"name\":\"Microsoft.Edge.Browser.Navigation\",\"count\":290}],\"sample\":null}," +
                "{\"name\":\"Учётная запись\",\"count\":250,\"share\":5.3,\"what\":\"Входы в систему, привязка к учётной записи Microsoft\",\"topNames\":[],\"sample\":null}]," +
                "\"identifiers\":[{\"key\":\"localId\",\"distinct\":2,\"values\":[{\"value\":\"m:A1B2C3D4E5F67890\",\"count\":4812}]}," +
                "{\"key\":\"deviceMake\",\"distinct\":1,\"values\":[{\"value\":\"HONOR\",\"count\":4812}]}," +
                "{\"key\":\"deviceModel\",\"distinct\":1,\"values\":[{\"value\":\"HVY-WXX9\",\"count\":4812}]}]," +
                "\"apps\":[{\"name\":\"Google Chrome\",\"count\":980},{\"name\":\"Visual Studio Code\",\"count\":610},{\"name\":\"Telegram Desktop\",\"count\":320},{\"name\":\"Steam\",\"count\":180}]," +
                "\"facts\":[" +
                "{\"id\":\"apps\",\"title\":\"Названия установленных программ\",\"distinct\":47,\"what\":\"Windows перечисляет, что у вас стоит: имя, издатель и версия каждой программы.\",\"examples\":[\"Google Chrome\",\"Visual Studio Code\",\"Steam\",\"Telegram Desktop\",\"VMware Workstation\"]}," +
                "{\"id\":\"device\",\"title\":\"Модель и производитель компьютера\",\"distinct\":3,\"what\":\"Точная модель железа — по ней устройство узнаётся среди прочих.\",\"examples\":[\"HONOR\",\"HVY-WXX9\",\"AMD Ryzen 7 5700U\"]}," +
                "{\"id\":\"ids\",\"title\":\"Идентификаторы, которыми вас метят\",\"distinct\":4,\"what\":\"Постоянные номера устройства и учётной записи: по ним события связываются в один профиль.\",\"examples\":[\"m:A1B2C3D4E5F67890\",\"g:5f3c9a11-77b2\"]}," +
                "{\"id\":\"devices\",\"title\":\"Подключённые устройства\",\"distinct\":19,\"what\":\"Всё, что вы подключали: принтеры, флешки, наушники, телефоны.\",\"examples\":[\"Kingston DataTraveler\",\"HUAWEI FreeBuds\",\"HP LaserJet 1020\"]}," +
                "{\"id\":\"user\",\"title\":\"Учётная запись и язык\",\"distinct\":5,\"what\":\"Имя пользователя, страна, часовой пояс и раскладка.\",\"examples\":[\"Profe\",\"RU\",\"Russian Standard Time\"]}]," +
                "\"db\":{\"mb\":42.7,\"files\":6}}";
            _lastXray = Json.ParseObject(xr);
            RenderXray(_lastXray);
            _lastAudit = Json.ParseObject(audit);

            string spy = "{\"time\":\"2026-08-31 19:20\",\"activeNow\":1,\"week\":9," +
                "\"days\":[" +
                "{\"date\":\"18.08\",\"cam\":0,\"mic\":1,\"loc\":0,\"other\":0}," +
                "{\"date\":\"19.08\",\"cam\":1,\"mic\":2,\"loc\":1,\"other\":0}," +
                "{\"date\":\"20.08\",\"cam\":0,\"mic\":0,\"loc\":0,\"other\":0}," +
                "{\"date\":\"21.08\",\"cam\":0,\"mic\":3,\"loc\":1,\"other\":0}," +
                "{\"date\":\"22.08\",\"cam\":2,\"mic\":4,\"loc\":0,\"other\":1}," +
                "{\"date\":\"23.08\",\"cam\":0,\"mic\":1,\"loc\":2,\"other\":0}," +
                "{\"date\":\"24.08\",\"cam\":0,\"mic\":0,\"loc\":1,\"other\":0}," +
                "{\"date\":\"25.08\",\"cam\":1,\"mic\":2,\"loc\":0,\"other\":0}," +
                "{\"date\":\"26.08\",\"cam\":0,\"mic\":5,\"loc\":1,\"other\":0}," +
                "{\"date\":\"27.08\",\"cam\":0,\"mic\":1,\"loc\":3,\"other\":0}," +
                "{\"date\":\"28.08\",\"cam\":1,\"mic\":0,\"loc\":0,\"other\":0}," +
                "{\"date\":\"29.08\",\"cam\":2,\"mic\":3,\"loc\":1,\"other\":0}," +
                "{\"date\":\"30.08\",\"cam\":0,\"mic\":6,\"loc\":0,\"other\":1}," +
                "{\"date\":\"31.08\",\"cam\":1,\"mic\":4,\"loc\":2,\"other\":0}]," +
                "\"caps\":[" +
                "{\"id\":\"webcam\",\"title\":\"Камера\",\"global\":\"Allow\",\"count\":2,\"items\":[" +
                  "{\"app\":\"Telegram.exe\",\"last\":\"2026-08-31 18:55\",\"minutes\":0,\"active\":true}," +
                  "{\"app\":\"chrome.exe\",\"last\":\"2026-08-29 21:14\",\"minutes\":41.5,\"active\":false}]}," +
                "{\"id\":\"microphone\",\"title\":\"Микрофон\",\"global\":\"Allow\",\"count\":3,\"items\":[" +
                  "{\"app\":\"cs2.exe\",\"last\":\"2026-08-30 19:43\",\"minutes\":103.6,\"active\":false}," +
                  "{\"app\":\"obs64.exe\",\"last\":\"2026-08-28 13:00\",\"minutes\":85.5,\"active\":false}," +
                  "{\"app\":\"chrome.exe\",\"last\":\"2026-08-27 18:36\",\"minutes\":2.2,\"active\":false}]}," +
                "{\"id\":\"location\",\"title\":\"Местоположение\",\"global\":\"Allow\",\"count\":2,\"items\":[" +
                  "{\"app\":\"Виджеты Windows\",\"last\":\"2026-08-31 19:14\",\"minutes\":0.2,\"active\":false}," +
                  "{\"app\":\"msedge.exe\",\"last\":\"2026-08-04 12:22\",\"minutes\":0,\"active\":false}]}]}";
            _lastSpy = Json.ParseObject(spy);

            string foot = "{\"time\":\"2026-08-31 19:21\",\"totalMb\":37.8,\"wipeable\":7,\"items\":[" +
                "{\"id\":\"adid\",\"title\":\"Рекламный идентификатор\",\"what\":\"Уникальный ID, по которому рекламные сети узнают вас во всех приложениях.\",\"value\":\"a1b2c3d4-e5f6-7890-abcd-ef0123456789\",\"mb\":0,\"count\":1,\"canWipe\":true}," +
                "{\"id\":\"machineid\",\"title\":\"Постоянные метки компьютера\",\"what\":\"MachineGuid и SQM MachineId — метки, которыми помечается телеметрия. Нужны системе, стереть нельзя.\",\"value\":\"cdfc5378-…\",\"mb\":0,\"count\":2,\"canWipe\":false}," +
                "{\"id\":\"networks\",\"title\":\"История сетей Wi-Fi и Ethernet\",\"what\":\"Список всех сетей, к которым подключался компьютер — по ним видно, где вы бывали. Пароли Wi-Fi не трогаются.\",\"value\":\"Home_5G, Cafe_Free, Airport-WiFi …\",\"mb\":0,\"count\":14,\"canWipe\":true}," +
                "{\"id\":\"usb\",\"title\":\"История подключённых флешек\",\"what\":\"Windows помнит каждую флешку и внешний диск. Запись системная, показываем для сведения.\",\"value\":\"Kingston DataTraveler, WD Elements …\",\"mb\":0,\"count\":6,\"canWipe\":false}," +
                "{\"id\":\"activity\",\"title\":\"База истории активности\",\"what\":\"ActivitiesCache.db — какие программы и документы вы открывали, с точным временем.\",\"value\":\"18.2 МБ\",\"mb\":18.2,\"count\":5,\"canWipe\":true}," +
                "{\"id\":\"recent\",\"title\":\"Недавние документы и папки\",\"what\":\"Ярлыки всего, что вы открывали, плюс списки переходов на панели задач.\",\"value\":\"212 записей\",\"mb\":1.4,\"count\":212,\"canWipe\":true}," +
                "{\"id\":\"clipboard\",\"title\":\"История буфера обмена\",\"what\":\"Всё скопированное (Win+V) хранится на диске.\",\"value\":\"включена, 6.1 МБ\",\"mb\":6.1,\"count\":31,\"canWipe\":true}," +
                "{\"id\":\"wer\",\"title\":\"Архив отчётов об ошибках\",\"what\":\"Дампы и отчёты о сбоях: содержат пути файлов, имена программ, куски памяти.\",\"value\":\"144 отчётов, 11.6 МБ\",\"mb\":11.6,\"count\":144,\"canWipe\":true}," +
                "{\"id\":\"dnscache\",\"title\":\"Кэш DNS (следы сайтов)\",\"what\":\"Адреса сайтов и служб, к которым недавно обращался компьютер.\",\"value\":\"103 записей\",\"mb\":0,\"count\":103,\"canWipe\":true}]}";
            string appsJson = "{\"time\":\"2026-09-01 00:30\",\"apps\":[" +
                "{\"name\":\"Microsoft.BingNews\",\"title\":\"Новости MSN\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":true}," +
                "{\"name\":\"Microsoft.BingWeather\",\"title\":\"Погода MSN\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":true}," +
                "{\"name\":\"Clipchamp.Clipchamp\",\"title\":\"Видеоредактор Clipchamp\",\"publisher\":\"CN=Clipchamp Pty Ltd\",\"bloat\":true}," +
                "{\"name\":\"Microsoft.GamingApp\",\"title\":\"Приложение Xbox\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":true}," +
                "{\"name\":\"Microsoft.MicrosoftSolitaireCollection\",\"title\":\"Коллекция пасьянсов\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":true}," +
                "{\"name\":\"MicrosoftTeams\",\"title\":\"Teams (личный)\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":true}," +
                "{\"name\":\"Microsoft.YourPhone\",\"title\":\"Связь с телефоном\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":true}," +
                "{\"name\":\"Microsoft.WindowsFeedbackHub\",\"title\":\"Центр отзывов\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":true}," +
                "{\"name\":\"Microsoft.WindowsCalculator\",\"title\":\"Microsoft.WindowsCalculator\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":false}," +
                "{\"name\":\"Microsoft.WindowsCamera\",\"title\":\"Microsoft.WindowsCamera\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":false}," +
                "{\"name\":\"Microsoft.Windows.Photos\",\"title\":\"Microsoft.Windows.Photos\",\"publisher\":\"CN=Microsoft Corporation\",\"bloat\":false}]}";
            RenderApps(Json.ParseObject(appsJson));

            string startJson = "{\"time\":\"2026-09-01 12:10\",\"total\":11,\"on\":8,\"advise\":5,\"items\":[" +
                "{\"id\":\"a1\",\"name\":\"GoogleUpdate\",\"publisher\":\"Google LLC\",\"cmd\":\"C:\\\\Program Files (x86)\\\\Google\\\\Update\\\\GoogleUpdate.exe /c\",\"source\":\"реестр, все пользователи\",\"kind\":\"run\",\"enabled\":true,\"advise\":true,\"keep\":false,\"note\":\"обновлятор Google: работает постоянно и шлёт статистику\"}," +
                "{\"id\":\"a2\",\"name\":\"OneDrive\",\"publisher\":\"Microsoft Corporation\",\"cmd\":\"C:\\\\Program Files\\\\Microsoft OneDrive\\\\OneDrive.exe /background\",\"source\":\"реестр, этот пользователь\",\"kind\":\"run\",\"enabled\":true,\"advise\":true,\"keep\":false,\"note\":\"OneDrive: синхронизация в облако\"}," +
                "{\"id\":\"a3\",\"name\":\"NvBackend\",\"publisher\":\"NVIDIA Corporation\",\"cmd\":\"C:\\\\Program Files (x86)\\\\NVIDIA Corporation\\\\Update Core\\\\NvBackend.exe\",\"source\":\"реестр, все пользователи\",\"kind\":\"run\",\"enabled\":true,\"advise\":true,\"keep\":false,\"note\":\"спутник драйвера NVIDIA: телеметрия и вход в аккаунт\"}," +
                "{\"id\":\"a4\",\"name\":\"HonorPCManager\",\"publisher\":\"HONOR Device Co., Ltd.\",\"cmd\":\"C:\\\\Program Files\\\\Honor\\\\PCManager\\\\PCManager.exe -autorun\",\"source\":\"планировщик задач, при входе\",\"kind\":\"task\",\"enabled\":true,\"advise\":true,\"keep\":false,\"note\":\"программа производителя: собирает сведения о ноутбуке\"}," +
                "{\"id\":\"a5\",\"name\":\"Steam\",\"publisher\":\"Valve Corporation\",\"cmd\":\"C:\\\\Program Files (x86)\\\\Steam\\\\steam.exe -silent\",\"source\":\"реестр, этот пользователь\",\"kind\":\"run\",\"enabled\":true,\"advise\":true,\"keep\":false,\"note\":\"программа сама себя запускает при входе\"}," +
                "{\"id\":\"a6\",\"name\":\"SecurityHealth\",\"publisher\":\"Microsoft Corporation\",\"cmd\":\"%windir%\\\\system32\\\\SecurityHealthSystray.exe\",\"source\":\"реестр, все пользователи\",\"kind\":\"run\",\"enabled\":true,\"advise\":false,\"keep\":true,\"note\":\"\"}," +
                "{\"id\":\"a7\",\"name\":\"RtkAudUService\",\"publisher\":\"Realtek Semiconductor\",\"cmd\":\"RtkAudUService64.exe -background\",\"source\":\"реестр, все пользователи\",\"kind\":\"run\",\"enabled\":true,\"advise\":false,\"keep\":true,\"note\":\"\"}," +
                "{\"id\":\"a8\",\"name\":\"vmware-tray\",\"publisher\":\"VMware, Inc.\",\"cmd\":\"C:\\\\Program Files (x86)\\\\VMware\\\\vmware-tray.exe\",\"source\":\"реестр, все пользователи\",\"kind\":\"run\",\"enabled\":true,\"advise\":false,\"keep\":false,\"note\":\"\"}," +
                "{\"id\":\"a9\",\"name\":\"MicrosoftEdgeAutoLaunch\",\"publisher\":\"Microsoft Corporation\",\"cmd\":\"C:\\\\Program Files (x86)\\\\Microsoft\\\\Edge\\\\Application\\\\msedge.exe --no-startup-window\",\"source\":\"реестр, этот пользователь\",\"kind\":\"run\",\"enabled\":false,\"advise\":true,\"keep\":false,\"note\":\"автозапуск и обновлятор Edge\"}," +
                "{\"id\":\"a10\",\"name\":\"Telegram\",\"publisher\":\"Telegram FZ-LLC\",\"cmd\":\"C:\\\\Users\\\\user\\\\AppData\\\\Roaming\\\\Telegram Desktop\\\\Telegram.exe -autostart\",\"source\":\"папка автозагрузки, этот пользователь\",\"kind\":\"folder\",\"enabled\":false,\"advise\":true,\"keep\":false,\"note\":\"программа сама себя запускает при входе\"}," +
                "{\"id\":\"a11\",\"name\":\"AdobeAAMUpdater-1.0\",\"publisher\":\"Adobe Inc.\",\"cmd\":\"C:\\\\Program Files (x86)\\\\Common Files\\\\Adobe\\\\OOBE\\\\PDApp\\\\UWA\\\\UpdaterStartupUtility.exe\",\"source\":\"реестр, все пользователи\",\"kind\":\"run\",\"enabled\":false,\"advise\":true,\"keep\":false,\"note\":\"служба обновлений Adobe\"}]}";
            RenderStartup(Json.ParseObject(startJson));

            string changesJson = "{\"count\":4,\"raw\":37,\"updated\":\"2026-09-01T21:14:00\",\"items\":[" +
                "{\"id\":\"c1\",\"kind\":\"startup\",\"title\":\"GoogleUpdate\",\"where\":\"автозагрузка\",\"was\":\"запускалась\",\"now\":\"отключена\",\"time\":\"2026-09-01T21:14:00\",\"count\":1}," +
                "{\"id\":\"c2\",\"kind\":\"reg\",\"title\":\"уровень телеметрии — минимальный\",\"where\":\"HKLM:\\\\SOFTWARE\\\\Policies\\\\Microsoft\\\\Windows\\\\DataCollection\",\"was\":\"3\",\"now\":\"0\",\"time\":\"2026-09-01T20:58:00\",\"count\":2}," +
                "{\"id\":\"c3\",\"kind\":\"reg\",\"title\":\"рекламный ID — выкл\",\"where\":\"HKCU:\\\\SOFTWARE\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\AdvertisingInfo\",\"was\":\"не было\",\"now\":\"0\",\"time\":\"2026-09-01T20:58:00\",\"count\":1}," +
                "{\"id\":\"c4\",\"kind\":\"reg\",\"title\":\"Windows Copilot — выкл\",\"where\":\"HKCU:\\\\SOFTWARE\\\\Policies\\\\Microsoft\\\\Windows\\\\WindowsCopilot\",\"was\":\"не было\",\"now\":\"1\",\"time\":\"2026-09-01T20:58:00\",\"count\":1}]}";
            RenderChanges(Json.ParseObject(changesJson));

            StringBuilder tl = new StringBuilder();
            tl.Append("{\"count\":30,\"peak\":5200,\"hasXray\":true,\"time\":\"2026-09-01 23:40\",\"days\":[");
            int[] ev = { 1200, 1180, 1240, 1210, 1190, 1220, 1205, 1230, 1215, 1198,
                         1240, 1260, 4900, 5200, 4780, 4600, 4520, 4480, 4400, 1320,
                         1280, 1250, 1230, 1210, 1190, 1205, 1180, 1160, 980, 640 };
            for (int i = 0; i < 30; i++)
            {
                DateTime day = new DateTime(2026, 8, 3).AddDays(i);
                string ups = (i == 12) ? "\"KB5065426\"" : ((i == 26) ? "\"KB5070101\"" : "");
                tl.Append(i > 0 ? "," : "").Append("{\"date\":\"").Append(day.ToString("yyyy-MM-dd"))
                  .Append("\",\"label\":\"").Append(day.ToString("dd.MM"))
                  .Append("\",\"events\":").Append(ev[i])
                  .Append(",\"sensors\":").Append((i % 4 == 0) ? 6 : 2)
                  .Append(",\"changes\":").Append((i == 19 || i == 29) ? 14 : 0)
                  .Append(",\"drifted\":").Append((i == 19) ? 6 : 0)
                  .Append(",\"fixed\":").Append((i == 19) ? 6 : 0)
                  .Append(",\"updates\":[").Append(ups).Append("]}");
            }
            tl.Append("],\"notes\":[" +
                "{\"date\":\"15.08\",\"kind\":\"update\",\"a\":0,\"b\":0,\"list\":\"KB5065426\"}," +
                "{\"date\":\"16.08\",\"kind\":\"grow\",\"a\":1260,\"b\":4900,\"list\":\"\"}," +
                "{\"date\":\"22.08\",\"kind\":\"drift\",\"a\":6,\"b\":6,\"list\":\"\"}," +
                "{\"date\":\"29.08\",\"kind\":\"update\",\"a\":0,\"b\":0,\"list\":\"KB5070101\"}]}");
            RenderTimeline(Json.ParseObject(tl.ToString()));
            if (_qcStartup != null) _qcStartup.SetStatus(5 + L.T(" лишних из ") + 8, Theme.Warn);
            if (_qcTimeline != null) _qcTimeline.SetStatus("29.08 — " + L.T("обновление Windows"), Theme.Accent);

            SetAboutBody(_aboutData, "Папка: C:\\ProgramData\\Win11Privacy\n" +
                "• История датчиков по дням: кто включал камеру, микрофон и геолокацию — 9,9 КБ, изменён 2026-09-01 20:03\n" +
                "• Журнал изменений: что программа поменяла и что было до неё — 4,2 КБ, изменён 2026-09-01 21:14\n" +
                "• Снимок «до»: состояние системы перед первым применением — 1,1 КБ, изменён 2026-09-01 20:58\n" +
                "Всего: 15,2 КБ. Наружу ничего из этого не уходит.");

            _lastFoot = Json.ParseObject(foot);
            if (Environment.GetEnvironmentVariable("WIN11_TEST_ONLYFOOT") == "1") _lastSpy = null;
            RenderDossier();

            RefreshHome();
            _xrayRecording = true;
            _btnXrayRec.Text = L.T("Выключить запись"); _btnXrayRec.Primary = false;
            foreach (Control c in _xrayList.Controls) { if (c is XrayCatRow) { ((XrayCatRow)c).Expand(); break; } }
        }
#endif
    }
}
