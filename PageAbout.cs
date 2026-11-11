// Часть MainForm: страница «О программе», данные программы, проверка обновления.

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
        //  Страница: О программе
        // ================================================================== //
        private Control BuildAboutPage()
        {
            int u = Font.Height;
            Panel page = new Panel(); page.BackColor = Theme.WindowBg; page.AutoScroll = true;
            FlowLayoutPanel f = new FlowLayoutPanel();
            f.FlowDirection = FlowDirection.TopDown; f.WrapContents = false; f.AutoSize = true;
            f.Dock = DockStyle.Top; f.Padding = new Padding(0);
            TableLayoutPanel aboutHead = new TableLayoutPanel();
            aboutHead.ColumnCount = 2; aboutHead.RowCount = 1; aboutHead.AutoSize = true;
            aboutHead.BackColor = Theme.WindowBg;
            aboutHead.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            aboutHead.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            aboutHead.Controls.Add(PageTitle(L.T("О программе")), 0, 0);
            FlowLayoutPanel aboutBtns = new FlowLayoutPanel();
            aboutBtns.AutoSize = true; aboutBtns.WrapContents = true;    // ширину задаёт FitAboutCards
            aboutBtns.Anchor = AnchorStyles.Left | AnchorStyles.Bottom;
            aboutBtns.Margin = new Padding((int)(u * 1.2F), 0, 0, (int)(u * 0.15F));
            _aboutBtns = aboutBtns;
            // как в Windows → русский → английский → как в Windows
            ModernButton bLang = new ModernButton(LangButtonText(), false);
            bLang.Font = Font;
            bLang.Click += delegate
            {
                _langChoice = (_langChoice + 1) % 3;
                SaveUiState();
                bLang.Text = LangButtonText();
                bool next = _langChoice == 0 ? L.SystemEnglish() : _langChoice == 2;
                if (next != L.English)
                    MessageBox.Show(this,
                        next ? "The language will change after restarting the program."
                             : "Язык интерфейса сменится после перезапуска программы.",
                        L.T("Приватность Windows 11"), MessageBoxButtons.OK, MessageBoxIcon.Information);
            };
            aboutBtns.Controls.Add(bLang);

            ModernButton bTheme = new ModernButton(ThemeButtonText(), false);
            bTheme.Font = Font;
            bTheme.Click += delegate
            {
                _themeChoice = (_themeChoice + 1) % 3;
                SaveUiState();
                bTheme.Text = ThemeButtonText();
                MessageBox.Show(this, L.T("Тема сменится после перезапуска программы."),
                    L.T("Приватность Windows 11"), MessageBoxButtons.OK, MessageBoxIcon.Information);
            };
            aboutBtns.Controls.Add(bTheme);

            ModernButton bUpd = new ModernButton(L.T("Проверить обновление"), false);
            _btnUpdate = bUpd;
            bUpd.Font = Font;
            bUpd.Click += delegate { CheckUpdate(bUpd); };
            aboutBtns.Controls.Add(bUpd);

            ModernButton bPurge = new ModernButton(L.T("Удалить данные программы"), false);
            bPurge.Font = Font;
            bPurge.Click += OnPurgeData;
            aboutBtns.Controls.Add(bPurge);
            foreach (Control b in aboutBtns.Controls) b.Margin = new Padding(0, 0, (int)(u * 0.4F), (int)(u * 0.3F));
            aboutHead.Controls.Add(aboutBtns, 1, 0);
            f.Controls.Add(aboutHead);

            _aboutVersion = AboutCard(L.T("Версия программы"), VersionText());
            f.Controls.Add(_aboutVersion);

            _aboutEdition = AboutCard(L.T("Ваша система"), L.T("Определение…"));
            f.Controls.Add(_aboutEdition);

            _aboutData = AboutCard(L.T("Что программа хранит о вас у себя"), L.T("Чтение…"));
            f.Controls.Add(_aboutData);

            f.Controls.Add(AboutCard(L.T("Что умеет эта программа, чего нет у других"),
                L.T("• Следы на компьютере: кто и когда реально включал камеру, микрофон и геолокацию — с длительностью и меткой «сейчас».\n") +
                L.T("• Слежение за датчиками: уведомление в момент, когда НОВАЯ программа впервые получила доступ; график по дням.\n") +
                L.T("• Цифровой след: рекламный ID, история сетей и флешек, всё, что Windows помнит о вас — с выборочным стиранием.\n") +
                L.T("• Сбор данных: настоящие события, собранные о компьютере, с сырым содержимым.\n") +
                L.T("• Проверка на деле: читает реальное состояние системы и показывает индекс, а не «галочки».\n") +
                L.T("• Сеть: показывает, кто и куда реально отправляет данные.\n") +
                L.T("• Автозащита: возвращает настройки, сбитые обновлениями Windows; машина времени со снимками состояния.\n") +
                L.T("• Телеметрия сторонних программ и слежка производителя ноутбука.\n") +
                L.T("• Блокировка через брандмауэр, а не только hosts; удаление накопленного буфера телеметрии.\n") +
                L.T("• Профили и тихий запуск из командной строки для настройки нескольких ПК.\n") +
                L.T("• Быстрые клавиши: Ctrl+1…9 и Ctrl+0 — страницы, Ctrl+F — поиск по настройкам.")));

            f.Controls.Add(AboutCard(L.T("Командная строка"),
                L.T("Win11Privacy.exe --profile \"C:\\путь\\profile.json\" --silent   тихо применить профиль\n") +
                L.T("Win11Privacy.exe --audit                                     проверка (код возврата = число несоответствий)\n") +
                L.T("Профиль сохраняется кнопкой «Сохранить профиль» на странице «Настройки»."), true));

            f.Controls.Add(AboutCard(L.T("Честно о пределах"),
                L.T("Полностью прекратить обмен данными с Microsoft на Windows нельзя: остаются проверка обновлений,\n") +
                L.T("активация лицензии и проверка сертификатов. На редакциях Home и Pro минимальный уровень телеметрии\n") +
                L.T("система трактует как «Обязательные данные» — это ограничение редакции, а не программы. Всё, что можно\n") +
                L.T("отключить без поломки системы, эта программа отключает, а автозащита не даёт вернуть обратно.")));

            f.Controls.Add(AboutCard(L.T("Запуск без предупреждения SmartScreen"),
                L.T("Синее окно показывается любому неподписанному приложению из интернета. Убрать его можно так:\n") +
                L.T("правый клик по файлу → Свойства → внизу галочка «Разблокировать» → ОК. Запрос прав администратора\n") +
                L.T("(UAC) остаётся — он нужен, потому что программа меняет системные настройки.")));
            page.Controls.Add(f);
            page.Resize += delegate { FitAboutCards(page); };
            _aboutFlow = f;
            return page;
        }
        private Control _aboutEdition, _aboutData, _aboutVersion;
        private ModernButton _btnUpdate;
#pragma warning disable 0649
        private bool _mockMode;             // ставится только в тестовой сборке
#pragma warning restore 0649
        // Переносимый режим: рядом с exe лежит файл portable.txt — тогда все
        // данные программы хранятся там же, а не в ProgramData, и на чужом
        // компьютере после себя ничего не остаётся.
        private static string _portableRoot;
        private static string PortableRoot()
        {
            if (_portableRoot != null) return _portableRoot;
            _portableRoot = "";
            try
            {
                string dir = Path.GetDirectoryName(Application.ExecutablePath);
                if (File.Exists(Path.Combine(dir, "portable.txt")))
                {
                    string data = Path.Combine(dir, "Win11Privacy-Data");
                    if (!Directory.Exists(data)) Directory.CreateDirectory(data);
                    _portableRoot = data;
                }
            }
            catch { }
            return _portableRoot;
        }
        private FlowLayoutPanel _aboutFlow, _aboutBtns;

        // Старый флаг «en» → выбор языка: совпадает с Windows — «как в Windows»
        internal static int LangChoiceFromOld(bool en, bool systemEnglish)
        {
            return en == systemEnglish ? 0 : (en ? 2 : 1);
        }

        private string LangButtonText()
        {
            if (_langChoice == 1) return L.T("Язык: русский");
            if (_langChoice == 2) return L.T("Язык: английский");
            return L.T("Язык: как в Windows");
        }

        private string ThemeButtonText()
        {
            if (_themeChoice == 1) return L.T("Тема: тёмная");
            if (_themeChoice == 2) return L.T("Тема: светлая");
            return L.T("Тема: как в Windows");
        }

        // Что программа накопила у себя — и кнопка это стереть
        private void RefreshDataInfo()
        {
            RunJson("-DataInfo", L.T("Чтение данных программы…"), delegate(Dictionary<string, object> d)
            {
                if (d == null) { SetAboutBody(_aboutData, L.T("Не удалось прочитать папку с данными.")); return; }
                List<object> items = Json.GetArr(d, "items");
                StringBuilder sb = new StringBuilder();
                sb.Append(L.T("Папка: ")).Append(Json.GetStr(d, "folder")).Append("\n");
                if (items.Count == 0) sb.Append(L.T("Программа ничего о вас не хранит."));
                else
                {
                    foreach (object o in items)
                    {
                        Dictionary<string, object> it = Json.Obj(o);
                        sb.Append("• ").Append(L.T(Json.GetStr(it, "title")))
                          .Append(" — ").Append(Json.GetStr(it, "kb")).Append(L.T(" КБ, изменён "))
                          .Append(Json.GetStr(it, "changed")).Append("\n");
                    }
                    sb.Append(L.T("Всего: ")).Append(Json.GetStr(d, "kb")).Append(L.T(" КБ. Наружу ничего из этого не уходит."));
                }
                SetAboutBody(_aboutData, sb.ToString());
            });
        }

        private void OnPurgeData(object sender, EventArgs e)
        {
            if (MessageBox.Show(this,
                L.T("Программа удалит всё, что накопила о вас у себя: историю датчиков,\n") +
                L.T("журнал изменений, снимки и эталоны сбора данных.\n\n") +
                L.T("Вернуть настройки «как было» после этого будет нечем — журнал отката\n") +
                L.T("пропадёт вместе с остальным.\n\nПродолжить?"),
                L.T("Удаление данных программы"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            RunStreaming("-PurgeData", L.T("Удаление данных программы…"), delegate { Navigate("about"); RefreshDataInfo(); });
        }

        // Карточки «О программе» тянутся по ширине окна, но не шире 54 строчных высот
        private void FitAboutCards(Control page)
        {
            if (_aboutFlow == null) return;
            int u = Font.Height;
            int w = Math.Max((int)(u * 24F), Math.Min((int)(u * 54F), page.ClientSize.Width - (int)(u * 1.2F)));
            // кнопки шапки переносятся, а не уезжают за край узкого окна
            Control title = _aboutBtns.Parent.Controls[0];
            int room = page.ClientSize.Width - title.PreferredSize.Width - title.Margin.Horizontal - _aboutBtns.Margin.Horizontal;
            _aboutBtns.MaximumSize = new Size(Math.Max((int)(u * 12F), room), 0);
            foreach (Control c in _aboutFlow.Controls)
            {
                TableLayoutPanel tl = null;
                foreach (Control cc in c.Controls) { tl = cc as TableLayoutPanel; if (tl != null) break; }
                if (tl == null || tl.ColumnStyles.Count == 0) continue;
                int inner = w - c.Padding.Horizontal;
                if ((int)tl.ColumnStyles[0].Width == inner) continue;
                tl.ColumnStyles[0].Width = inner;
                tl.Width = inner;
                foreach (Control lb in tl.Controls)
                    if (lb is Label) lb.MaximumSize = new Size(inner, 0);
            }
        }

        private Control AboutCard(string title, string body) { return AboutCard(title, body, false); }

        // ВАЖНО: шрифт меткам задаём здесь же. Раньше высота карточки считалась
        // до того, как ей доставался шрифт формы, — по системному 8-точечному,
        // и настоящий текст в эту высоту потом не влезал (обрезался снизу).
        private Control AboutCard(string title, string body, bool mono)
        {
            int u = Font.Height;
            int cardW = (int)(u * 54F);
            int padX = (int)(u * 0.9F);
            int innerW = cardW - padX * 2;
            Card c = new Card();
            c.Margin = new Padding(0, 0, 0, (int)(u * 0.6F));
            c.Padding = new Padding(padX, (int)(u * 0.7F), padX, (int)(u * 0.7F));
            c.AutoSize = true;
            c.AutoSizeMode = AutoSizeMode.GrowAndShrink;

            TableLayoutPanel tl = new TableLayoutPanel();
            tl.AutoSize = true; tl.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            tl.ColumnCount = 1; tl.RowCount = 2; tl.BackColor = Theme.CardBg;
            tl.Margin = new Padding(0);
            // обычная панель не двигает недокованных детей на свой Padding —
            // ставим руками, иначе текст прижимается к самому краю карточки
            tl.Location = new Point(padX, (int)(u * 0.7F));
            tl.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, innerW));
            tl.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            tl.RowStyles.Add(new RowStyle(SizeType.AutoSize));

            Label t = new Label(); t.Text = title; t.Font = Theme.Bold(Font); t.ForeColor = Theme.Text;
            t.AutoSize = true; t.MaximumSize = new Size(innerW, 0);
            t.Margin = new Padding(0, 0, 0, (int)(u * 0.4F));
            Label b = new Label(); b.Text = body; b.ForeColor = Theme.TextDim; b.AutoSize = true;
            // моноширинный — для командной строки: только так колонки сходятся
            b.Font = mono ? Theme.PickFont(Theme.MonoFonts, Font.Size * 0.95F, FontStyle.Regular) : Font;
            b.Margin = new Padding(0);
            b.MaximumSize = new Size(innerW, 0); b.Tag = "body";
            tl.Controls.Add(t, 0, 0); tl.Controls.Add(b, 0, 1);
            c.Controls.Add(tl);
            return c;
        }
        // Версия видна не из любви к номерам: в 1.1–1.5 настройки писались под
        // числовыми именами и ничего не меняли, и человеку нужно понимать,
        // относится ли к нему совет «нажмите „Убрать мусор“».
        private string VersionText()
        {
            string s = L.T("Версия ") + AppInfo.Version + "." + "\n" +
                       L.T("Обновления сама программа не проверяет и в сеть не выходит: только по кнопке «Проверить обновление».");
            if (_updateNote != null) s += "\n" + _updateNote;
            string dir = EngineFile.Folder;
            if (dir.Length > 0)
                s += "\n" + L.T("Движок распакован: ") + dir +
                     (EngineFile.Guarded ? L.T(" (папка закрыта для записи без прав администратора)")
                                         : L.T(" (временная папка — прав на защищённую не хватило)"));
            return s;
        }

#if UITEST
        // Нажимает кнопку так же, как это делает человек: проверяется весь путь
        // от щелчка до вердикта, а не одна лишь работа с сетью.
        internal void PressUpdateForTest()
        {
            if (_btnUpdate == null) { Console.WriteLine("UPDATE кнопка не найдена"); return; }
            InvokeOnClick(_btnUpdate, EventArgs.Empty);
        }
#endif

        // Что ответил GitHub в прошлый раз. Хранится, потому что карточку
        // перерисовывает и определение системы — оно заканчивается позже
        // проверки и раньше затирало её ответ.
        private string _updateNote;

        private void CheckUpdate(ModernButton btn)
        {
            btn.Enabled = false;
            _status.Text = L.T("Проверка обновления…");
            System.Threading.Thread th = new System.Threading.Thread(delegate()
            {
                string err;
                string tag = AppInfo.LatestRelease(out err);
                try { BeginInvoke((MethodInvoker)delegate { ShowUpdate(tag, err, btn); }); } catch { }
            });
            th.IsBackground = true;
            th.Start();
        }

        // Что именно сказать про версию — решается отдельно от показа окна.
        // Так вердикт можно проверить, не открывая модальных диалогов, и так
        // видно, что состояний не два, а четыре: своя сборка бывает и новее
        // последнего релиза (промежуточная, собранная из исходников).
        internal enum UpdateState { Failed, Newer, Same, Ahead }

        internal static UpdateState UpdateVerdict(string tag, string err, out string status, out string card)
        {
            if (tag == null || tag.Length == 0)
            {
                status = L.T("Проверить не удалось.");
                card = err;
                return UpdateState.Failed;
            }
            int cmp = AppInfo.Compare(AppInfo.Version, tag);
            if (cmp < 0)
            {
                status = L.T("Есть новая версия: ") + tag;
                card = L.T("На GitHub выложена ") + tag;
                return UpdateState.Newer;
            }
            if (cmp == 0)
            {
                status = L.T("У вас последняя версия.");
                card = L.T("На GitHub та же версия — обновляться не нужно.");
                return UpdateState.Same;
            }
            status = L.T("У вас сборка новее релиза.");
            card = L.T("На GitHub пока ") + tag + L.T(" — ваша сборка новее.");
            return UpdateState.Ahead;
        }

        private void ShowUpdate(string tag, string err, ModernButton btn)
        {
            btn.Enabled = true;
            string status, card;
            UpdateState st = UpdateVerdict(tag, err, out status, out card);
            _status.Text = status;
            if (st != UpdateState.Failed) _updateNote = card;
            if (_aboutVersion != null) SetAboutBody(_aboutVersion, VersionText());
#if UITEST
            // в тестовой сборке модальных окон не открываем — иначе прогон встанет
            Console.WriteLine("UPDATE " + st + " | " + status + " | " + card);
            return;
#pragma warning disable 0162
#endif
            if (st == UpdateState.Failed)
            {
                MessageBox.Show(this, err, L.T("Проверка обновления"), MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            if (st != UpdateState.Newer)
            {
                MessageBox.Show(this, status + "\n\n" + L.T("Версия программы: ") + AppInfo.Version,
                    L.T("Проверка обновления"), MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            if (MessageBox.Show(this, L.T("Вышла версия ") + tag + L.T(", у вас ") + AppInfo.Version + "." + "\n" + "\n" +
                                      L.T("Открыть страницу загрузки в браузере?"),
                                L.T("Проверка обновления"), MessageBoxButtons.YesNo, MessageBoxIcon.Information) == DialogResult.Yes)
            { try { Process.Start(AppInfo.ReleasesUrl); } catch { } }
#if UITEST
#pragma warning restore 0162
#endif
        }

        private void SetAboutBody(Control card, string text)
        {
            foreach (Control c in card.Controls)   // c = TableLayoutPanel
                foreach (Control cc in c.Controls)
                    if (cc is Label && (string)cc.Tag == "body") cc.Text = text;
        }
    }
}
