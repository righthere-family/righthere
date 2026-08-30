const KV_ID_PREFIX = 'kv_';

const UUID_SHAPE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const KEY_NAMESPACE = 'postcard/';

export const PHOTO_TTL_SECONDS = 7 * 24 * 60 * 60;

export function photoKey(id: string): string {
  return `${KEY_NAMESPACE}${id}`;
}

export function isKvPhotoId(value: string): boolean {
  if (!value.startsWith(KV_ID_PREFIX)) return false;
  return UUID_SHAPE.test(value.slice(KV_ID_PREFIX.length));
}

const DAILY_PHOTO_QUOTA = 30;

export async function withinPhotoQuota(kv: KVNamespace, familyId: string): Promise<boolean> {
  const today = new Date().toISOString().slice(0, 10);
  const key = `quota/${familyId}/${today}`;
  const used = Number((await kv.get(key)) ?? '0') || 0;
  if (used >= DAILY_PHOTO_QUOTA) return false;

  await kv.put(key, String(used + 1), { expirationTtl: 60 * 60 * 25 });
  return true;
}

export async function putPhoto(
  kv: KVNamespace,
  familyId: string,
  bytes: ArrayBuffer,
): Promise<string> {

  const id = `${KV_ID_PREFIX}${crypto.randomUUID()}`;

  await kv.put(photoKey(id), bytes, {
    expirationTtl: PHOTO_TTL_SECONDS,
    metadata: { family: familyId },
  });
  return id;
}

export async function takePhoto(
  kv: KVNamespace,
  familyId: string,
  id: string,
): Promise<ArrayBuffer | null> {
  const key = photoKey(id);

  const stored = await kv.getWithMetadata<{ family?: string }>(key, 'arrayBuffer');
  const bytes = stored.value;

  if (bytes !== null && stored.metadata?.family !== familyId) {
    return null;
  }
  if (bytes === null) {

    return null;
  }

  try {
    await kv.delete(key);
  } catch {

  }

  return bytes;
}
