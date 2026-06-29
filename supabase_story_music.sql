-- Story хөгжмийн багана нэмэх
alter table public.stories
  add column if not exists music_url    text,
  add column if not exists music_title  text,
  add column if not exists music_artist text;
