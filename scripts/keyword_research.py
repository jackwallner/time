"""Keyword fields per locale, from the 2026-09-22 research.

Sources: Astro popularity/difficulty per storefront (temporary app 133), the
Apple Ads search-term-popularity census for Aug 2026 (top 500 per genre, 38
storefronts), and App Store autocomplete. Findings that shaped these lists:

- The niche terms (time blindness, leave on time, late, punctual, and their
  translations) are Astro popularity 5 everywhere and absent from the census.
  They stay in the name and subtitle, where they cost no keyword space.
- The demand sits in the heads that combine with them: the local word for ADHD
  (DE adhs 34, FR/ES/BR/CA tdah 28, JP/KR adhd 45+, RU сдвг 26), routine
  (DE 36, FR 42, BR rotina 56, KR 루틴 66), timer, reminder, countdown and
  planner (pop 40-70 with difficulty 20-55 in most stores). Countdown and
  reminder are census top-500 Productivity terms in nearly every storefront.
- Words already in a locale's name or subtitle are dropped by the builder.

Order is priority: the builder keeps terms in order until 100 characters.
"""

EN = "routine,morning,planner,timer,visual,schedule,management,reminder,countdown,neurodivergent,tracker,app,late,punctual,focus,habit"
EN_INDIC = "timer,planner,reminder,countdown,adhd,routine,habit,morning,late,schedule,alarm,app"

KEYWORDS = {
    "en-US": EN, "en-GB": EN, "en-AU": EN, "en-CA": EN,
    "de-DE": "timer,planer,erinnerung,countdown,zeitmanagement,morgenroutine,tagesablauf,tagesplaner,gewohnheiten,visueller,app,zu spät,struktur,wecker",
    "fr-FR": "minuteur,rappel,compte à rebours,planning,organisation,gestion,matin,planificateur,visuel,retard,ponctualité,app,réveil,habitudes",
    "fr-CA": "minuterie,rappel,compte à rebours,planification,organisation,gestion,matin,planificateur,visuel,retard,ponctualité,app,réveil,habitudes",
    "es-ES": "temporizador,agenda,organizador,cuenta atrás,recordatorio,planificador,rutinas,mañana,hábitos,gestión,visual,puntualidad,tarde,despertador",
    "es-MX": "temporizador,cuenta regresiva,agenda,recordatorio,organizador,rutina,mañana,planificador,hábitos,administrar,visual,tarde,despertador",
    "it": "promemoria,agenda,timer,planner,conto alla rovescia,organizzazione,mattina,abitudini,gestione,visivo,ritardo,sveglia",
    "pt-BR": "agenda,planner,contagem regressiva,temporizador,lembrete,matinal,hábitos,organização,gestão,cronômetro,visual,atraso,despertador",
    "pt-PT": "agenda,rotina,temporizador,lembrete,planeador,matinal,hábitos,organização,gestão,contagem,visual,atraso,despertador,tdah",
    "nl-NL": "planner,timer,aftellen,planning,agenda,herinnering,ochtendroutine,dagritme,gewoontes,structuur,timemanagement,te laat,wekker",
    "ca": "temporitzador,agenda,recordatori,planificador,compte enrere,matí,hàbits,organització,rutines,visual,tard,despertador",
    "da": "nedtælling,påmindelse,timer,kalender,planlægger,morgenrutine,struktur,vaner,dagsplan,for sent,vækkeur,app",
    "sv": "nedräkning,påminnelse,timer,kalender,planerare,morgonrutin,struktur,vanor,dagsplanering,för sent,väckarklocka,app",
    "no": "nedtelling,påminnelse,timer,kalender,planlegger,morgenrutine,struktur,vaner,dagsplan,for sent,vekkerklokke,app",
    "fi": "kalenteri,ajastin,muistutus,suunnittelija,aamurutiini,aikataulu,lähtölaskenta,tavat,myöhässä,herätys,rakenne,sovellus",
    "pl": "planer,kalendarz,odliczanie,minutnik,timer,nawyki,przypomnienie,poranna,organizacja,zarządzanie,spóźnienie,budzik",
    "cs": "kalendář,plánovač,timer,časovač,odpočet,připomínka,návyky,ranní,organizace,pozdě,budík,aplikace",
    "sk": "kalendár,plánovač,timer,časovač,odpočítavanie,pripomienka,návyky,ranná,organizácia,neskoro,budík,aplikácia",
    "hu": "naptár,tervező,időzítő,visszaszámlálás,emlékeztető,szokások,reggeli,szervezés,késés,ébresztő,alkalmazás,timer",
    "ro": "calendar,planificator,cronometru,numărătoare,memento,obiceiuri,dimineața,organizare,întârziere,alarmă,timer,aplicație",
    "hr": "kalendar,planer,timer,odbrojavanje,podsjetnik,navike,jutarnja,organizacija,kašnjenje,budilica,aplikacija,adhd,raspored,plan",
    "sl-SI": "koledar,načrtovalnik,časovnik,odštevanje,opomnik,navade,jutranja,organizacija,zamujanje,budilka,timer,aplikacija",
    "el": "χρονόμετρο,αντίστροφη μέτρηση,υπενθύμιση,ημερολόγιο,πρόγραμμα,οργάνωση,συνήθειες,πρωινή,αργοπορία,ξυπνητήρι,timer,adhd",
    "tr": "sayaç,geri sayım,hatırlatıcı,planlayıcı,zamanlayıcı,alışkanlık,sabah,günlük,plan,takvim,alarm,adhd,geç",
    "ru": "таймер,обратный отсчет,привычки,напоминание,планировщик,распорядок,дня,рутина,тайм-менеджмент,опоздание,будильник,adhd",
    "uk": "таймер,нагадування,звички,планувальник,розпорядок,дня,ранкова,відлік,запізнення,будильник,adhd",
    "he": "טיימר,תזכורת,ספירה לאחור,מתכנן,לוח זמנים,הרגלים,בוקר,ארגון,איחור,שעון מעורר,adhd,קשב,ריכוז,יומן,משימות,שגרה",
    "ar-SA": "منبه,جدول,تنظيم,مؤقت,عد تنازلي,تذكير,مخطط,عادات,الصباح,تأخير,adhd,تشتت,انتباه,مواعيد,يومي,ساعة,خطة,تركيز",
    "hi": "टाइमर,रिमाइंडर,प्लानर,काउंटडाउन,आदत,सुबह,दिनचर्या,देर,अलार्म," + EN_INDIC,
    "bn-BD": "টাইমার,রিমাইন্ডার,পরিকল্পনা,অভ্যাস,সকাল,দেরি,অ্যালার্ম," + EN_INDIC,
    "gu-IN": "ટાઈમર,રીમાઇન્ડર,આયોજન,આદત,સવાર,મોડું,એલાર્મ," + EN_INDIC,
    "kn-IN": "ಟೈಮರ್,ಜ್ಞಾಪನೆ,ಯೋಜನೆ,ಅಭ್ಯಾಸ,ಬೆಳಿಗ್ಗೆ,ತಡ,ಅಲಾರಂ," + EN_INDIC,
    "ml-IN": "ടൈമർ,ഓർമ്മപ്പെടുത്തൽ,പ്ലാനർ,ശീലം,രാവിലെ,വൈകൽ,അലാറം," + EN_INDIC,
    "mr-IN": "टायमर,स्मरणपत्र,नियोजक,सवय,सकाळ,उशीर,अलार्म," + EN_INDIC,
    "or-IN": "ଟାଇମର,ସ୍ମାରକ,ଯୋଜନା,ଅଭ୍ୟାସ,ସକାଳ,ଡେରି,ଆଲାର୍ମ," + EN_INDIC,
    "pa-IN": "ਟਾਈਮਰ,ਯਾਦ-ਪੱਤਰ,ਯੋਜਨਾ,ਆਦਤ,ਸਵੇਰ,ਦੇਰੀ,ਅਲਾਰਮ," + EN_INDIC,
    "ta-IN": "டைமர்,நினைவூட்டல்,திட்டமிடல்,பழக்கம்,காலை,தாமதம்,அலாரம்," + EN_INDIC,
    "te-IN": "టైమర్,రిమైండర్,ప్లానర్,అలవాటు,ఉదయం,ఆలస్యం,అలారం," + EN_INDIC,
    "ur-PK": "ٹائمر,یاد دہانی,منصوبہ,عادت,صبح,دیر,الارم," + EN_INDIC,
    "id": "timer,pengingat,jadwal,harian,perencana,hitung mundur,kebiasaan,pagi,manajemen,terlambat,alarm,disiplin",
    "ms": "pemasa,peringatan,jadual,harian,perancang,kira detik,tabiat,pagi,lewat,penggera,timer,disiplin",
    "th": "จับเวลา,เตือนความจำ,วางแผน,นับถอยหลัง,ตารางเวลา,นิสัย,ตอนเช้า,มาสาย,นาฬิกาปลุก,timer,สมาธิสั้น",
    "vi": "hẹn giờ,đếm ngược,nhắc nhở,lập kế hoạch,lịch trình,thời gian,buổi sáng,đi muộn,báo thức,timer,thói quen,tập trung,lịch",
    "ja": "リマインダー,カウントダウン,習慣,ルーティン,朝活,発達障害,遅刻防止,身支度,スケジュール,時間割,目覚まし,集中,段取り,予定,手帳,ToDo,アラーム,タスク管理,自己管理,朝ルーティン",
    "ko": "루틴,타이머,습관,플래너,알림,리마인더,카운트다운,스케줄,아침,지각,외출 준비,시간 관리,집중,일정,할일,알람,자기관리,모닝루틴,출근 준비,습관 만들기,계획",
    "zh-Hans": "计时器,倒计时,提醒,习惯,自律,日程,计划,早起,打卡,多动症,迟到,专注,番茄钟,待办,闹钟,晨间,自我管理,时间规划,效率,出门",
    "zh-Hant": "計時器,倒數,提醒,習慣,自律,行程,計畫,打卡,早起,過動症,遲到,專注,番茄鐘,待辦,鬧鐘,晨間,自我管理,時間規劃,效率,出門",
}
