export type Lang = 'ru' | 'en';
export type ChildGender = 'son' | 'daughter';

export function resolveLang(value: string | null | undefined): Lang {
  return value === 'en' ? 'en' : 'ru';
}

export function langFromTelegram(code: string | undefined): Lang {
  if (!code) return 'ru';
  const base = code.toLowerCase().split('-')[0]!;
  return ['ru', 'uk', 'be', 'kk', 'ky', 'uz', 'tg', 'hy', 'az', 'ka', 'md', 'ro'].includes(base)
    ? 'ru'
    : 'en';
}

export function render(template: string, vars: Record<string, string | number>): string {
  return template.replace(/\{([^{}]+)\}/g, (whole, key: string) =>
    key in vars ? String(vars[key]) : whole,
  );
}

export function templateVars(v: {
  name?: string;
  child?: string;
  medication?: string;
  question?: string;
  days?: number;
  answers?: number;
}): Record<string, string | number> {
  const out: Record<string, string | number> = {};
  if (v.name !== undefined) { out['имя'] = v.name; out['name'] = v.name; }
  if (v.child !== undefined) { out['ребёнок'] = v.child; out['child'] = v.child; }
  if (v.medication !== undefined) { out['лекарство'] = v.medication; out['medication'] = v.medication; }
  if (v.question !== undefined) { out['вопрос'] = v.question; out['question'] = v.question; }
  if (v.days !== undefined) { out['дней'] = v.days; out['days'] = v.days; }
  if (v.answers !== undefined) { out['ответов'] = v.answers; out['answers'] = v.answers; }
  return out;
}

const g = (gender: ChildGender, son: string, daughter: string) =>
  gender === 'son' ? son : daughter;

type Pair = readonly [string, string];

const ru = {
  invite: {
    expired: 'Эта ссылка устарела — попросите близкого прислать новую, это одна минута.',
    alreadyUsed: 'Ссылка уже использована',
  },

  onboarding: {
    identityCheck: (parentName: string, _childName: string) =>
      `Здравствуйте! Вы — ${parentName}?`,
    identityYes: 'Да, это я',
    identityPreview: (childName: string) => `Нет, я ${childName} — просто посмотреть`,

    hello: (childName: string, gender: ChildGender) =>
      `Здравствуйте!\n\nЭтого помощника для вас ${g(gender, 'настроил', 'настроила')} ${childName}. ` +
      `${g(gender, 'Он живёт', 'Она живёт')} далеко, но думает о вас каждый день — и ему будет гораздо спокойнее, ` +
      `если раз в день, одним нажатием кнопки, вы будете давать знать, что всё в порядке.\n\n` +
      `Это займёт три секунды в день. Честно.`,

    whatIDo: (childName: string) =>
      `Всё устроено просто.\n\nЧто я буду делать:\n` +
      `— каждое утро спрошу, как вы. Одна кнопка — и ${childName} видит: всё хорошо;\n` +
      `— если попросите, буду напоминать про лекарства;\n` +
      `— если вы за день не выйдете на связь, ${childName} узнает об этом и, скорее всего, просто вам позвонит.`,

    whatINeverDo:
      `Чего я не делаю никогда:\n` +
      `— не слежу, где вы находитесь;\n` +
      `— не читаю ваши переписки;\n` +
      `— не показываю никому ничего, кроме того, что вы сами нажали или написали мне.\n\n` +
      `И ещё: я никогда не попрошу у вас коды из СМС, пароли или деньги. Если кто-то просит — это не я.`,

    consentYes: 'Мне подходит, начнём',
    consentQuestions: 'Есть вопросы',

    alreadyConnected: (time: string) =>
      `Мы уже знакомы! Всё работает, завтра напишу в ${time}. Вот кнопки 👇`,

    coldStart:
      'Здравствуйте! Этот помощник соединяет родителей и их взрослых детей: одна кнопка утром — ' +
      'и дети знают, что у вас всё хорошо.\n\n' +
      'Чтобы начать, нужна ссылка-приглашение от вашего сына или дочери. Попросите прислать её сюда, в Telegram.',

    previewIntro: 'Показываю, как это увидит ваш родитель 👇 (предпросмотр, ничего не сохраняется)',
    previewChildName: 'ваш ребёнок',

    faq: {
      isItPaid: `Для вас — бесплатно. Насовсем.`,
      whoSees: (childName: string) =>
        `Только ${childName} и те родные, кого ${childName} подключит. Больше никто.`,
      ifNoAnswer: (childName: string) =>
        `Ничего страшного не случится. ${childName} просто узнает, что вы не выходили на связь, — и позвонит. Услышать ваш голос.`,
    },

    allSet: (time: string) =>
      `Договорились! Завтра в ${time} напишу вам первый раз — а дальше каждое утро.\n\n` +
      `Кнопки уже внизу. Хотите — попробуйте прямо сейчас 👇`,
  },

  faqIntro: { paid: 'Это платно?', whoSees: 'Кто видит мои ответы?', noAnswer: 'Если я один день не отвечу?' },

  morningPool: [
    (n: string) => `Доброе утро, ${n}! Как вы сегодня?`,
    (n: string) => `${n}, с добрым утром. Как спалось?`,
    (n: string) => `Здравствуйте, ${n}! Как самочувствие с утра?`,
    (n: string) => `Доброе утро! Как начинается ваш день?`,
    (n: string) => `${n}, доброе утро. Какое у вас сегодня настроение?`,
    (n: string) => `С добрым утром, ${n}! Как вы?`,
    (n: string) => `${n}, новый день пришёл. Как вы его встречаете?`,
    (n: string) => `${n}, доброе утро! Всё ли у вас спокойно?`,
    (n: string) => `${n}, доброе утро. Пусть день будет спокойным. А пока — как вы?`,
    (n: string) => `Доброе утро! Всё ли у вас в порядке, ${n}?`,
    (n: string) => `Утро доброе, ${n}! Как вы себя чувствуете?`,
    (n: string) => `Доброе утро! Начнём день с доброй привычки. Как вы, ${n}?`,
  ],

  okReplies: [
    (_c: string) => `Отлично! Хорошего дня ☀️`,
    (c: string) => `Замечательно. ${c} уже видит.`,
    (_c: string) => `Вот и славно. До завтра!`,
    (_c: string) => `Спасибо! Спокойного вам дня.`,
    (_c: string) => `Принято ✅ Пусть день удастся.`,
    (_c: string) => `Хорошо! Это лучшая новость с утра.`,
  ],

  okRepeatSameDay: (name: string) =>
    `Уже записано с утра — спасибо! До завтра, ${name}.`,

  notOk: {
    ask: (name: string) =>
      `Понимаю, ${name}. Подскажете, что случилось? Это поможет близким понять, как поддержать.`,
    buttons: [
      'Здоровье',
      'Настроение',
      'Просто день такой',
      'Позвоните мне',
      'Ой, нажала случайно — всё хорошо',
      'Не хочется рассказывать',
    ] as readonly string[],
    alreadyKnown: (child: string) =>
      `${child} уже знает. Если нужно — нажмите «Позвоните мне» в вопросе выше, или напишите словами.`,
    health: (name: string, child: string, emergency: string) =>
      `Берегите себя, ${name}. ${child} уже знает — и позвонит, как только сможет.\n\n` +
      `Если чувствуете, что помощь нужна прямо сейчас, — не ждите звонка, звоните в скорую: ${emergency}.\n\n` +
      `Если хотите, напишите или наговорите голосом, что беспокоит, — ${child} это увидит.`,
    mood: (child: string) =>
      `Так бывает, и это нормально. Хорошо, что вы не промолчали.\n\n` +
      `Хотите — расскажите словами или голосом, что на душе. ${child} обязательно это увидит.`,
    justDay: (child: string) =>
      `Бывают такие дни — без причины и без названия. Завтра будет новый.\n\n` +
      `${child} знает, что вы на связи, — это главное. Если что-то понадобится, я рядом.`,
    callMe: (child: string) => `Передаю. ${child} увидит это прямо сейчас.`,
    accidental: `Хорошо, что всё хорошо! Так и передам ✅`,
    private: (name: string, child: string) =>
      `Конечно, это ваше право, ${name}. ${child} будет знать только то, что сегодня день не задался, — без подробностей.\n\nЕсли передумаете — просто напишите сюда.`,
  },

  missed: {
    reping: [
      (n: string) => `${n}, я ещё тут. Как вы сегодня?`,
      (n: string) => `${n}, загляну ещё разок. Всё ли в порядке?`,
      (n: string) => `${n}, утро в разгаре. Как вы?`,
    ],
    afterDeadline: (name: string, child: string) =>
      `${name}, сегодня вы пока не откликнулись — ничего страшного, всякое бывает: дела, гости, телефон в другой комнате.\n\n` +
      `${child} увидит, что утро прошло без вашей весточки, и, скорее всего, позвонит — просто услышать ваш голос.\n\n` +
      `А кнопки по-прежнему внизу — нажмите, когда будет минутка.`,
    lateCheckin: (name: string, child: string) =>
      `Вот и вы! ${child} сразу увидит, что всё в порядке. Хорошего дня, ${name}!`,
  },

  milestones: {
    7:   (_n: string, c: string) => `И кстати: сегодня ровно неделя, как мы с вами встречаем утро вместе. ${c} каждый день получает вашу весточку — и это лучшая новость в его дне.`,
    30:  (n: string, _c: string) => `Сегодня месяц, как вы выходите на связь каждый день. Тридцать спокойных утренних встреч — у вас и у ваших близких. Это дорогого стоит, ${n}.`,
    100: (n: string, _c: string) => `Сто утренних приветов подряд. Есть привычки, которые делают жизнь надёжнее, — у вас такая появилась. Спасибо, что вы есть, ${n} ❤️`,
    365: (n: string, _c: string) => `Целый год, день за днём. Такое постоянство — редкость и настоящий подарок близким. С годовщиной, ${n} ❤️`,
  } as Record<number, (name: string, child: string) => string>,

  freeInput: {
    recordedOk: `Записано: всё хорошо ✅`,
    text: (name: string, child: string) =>
      `Спасибо, что написали, ${name}! ${child} увидит это сегодня же.`,
    voice: (child: string) =>
      `Голосовое — это почти как звонок. ${child} обязательно послушает, передаю.`,
    photo: (child: string) => `Фотография дошла ✅ ${child} её увидит.`,
    keyboardHint: `А чтобы отметка стала зелёной — нажмите кнопку, она вот здесь 👇`,
  },

  trouble: {
    checkinFailed:
      `Кажется, у меня сейчас сбой — ответ не записался. ` +
      `Нажмите кнопку ещё раз через минуту, пожалуйста.`,
  },

  stop: {
    ask: `Хорошо. Совсем перестать писать или сделать паузу?`,
    buttons: ['Пауза', 'Совсем перестать'] as Pair,
    confirmed: `Договорились — больше не пишу. Ваши данные удалены. Спасибо, что попробовали, и будьте здоровы.`,
  },

  pause: {
    ask: `Дело житейское. На сколько сделать паузу? Всё это время я не буду писать по утрам, а близкие будут знать, что вы отдыхаете, — и не будут волноваться.`,
    buttons: ['До завтра', '3 дня', 'Неделя', 'Пока не вернусь'] as readonly string[],
    untilReturn: 'вашего возвращения',
    confirmed: (until: string) =>
      `Пауза до ${until}. Вернётесь раньше — просто нажмите «Всё хорошо», и продолжим.`,
  },

  beta: {
    joined:
      'Готово — вы в списке ✅\n\n' +
      'Когда откроем бету, я напишу вам сюда: пришлю ссылку на приложение для вас ' +
      'и объясню, как позвать маму. Это будет осенью.\n\n' +
      'Пока можно ничего не делать. Спасибо, что дождались этой кнопки.',
    already:
      'Вы уже в списке ✅ Напишу, как только откроем бету — не пропустите.',
    waitButton: 'Записаться в бету',

    invite:
      'Здравствуйте! Это «Мама, я рядом» — вы записывались в бету, и ваша очередь подошла ✅\n\n' +
      'Что нужно сделать:\n' +
      '1. Установите TestFlight из App Store: https://apps.apple.com/app/testflight/id899247664\n' +
      '2. Откройте в нём ссылку на приложение: {ссылка}\n' +
      '3. Добавьте в приложении маму — дальше бот сам всё ей объяснит.\n\n' +
      'Если что-то не получится — просто ответьте на это сообщение.',
    offer:
      '\n\nЕсли ссылки-приглашения у вас нет, а попробовать хочется — записывайтесь в бету, ' +
      'позовём одними из первых.',
  },

  help: (child: string) =>
    'Что я умею:\n\n' +
    '• Утром спрашиваю, как ваши дела. Один тап — и ' + (child || 'близкие') + ' знает, что всё хорошо.\n' +
    '• Напоминаю про лекарства, если их завели в приложении.\n' +
    '• Передаю ваши сообщения, голосовые и фотографии семье.\n\n' +
    'Команды:\n' +
    '/time — поменять время утреннего сообщения\n' +
    '/family — ссылка для семьи, если кто-то сменил телефон\n' +
    '/pause — сделать паузу на несколько дней\n' +
    '/stop — перестать писать совсем\n\n' +
    'Геолокацию не вижу, переписку не читаю, звонить не заставляю.',

  time: {
    ask: (current: string) =>
      `Сейчас утреннее сообщение приходит в ${current}. Во сколько удобнее?`,
    options: ['07:00', '08:00', '09:00', '10:00', '11:00'] as readonly string[],
    keep: 'Оставить как есть',
    kept: (current: string) => `Хорошо, всё остаётся как было — пишу в ${current}.`,
    confirmed: (value: string) =>
      `Договорились — теперь пишу в ${value}. Если передумаете, скажите /time.`,
    unchanged: (value: string) => `Так и было — пишу в ${value}. Ничего не меняю.`,
    failed: 'Не получилось поменять время. Попробуйте ещё раз чуть позже.',
  },

  digest: {
    full: (name: string, child: string, days: number) =>
      `${name}, неделя закрыта: вы отметились все ${days} дней. ` +
      `${child || 'Ваши близкие'} видел это каждое утро — спасибо вам за это.`,
    most: (name: string, child: string, ok: number, total: number) =>
      `${name}, за неделю вы ответили ${ok} раз из ${total}. ` +
      `${child || 'Ваши близкие'} всё это время знал, что у вас всё идёт своим чередом.`,
    few: (name: string) =>
      `${name}, на этой неделе мы почти не виделись. Если утро — неудобное время, ` +
      `скажите /time и я подстроюсь. А если писать не нужно совсем — скажите /pause.`,
  },

  postcard: {
    delivered: (author: string, body: string) =>
      (author ? `Вам открытка от ${author}:` : 'Вам открытка:') + `\n\n«${body}»`,
  },

  familyLink: {
    message: (child: string, url: string) =>
      (child ? `Если ${child} сменил телефон или приложение сбилось` : 'Если в семье кто-то сменил телефон') +
      ` — отправьте эту ссылку, и всё вернётся на место:\n\n${url}\n\n` +
      'Передавайте её только своим: по ней открывается ваша семейная карточка.',
  },

  evening: {
    ask: (name: string) => `${name}, как прошёл день?`,
    buttons: ['Хорошо ✨', 'Так себе'] as Pair,
    ok: `Спокойной ночи!`,
    notOk: `Пусть завтра будет полегче. Спокойной ночи.`,
  },

  story: {

    pool: [
      'Какая песня сразу возвращает вас в молодость?',
      'Какое блюдо вы готовите лучше всех — и у кого научились?',
      'Какой запах мгновенно возвращает вас в детство?',
      'Какой совет вы бы дали себе в шестнадцать лет?',
    ] as readonly string[],
    ask: (name: string, question: string) =>
      `${name}, вопрос недели — просто так, для семейной памяти:\n\n${question}\n\n` +
      'Можно ответить словами или голосовым — как удобнее. А можно и пропустить, ничего страшного.',
    captured: `Записала в семейную копилку. Спасибо, что поделились ❤️`,
  },

  keyboard: {
    ok: '☀️ Всё хорошо',
    notOk: 'Не очень',
  },

  meds: {
    reminder: (name: string, title: string) => `${name}, время лекарства: ${title}.`,
    buttons: ['Готово ✅', 'Через полчаса'] as Pair,
    done: `Записано ✅`,
    later: `Хорошо, напомню через полчаса.`,
    stale: `Это напоминание уже не актуально — оно от другого дня.`,
  },
};

export type BotStrings = typeof ru;

const en: BotStrings = {
  invite: {
    expired: 'This link has expired — ask your family to send a fresh one, it takes a minute.',
    alreadyUsed: 'This link has already been used',
  },

  onboarding: {
    identityCheck: (parentName: string, _childName: string) =>
      `Hello! Are you ${parentName}?`,
    identityYes: 'Yes, that’s me',
    identityPreview: (childName: string) => `No, I’m ${childName} — just looking`,

    hello: (childName: string, gender: ChildGender) =>
      `Hello!\n\nThis helper was set up for you by ${childName}, who lives far away ` +
      `but thinks of you every day — and it will put ${g(gender, 'his', 'her')} mind at ease if, ` +
      `once a day, with a single tap of a button, you let ${g(gender, 'him', 'her')} know that all is well.\n\n` +
      `It takes three seconds a day. Honestly.`,

    whatIDo: (childName: string) =>
      `It’s all quite simple.\n\nWhat I will do:\n` +
      `— every morning I’ll ask how you are. One button — and ${childName} sees: all is well;\n` +
      `— if you ask, I’ll remind you about your medications;\n` +
      `— if a day goes by without a word from you, ${childName} will know — and will most likely simply call you.`,

    whatINeverDo:
      `What I never do:\n` +
      `— I don’t track where you are;\n` +
      `— I don’t read your conversations;\n` +
      `— I don’t show anyone anything beyond what you yourself tapped or wrote to me.\n\n` +
      `And one more thing: I will never ask you for codes from text messages, passwords or money. If someone does — it’s not me.`,

    consentYes: 'Works for me, let’s start',
    consentQuestions: 'I have questions',

    alreadyConnected: (time: string) =>
      `We already know each other! Everything is working — I’ll write tomorrow at ${time}. Here are the buttons 👇`,

    coldStart:
      'Hello! This helper connects parents with their grown-up children: one button in the morning — ' +
      'and your children know you’re doing fine.\n\n' +
      'To begin, you need an invitation link from your son or daughter. Ask them to send it here, in Telegram.',

    previewIntro: 'Here’s how your parent will see it 👇 (a preview, nothing is saved)',
    previewChildName: 'your child',

    faq: {
      isItPaid: `For you — free. For good.`,
      whoSees: (childName: string) =>
        `Only ${childName} and the family members ${childName} connects. No one else.`,
      ifNoAnswer: (childName: string) =>
        `Nothing bad will happen. ${childName} will simply know you haven’t been in touch — and will call. To hear your voice.`,
    },

    allSet: (time: string) =>
      `It’s a deal! Tomorrow at ${time} I’ll write to you for the first time — and every morning after that.\n\n` +
      `The buttons are already below. Feel free to try one right now 👇`,
  },

  faqIntro: { paid: 'Is it paid?', whoSees: 'Who sees my answers?', noAnswer: 'What if I miss a day?' },

  morningPool: [
    (n: string) => `Good morning, ${n}! How are you today?`,
    (n: string) => `${n}, good morning. How did you sleep?`,
    (n: string) => `Hello, ${n}! How are you feeling this morning?`,
    (n: string) => `Good morning! How is your day starting out?`,
    (n: string) => `${n}, good morning. How are your spirits today?`,
    (n: string) => `Good morning, ${n}! How are you doing?`,
    (n: string) => `${n}, a new day is here. How does it find you?`,
    (n: string) => `${n}, good morning! Is everything calm and well?`,
    (n: string) => `${n}, good morning. May the day be gentle. But first — how are you?`,
    (n: string) => `Good morning! Is everything all right, ${n}?`,
    (n: string) => `Morning, ${n}! How are you feeling?`,
    (n: string) => `Good morning! Let’s start the day with a good habit. How are you, ${n}?`,
  ],

  okReplies: [
    (_c: string) => `Wonderful! Have a lovely day ☀️`,
    (c: string) => `Lovely. ${c} can already see it.`,
    (_c: string) => `Glad to hear it. Until tomorrow!`,
    (_c: string) => `Thank you! Have a peaceful day.`,
    (_c: string) => `Noted ✅ May the day go well.`,
    (_c: string) => `Good! That’s the best news of the morning.`,
  ],

  okRepeatSameDay: (name: string) =>
    `Already noted this morning — thank you! Until tomorrow, ${name}.`,

  notOk: {
    ask: (name: string) =>
      `I understand, ${name}. Would you tell me what happened? It will help your family know how to support you.`,
    buttons: [
      'Health',
      'Mood',
      'Just one of those days',
      'Please call me',
      'Oh, I tapped by accident — all is well',
      'I’d rather not say',
    ] as readonly string[],
    alreadyKnown: (child: string) =>
      `${child} already knows. If you need to — tap “Please call me” in the question above, or just write to me.`,
    health: (name: string, child: string, emergency: string) =>
      `Take care of yourself, ${name}. ${child} already knows — and will call as soon as possible.\n\n` +
      `If you feel you need help right now — don’t wait for the call, dial emergency services: ${emergency}.\n\n` +
      `If you’d like, write or record a voice message about what’s troubling you — ${child} will see it.`,
    mood: (child: string) =>
      `That happens, and it’s all right. It’s good that you didn’t keep it to yourself.\n\n` +
      `If you’d like, tell me in words or by voice what’s on your mind. ${child} will be sure to see it.`,
    justDay: (child: string) =>
      `Some days are like that — no reason, no name. Tomorrow will be a new one.\n\n` +
      `${child} knows you’re in touch — that’s what matters. If you need anything, I’m here.`,
    callMe: (child: string) => `Passing it on. ${child} will see this right now.`,
    accidental: `Glad everything is fine! I’ll pass that along ✅`,
    private: (name: string, child: string) =>
      `Of course, that’s your right, ${name}. ${child} will only know that today wasn’t the best — no details.\n\nIf you change your mind — just write here.`,
  },

  missed: {
    reping: [
      (n: string) => `${n}, I’m still here. How are you today?`,
      (n: string) => `${n}, checking in once more. Is everything all right?`,
      (n: string) => `${n}, the morning is in full swing. How are you?`,
    ],
    afterDeadline: (name: string, child: string) =>
      `${name}, no word from you yet today — that’s all right, life happens: errands, guests, the phone in another room.\n\n` +
      `${child} will see that the morning went by without your hello and will most likely call — just to hear your voice.\n\n` +
      `The buttons are still down below — tap one when you have a minute.`,
    lateCheckin: (name: string, child: string) =>
      `There you are! ${child} will see right away that everything is fine. Have a lovely day, ${name}!`,
  },

  milestones: {
    7:   (_n: string, c: string) => `And by the way: today marks a whole week of us greeting the morning together. ${c} gets your hello every day — and it’s the best news of the day.`,
    30:  (n: string, _c: string) => `Today makes a month of you being in touch every single day. Thirty calm mornings — for you and for your family. That is worth a lot, ${n}.`,
    100: (n: string, _c: string) => `One hundred morning hellos in a row. Some habits make life sturdier — you’ve built one. Thank you for being you, ${n} ❤️`,
    365: (n: string, _c: string) => `A whole year, day after day. Such constancy is rare — and a true gift to your family. Happy anniversary, ${n} ❤️`,
  } as Record<number, (name: string, child: string) => string>,

  freeInput: {
    recordedOk: `Noted: all is well ✅`,
    text: (name: string, child: string) =>
      `Thank you for writing, ${name}! ${child} will see it today.`,
    voice: (child: string) =>
      `A voice message is almost like a phone call. ${child} will be sure to listen — passing it on.`,
    photo: (child: string) => `The photo came through ✅ ${child} will see it.`,
    keyboardHint: `And to make today’s mark green — tap the button, it’s right here 👇`,
  },

  trouble: {
    checkinFailed:
      `Something went wrong on my end — the answer didn’t get recorded. ` +
      `Please tap the button again in a minute.`,
  },

  stop: {
    ask: `All right. Stop writing completely, or take a pause?`,
    buttons: ['Pause', 'Stop completely'] as Pair,
    confirmed: `Understood — I won’t write any more. Your data has been erased. Thank you for giving it a try, and take care.`,
  },

  pause: {
    ask: `Happens to everyone. How long should the pause be? All that time I won’t write in the mornings, and your family will know you’re resting — so nobody worries.`,
    buttons: ['Until tomorrow', '3 days', 'A week', 'Until I’m back'] as readonly string[],
    untilReturn: 'your return',
    confirmed: (until: string) =>
      `Paused until ${until}. If you’re back sooner — just tap “All good” and we’ll continue.`,
  },

  beta: {
    joined:
      'Done — you’re on the list ✅\n\n' +
      'When the beta opens, I’ll write to you here: I’ll send the app link for you ' +
      'and explain how to invite your mom. That will be this fall.\n\n' +
      'Nothing to do for now. Thank you for waiting for this button.',
    already:
      'You’re already on the list ✅ I’ll write as soon as the beta opens — you won’t miss it.',
    waitButton: 'Join the beta list',
    invite:
      'Hello! This is “Mom, I’m Right Here” — you signed up for the beta, and your turn has come ✅\n\n' +
      'What to do:\n' +
      '1. Install TestFlight from the App Store: https://apps.apple.com/app/testflight/id899247664\n' +
      '2. Open the app link inside it: {link}\n' +
      '3. Add your mom in the app — the bot will explain everything to her from there.\n\n' +
      'If anything doesn’t work — just reply to this message.',
    offer:
      '\n\nIf you don’t have an invitation link but would like to try — join the beta list, ' +
      'and we’ll invite you among the first.',
  },

  help: (child: string) =>
    'What I can do:\n\n' +
    '• In the morning I ask how you are doing. One tap — and ' + (child || 'your family') + ' knows all is well.\n' +
    '• I remind you about medications, if they’re set up in the app.\n' +
    '• I pass your messages, voice notes and photos on to the family.\n\n' +
    'Commands:\n' +
    '/time — change the time of the morning message\n' +
    '/family — the family link, in case someone changed phones\n' +
    '/pause — take a break for a few days\n' +
    '/stop — stop the messages completely\n\n' +
    'I don’t see your location, don’t read your chats, and never make you call anyone.',

  time: {
    ask: (current: string) =>
      `Right now the morning message arrives at ${current}. What time works better?`,
    options: ['07:00', '08:00', '09:00', '10:00', '11:00'] as readonly string[],
    keep: 'Keep it as is',
    kept: (current: string) => `All right, everything stays as it was — I write at ${current}.`,
    confirmed: (value: string) =>
      `Done — from now on I write at ${value}. If you change your mind, say /time.`,
    unchanged: (value: string) => `That’s already the time — I write at ${value}. Nothing to change.`,
    failed: 'Couldn’t change the time. Please try again a little later.',
  },

  digest: {
    full: (name: string, child: string, days: number) =>
      `${name}, the week is complete: you checked in on all ${days} days. ` +
      `${child || 'Your family'} saw it every morning — thank you for that.`,
    most: (name: string, child: string, ok: number, total: number) =>
      `${name}, this week you answered ${ok} times out of ${total}. ` +
      `${child || 'Your family'} knew all along that things were going their usual way.`,
    few: (name: string) =>
      `${name}, we hardly saw each other this week. If mornings are an inconvenient time, ` +
      `say /time and I’ll adjust. And if you’d rather I not write at all — say /pause.`,
  },

  postcard: {
    delivered: (author: string, body: string) =>
      (author ? `A postcard for you from ${author}:` : 'A postcard for you:') + `\n\n“${body}”`,
  },

  familyLink: {
    message: (child: string, url: string) =>
      (child ? `If ${child} gets a new phone or the app gets reset` : 'If someone in the family gets a new phone') +
      ` — send this link, and everything falls back into place:\n\n${url}\n\n` +
      'Share it only with your own people: it opens your family’s card.',
  },

  evening: {
    ask: (name: string) => `${name}, how was your day?`,
    buttons: ['Good ✨', 'So-so'] as Pair,
    ok: `Good night!`,
    notOk: `May tomorrow be kinder. Good night.`,
  },

  story: {
    pool: [
      'What song takes you straight back to your youth?',
      'What dish do you cook better than anyone — and who taught you?',
      'What smell instantly brings back your childhood?',
      'What advice would you give your sixteen-year-old self?',
    ] as readonly string[],
    ask: (name: string, question: string) =>
      `${name}, this week’s question — just for the family’s memory box:\n\n${question}\n\n` +
      'You can answer in words or with a voice message, whichever is easier. Or skip it — that’s perfectly fine.',
    captured: `Saved into the family keepsake box. Thank you for sharing ❤️`,
  },

  keyboard: {
    ok: '☀️ All good',
    notOk: 'Not great',
  },

  meds: {
    reminder: (name: string, title: string) => `${name}, it’s time for your medication: ${title}.`,
    buttons: ['Done ✅', 'In half an hour'] as Pair,
    done: `Noted ✅`,
    later: `All right, I’ll remind you in half an hour.`,
    stale: `This reminder is from another day and no longer applies.`,
  },
};

export function T(lang: Lang): BotStrings {
  return lang === 'en' ? en : ru;
}

export function faqAnswers(lang: Lang, child: string): string {
  const s = T(lang);
  return (
    `${s.faqIntro.paid}\n— ${s.onboarding.faq.isItPaid}\n\n` +
    `${s.faqIntro.whoSees}\n— ${s.onboarding.faq.whoSees(child)}\n\n` +
    `${s.faqIntro.noAnswer}\n— ${s.onboarding.faq.ifNoAnswer(child)}`
  );
}

export const okButtonLabels = [ru.keyboard.ok, en.keyboard.ok] as const;
export const notOkButtonLabels = [ru.keyboard.notOk, en.keyboard.notOk] as const;

const notOkPatternRu =
  /((?<!не)плохо|неважно|боле[юе]|нездоров|давлени|температур|(^|\s)не\s+(вс[её]\s+)?(очень|хорошо|нормально|в\s*порядке|отлично))/;
const okPatternRu =
  /(^|[\s,.!—-])(вс[её]\s+)?(хорошо|нормально|отлично|в\s*порядке)(?![а-яё])/;

const notOkPatternEn =
  /(not\s+((so|too|very|really)\s+)?((feeling|doing)\s+)?((so|too|very|really)\s+)?(good|great|well|fine|okay|ok)\b|unwell|sick\b|poorly|feeling\s+(bad|low|awful|terrible)|blood\s+pressure|dizzy|in\s+pain|it\s+hurts)/;

const okPatternEn =
  /(^|[\s,.!—-])((i['’]?m|i\s+am|doing|feeling)\s+(all\s+|pretty\s+|very\s+)?(good|fine|okay|ok|great|alright|all\s*right|well)|(all\s+)?(good|fine|okay|ok|great|alright|all\s*right))(?![a-z])/;

export function matchesNotOk(lowercased: string): boolean {
  return notOkPatternRu.test(lowercased) || notOkPatternEn.test(lowercased);
}

export function matchesOk(lowercased: string): boolean {
  return okPatternRu.test(lowercased) || okPatternEn.test(lowercased);
}

const stopWordsRu = ['стоп', 'хватит', 'не пишите', 'не пиши', 'отстань', 'отключи'];
const stopPatternEn =
  /\b(stop\s+(writing|messaging|texting|it)|don['’]?t\s+(write|text|message)\s+(to\s+)?me|leave\s+me\s+alone|unsubscribe)\b/;

export function wantsStop(lowercased: string): boolean {
  return stopWordsRu.some((word) => lowercased.includes(word)) || stopPatternEn.test(lowercased);
}
