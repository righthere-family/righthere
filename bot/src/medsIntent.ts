export interface MedOption {
  id: string;
  title: string;
}

export interface MedRequest {
  title: string;
  times: string[];
}

const TAKEN = /(^|[^a-zа-яё])(выпил|выпила|принял|приняла|попил|попила|проглотил|проглотила|закапал|закапала|уколол|укололась|took|taken|swallowed)(?![a-zа-яё])/i;
const NEGATED = /(^|[^a-zа-яё])(не|ещё|еще|забыл|забыла|пока|forgot|not|haven't|didn't|hasn't|yet)(?![a-zа-яё])/i;
const MED_WORDS = /(таблет|лекарств|капл|укол|витамин|пилюл|микстур|инсулин|пастилк|сироп|pill|tablet|medic|meds|drops|vitamin|insulin|injection|dose|capsule)/i;

const REQUEST = /(^|[^a-zа-яё])(напоминай|напомни|напоминать|напоминание|напоминания|remind|reminder)(?![a-zа-яё])/i;
const REQUEST_LEAD = /^(мне|me|пожалуйста|please|о|об|про|to|about|of|take|taking|принимать|пить|выпить|выпивать|принять|что|чтобы|надо|нужно)$/i;

const WORD_TIMES: Array<[RegExp, string]> = [
  [/после\s+завтрака|after\s+breakfast/i, '09:30'],
  [/после\s+обеда|after\s+lunch/i, '14:30'],
  [/после\s+ужина|after\s+dinner/i, '19:30'],
  [/перед\s+сном|before\s+bed|at\s+night|на\s+ночь|ночью/i, '22:00'],
  [/(^|[^а-яё])утром|(^|[^a-z])in\s+the\s+morning|(^|[^a-z])mornings?(?![a-z])/i, '09:00'],
  [/(^|[^а-яё])дн[её]м|(^|[^a-z])in\s+the\s+afternoon|(^|[^a-z])at\s+noon/i, '14:00'],
  [/(^|[^а-яё])вечером|(^|[^a-z])in\s+the\s+evening|(^|[^a-z])evenings?(?![a-z])/i, '19:00'],
];

const CLOCK = /(?:^|[^\d:])(?:в|at)\s*(\d{1,2})(?:[:.](\d{2}))?\s*(утра|вечера|дня|ночи|am|pm|часов|часа)?(?![\d:])/gi;

function stem(word: string): string {
  return word.length > 5 ? word.slice(0, 5) : word;
}

function tokens(text: string): string[] {
  return text.toLowerCase().split(/[^a-zа-яё0-9]+/).filter((t) => t.length >= 3);
}

function titleMatches(title: string, text: string): boolean {
  const words = tokens(text).map(stem);
  const all = tokens(title);
  const specific = all.filter((t) => !MED_WORDS.test(t));
  return (specific.length ? specific : all).some((t) => words.includes(stem(t)));
}

export function detectMedTaken(text: string, meds: MedOption[]): MedOption | null {
  if (meds.length === 0 || !TAKEN.test(text) || NEGATED.test(text)) return null;
  const named = meds.filter((m) => titleMatches(m.title, text));
  if (named.length === 1) return named[0]!;
  if (named.length > 1) return null;
  if (meds.length === 1 && MED_WORDS.test(text)) return meds[0]!;
  return null;
}

function normalizeHour(hour: number, suffix: string | undefined): number | null {
  let h = hour;
  const s = (suffix ?? '').toLowerCase();
  if ((s === 'вечера' || s === 'pm') && h < 12) h += 12;
  if (s === 'дня' && h <= 6) h += 12;
  if ((s === 'ночи' || s === 'am') && h === 12) h = 0;
  return h >= 0 && h <= 23 ? h : null;
}

export function parseTimes(text: string): string[] {
  const out: string[] = [];
  for (const match of text.matchAll(CLOCK)) {
    const hour = normalizeHour(Number(match[1]), match[3]);
    const minute = match[2] ? Number(match[2]) : 0;
    if (hour === null || minute > 59) continue;
    out.push(`${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`);
  }
  if (out.length === 0) {
    for (const [pattern, time] of WORD_TIMES) {
      if (pattern.test(text)) out.push(time);
    }
  }
  return [...new Set(out)].sort();
}

function stripTimes(text: string): string {
  let rest = text.replace(CLOCK, ' ');
  for (const [pattern] of WORD_TIMES) rest = rest.replace(new RegExp(pattern.source, 'gi'), ' ');
  return rest;
}

export function detectMedRequest(text: string): MedRequest | null {
  if (!REQUEST.test(text)) return null;
  const times = parseTimes(text);
  if (times.length === 0) return null;

  const rest = stripTimes(text.replace(REQUEST, ' '))
    .replace(/[«»"“”]/g, ' ')
    .replace(/\s+(и|and)\s+/gi, ' ')
    .replace(/[.!?;,]+/g, ' ');
  const words = rest.split(/\s+/).filter(Boolean);
  while (words.length && REQUEST_LEAD.test(words[0]!)) words.shift();
  while (words.length && REQUEST_LEAD.test(words[words.length - 1]!)) words.pop();
  const title = words.join(' ').trim();
  if (title.length < 2 || title.length > 60) return null;
  return { title: title.charAt(0).toUpperCase() + title.slice(1), times };
}

export function pickOpenSlot(times: string[], taken: string[], localTime: string): string | null {
  const open = times.map((t) => t.slice(0, 5)).filter((t) => !taken.some((x) => x.slice(0, 5) === t)).sort();
  if (open.length === 0) return null;
  const [h, m] = localTime.split(':').map(Number);
  const limit = (h ?? 0) * 60 + (m ?? 0) + 30;
  const past = open.filter((t) => {
    const [th, tm] = t.split(':').map(Number);
    return (th ?? 0) * 60 + (tm ?? 0) <= limit;
  });
  return past.length ? past[past.length - 1]! : open[0]!;
}
