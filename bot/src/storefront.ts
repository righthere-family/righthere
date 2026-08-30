import { tgCall, type TgOutcome } from './telegram';

interface Command {
  command: string;
  description: string;
}

interface Storefront {
  language: string;
  commands: Command[];
  name: string;
  shortDescription: string;
  description: string;
}

const STOREFRONTS: Storefront[] = [
  {
    language: '',
    commands: [
      { command: 'time', description: 'Время утреннего сообщения' },
      { command: 'family', description: 'Ссылка для семьи' },
      { command: 'pause', description: 'Пауза на несколько дней' },
      { command: 'help', description: 'Что я умею' },
      { command: 'stop', description: 'Перестать писать' },
    ],
    name: 'Мама, я рядом',
    shortDescription:
      'Одна кнопка утром — и близкие знают, что всё хорошо. Тёплый помощник для родителей.',
    description:
      'Здравствуйте! Я помогаю родителям и их взрослым детям быть на связи: ' +
      'одна кнопка утром — и дети знают, что у вас всё хорошо.\n\n' +
      'Не слежу за местоположением, не читаю переписки, никогда не прошу коды или деньги. ' +
      'Для родителей — бесплатно насовсем.\n\n' +
      'Чтобы начать, нужна ссылка-приглашение от сына или дочери.',
  },
  {
    language: 'en',
    commands: [
      { command: 'time', description: 'Morning message time' },
      { command: 'family', description: 'Family link' },
      { command: 'pause', description: 'Pause for a few days' },
      { command: 'help', description: 'What I can do' },
      { command: 'stop', description: 'Stop writing' },
    ],
    name: "Mom, I'm Right Here",
    shortDescription:
      'One button in the morning — and the family knows all is well. A warm helper for parents.',
    description:
      "Hello! I help parents and their grown children stay in touch: " +
      'one button in the morning — and the children know all is well.\n\n' +
      'No location tracking, no reading chats, and I never ask for codes or money. ' +
      'Free for parents, forever.\n\n' +
      'To start, you need an invite link from your son or daughter.',
  },
];

export interface StorefrontReport {
  checked: number;
  changed: string[];
  failed: string[];
}

function languageParams(language: string): Record<string, string> {
  return language ? { language_code: language } : {};
}

function readValue(outcome: TgOutcome, field: string): string | null {
  if (outcome.kind !== 'ok') return null;
  const result = outcome.result as Record<string, unknown> | null;
  const value = result?.[field];
  return typeof value === 'string' ? value : null;
}

function readCommands(outcome: TgOutcome): Command[] | null {
  if (outcome.kind !== 'ok') return null;
  if (!Array.isArray(outcome.result)) return null;
  return outcome.result as Command[];
}

function sameCommands(a: Command[] | null, b: Command[]): boolean {
  if (!a || a.length !== b.length) return false;
  return a.every(
    (item, index) =>
      item.command === b[index]!.command && item.description === b[index]!.description,
  );
}

export async function syncStorefront(token: string): Promise<StorefrontReport> {
  const report: StorefrontReport = { checked: 0, changed: [], failed: [] };

  for (const front of STOREFRONTS) {
    const lang = front.language || 'default';
    const params = languageParams(front.language);

    const fields: [string, string, string, string][] = [
      ['name', 'getMyName', 'setMyName', front.name],
      ['short_description', 'getMyShortDescription', 'setMyShortDescription', front.shortDescription],
      ['description', 'getMyDescription', 'setMyDescription', front.description],
    ];

    for (const [field, getter, setter, desired] of fields) {
      report.checked += 1;
      const current = readValue(await tgCall(token, getter, params), field);
      if (current === desired) continue;
      const written = await tgCall(token, setter, { ...params, [field]: desired });
      if (written.kind === 'ok') report.changed.push(`${lang}:${field}`);
      else report.failed.push(`${lang}:${field}: ${describe(written)}`);
    }

    report.checked += 1;
    const currentCommands = readCommands(await tgCall(token, 'getMyCommands', params));
    if (sameCommands(currentCommands, front.commands)) continue;
    const written = await tgCall(token, 'setMyCommands', {
      ...params,
      commands: front.commands,
    });
    if (written.kind === 'ok') report.changed.push(`${lang}:commands`);
    else report.failed.push(`${lang}:commands: ${describe(written)}`);
  }

  return report;
}

function describe(outcome: TgOutcome): string {
  switch (outcome.kind) {
    case 'retry':
      return `retry after ${outcome.afterSec}s`;
    case 'gone':
      return outcome.description;
    case 'migrate':
      return `migrated to ${outcome.chatId}`;
    case 'failed':
      return `${outcome.status} ${outcome.description}`;
    default:
      return 'ok';
  }
}
