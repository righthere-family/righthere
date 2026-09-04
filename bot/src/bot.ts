import { Bot, Context, InlineKeyboard, Keyboard } from 'grammy';
import type { UserFromGetMe } from 'grammy/types';
import type { Env } from './index';
import { pushToFamily } from './apns';
import { db, CheckinResult, type MomChannel } from './db';
import {
  T,
  faqAnswers,
  langFromTelegram,
  matchesNotOk,
  matchesOk,
  notOkButtonLabels,
  okButtonLabels,
  render,
  resolveLang,
  templateVars,
  wantsStop,
  type Lang,
} from './texts';

function localDate(timezone?: string | null): string {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone: timezone ?? 'UTC' }).format(new Date());
  } catch {
    return new Intl.DateTimeFormat('en-CA', { timeZone: 'UTC' }).format(new Date());
  }
}

const JOIN_BASE_URL = 'https://righthere.family';

export function makeBot(env: Env, botInfo?: UserFromGetMe): Bot {
  const bot = new Bot(env.TELEGRAM_BOT_TOKEN, { botInfo });
  const d = db(env);

  const langFor = (ctx: Context): Promise<Lang> =>
    d.parentLang(ctx.from!.id, ctx.from?.language_code);

  const ringCheckin = async (res: CheckinResult) => {
    if (res.family_id && res.result !== 'duplicate') {
      await d.broadcastToApp(res.family_id, 'checkin');
    }
  };

  const pushNotOk = async (res: CheckinResult, telegramUserId: number) => {
    if (!res.family_id || res.result === 'duplicate') return;
    await pushToFamily(env, res.family_id, {
      title: await d.addressForm(telegramUserId),
      body: {
        ru: 'Сегодня не очень. Загляните в приложение — и лучше позвоните.',
        en: 'Not a great day today. Open the app — better yet, call.',
      },
      level: 'time-sensitive',
      category: 'NOT_OK',
    });
  };

  const pushRelief = async (res: CheckinResult, telegramUserId: number) => {
    if (!res.family_id || res.result === 'duplicate') return;
    const title = await d.addressForm(telegramUserId);
    if (res.was_escalated) {
      await pushToFamily(env, res.family_id, {
        title,
        body: {
          ru: 'На связи: всё хорошо ✅',
          en: 'In touch: all is well ✅',
        },
        level: 'active',
        category: 'CHECKIN_OK',
      });
      return;
    }
    await pushToFamily(env, res.family_id, {
      title,
      body: {
        ru: 'Всё хорошо ☀️',
        en: 'All is well ☀️',
      },
      level: 'active',
      silent: true,
      category: 'CHECKIN_OK',
    });
  };

  const MESSAGE_PUSH_GAP_MS = 3 * 60_000;

  const pushMessage = async (
    forwarded: { familyId: string; name: string; kind: 'text' | 'voice' | 'photo' } | null,
  ) => {
    if (!forwarded) return;
    const stamp = `msg-push/${forwarded.familyId}`;
    try {
      if (await env.SYSTEM.get(stamp)) return;
      await env.SYSTEM.put(stamp, '1', { expirationTtl: MESSAGE_PUSH_GAP_MS / 1000 });
    } catch {
      return;
    }
    const body = {
      text: { ru: 'Пара слов для вас', en: 'A few words for you' },
      voice: { ru: 'Голосовое сообщение', en: 'A voice message' },
      photo: { ru: 'Фотография', en: 'A photo' },
    }[forwarded.kind];
    await pushToFamily(env, forwarded.familyId, {
      title: forwarded.name,
      body,
      level: 'active',
      category: 'MESSAGE',
    });
  };

  const checkinKeyboard = (lang: Lang) =>
    new Keyboard()
      .text(T(lang).keyboard.ok).row()
      .text(T(lang).keyboard.notOk)
      .resized()
      .oneTime();

  const hideKeyboard = { remove_keyboard: true } as const;

  const notOkOptionsKeyboard = (lang: Lang) => {
    const kb = new InlineKeyboard();
    T(lang).notOk.buttons.forEach((label, index) => {
      kb.text(label, `notok:${index}`);
      kb.row();
    });
    return kb;
  };

  bot.command('start', async (ctx) => {
    const payload = ctx.match?.toString() ?? '';

    if (payload.startsWith('inv_')) {
      const invite = await d.findInvite(payload.slice(4));
      if (!invite) {

        await ctx.reply(T(langFromTelegram(ctx.from?.language_code)).invite.expired);
        return;
      }

      const S = T(resolveLang(invite.lang));
      await ctx.reply(S.onboarding.identityCheck(invite.parent_name, invite.child_name), {
        reply_markup: new InlineKeyboard()
          .text(S.onboarding.identityYes, `id_yes:${invite.code}`).row()
          .text(S.onboarding.identityPreview(invite.child_name), `id_preview:${invite.code}`),
      });
      return;
    }

    const parent = await d.parentByTelegramId(ctx.from!.id);
    if (parent) {
      const lang = resolveLang(parent.lang);

      await ctx.reply(T(lang).onboarding.alreadyConnected(parent.checkin_time.slice(0, 5)), {
        reply_markup: checkinKeyboard(lang),
      });
      return;
    }

    const guest = T(langFromTelegram(ctx.from?.language_code));

    if (payload === 'beta') {
      const result = await d.joinWaitlist(
        ctx.from!.id,
        ctx.from!.username,
        ctx.from!.first_name,
        ctx.from!.language_code,
      );
      await ctx.reply(result === 'added' ? guest.beta.joined : guest.beta.already);
      return;
    }

    await ctx.reply(guest.onboarding.coldStart + guest.beta.offer, {
      reply_markup: new InlineKeyboard().text(guest.beta.waitButton, 'beta_join'),
    });
  });

  bot.callbackQuery('beta_join', async (ctx) => {
    await ctx.answerCallbackQuery();
    const guest = T(langFromTelegram(ctx.from.language_code));
    const result = await d.joinWaitlist(
      ctx.from.id,
      ctx.from.username,
      ctx.from.first_name,
      ctx.from.language_code,
    );
    try {
      await ctx.editMessageReplyMarkup();
    } catch {

    }
    await ctx.reply(result === 'added' ? guest.beta.joined : guest.beta.already);

    if ((await d.waitlistMomChannel(ctx.from.id)) === null) {
      const labels = guest.beta.channelButtons;
      await ctx.reply(guest.beta.channelAsk, {
        reply_markup: new InlineKeyboard()
          .text(labels[0]!, 'mom:telegram')
          .row()
          .text(labels[1]!, 'mom:whatsapp')
          .row()
          .text(labels[2]!, 'mom:sms')
          .row()
          .text(labels[3]!, 'mom:unknown'),
      });
    }
  });

  bot.callbackQuery(/^mom:(telegram|whatsapp|sms|unknown)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    await d.setWaitlistMomChannel(ctx.from.id, ctx.match[1] as MomChannel);
    try {
      await ctx.editMessageReplyMarkup();
    } catch {

    }
    await ctx.reply(T(langFromTelegram(ctx.from.language_code)).beta.channelThanks);
  });

  bot.callbackQuery(/^id_yes:(.+)$/, async (ctx) => {
    const code = ctx.match[1]!;
    const invite = await d.bindInvite(code, ctx.from.id);
    if (!invite) {
      await ctx.answerCallbackQuery({
        text: T(langFromTelegram(ctx.from.language_code)).invite.alreadyUsed,
      });
      return;
    }
    const S = T(resolveLang(invite.lang));
    await ctx.answerCallbackQuery();
    await d.broadcastToApp(invite.family_id, 'bound');
    await ctx.reply(S.onboarding.hello(invite.child_name, invite.child_gender));
    await ctx.reply(S.onboarding.whatIDo(invite.child_name));
    await ctx.reply(S.onboarding.whatINeverDo, {
      reply_markup: new InlineKeyboard()
        .text(S.onboarding.consentYes, `ob_go:${invite.parent_id}`).row()
        .text(S.onboarding.consentQuestions, `ob_faq:${invite.parent_id}`),
    });

  });

  bot.callbackQuery(/^ob_go:(.+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    await d.activateParent(ctx.match[1]!);
    const parent = await d.parentByTelegramId(ctx.from.id);
    const lang = parent ? resolveLang(parent.lang) : langFromTelegram(ctx.from.language_code);
    const time = (parent?.checkin_time as string | undefined)?.slice(0, 5) ?? '09:00';
    await ctx.reply(T(lang).onboarding.allSet(time), { reply_markup: checkinKeyboard(lang) });
  });

  bot.callbackQuery(/^ob_faq:(.+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const lang = await langFor(ctx);
    const child = await d.childName(ctx.from.id);
    await ctx.reply(faqAnswers(lang, child), {
      reply_markup: new InlineKeyboard().text(T(lang).onboarding.consentYes, `ob_go:${ctx.match[1]}`),
    });
  });

  bot.callbackQuery(/^id_preview:(.+)$/, async (ctx) => {
    await ctx.answerCallbackQuery();

    const S = T(langFromTelegram(ctx.from.language_code));
    await ctx.reply(S.onboarding.previewIntro);
    await ctx.reply(S.onboarding.hello(S.onboarding.previewChildName, 'son'));

  });

  bot.command('help', async (ctx) => {
    const lang = await langFor(ctx);
    await ctx.reply(T(lang).help(await d.childName(ctx.from!.id)));
  });

  bot.command('time', async (ctx) => {
    const parent = await d.parentByTelegramId(ctx.from!.id);
    if (!parent) {
      await ctx.reply(T(langFromTelegram(ctx.from?.language_code)).onboarding.coldStart);
      return;
    }
    const S = T(resolveLang(parent.lang));
    const current = (parent.checkin_time as string).slice(0, 5);

    const kb = new InlineKeyboard();
    S.time.options.forEach((value) => {
      kb.text(value === current ? `· ${value} ·` : value, `time:${value}`);
    });
    kb.row().text(S.time.keep, `time:keep:${current}`);
    await ctx.reply(S.time.ask(current), { reply_markup: kb });
  });

  const closeTimePicker = async (ctx: Context) => {
    try {
      await ctx.editMessageReplyMarkup();
    } catch {

    }
  };

  bot.callbackQuery(/^time:keep:(\d\d:\d\d)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    await closeTimePicker(ctx);
    await ctx.reply(T(await langFor(ctx)).time.kept(ctx.match[1]!));
  });

  bot.callbackQuery(/^time:(\d\d:\d\d)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const value = ctx.match[1]!;
    const parent = await d.parentByTelegramId(ctx.from.id);
    const S = T(parent ? resolveLang(parent.lang) : langFromTelegram(ctx.from.language_code));
    const current = (parent?.checkin_time as string | undefined)?.slice(0, 5);
    await closeTimePicker(ctx);
    if (current === value) {
      await ctx.reply(S.time.unchanged(value));
      return;
    }
    const changed = await d.setCheckinTime(ctx.from.id, value);
    await ctx.reply(changed ? S.time.confirmed(value) : S.time.failed);
  });

  bot.command('family', async (ctx) => {
    const lang = await langFor(ctx);
    const token = await d.familyJoinToken(ctx.from!.id);
    if (!token) {
      await ctx.reply(T(lang).onboarding.coldStart);
      return;
    }
    const child = await d.childName(ctx.from!.id);
    await ctx.reply(T(lang).familyLink.message(child, `${JOIN_BASE_URL}/join/${token}`));
  });

  bot.command('pause', async (ctx) => {
    const S = T(await langFor(ctx));
    const kb = new InlineKeyboard();
    S.pause.buttons.forEach((label, index) => kb.text(label, `pause:${index}`));
    await ctx.reply(S.pause.ask, { reply_markup: kb });
  });

  const offerStop = async (ctx: Context, lang: Lang) => {
    const S = T(lang);
    await ctx.reply(S.stop.ask, {
      reply_markup: new InlineKeyboard()
        .text(S.stop.buttons[0], 'stop:pause')
        .text(S.stop.buttons[1], 'stop:full'),
    });
  };

  bot.command('stop', async (ctx) => {
    await offerStop(ctx, await langFor(ctx));
  });

  bot.hears([...okButtonLabels], async (ctx) => {
    const lang = await langFor(ctx);
    const S = T(lang);
    const name = await d.addressForm(ctx.from!.id);
    const child = await d.childName(ctx.from!.id);
    const res = await d.recordCheckin(ctx.from!.id, 'ok', 'button');

    if (res.result === 'failed') {

      await ctx.reply(S.trouble.checkinFailed, { reply_markup: checkinKeyboard(lang) });
      return;
    }
    if (res.result === 'duplicate') {
      await ctx.reply(S.okRepeatSameDay(name), { reply_markup: hideKeyboard });
      return;
    }

    const texts = await d.botTexts();
    const okPool = texts[lang].ok_reply;
    const childOrFamily = child || (lang === 'en' ? 'your family' : 'семья');
    let reply = res.was_escalated
      ? S.missed.lateCheckin(name, child)
      : okPool?.length
        ? render(okPool[Math.floor(Math.random() * okPool.length)]!, templateVars({ child: childOrFamily }))
        : S.okReplies[Math.floor(Math.random() * S.okReplies.length)]!(child);
    if (res.milestone) {
      const milestone = texts[lang][`milestone_${res.milestone}`]?.[0];
      reply += `\n\n${
        milestone
          ? render(milestone, templateVars({ name, child: childOrFamily }))
          : S.milestones[res.milestone]!(name, child)
      }`;
    }
    await ctx.reply(reply, { reply_markup: hideKeyboard });
    await ringCheckin(res);
    await pushRelief(res, ctx.from!.id);
  });

  bot.hears([...notOkButtonLabels], async (ctx) => {
    const lang = await langFor(ctx);
    const S = T(lang);
    const name = await d.addressForm(ctx.from!.id);
    const res = await d.recordCheckin(ctx.from!.id, 'not_ok', 'button');

    if (res.result === 'failed') {
      await ctx.reply(S.trouble.checkinFailed, { reply_markup: checkinKeyboard(lang) });
      return;
    }
    if (res.result === 'duplicate') {
      await ctx.reply(S.notOk.alreadyKnown(await d.childName(ctx.from!.id)), {
        reply_markup: hideKeyboard,
      });
      return;
    }

    await ctx.reply(S.notOk.ask(name), { reply_markup: notOkOptionsKeyboard(lang) });
    await ringCheckin(res);
    await pushNotOk(res, ctx.from!.id);
  });

  bot.callbackQuery(/^notok:(\d)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const index = Number(ctx.match[1]);
    const S = T(await langFor(ctx));
    const child = await d.childName(ctx.from.id);
    const name = await d.addressForm(ctx.from.id);

    const done = (text: string) => ctx.reply(text, { reply_markup: hideKeyboard });

    switch (index) {
      case 0:
        await done(S.notOk.health(name, child, await d.emergencyNumber(ctx.from.id)));
        await d.setNotOkDetail(ctx.from.id, 'health');
        break;
      case 1:
        await done(S.notOk.mood(child));
        await d.setNotOkDetail(ctx.from.id, 'mood');
        break;
      case 2:
        await done(S.notOk.justDay(child));
        await d.setNotOkDetail(ctx.from.id, 'just_day');
        break;
      case 3: {
        await done(S.notOk.callMe(child));
        await d.setNotOkDetail(ctx.from.id, 'call_me');
        const parent = await d.parentByTelegramId(ctx.from.id);
        if (parent?.family_id) {
          await pushToFamily(env, parent.family_id, {
            title: parent.address_form ?? parent.display_name,
            body: { ru: 'Просит позвонить.', en: 'Asking you to call.' },
            level: 'time-sensitive',
            category: 'NOT_OK',
          });
        }
        break;
      }
      case 4: {
        const converted = await d.convertToAccidentalOk(ctx.from.id);
        await done(converted ? S.notOk.accidental : S.okRepeatSameDay(name));
        break;
      }
      default:
        await done(S.notOk.private(name, child));
        await d.setNotOkDetail(ctx.from.id, 'private');
    }
  });

  bot.on('message:text', async (ctx) => {
    const text = ctx.message.text.toLowerCase().trim();
    const lang = await langFor(ctx);
    const S = T(lang);

    if (text.startsWith('/')) {
      await ctx.reply(S.help(await d.childName(ctx.from!.id)));
      return;
    }

    if (wantsStop(text)) {
      await offerStop(ctx, lang);
      return;
    }

    if (matchesNotOk(text)) {
      const res = await d.recordCheckin(ctx.from!.id, 'not_ok', 'text');
      if (res.result === 'failed') {
        await ctx.reply(S.trouble.checkinFailed, { reply_markup: checkinKeyboard(lang) });
        return;
      }
      if (res.result !== 'duplicate') {
        await ctx.reply(S.notOk.ask(await d.addressForm(ctx.from!.id)), {
          reply_markup: notOkOptionsKeyboard(lang),
        });
      }
      await ringCheckin(res);
      await pushNotOk(res, ctx.from!.id);
      return;
    }
    if (matchesOk(text)) {
      const res = await d.recordCheckin(ctx.from!.id, 'ok', 'text');
      if (res.result === 'failed') {
        await ctx.reply(S.trouble.checkinFailed, { reply_markup: checkinKeyboard(lang) });
        return;
      }
      if (res.result !== 'duplicate') {
        await ctx.reply(S.freeInput.recordedOk, { reply_markup: hideKeyboard });
      } else {
        await ctx.reply(S.okRepeatSameDay(await d.addressForm(ctx.from!.id)), {
          reply_markup: hideKeyboard,
        });
      }
      await ringCheckin(res);
      await pushRelief(res, ctx.from!.id);
      return;
    }

    const storyFamily = await d.storyCapture(ctx.from!.id, ctx.message.text, null);

    const forwardedText = await d.forwardToFamily(ctx.from!.id, { text: ctx.message.text });
    const name = await d.addressForm(ctx.from!.id);
    const child = await d.childName(ctx.from!.id);
    if (storyFamily) {
      await ctx.reply(S.story.captured);
      await d.broadcastToApp(storyFamily, 'story');
      await pushMessage(forwardedText);
      return;
    }
    const hasCheckin = await d.hasCheckinToday(ctx.from!.id);
    await ctx.reply(
      S.freeInput.text(name, child) + (hasCheckin ? '' : `\n\n${S.freeInput.keyboardHint}`),
      { reply_markup: hasCheckin ? hideKeyboard : checkinKeyboard(lang) },
    );
    await pushMessage(forwardedText);
  });

  const markupForChat = async (telegramId: number, lang: Lang) =>
    (await d.hasCheckinToday(telegramId)) ? hideKeyboard : checkinKeyboard(lang);

  bot.on('message:voice', async (ctx) => {
    const lang = await langFor(ctx);
    const S = T(lang);
    const storyFamily = await d.storyCapture(ctx.from!.id, null, ctx.message.voice.file_id);
    const forwardedVoice = await d.forwardToFamily(ctx.from!.id, { voiceFileId: ctx.message.voice.file_id });
    await pushMessage(forwardedVoice);
    if (storyFamily) {
      await ctx.reply(S.story.captured);
      await d.broadcastToApp(storyFamily, 'story');
      return;
    }
    await ctx.reply(S.freeInput.voice(await d.childName(ctx.from!.id)), {
      reply_markup: await markupForChat(ctx.from!.id, lang),
    });
  });

  bot.on('message:photo', async (ctx) => {
    const lang = await langFor(ctx);
    const forwardedPhoto = await d.forwardToFamily(ctx.from!.id, { photoFileId: ctx.message.photo.at(-1)!.file_id });
    await pushMessage(forwardedPhoto);
    await ctx.reply(T(lang).freeInput.photo(await d.childName(ctx.from!.id)), {
      reply_markup: await markupForChat(ctx.from!.id, lang),
    });
  });

  bot.on('message_reaction', async (ctx) => {
    const res = await d.recordCheckin(ctx.from!.id, 'ok', 'reaction');
    if (res.result === 'failed') {
      const lang = await langFor(ctx);

      await ctx.reply(T(lang).trouble.checkinFailed, { reply_markup: checkinKeyboard(lang) });
      return;
    }
    await ringCheckin(res);
    await pushRelief(res, ctx.from!.id);
  });

  bot.on('my_chat_member', async (ctx) => {

    if (ctx.chat?.type !== 'private') return;
    const status = ctx.myChatMember.new_chat_member.status;
    if (status === 'kicked') {
      await d.setBotBlocked(ctx.from.id, true);
      return;
    }
    if (status === 'member') {
      await d.setBotBlocked(ctx.from.id, false);
    }
  });

  const handleMed = async (
    ctx: Context,
    medId: string,
    slot: string,
    status: 'taken' | 'postponed',
    localDate: string,
  ) => {
    await ctx.answerCallbackQuery();
    const S = T(await langFor(ctx));
    const marked = await d.medMark(ctx.from!.id, medId, slot, status, localDate);
    try {
      await ctx.editMessageReplyMarkup();
    } catch {

    }
    if (!marked) {
      await ctx.reply(S.meds.stale);
      return;
    }
    await ctx.reply(status === 'taken' ? S.meds.done : S.meds.later);
    if (status === 'taken') {
      const parent = await d.parentByTelegramId(ctx.from!.id);
      if (parent) await d.broadcastToApp(parent.family_id, 'meds');
    }
  };

  bot.callbackQuery(/^med:([0-9a-f-]{36}):(\d\d:\d\d):([tp]):(\d{4}-\d\d-\d\d)$/, async (ctx) => {
    const [, medId, slot, flag, localDate] = ctx.match;
    await handleMed(ctx, medId!, slot!, flag === 't' ? 'taken' : 'postponed', localDate!);
  });

  bot.callbackQuery(/^med:([0-9a-f-]{36}):(\d\d:\d\d):(taken|postponed)$/, async (ctx) => {
    const [, medId, slot, status] = ctx.match;
    const parent = await d.parentByTelegramId(ctx.from.id);
    await handleMed(ctx, medId!, slot!, status as 'taken' | 'postponed', localDate(parent?.timezone));
  });

  bot.callbackQuery(/^evening:(ok|not_ok)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const S = T(await langFor(ctx));
    const status = ctx.match[1] as 'ok' | 'not_ok';
    const familyId = await d.recordEvening(ctx.from.id, status);
    try {
      await ctx.editMessageReplyMarkup();
    } catch {

    }
    await ctx.reply(status === 'ok' ? S.evening.ok : S.evening.notOk);
    if (familyId) await d.broadcastToApp(familyId, 'evening');
  });

  bot.callbackQuery('stop:full', async (ctx) => {
    await ctx.answerCallbackQuery();

    const S = T(await langFor(ctx));
    await d.stopAndErase(ctx.from.id);

    await ctx.reply(S.stop.confirmed, { reply_markup: hideKeyboard });

  });

  bot.callbackQuery('stop:pause', async (ctx) => {
    await ctx.answerCallbackQuery();
    const S = T(await langFor(ctx));
    const kb = new InlineKeyboard();
    S.pause.buttons.forEach((label, index) => kb.text(label, `pause:${index}`));
    await ctx.reply(S.pause.ask, { reply_markup: kb });
  });

  bot.callbackQuery(/^pause:(\d)$/, async (ctx) => {
    await ctx.answerCallbackQuery();
    const lang = await langFor(ctx);
    const S = T(lang);
    const days = [1, 3, 7, 3650][Number(ctx.match[1])] ?? 1;
    const until = new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
    await d.setPause(ctx.from.id, until);
    const label = days > 365 ? S.pause.untilReturn : until;

    await ctx.reply(S.pause.confirmed(label), { reply_markup: checkinKeyboard(lang) });

  });

  return bot;
}
