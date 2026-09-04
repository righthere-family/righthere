import { tgCall, tgUpload, type TgOutcome } from './telegram';
import { T, type Lang } from './texts';

export type ChannelKind = 'telegram' | 'max' | 'sms';

export const CHANNELS: readonly ChannelKind[] = ['telegram', 'max', 'sms'];

export function asChannel(value: string | null | undefined): ChannelKind {
  return CHANNELS.includes(value as ChannelKind) ? (value as ChannelKind) : 'telegram';
}

export interface Recipient {
  kind: ChannelKind;
  address: string;
}

export interface Button {
  text: string;
  data: string;
}

export interface Outgoing {
  text: string;
  checkinKeyboard?: Lang;
  buttons?: Button[][];
}

export type Delivery =
  | { kind: 'ok' }
  | { kind: 'retry'; afterSec: number; detail: string }
  | { kind: 'gone'; detail: string }
  | { kind: 'failed'; detail: string };

export interface Channel {
  readonly kind: ChannelKind;
  send(address: string, message: Outgoing): Promise<Delivery>;
  sendPhoto(address: string, bytes: ArrayBuffer, caption: string): Promise<Delivery>;
}

export interface ChannelEnv {
  TELEGRAM_BOT_TOKEN: string;
}

export function channelFor(env: ChannelEnv, kind: ChannelKind): Channel {
  if (kind === 'telegram') return telegramChannel(env.TELEGRAM_BOT_TOKEN);
  return notWired(kind);
}

export function describeDelivery(delivery: Delivery): string {
  switch (delivery.kind) {
    case 'ok':
      return 'ok';
    case 'retry':
      return `retry in ${delivery.afterSec}s: ${delivery.detail}`;
    default:
      return `${delivery.kind}: ${delivery.detail}`;
  }
}

function telegramChannel(token: string): Channel {
  return {
    kind: 'telegram',

    async send(address, message) {
      const body = {
        chat_id: Number(address),
        text: message.text,
        reply_markup: telegramMarkup(message),
      };
      return fromTelegram(await tgCall(token, 'sendMessage', body));
    },

    async sendPhoto(address, bytes, caption) {
      const form = new FormData();
      form.set('chat_id', address);
      form.set('photo', new Blob([bytes], { type: 'image/jpeg' }), 'postcard.jpg');
      if (caption) form.set('caption', caption);
      return fromTelegram(await tgUpload(token, 'sendPhoto', form));
    },
  };
}

function telegramMarkup(message: Outgoing): unknown {
  if (message.checkinKeyboard) {
    const keyboard = T(message.checkinKeyboard).keyboard;
    return {
      keyboard: [[{ text: keyboard.ok }], [{ text: keyboard.notOk }]],
      resize_keyboard: true,
      one_time_keyboard: true,
    };
  }
  if (message.buttons) {
    return {
      inline_keyboard: message.buttons.map((row) =>
        row.map((button) => ({ text: button.text, callback_data: button.data })),
      ),
    };
  }
  return undefined;
}

function fromTelegram(outcome: TgOutcome): Delivery {
  switch (outcome.kind) {
    case 'ok':
      return { kind: 'ok' };
    case 'retry':
      return { kind: 'retry', afterSec: outcome.afterSec, detail: outcome.description };
    case 'gone':
      return { kind: 'gone', detail: outcome.description };
    case 'migrate':
      return { kind: 'failed', detail: `chat migrated to ${outcome.chatId}` };
    default:
      return { kind: 'failed', detail: `${outcome.status} ${outcome.description}` };
  }
}

function notWired(kind: ChannelKind): Channel {
  const refuse = async (): Promise<Delivery> => ({
    kind: 'failed',
    detail: `channel ${kind} has no transport yet`,
  });
  return { kind, send: refuse, sendPhoto: refuse };
}
