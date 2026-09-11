import type { Env } from './index';
import { pushToFamily, type Push } from './apns';
import type { InviteNudge } from './db';
import { db } from './db';
import type { Delivery } from './channels';
import { T, render, resolveLang, templateVars, type Lang } from './texts';

export const NIGHT_START_HOUR = 23;
export const NIGHT_END_HOUR = 8;

function ruDays(n: number): string {
  const m10 = n % 10;
  const m100 = n % 100;
  if (m10 === 1 && m100 !== 11) return `${n} день`;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return `${n} дня`;
  return `${n} дней`;
}

function inviteNudgePush(nudge: InviteNudge): Push {
  const body = {
    '1': {
      ru: 'Ссылка ещё не открыта. Отправьте её — подключение занимает минуту.',
      en: 'The link hasn’t been opened yet. Send it over — connecting takes a minute.',
    },
    '2': {
      ru: 'Пока не подключились. Чаще всего помогает позвонить и вместе нажать «Запустить». Ссылка та же, она в приложении.',
      en: 'Not connected yet. A call usually helps: press “Start” together. The link is the same, it’s in the app.',
    },
    '3': {
      ru: 'Больше напоминать не буду. Когда будет удобно — ссылка ждёт в приложении.',
      en: 'I won’t remind you again. Whenever it’s convenient, the link is waiting in the app.',
    },
    hot: {
      ru: 'Бот открыт, но подтверждения нет. Позвоните и нажмите «Да, это я» вместе.',
      en: 'The bot is open, but not confirmed yet. Call and press “Yes, it’s me” together.',
    },
  }[nudge.stage];
  return { title: nudge.name, body, level: 'active', category: 'INVITE', parentId: nudge.parent_id };
}

function escalationPush(silentDays: number, name: string): Push | null {
  if (silentDays <= 1) {
    return {
      title: name,
      body: {
        ru: 'Утром ответа не было. Скорее всего, всё в порядке — но лучше позвонить.',
        en: 'The morning went by without a hello. Most likely all is fine — but a call would be best.',
      },
      level: 'time-sensitive',
      category: 'ESCALATION',
    };
  }
  if (silentDays === 2) {
    return {
      title: name,
      body: {
        ru: 'Второй день без ответа. Если вы уже созвонились — всё в порядке, просто кнопка не нажата. Если нет — позвоните.',
        en: 'Second day without a hello. If you have already talked, all is fine and the button just wasn’t pressed. If not, please call.',
      },
      level: 'time-sensitive',
      category: 'ESCALATION',
    };
  }
  if (silentDays === 3) {
    return {
      title: name,
      body: {
        ru: 'Третий день без ответа. Похоже, бот больше не работает: телефон, Telegram или ответы прекратились. Проверьте, а если всё хорошо — поставьте паузу в приложении.',
        en: 'Third day without a hello. The bot may have stopped working: the phone, Telegram, or the replies just stopped. Check in, and if all is well, pause the reminders in the app.',
      },
      level: 'active',
      category: 'ESCALATION',
    };
  }
  if (silentDays % 7 === 0) {
    return {
      title: name,
      body: {
        ru: `Без ответа уже ${ruDays(silentDays)}.`,
        en: `No hello for ${silentDays} days now.`,
      },
      level: 'passive',
      category: 'ESCALATION',
    };
  }
  return null;
}

export async function runCronTick(env: Env, reserve = 0): Promise<void> {
  const d = db(env);

  await d.housekeeping();
  try {
    await tick(d, env, reserve);
  } catch (err) {

    await d.logEvent('error', 'cron', String(err));
  }
}

const SUBREQUEST_BUDGET = 44;

const COST = {
  select: 1,
  morning: 3,
  reping: 3,

  escalation: 15,
  meds: 2,

  postcard: 5,
  evening: 2,
  story: 2,
  digest: 2,
  nudge: 5,
  wave: 2,
  medAlert: 4,
};

const FLOOD_STAMP = 'telegram/not-before';

async function floodedUntil(env: Env): Promise<number> {
  try {
    return Number((await env.SYSTEM.get(FLOOD_STAMP)) ?? '0') || 0;
  } catch {
    return 0;
  }
}

async function holdOff(env: Env, seconds: number): Promise<void> {
  const until = Date.now() + seconds * 1000;
  await env.SYSTEM.put(FLOOD_STAMP, String(until), {

    expirationTtl: Math.max(60, Math.ceil(seconds) + 60),
  }).catch(() => undefined);
}

function subrequestBudget(limit: number) {
  let left = limit;
  return {

    spend(cost: number): void {
      left -= cost;
    },

    afford(cost: number): boolean {
      if (left < cost) return false;
      left -= cost;
      return true;
    },

    refund(cost: number): void {
      left += cost;
    },
  };
}

async function tick(d: ReturnType<typeof db>, env: Env, reserve: number): Promise<void> {
  const budget = subrequestBudget(SUBREQUEST_BUDGET - reserve);
  let deferred = 0;

  const holdUntil = await floodedUntil(env);
  let flooded = holdUntil > Date.now();
  if (flooded) {
    await d.logEvent(
      'warn',
      'tg-flood',
      `holding off ${Math.ceil((holdUntil - Date.now()) / 1000)}s`,
    );
  }

  const delivered = async (outcome: Delivery): Promise<boolean> => {
    if (outcome.kind === 'retry') {
      flooded = true;
      await holdOff(env, outcome.afterSec);
      await d.logEvent('warn', 'tg-flood', `pausing ${outcome.afterSec}s: ${outcome.detail}`);
      return false;
    }

    if (outcome.kind === 'gone') budget.spend(2);
    else if (outcome.kind === 'failed') budget.spend(1);
    return outcome.kind === 'ok';
  };

  budget.spend(1);
  const texts = await d.botTexts();

  budget.spend(COST.select);
  const due = await d.cronDue();

  for (const [i, parent] of due.deadline.entries()) {

    if (!budget.afford(COST.escalation)) {
      deferred += due.deadline.length - i;
      break;
    }

    let used = 2;
    const escalation = await d.createEscalation(parent.parent_id, parent.local_date);
    if (!escalation) {

      budget.refund(COST.escalation - 1);
      continue;
    }

    await d.broadcastToApp(parent.family_id, 'escalation');
    const name = parent.address_form ?? parent.display_name;
    const lang = resolveLang(parent.lang);
    const S = T(lang);

    const silentDays = await d.silentDays(parent.parent_id, parent.local_date);
    used += 1;
    const push = escalationPush(silentDays, name);
    if (push) {
      const pushed = await pushToFamily(env, parent.family_id, push, COST.escalation - used - 1);
      used += pushed.spent;
      if (pushed.delivered > 0) {
        await d.markChildrenNotified(parent.parent_id, parent.local_date);
        used += 1;
      }
    }

    if (!flooded) {
      const child = parent.child_display_name || (lang === 'en' ? 'your family' : 'семья');
      const text = texts[lang].missed?.[0]
        ? render(texts[lang].missed[0]!, templateVars({ name, child }))
        : S.missed.afterDeadline(name, parent.child_display_name);
      try {
        await delivered(await d.send(parent.telegram_user_id, { text, checkinKeyboard: lang }));
        used += 1;
      } catch {

      }
    }

    budget.refund(COST.escalation - used);

  }

  if (!flooded) {
    const dueMorning = due.morning;
    for (const [i, parent] of dueMorning.entries()) {
      if (!budget.afford(COST.morning)) {
        deferred += dueMorning.length - i;
        break;
      }
      const name = parent.address_form ?? parent.display_name;
      const lang = resolveLang(parent.lang);
      const text = pickMorning(name, parent.parent_id, parent.local_date, lang, texts[lang].morning);
      const outcome = await d.send(parent.telegram_user_id, { text, checkinKeyboard: lang });
      const sent = await delivered(outcome);

      if (flooded) break;
      await d.markMorningSent(parent.parent_id, sent);
      await d.broadcastToApp(parent.family_id, 'morning');
    }
  }

  if (!flooded) {
    const dueRePing = due.reping;
    for (const [i, parent] of dueRePing.entries()) {
      if (!budget.afford(COST.reping)) {
        deferred += dueRePing.length - i;
        break;
      }
      const name = parent.address_form ?? parent.display_name;
      const lang = resolveLang(parent.lang);
      const seed = hash(parent.parent_id + 'reping');
      const pool = texts[lang].reping;
      const fallback = T(lang).missed.reping;
      const text = pool?.length
        ? render(pool[seed % pool.length]!, templateVars({ name }))
        : fallback[seed % fallback.length]!(name);

      await delivered(await d.send(parent.telegram_user_id, { text, checkinKeyboard: lang }));
      if (flooded) break;
      await d.markRePingSent(parent.parent_id);
      await d.broadcastToApp(parent.family_id, 'reping');

    }
  }

  if (!flooded) {
    const dueMeds = due.meds;
    for (const [i, med] of dueMeds.entries()) {
      if (!budget.afford(COST.meds)) {
        deferred += dueMeds.length - i;
        break;
      }
      const name = med.address_form ?? med.display_name;
      const lang = resolveLang(med.lang);
      const S = T(lang);

      await d.medRemindStarted(med.med_id, med.local_date, med.slot.slice(0, 5));
      const reminderText = texts[lang].meds?.[0]
        ? render(texts[lang].meds[0]!, templateVars({ name, medication: med.med_title }))
        : S.meds.reminder(name, med.med_title);
      await delivered(
        await d.send(med.telegram_user_id, {
          text: reminderText,
          buttons: [[
            { text: S.meds.buttons[0], data: `med:${med.med_id}:${med.slot.slice(0, 5)}:t:${med.local_date}` },
            { text: S.meds.buttons[1], data: `med:${med.med_id}:${med.slot.slice(0, 5)}:p:${med.local_date}` },
          ]],
        }),
      );
      if (flooded) break;
    }
  }

  if (!flooded && budget.afford(1)) {
    for (const alert of await d.medAlertsDue()) {
      if (!budget.afford(COST.medAlert)) break;
      await d.markMedAlertSent(alert.event_id);
      await d.broadcastToApp(alert.family_id, 'meds');
      await pushToFamily(
        env,
        alert.family_id,
        {
          title: alert.name,
          body: {
            ru: `Лекарство не отмечено: ${alert.med_title} в ${alert.slot}. Кнопка не нажата — стоит спросить.`,
            en: `Medication not marked: ${alert.med_title} at ${alert.slot}. The button wasn’t pressed — worth asking.`,
          },
          level: 'active',
          category: 'MEDS',
          parentId: alert.parent_id,
        },
        COST.medAlert - 2,
      );
    }
  }

  if (!flooded) {
    const duePostcards = due.postcards;
    for (const [i, card] of duePostcards.entries()) {
      if (!budget.afford(COST.postcard)) {
        deferred += duePostcards.length - i;
        break;
      }
      await d.markPostcardSent(card.postcard_id);
      const caption = T(resolveLang(card.lang)).postcard.delivered(card.author_name, card.body);
      if (card.photo_path) {
        const bytes = await d.takePostcardPhoto(card.family_id, card.photo_path);
        if (bytes) {
          await delivered(await d.sendPhoto(card.telegram_user_id, bytes, caption));
          if (flooded) break;
          continue;
        }
      }
      await delivered(await d.send(card.telegram_user_id, { text: caption }));
      if (flooded) break;
    }
  }

  if (!flooded && budget.afford(1)) {
    for (const wave of await d.wavesDue()) {
      if (!budget.afford(COST.wave)) break;
      await d.markWaveSent(wave.wave_id);
      const text = T(resolveLang(wave.lang)).wave(wave.author, wave.gender === 'daughter');
      await delivered(await d.send(wave.telegram_user_id, { text }));
      if (flooded) break;
    }
  }

  if (!flooded) {
    const dueEvening = due.evening;
    for (const [i, parent] of dueEvening.entries()) {
      if (!budget.afford(COST.evening)) {
        deferred += dueEvening.length - i;
        break;
      }
      const name = parent.address_form ?? parent.display_name;
      const lang = resolveLang(parent.lang);
      const S = T(lang);
      await d.markEveningSent(parent.parent_id, parent.local_date);
      const eveningText = texts[lang].evening?.[0]
        ? render(texts[lang].evening[0]!, templateVars({ name }))
        : S.evening.ask(name);
      await delivered(
        await d.send(parent.telegram_user_id, {
          text: eveningText,
          buttons: [[
            { text: S.evening.buttons[0], data: 'evening:ok' },
            { text: S.evening.buttons[1], data: 'evening:not_ok' },
          ]],
        }),
      );
      if (flooded) break;
    }
  }

  if (!flooded) {
    const dueStories = due.story;
    if (dueStories.length > 0) {
      budget.spend(1);
      const pools = await d.storyQuestionPools();
      for (const [i, parent] of dueStories.entries()) {
        if (!budget.afford(COST.story)) {
          deferred += dueStories.length - i;
          break;
        }
        const name = parent.address_form ?? parent.display_name;
        const lang = resolveLang(parent.lang);
        const S = T(lang);
        const questions = pools[lang].length > 0 ? pools[lang] : [...S.story.pool];
        const week = Math.floor(Date.parse(parent.week_start) / 604_800_000);
        const question = questions[(week + hash(parent.parent_id)) % questions.length]!;
        await d.storyAsked(parent.parent_id, parent.family_id, question, parent.week_start);
        const askText = texts[lang].story_ask?.[0]
          ? render(texts[lang].story_ask[0]!, templateVars({ name, question }))
          : S.story.ask(name, question);
        await delivered(await d.send(parent.telegram_user_id, { text: askText }));
        if (flooded) break;
      }
    }
  }

  if (!flooded) {
    const dueDigest = due.digest;
    for (const [i, parent] of dueDigest.entries()) {
      if (!budget.afford(COST.digest)) {
        deferred += dueDigest.length - i;
        break;
      }
      const name = parent.address_form ?? parent.display_name;
      const child = parent.child_display_name;
      const lang = resolveLang(parent.lang);
      const S = T(lang);
      const P = texts[lang];
      await d.markDigestSent(parent.parent_id, parent.week_start);
      const vars = templateVars({
        name,
        child: child || (lang === 'en' ? 'Your family' : 'Ваши близкие'),
        days: parent.covered_days,
        answers: parent.ok_days,
      });
      const text =
        parent.ok_days >= parent.covered_days
          ? (P.digest_full?.[0] ? render(P.digest_full[0]!, vars) : S.digest.full(name, child, parent.covered_days))
          : parent.ok_days >= Math.ceil(parent.covered_days / 2)
            ? (P.digest_most?.[0] ? render(P.digest_most[0]!, vars) : S.digest.most(name, child, parent.ok_days, parent.covered_days))
            : (P.digest_few?.[0] ? render(P.digest_few[0]!, vars) : S.digest.few(name));
      await delivered(await d.send(parent.telegram_user_id, { text }));
      if (flooded) break;
    }
  }

  if (budget.afford(1)) {
    for (const event of await d.demoTick()) {
      if (!budget.afford(3)) break;
      if (event.kind === 'checkin') {
        await d.broadcastToApp(event.family_id, 'checkin');
        await pushToFamily(
          env,
          event.family_id,
          {
            title: event.name,
            body: event.status === 'ok'
              ? { ru: 'Всё хорошо ☀️', en: 'All is well ☀️' }
              : { ru: 'Сегодня не очень. Загляните в приложение — и лучше позвоните.', en: 'Not a great day today. Open the app — better yet, call.' },
            level: 'active',
            category: event.status === 'ok' ? 'CHECKIN_OK' : 'NOT_OK',
          },
          2,
        );
      } else {
        await d.broadcastToApp(event.family_id, 'detail');
        await pushToFamily(
          env,
          event.family_id,
          { title: event.name, body: { ru: 'Пара слов для вас', en: 'A few words for you' }, level: 'active', category: 'MESSAGE' },
          2,
        );
      }
    }
  }

  if (budget.afford(1)) {
    for (const nudge of await d.inviteNudgesDue()) {
      if (!budget.afford(COST.nudge)) break;
      await d.markInviteNudge(nudge.parent_id, nudge.stage);
      await pushToFamily(env, nudge.family_id, inviteNudgePush(nudge), COST.nudge - 1);
    }
  }

  if (deferred > 0) {
    await d.logEvent('warn', 'cron-budget', `${deferred} item(s) deferred to the next tick`);
  }

}

function pickMorning(
  name: string,
  parentId: string,
  localDate: string,
  lang: Lang,
  pool?: string[],
): string {
  const dayOfYear = Math.floor(Date.parse(localDate) / 86_400_000);
  const seed = dayOfYear + hash(parentId);
  if (pool?.length) return render(pool[seed % pool.length]!, templateVars({ name }));
  const fallback = T(lang).morningPool;
  return fallback[seed % fallback.length]!(name);
}

function hash(value: string): number {
  let h = 0;
  for (let i = 0; i < value.length; i++) h = (h * 31 + value.charCodeAt(i)) >>> 0;
  return h;
}
