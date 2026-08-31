import { createClient, SupabaseClient } from '@supabase/supabase-js';
import type { Env } from './index';
import { T, langFromTelegram, resolveLang, type Lang } from './texts';
import { tgCall, tgUpload, type TgOutcome } from './telegram';
import { isKvPhotoId, putPhoto, takePhoto, withinPhotoQuota } from './photos';

export type CheckinStatus = 'ok' | 'not_ok' | 'accidental_ok';
export type CheckinSource = 'button' | 'text' | 'voice' | 'reaction' | 'late';
export type NotOkKind = 'health' | 'mood' | 'just_day' | 'call_me' | 'private';

export interface CheckinResult {

  result: 'ok' | 'upgraded' | 'worsened' | 'duplicate' | 'unknown_parent' | 'failed';
  was_escalated?: boolean;
  streak?: number;
  milestone?: number | null;
  parent_id?: string;
  family_id?: string;
}

export interface DueParent {
  parent_id: string;
  family_id: string;
  telegram_user_id: number;
  display_name: string;
  address_form: string | null;
  checkin_time: string;
  window_min: number;
  tz: string;
  child_display_name: string;
  lang: string;
  local_date: string;
}

export interface DueMed {
  telegram_user_id: number;
  family_id: string;
  med_id: string;
  med_title: string;
  slot: string;
  address_form: string | null;
  display_name: string;
  lang: string;
  is_repeat: boolean;
  local_date: string;
}

export interface DuePostcard {
  postcard_id: string;
  family_id: string;
  telegram_user_id: number;
  author_name: string;
  body: string;
  photo_path: string | null;
  lang: string;
}

export interface DueEvening {
  parent_id: string;
  family_id: string;
  telegram_user_id: number;
  address_form: string | null;
  display_name: string;
  lang: string;
  local_date: string;
}

export interface DueStory {
  parent_id: string;
  family_id: string;
  telegram_user_id: number;
  address_form: string | null;
  display_name: string;
  lang: string;
  week_start: string;
}

export interface DueDigest {
  parent_id: string;
  telegram_user_id: number;
  address_form: string | null;
  display_name: string;
  child_display_name: string;
  lang: string;
  ok_days: number;
  covered_days: number;
  week_start: string;
}

export interface CronDue {
  at: string;
  deadline: DueParent[];
  morning: DueParent[];
  reping: DueParent[];
  meds: DueMed[];
  postcards: DuePostcard[];
  evening: DueEvening[];
  story: DueStory[];
  digest: DueDigest[];
}

const EMPTY_DUE: CronDue = {
  at: '',
  deadline: [],
  morning: [],
  reping: [],
  meds: [],
  postcards: [],
  evening: [],
  story: [],
  digest: [],
};

export interface InviteInfo {
  code: string;
  parent_id: string;
  parent_name: string;
  address_form: string | null;
  child_name: string;
  child_gender: 'son' | 'daughter';
  lang: string;
}

export interface BoundInvite {
  parent_id: string;
  family_id: string;
  child_name: string;
  child_gender: 'son' | 'daughter';
  lang: string;
}

export interface ParentRow {
  id: string;
  family_id: string;
  display_name: string;
  address_form: string | null;
  timezone: string;
  checkin_time: string;
  window_min: number;
  telegram_user_id: number | null;
  bot_state: string;
  paused_until: string | null;
  evening_time: string | null;
  city: string | null;
  phone: string | null;
  lang: string;
}

type PgResult<T> = { data: T | null; error: { message: string } | null };

function describeOutcome(outcome: TgOutcome): string {
  switch (outcome.kind) {
    case 'ok':
      return 'ok';
    case 'retry':
      return `retry after ${outcome.afterSec}s: ${outcome.description}`;
    case 'gone':
      return `gone: ${outcome.description}`;
    case 'migrate':
      return `migrated to ${outcome.chatId}`;
    case 'failed':
      return `${outcome.status} ${outcome.description}`;
  }
}

export type BotTextGroups = Record<Lang, Record<string, string[]>>;

let botTextsCache: { at: number; groups: BotTextGroups } | null = null;

export function db(env: Env) {
  const sb: SupabaseClient = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  const telegram = (method: string, body: unknown) =>
    tgCall(env.TELEGRAM_BOT_TOKEN, method, body);

  const logEvent = async (level: 'error' | 'warn', kind: string, detail: string) => {
    try {
      await sb.from('bot_events').insert({ level, kind, detail: detail.slice(0, 500) });
    } catch {

    }
  };

  const must = async <T>(label: string, q: PromiseLike<PgResult<T>>): Promise<T | null> => {
    const { data, error } = await q;
    if (error) throw new Error(`${label}: ${error.message}`);
    return data;
  };

  const best = async <T>(label: string, q: PromiseLike<PgResult<T>>, fallback: T): Promise<T> => {
    try {
      const { data, error } = await q;
      if (error) {
        await logEvent('error', label, error.message);
        return fallback;
      }
      return (data ?? fallback) as T;
    } catch (err) {
      await logEvent('error', label, String(err));
      return fallback;
    }
  };

  const parentCache = new Map<number, ParentRow | null>();
  const forgetParents = () => parentCache.clear();

  return {
    logEvent,

    async housekeeping(): Promise<void> {
      try {
        await sb.rpc('cron_housekeeping');
      } catch (err) {
        await logEvent('error', 'housekeeping', String(err));
      }
    },

    async sendTelegram(
      chatId: number,
      text: string,
      opts?: { checkinKeyboard?: Lang; replyMarkup?: unknown },
    ): Promise<TgOutcome> {

      const kb = opts?.checkinKeyboard ? T(opts.checkinKeyboard).keyboard : null;
      const reply_markup = kb
        ? {
            keyboard: [[{ text: kb.ok }], [{ text: kb.notOk }]],
            resize_keyboard: true,
            one_time_keyboard: true,
          }
        : opts?.replyMarkup;
      const outcome = await telegram('sendMessage', { chat_id: chatId, text, reply_markup });
      if (outcome.kind === 'gone') {
        await sb.from('parents').update({ bot_state: 'blocked' }).eq('telegram_user_id', chatId);
        forgetParents();
        await logEvent('warn', 'tg-blocked', `chat ${chatId}: ${outcome.description}`);
        return outcome;
      }
      if (outcome.kind === 'failed') {
        await logEvent('error', 'tg-send', `chat ${chatId}: ${outcome.status} ${outcome.description}`);
      }
      return outcome;
    },

    async setBotBlocked(telegramUserId: number, blocked: boolean): Promise<void> {
      const next = blocked ? 'blocked' : 'active';
      await best(
        'bot-state',
        sb
          .from('parents')
          .update({ bot_state: next })
          .eq('telegram_user_id', telegramUserId)

          .in('bot_state', blocked ? ['active'] : ['blocked']),
        null,
      );
      forgetParents();
    },

    async broadcastToApp(
      familyId: string,
      kind:
        | 'checkin'
        | 'detail'
        | 'escalation'
        | 'pause'
        | 'morning'
        | 'reping'
        | 'stop'
        | 'bound'
        | 'meds'
        | 'evening'
        | 'story',
    ): Promise<void> {
      try {
        await sb.rpc('ring_family', { p_family_id: familyId, p_kind: kind });
      } catch {

      }
    },

    async findInvite(code: string): Promise<InviteInfo | null> {
      const { data } = await sb.rpc('find_invite', { p_code: code });
      return (data as InviteInfo | null) ?? null;
    },

    async bindInvite(code: string, telegramUserId: number): Promise<BoundInvite | null> {
      const { data } = await sb.rpc('bind_invite', {
        p_code: code,
        p_telegram_user_id: telegramUserId,
      });
      return (data as BoundInvite | null) ?? null;
    },

    async recordCheckin(
      telegramUserId: number,
      status: CheckinStatus,
      source: CheckinSource,
    ): Promise<CheckinResult> {
      const { data, error } = await sb.rpc('record_checkin', {
        p_telegram_user_id: telegramUserId,
        p_status: status,
        p_source: source,
      });
      if (error) {
        await logEvent('error', 'record_checkin', `${telegramUserId}: ${error.message}`);
        return { result: 'failed' };
      }
      return data as CheckinResult;
    },

    async setNotOkDetail(telegramUserId: number, kind: NotOkKind, freeText?: string) {
      await sb.rpc('set_not_ok_detail', {
        p_telegram_user_id: telegramUserId,
        p_kind: kind,
        p_free_text: freeText ?? null,
      });
      const parent = await this.parentByTelegramId(telegramUserId);
      if (parent) await this.broadcastToApp(parent.family_id, 'detail');
    },

    async convertToAccidentalOk(telegramUserId: number): Promise<boolean> {
      const { data } = await sb.rpc('convert_to_accidental', {
        p_telegram_user_id: telegramUserId,
      });
      if (data === true) {
        const parent = await this.parentByTelegramId(telegramUserId);
        if (parent) await this.broadcastToApp(parent.family_id, 'checkin');
      }
      return data === true;
    },

    async activateParent(parentId: string) {
      await must('activate-parent', sb.from('parents').update({ bot_state: 'active' }).eq('id', parentId));
      forgetParents();
    },

    async parentByTelegramId(telegramUserId: number): Promise<ParentRow | null> {
      const cached = parentCache.get(telegramUserId);
      if (cached !== undefined) return cached;
      const row = await best<ParentRow | null>(
        'parent-read',
        sb.from('parents').select('*').eq('telegram_user_id', telegramUserId).maybeSingle(),
        null,
      );
      parentCache.set(telegramUserId, row);
      return row;
    },

    async addressForm(telegramUserId: number): Promise<string> {
      const parent = await this.parentByTelegramId(telegramUserId);
      return parent?.address_form ?? parent?.display_name ?? '';
    },

    async childName(telegramUserId: number): Promise<string> {
      const parent = await this.parentByTelegramId(telegramUserId);
      if (!parent) return '';
      const owner = await best<{ display_name: string } | null>(
        'owner-read',
        sb
          .from('family_members')
          .select('display_name')
          .eq('family_id', parent.family_id)
          .eq('role', 'owner')
          .maybeSingle(),
        null,
      );
      return owner?.display_name ?? '';
    },

    async parentLang(telegramUserId: number, telegramCode?: string): Promise<Lang> {
      const parent = await this.parentByTelegramId(telegramUserId);
      return parent ? resolveLang(parent.lang) : langFromTelegram(telegramCode);
    },

    async emergencyNumber(telegramUserId: number): Promise<string> {
      const parent = await this.parentByTelegramId(telegramUserId);
      const tz: string = parent?.timezone ?? '';

      if (tz.startsWith('Asia/Almaty') || tz.startsWith('Asia/Aqtobe') || tz.startsWith('Asia/Qostanay')) return '103';
      if (tz.startsWith('Asia/Yerevan')) return '911';
      if (tz.startsWith('Asia/Tbilisi')) return '112';
      if (tz.startsWith('America/')) return '911';
      if (tz.startsWith('Australia/')) return '000';
      if (tz === 'Europe/Moscow' || tz === 'Europe/Samara' || tz === 'Europe/Kaliningrad'
          || tz === 'Europe/Volgograd' || tz === 'Europe/Saratov' || tz === 'Europe/Ulyanovsk'
          || tz === 'Europe/Astrakhan' || tz === 'Europe/Kirov'
          || tz.startsWith('Asia/Yekaterinburg') || tz.startsWith('Asia/Novosibirsk')
          || tz.startsWith('Asia/Krasnoyarsk') || tz.startsWith('Asia/Irkutsk')
          || tz.startsWith('Asia/Omsk') || tz.startsWith('Asia/Vladivostok')
          || tz.startsWith('Asia/Yakutsk') || tz.startsWith('Asia/Sakhalin')
          || tz.startsWith('Asia/Kamchatka') || tz.startsWith('Asia/Magadan')
          || tz.startsWith('Asia/Barnaul') || tz.startsWith('Asia/Tomsk')
          || tz.startsWith('Asia/Novokuznetsk') || tz.startsWith('Asia/Chita')
          || tz.startsWith('Asia/Bishkek') || tz.startsWith('Asia/Tashkent')
          || tz.startsWith('Asia/Dushanbe') || tz === 'Europe/Minsk') return '103';
      return '112';
    },

    async cronDue(): Promise<CronDue> {
      const data = await must<CronDue>('cron_due', sb.rpc('cron_due'));
      return data ?? EMPTY_DUE;
    },

    async parentsDueForMorning(): Promise<DueParent[]> {
      const data = await must<DueParent[]>('parents_due_for_morning', sb.rpc('parents_due_for_morning'));
      return data ?? [];
    },

    async parentsDueForRePing(): Promise<DueParent[]> {
      const data = await must<DueParent[]>('parents_due_for_reping', sb.rpc('parents_due_for_reping'));
      return data ?? [];
    },

    async parentsPastDeadline(): Promise<DueParent[]> {
      const data = await must<DueParent[]>('parents_past_deadline', sb.rpc('parents_past_deadline'));
      return data ?? [];
    },

    async markMorningSent(parentId: string, delivered: boolean) {
      await must(
        'mark_morning_sent',
        sb.rpc('mark_morning_sent', { p_parent_id: parentId, p_delivered: delivered }),
      );
    },

    async markRePingSent(parentId: string) {
      await must('mark_reping_sent', sb.rpc('mark_reping_sent', { p_parent_id: parentId }));
    },

    async createEscalation(parentId: string, localDate: string) {
      const data = await must(
        'create_escalation',
        sb.rpc('create_escalation', { p_parent_id: parentId, p_local_date: localDate }),
      );
      return data ?? null;
    },

    async medsDue(): Promise<DueMed[]> {
      const data = await must<DueMed[]>('meds_due', sb.rpc('meds_due'));
      return data ?? [];
    },

    async medRemindStarted(medId: string, localDate: string, slot: string) {
      await must(
        'med_remind_started',
        sb.rpc('med_remind_started', { p_med_id: medId, p_local_date: localDate, p_slot: slot }),
      );
    },

    async postcardsDue(): Promise<DuePostcard[]> {
      const data = await must<DuePostcard[]>('postcards_due', sb.rpc('postcards_due'));
      return data ?? [];
    },

    async storePostcardPhoto(appToken: string, bytes: ArrayBuffer): Promise<string | null> {
      const family = await best<{ id: string } | null>(
        'family-by-token',
        sb.from('families').select('id').eq('app_token', appToken).maybeSingle(),
        null,
      );
      if (!family) return null;
      if (!(await withinPhotoQuota(env.POSTCARD_PHOTOS, family.id))) {
        await logEvent('warn', 'photo-quota', `family ${family.id} hit the daily photo quota`);
        return 'quota';
      }
      return putPhoto(env.POSTCARD_PHOTOS, family.id, bytes);
    },

    async takePostcardPhoto(familyId: string, photoPath: string): Promise<ArrayBuffer | null> {
      if (isKvPhotoId(photoPath)) {
        return takePhoto(env.POSTCARD_PHOTOS, familyId, photoPath);
      }
      return this.takeLegacyPhoto(photoPath);
    },

    async takeLegacyPhoto(blobId: string): Promise<ArrayBuffer | null> {
      const row = await best<{ bytes: string } | null>(
        'legacy-photo',
        sb.from('postcard_blobs').select('bytes').eq('id', blobId).maybeSingle(),
        null,
      );
      const hex = row?.bytes;
      if (!hex || !hex.startsWith('\\x')) return null;
      const raw = hex.slice(2);
      const LEGACY_LIMIT_BYTES = 1_500_000;
      if (raw.length / 2 > LEGACY_LIMIT_BYTES) {
        await logEvent('warn', 'legacy-photo', `${blobId}: ${raw.length / 2} bytes, sent as text`);
        await sb.from('postcard_blobs').delete().eq('id', blobId);
        return null;
      }
      const bytes = new Uint8Array(raw.length / 2);
      for (let i = 0; i < bytes.length; i++) {
        bytes[i] = parseInt(raw.slice(i * 2, i * 2 + 2), 16);
      }
      await sb.from('postcard_blobs').delete().eq('id', blobId);
      return bytes.buffer;
    },

    async sendPhoto(chatId: number, bytes: ArrayBuffer, caption: string): Promise<TgOutcome> {
      const form = new FormData();
      form.set('chat_id', String(chatId));
      form.set('photo', new Blob([bytes], { type: 'image/jpeg' }), 'postcard.jpg');
      if (caption) form.set('caption', caption);
      const outcome = await tgUpload(env.TELEGRAM_BOT_TOKEN, 'sendPhoto', form);
      if (outcome.kind === 'failed' || outcome.kind === 'gone') {
        await logEvent('error', 'tg-photo', `chat ${chatId}: ${describeOutcome(outcome)}`);
      }
      return outcome;
    },

    async parentsDueForEvening(): Promise<DueEvening[]> {
      const data = await must<DueEvening[]>('parents_due_for_evening', sb.rpc('parents_due_for_evening'));
      return data ?? [];
    },

    async markEveningSent(parentId: string, localDate: string): Promise<void> {
      await must(
        'mark_evening_sent',
        sb.rpc('mark_evening_sent', { p_parent_id: parentId, p_local_date: localDate }),
      );
    },

    async recordEvening(telegramUserId: number, status: 'ok' | 'not_ok'): Promise<string | null> {
      const { data } = await sb.rpc('record_evening', {
        p_telegram_user_id: telegramUserId,
        p_status: status,
      });
      return (data as string | null) ?? null;
    },

    async markPostcardSent(id: string): Promise<void> {
      await must('mark_postcard_sent', sb.rpc('mark_postcard_sent', { p_id: id }));
    },

    async familyJoinToken(telegramUserId: number): Promise<string | null> {
      const parent = await this.parentByTelegramId(telegramUserId);
      if (!parent) return null;
      const { data } = await sb
        .from('families')
        .select('app_token')
        .eq('id', parent.family_id)
        .maybeSingle();
      return (data?.app_token as string | undefined) ?? null;
    },

    async parentsDueForStory(): Promise<DueStory[]> {
      const data = await must<DueStory[]>('parents_due_for_story', sb.rpc('parents_due_for_story'));
      return data ?? [];
    },

    async botTexts(): Promise<BotTextGroups> {
      if (botTextsCache && Date.now() - botTextsCache.at < 120_000) {
        return botTextsCache.groups;
      }
      const { data } = await sb
        .from('bot_texts')
        .select('group_key, text, lang')
        .eq('active', true)
        .order('sort')
        .order('id');
      const groups: BotTextGroups = { ru: {}, en: {} };
      for (const row of data ?? []) {
        const bucket = groups[resolveLang(row.lang as string)];
        (bucket[row.group_key as string] ??= []).push(row.text as string);
      }
      botTextsCache = { at: Date.now(), groups };
      return groups;
    },

    async storyQuestionPools(): Promise<Record<Lang, string[]>> {
      const { data } = await sb
        .from('story_questions')
        .select('text, lang')
        .eq('active', true)
        .order('sort')
        .order('id');
      const pools: Record<Lang, string[]> = { ru: [], en: [] };
      for (const row of data ?? []) {
        pools[resolveLang(row.lang as string)].push(row.text as string);
      }
      return pools;
    },

    async storyAsked(parentId: string, familyId: string, question: string, weekStart: string) {
      await must(
        'story_asked',
        sb.rpc('story_asked', {
          p_parent_id: parentId,
          p_family_id: familyId,
          p_question: question,
          p_week_start: weekStart,
        }),
      );
    },

    async storyCapture(
      telegramUserId: number,
      text: string | null,
      voiceFileId: string | null,
    ): Promise<string | null> {
      const { data } = await sb.rpc('story_capture', {
        p_telegram_user_id: telegramUserId,
        p_text: text,
        p_voice_file_id: voiceFileId,
      });
      return (data as string | null) ?? null;
    },

    async storyVoiceBelongs(appToken: string, fileId: string): Promise<boolean> {
      const { data } = await sb
        .from('family_stories')
        .select('id, families!inner(app_token)')
        .eq('voice_file_id', fileId)
        .eq('families.app_token', appToken)
        .maybeSingle();
      if (data != null) return true;

      const { data: message } = await sb
        .from('parent_messages')
        .select('id, families!inner(app_token)')
        .or(`voice_file_id.eq.${fileId},photo_file_id.eq.${fileId}`)
        .eq('families.app_token', appToken)
        .limit(1)
        .maybeSingle();
      return message != null;
    },

    async adminOverview() {
      const { data } = await sb.rpc('admin_stats');
      return data ?? {};
    },

    async adminFamily(familyId: string) {
      const { data } = await sb.rpc('admin_family', { p_family_id: familyId });
      return data ?? null;
    },

    async adminParentUpdate(
      parentId: string,
      fields: {
        bot_state?: string;
        checkin_time?: string;
        evening_time?: string | null;
        window_min?: number;
        paused_until?: string | null;
        lang?: string;
      },
    ): Promise<boolean> {
      const update: Record<string, unknown> = {};
      if (fields.bot_state && ['active', 'paused'].includes(fields.bot_state)) {
        update.bot_state = fields.bot_state;
        if (fields.bot_state === 'active') update.paused_until = null;
      }
      if (fields.lang && ['ru', 'en'].includes(fields.lang)) {
        update.lang = fields.lang;
      }
      if (fields.paused_until !== undefined) update.paused_until = fields.paused_until;
      if (fields.checkin_time && /^\d\d:\d\d$/.test(fields.checkin_time)) {
        update.checkin_time = fields.checkin_time;
      }
      if (fields.evening_time !== undefined) {
        update.evening_time =
          fields.evening_time && /^\d\d:\d\d$/.test(fields.evening_time)
            ? fields.evening_time
            : null;
      }
      if (fields.window_min && fields.window_min >= 60 && fields.window_min <= 360) {
        update.window_min = fields.window_min;
      }
      if (Object.keys(update).length === 0) return false;
      const { error } = await sb.from('parents').update(update).eq('id', parentId);
      return !error;
    },

    async adminGrantPremium(familyId: string, entitlement: 'premium' | 'family'): Promise<string> {
      const { data, error } = await sb.rpc('admin_set_entitlement', {
        p_family_id: familyId,
        p_entitlement: entitlement,
      });
      return error ? error.message : ((data as string | null) ?? 'unknown');
    },

    async adminRevokePremium(familyId: string): Promise<string> {
      const { data, error } = await sb.rpc('admin_clear_entitlement', { p_family_id: familyId });
      return error ? error.message : ((data as string | null) ?? 'unknown');
    },

    async adminQuestions() {
      const { data } = await sb
        .from('story_questions')
        .select('id, text, active, sort, lang')
        .order('lang')
        .order('sort')
        .order('id');
      return data ?? [];
    },

    async adminQuestionAdd(text: string, lang: Lang) {
      const { data: max } = await sb
        .from('story_questions')
        .select('sort')
        .eq('lang', lang)
        .order('sort', { ascending: false })
        .limit(1)
        .maybeSingle();
      await sb.from('story_questions').insert({ text, lang, sort: (max?.sort ?? 0) + 10 });
    },

    async adminQuestionUpdate(id: string, fields: { text?: string; active?: boolean }) {
      const update: Record<string, unknown> = {};
      if (fields.text !== undefined) update.text = fields.text.trim();
      if (fields.active !== undefined) update.active = fields.active;
      if (Object.keys(update).length > 0) {
        await sb.from('story_questions').update(update).eq('id', id);
      }
    },

    async adminQuestionDelete(id: string) {
      await sb.from('story_questions').delete().eq('id', id);
    },

    async adminTexts() {
      const { data } = await sb
        .from('bot_texts')
        .select('id, group_key, text, active, sort, lang')
        .order('group_key')
        .order('lang')
        .order('sort')
        .order('id');
      return data ?? [];
    },

    async adminTextAdd(groupKey: string, text: string, lang: Lang) {
      const { data: max } = await sb
        .from('bot_texts')
        .select('sort')
        .eq('group_key', groupKey)
        .eq('lang', lang)
        .order('sort', { ascending: false })
        .limit(1)
        .maybeSingle();
      await sb
        .from('bot_texts')
        .insert({ group_key: groupKey, text, lang, sort: (max?.sort ?? 0) + 10 });
      botTextsCache = null;
    },

    async adminTextUpdate(id: string, fields: { text?: string; active?: boolean }) {
      const update: Record<string, unknown> = {};
      if (fields.text !== undefined) update.text = fields.text.trim();
      if (fields.active !== undefined) update.active = fields.active;
      if (Object.keys(update).length > 0) {
        await sb.from('bot_texts').update(update).eq('id', id);
        botTextsCache = null;
      }
    },

    async adminTextDelete(id: string) {
      await sb.from('bot_texts').delete().eq('id', id);
      botTextsCache = null;
    },

    async joinWaitlist(
      telegramUserId: number,
      username: string | undefined,
      firstName: string | undefined,
      languageCode: string | undefined,
    ): Promise<'added' | 'already'> {

      const { data, error } = await sb
        .from('waitlist')
        .upsert(
          {
            telegram_user_id: telegramUserId,
            username: username ?? null,
            first_name: firstName ?? null,

            lang: langFromTelegram(languageCode),
          },
          { onConflict: 'telegram_user_id', ignoreDuplicates: true },
        )
        .select('telegram_user_id');
      if (error) {
        await logEvent('error', 'waitlist', error.message);
        return 'already';
      }
      return (data?.length ?? 0) > 0 ? 'added' : 'already';
    },

    async pushTargets(
      familyId: string,
    ): Promise<{ user_id: string; apns_token: string; apns_env: string; tz: string; lang: string }[]> {
      const { data } = await sb.rpc('push_targets', { p_family_id: familyId });
      return (
        (data as
          | { user_id: string; apns_token: string; apns_env: string; tz: string; lang: string }[]
          | null) ?? []
      );
    },

    async clearPushToken(userId: string, familyId: string): Promise<void> {
      await sb
        .from('family_members')
        .update({ apns_token: null })
        .eq('family_id', familyId)
        .eq('user_id', userId);
    },

    async adminWaitlistInvite(telegramUserId: number): Promise<string> {

      const { data: row } = await sb
        .from('waitlist')
        .select('lang')
        .eq('telegram_user_id', telegramUserId)
        .maybeSingle();
      const lang = resolveLang(row?.lang as string | undefined);
      const texts = await this.botTexts();
      const template = texts[lang].beta_invite?.[0] ?? T(lang).beta.invite;

      if (template.includes('{')) return 'template-incomplete';

      const outcome = await this.sendTelegram(telegramUserId, template);
      if (outcome.kind !== 'ok') return `send-failed: ${describeOutcome(outcome)}`;
      await sb
        .from('waitlist')
        .update({ invited_at: new Date().toISOString() })
        .eq('telegram_user_id', telegramUserId);
      return 'ok';
    },

    async adminWaitlistDelete(telegramUserId: number): Promise<void> {
      await sb.from('waitlist').delete().eq('telegram_user_id', telegramUserId);
    },

    async allFamilyIds(): Promise<string[]> {
      const { data } = await sb.from('families').select('id');
      return (data ?? []).map((row) => row.id as string);
    },

    async setCheckinTime(telegramUserId: number, value: string): Promise<boolean> {
      const { data } = await sb.rpc('set_checkin_time', {
        p_telegram_user_id: telegramUserId,
        p_time: `${value}:00`,
      });
      const familyId = data as string | null;
      if (!familyId) return false;
      forgetParents();
      await this.broadcastToApp(familyId, 'detail');
      return true;
    },

    async parentsDueForDigest(): Promise<DueDigest[]> {
      const data = await must<DueDigest[]>('parents_due_for_digest', sb.rpc('parents_due_for_digest'));
      return data ?? [];
    },

    async markDigestSent(parentId: string, weekStart: string): Promise<void> {
      await must(
        'mark_digest_sent',
        sb.rpc('mark_digest_sent', { p_parent_id: parentId, p_week_start: weekStart }),
      );
    },

    async medMark(
      telegramUserId: number,
      medId: string,
      slot: string,
      status: 'taken' | 'postponed',
      localDate: string,
    ): Promise<boolean> {
      const { data } = await sb.rpc('med_mark', {
        p_telegram_user_id: telegramUserId,
        p_med_id: medId,
        p_slot: slot,
        p_status: status,
        p_local_date: localDate,
      });
      return data === true;
    },

    async hasCheckinToday(telegramUserId: number): Promise<boolean> {
      const parent = await this.parentByTelegramId(telegramUserId);
      if (!parent) return false;
      const { data: localDate } = await sb.rpc('parent_local_date', { p_parent_id: parent.id });
      const { count } = await sb
        .from('checkins')
        .select('id', { count: 'exact', head: true })
        .eq('parent_id', parent.id)
        .eq('local_date', localDate as string);
      return (count ?? 0) > 0;
    },

    async forwardToFamily(
      telegramUserId: number,
      payload: { text?: string; voiceFileId?: string; photoFileId?: string },
    ) {
      const parent = await this.parentByTelegramId(telegramUserId);
      if (!parent) return;

      const kind = payload.text ? 'text' : payload.voiceFileId ? 'voice' : 'photo';
      await best(
        'parent-message',
        sb.from('parent_messages').insert({
          family_id: parent.family_id,
          parent_id: parent.id,
          kind,
          body: payload.text ?? null,
          voice_file_id: payload.voiceFileId ?? null,
          photo_file_id: payload.photoFileId ?? null,
        }),
        null,
      );

      if (payload.text) {
        await best(
          'set_not_ok_detail',
          sb.rpc('set_not_ok_detail', {
            p_telegram_user_id: telegramUserId,
            p_kind: null,
            p_free_text: payload.text,
          }),
          null,
        );
      }
      await this.broadcastToApp(parent.family_id, 'detail');
    },

    async stopAndErase(telegramUserId: number) {
      const parent = await this.parentByTelegramId(telegramUserId);
      if (!parent) return;
      const summary = await must('erase_parent', sb.rpc('erase_parent', { p_parent_id: parent.id }));
      forgetParents();
      await logEvent('warn', 'erase', JSON.stringify(summary ?? {}).slice(0, 400));
      await this.broadcastToApp(parent.family_id, 'stop');
    },

    async setPause(telegramUserId: number, untilLocalDate: string) {
      const parent = await this.parentByTelegramId(telegramUserId);
      if (!parent) return;
      await must(
        'set-pause',
        sb
          .from('parents')
          .update({ bot_state: 'paused', paused_until: untilLocalDate })
          .eq('id', parent.id),
      );
      forgetParents();
      await this.broadcastToApp(parent.family_id, 'pause');
    },

    async applyRevenueCatEvent(_payload: unknown) {

    },
  };
}
