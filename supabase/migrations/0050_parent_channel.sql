alter table parents
  add column if not exists channel text not null default 'telegram'
    check (channel in ('telegram', 'max', 'sms'));

alter table parents
  add column if not exists channel_address text;

alter table parents
  add constraint parents_channel_address_required
    check (channel = 'telegram' or channel_address is not null);

create index if not exists parents_channel on parents (channel)
  where channel <> 'telegram';
