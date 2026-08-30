interface OggPacket {
  bytes: Uint8Array;
}

function parseOggPackets(data: Uint8Array): OggPacket[] {
  const packets: OggPacket[] = [];
  let pending: Uint8Array[] = [];
  let offset = 0;

  while (offset + 27 <= data.length) {
    if (
      data[offset] !== 0x4f || data[offset + 1] !== 0x67 ||
      data[offset + 2] !== 0x67 || data[offset + 3] !== 0x53
    ) {
      throw new Error('not an Ogg stream');
    }
    const segmentCount = data[offset + 26]!;
    const lacingStart = offset + 27;
    let bodyOffset = lacingStart + segmentCount;

    for (let i = 0; i < segmentCount; i++) {
      const lace = data[lacingStart + i]!;
      pending.push(data.subarray(bodyOffset, bodyOffset + lace));
      bodyOffset += lace;

      if (lace < 255) {
        const total = pending.reduce((n, part) => n + part.length, 0);
        const merged = new Uint8Array(total);
        let at = 0;
        for (const part of pending) {
          merged.set(part, at);
          at += part.length;
        }
        packets.push({ bytes: merged });
        pending = [];
      }
    }
    offset = bodyOffset;
  }
  return packets;
}

const CONFIG_SAMPLES = (() => {
  const table = new Array<number>(32);
  for (let config = 0; config < 32; config++) {
    if (config < 12) table[config] = [480, 960, 1920, 2880][config % 4]!;
    else if (config < 16) table[config] = [480, 960][config % 2]!;
    else table[config] = [120, 240, 480, 960][config % 4]!;
  }
  return table;
})();

function packetSamples(packet: Uint8Array): number {
  if (packet.length === 0) return 0;
  const toc = packet[0]!;
  const perFrame = CONFIG_SAMPLES[toc >> 3]!;
  const code = toc & 0x03;
  const frames =
    code === 0 ? 1 :
    code === 3 ? (packet.length > 1 ? packet[1]! & 0x3f : 0) :
    2;
  return perFrame * frames;
}

class ByteWriter {
  private chunks: Uint8Array[] = [];

  bytes(data: Uint8Array) { this.chunks.push(data); }
  ascii(text: string) { this.bytes(new TextEncoder().encode(text)); }
  u16(value: number) {
    const b = new Uint8Array(2);
    new DataView(b.buffer).setUint16(0, value);
    this.bytes(b);
  }
  u32(value: number) {
    const b = new Uint8Array(4);
    new DataView(b.buffer).setUint32(0, value);
    this.bytes(b);
  }
  i64(value: number) {
    const b = new Uint8Array(8);
    new DataView(b.buffer).setBigInt64(0, BigInt(value));
    this.bytes(b);
  }
  f64(value: number) {
    const b = new Uint8Array(8);
    new DataView(b.buffer).setFloat64(0, value);
    this.bytes(b);
  }

  vlq(value: number) {
    const groups: number[] = [];
    let rest = value;
    do {
      groups.unshift(rest & 0x7f);
      rest = Math.floor(rest / 128);
    } while (rest > 0);
    const b = new Uint8Array(groups.length);
    groups.forEach((g, i) => { b[i] = i < groups.length - 1 ? g | 0x80 : g; });
    this.bytes(b);
  }
  build(): Uint8Array {
    const total = this.chunks.reduce((n, c) => n + c.length, 0);
    const out = new Uint8Array(total);
    let at = 0;
    for (const c of this.chunks) {
      out.set(c, at);
      at += c.length;
    }
    return out;
  }
}

export function oggOpusToCaf(ogg: Uint8Array): Uint8Array {
  const packets = parseOggPackets(ogg);
  if (packets.length < 3) throw new Error('too few Ogg packets for Opus');
  const head = packets[0]!.bytes;
  const isOpusHead =
    head.length >= 19 && new TextDecoder().decode(head.subarray(0, 8)) === 'OpusHead';
  if (!isOpusHead) throw new Error('first Ogg packet is not OpusHead');
  const channels = head[9]!;
  const preSkip = head[10]! | (head[11]! << 8);

  const audio = packets.slice(2).map((p) => p.bytes).filter((p) => p.length > 0);

  const totalBytes = audio.reduce((n, p) => n + p.length, 0);
  const totalFrames = audio.reduce((n, p) => n + packetSamples(p), 0);

  const w = new ByteWriter();
  w.ascii('caff'); w.u16(1); w.u16(0);

  w.ascii('desc'); w.i64(32);
  w.f64(48000); w.ascii('opus'); w.u32(0); w.u32(0); w.u32(0); w.u32(channels); w.u32(0);

  const pakt = new ByteWriter();
  pakt.i64(audio.length);
  pakt.i64(totalFrames - preSkip);
  pakt.u32(preSkip);
  pakt.u32(0);
  for (const p of audio) {
    pakt.vlq(p.length);
    pakt.vlq(packetSamples(p));
  }
  const paktBytes = pakt.build();
  w.ascii('pakt'); w.i64(paktBytes.length); w.bytes(paktBytes);

  w.ascii('data'); w.i64(4 + totalBytes); w.u32(0);
  for (const p of audio) w.bytes(p);

  return w.build();
}
