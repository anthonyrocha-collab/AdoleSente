-- =====================================================================
-- AdoleSente · schema do Supabase (Postgres) com RLS estrito
-- Como usar: Supabase > SQL Editor > cole tudo > Run. Depois rode seed.sql.
-- Pode ser executado de novo sem erro (usa IF NOT EXISTS / DROP POLICY IF EXISTS).
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------- utilitário: updated_at automático ----------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

-- ---------- profiles: 1 linha por usuário (auth.users) ----------
create table if not exists public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  name           text        not null default '' check (char_length(name) <= 30),
  pronouns       text        not null default '' check (char_length(pronouns) <= 30),
  avatar         jsonb       not null default '{"type":"initial","icon":"star","bg":"","charId":"","zoom":100,"y":0}',
  colors         jsonb,                      -- paleta escolhida em Perfil (ou null = padrão)
  diary_style    jsonb       not null default '{}',   -- cor/pauta do papel do diário
  text_size      int         not null default 100 check (text_size in (100,125,150,175)),
  layout         text        not null default 'auto' check (layout in ('auto','mobile','desktop')),
  tutorial_asked boolean     not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
drop trigger if exists trg_profiles_updated on public.profiles;
create trigger trg_profiles_updated before update on public.profiles
  for each row execute function public.set_updated_at();

-- cria o profile automaticamente quando alguém se cadastra
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- diary_keys: chaves do diário, já "embrulhadas" no navegador ----------
-- O app usa criptografia de ponta a ponta: a chave do diário (DEK) é gerada no
-- navegador e só chega aqui criptografada pela senha (wk) e pela chave de
-- recuperação (rwk). O servidor NUNCA vê a senha, a chave nem o texto.
create table if not exists public.diary_keys (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  version    int   not null default 2,
  salt       text  not null,      -- sal do PBKDF2 da senha (base64)
  wk         jsonb not null,      -- {iv, ct}: DEK criptografada pela senha
  rsalt      text,                -- sal do PBKDF2 da chave de recuperação
  rwk        jsonb,               -- {iv, ct}: DEK criptografada pela chave de recuperação
  updated_at timestamptz not null default now()
);
drop trigger if exists trg_diary_keys_updated on public.diary_keys;
create trigger trg_diary_keys_updated before update on public.diary_keys
  for each row execute function public.set_updated_at();

-- ---------- notes: páginas do diário, SEMPRE criptografadas (AES-GCM) ----------
create table if not exists public.notes (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  iv         text not null,                                   -- base64
  ciphertext text not null check (char_length(ciphertext) <= 400000), -- {title,text,date} cifrado
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists notes_user_idx on public.notes (user_id, updated_at desc);
drop trigger if exists trg_notes_updated on public.notes;
create trigger trg_notes_updated before update on public.notes
  for each row execute function public.set_updated_at();

-- ---------- answers: respostas às perguntas da sessão ----------
create table if not exists public.answers (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  question    text not null check (char_length(question) <= 300),
  answer      text not null check (char_length(answer) <= 2000),
  answered_on date not null default current_date,
  created_at  timestamptz not null default now()
);
create index if not exists answers_user_idx on public.answers (user_id, created_at desc);

-- ---------- conteúdo público (somente leitura para o app) ----------
create table if not exists public.characters (
  id        text primary key,                 -- c1, c2...
  position  int  not null default 0,
  name      text not null,
  role      text not null default '',
  bio       text not null default '',
  traits    text[] not null default '{}',
  likes     text not null default '',
  color     text not null default '#892CB0',
  img_url   text not null default '',         -- PNG com fundo transparente (Supabase Storage)
  quote     text not null default '',
  fields    jsonb not null default '[]',      -- [{"k":"Idade","v":"12 anos"}]
  active    boolean not null default true
);

create table if not exists public.suggestions (
  id       int generated always as identity primary key,
  category text not null,
  title    text not null,
  body     text not null,
  active   boolean not null default true
);

create table if not exists public.questions (
  id     int generated always as identity primary key,
  body   text not null,
  active boolean not null default true
);

create table if not exists public.diary_ideas (
  id     int generated always as identity primary key,
  body   text not null,
  active boolean not null default true
);

-- =====================================================================
-- RLS: tudo trancado por padrão; só o dono acessa o que é dele
-- =====================================================================
alter table public.profiles     enable row level security;
alter table public.diary_keys   enable row level security;
alter table public.notes        enable row level security;
alter table public.answers      enable row level security;
alter table public.characters   enable row level security;
alter table public.suggestions  enable row level security;
alter table public.questions    enable row level security;
alter table public.diary_ideas  enable row level security;

-- profiles (a linha é criada pelo trigger; o usuário só lê e edita a própria)
drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_select_own" on public.profiles for select to authenticated
  using ((select auth.uid()) = id);
create policy "profiles_update_own" on public.profiles for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

-- diary_keys
drop policy if exists "diary_keys_all_own" on public.diary_keys;
create policy "diary_keys_all_own" on public.diary_keys for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- notes: ninguém lê nota de outro usuário
drop policy if exists "notes_select_own" on public.notes;
drop policy if exists "notes_insert_own" on public.notes;
drop policy if exists "notes_update_own" on public.notes;
drop policy if exists "notes_delete_own" on public.notes;
create policy "notes_select_own" on public.notes for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "notes_insert_own" on public.notes for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "notes_update_own" on public.notes for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "notes_delete_own" on public.notes for delete to authenticated
  using ((select auth.uid()) = user_id);

-- answers
drop policy if exists "answers_select_own" on public.answers;
drop policy if exists "answers_insert_own" on public.answers;
drop policy if exists "answers_delete_own" on public.answers;
create policy "answers_select_own" on public.answers for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "answers_insert_own" on public.answers for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "answers_delete_own" on public.answers for delete to authenticated
  using ((select auth.uid()) = user_id);

-- conteúdo público: leitura liberada, escrita só pelo painel/service_role
drop policy if exists "characters_read"  on public.characters;
drop policy if exists "suggestions_read" on public.suggestions;
drop policy if exists "questions_read"   on public.questions;
drop policy if exists "diary_ideas_read" on public.diary_ideas;
create policy "characters_read"  on public.characters  for select to anon, authenticated using (active);
create policy "suggestions_read" on public.suggestions for select to anon, authenticated using (active);
create policy "questions_read"   on public.questions   for select to anon, authenticated using (active);
create policy "diary_ideas_read" on public.diary_ideas for select to anon, authenticated using (active);

-- Remove permissões amplas herdadas e concede só o necessário
revoke all on public.profiles, public.diary_keys, public.notes, public.answers from anon;
revoke all on public.characters, public.suggestions, public.questions, public.diary_ideas from anon, authenticated;
grant select on public.characters, public.suggestions, public.questions, public.diary_ideas to anon, authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.diary_keys, public.notes to authenticated;
grant select, insert, delete on public.answers to authenticated;
