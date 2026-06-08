-- ============================================================
-- BOLÃO COPA 2026 — Esquema do banco (Supabase / PostgreSQL)
-- Cole tudo isto no Supabase: SQL Editor > New query > Run.
-- ============================================================

-- 1) CONFIGURAÇÃO GLOBAL (linha única, id = 1)
create table if not exists app_config (
  id              int primary key default 1,
  lock_at         timestamptz not null default '2026-06-11T19:00:00Z', -- início da Copa (11/06 16h BRT)
  admin_password  text not null default 'copa2026admin',
  ko32            jsonb not null default '[]'::jsonb,   -- confrontos da 1ª fase do mata-mata (admin define)
  official_groups jsonb not null default '{}'::jsonb,   -- gabarito 1º/2º de cada grupo {"A":{"first":"","second":""},...}
  official_special jsonb not null default '{}'::jsonb,   -- {"champion":"","runner_up":"","top_scorer":""}
  constraint app_config_singleton check (id = 1)
);
insert into app_config (id) values (1) on conflict (id) do nothing;

-- 2) PARTICIPANTES (sem senha; admin entra com a senha do app_config)
create table if not exists participants (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  created_at  timestamptz not null default now()
);

-- 3) PALPITES DE JOGOS (fase de grupos + mata-mata). match_id ex: "G1".."G72", "R32-1", "R16-1"...
create table if not exists predictions (
  participant_id uuid not null references participants(id) on delete cascade,
  match_id       text not null,
  home_goals     int,
  away_goals     int,
  advance        text,            -- em mata-mata empatado: quem o participante crê que avança (nome do time)
  updated_at     timestamptz not null default now(),
  primary key (participant_id, match_id)
);

-- 4) PALPITE DE CLASSIFICAÇÃO POR GRUPO (1º e 2º lugar)
create table if not exists group_predictions (
  participant_id uuid not null references participants(id) on delete cascade,
  grp            text not null,   -- "A".."L"
  pos1           text,            -- 1º lugar (nome do time)
  pos2           text,            -- 2º lugar (nome do time)
  updated_at     timestamptz not null default now(),
  primary key (participant_id, grp)
);

-- 5) PALPITES ESPECIAIS (campeão / vice / artilheiro)
create table if not exists special_predictions (
  participant_id uuid primary key references participants(id) on delete cascade,
  champion       text,
  runner_up      text,
  top_scorer     text,
  updated_at     timestamptz not null default now()
);

-- 6) RESULTADOS OFICIAIS (preenchidos pelo admin)
create table if not exists results (
  match_id    text primary key,
  home_goals  int,
  away_goals  int,
  advance     text,               -- time que avançou (mata-mata, em caso de empate/pênaltis)
  updated_at  timestamptz not null default now()
);

-- ============================================================
-- SEGURANÇA (Row Level Security)
-- Leitura liberada para todos. Escrita de PALPITES bloqueada
-- automaticamente após o início da Copa (lock_at).
-- ============================================================
alter table participants        enable row level security;
alter table predictions         enable row level security;
alter table group_predictions   enable row level security;
alter table special_predictions enable row level security;
alter table results             enable row level security;
alter table app_config          enable row level security;

-- Função auxiliar: a Copa já começou?
create or replace function copa_iniciada() returns boolean
language sql stable as $$
  select now() >= (select lock_at from app_config where id = 1)
$$;

-- Leitura pública em tudo
create policy "ler participants"  on participants        for select using (true);
create policy "ler predictions"   on predictions         for select using (true);
create policy "ler grouppred"     on group_predictions   for select using (true);
create policy "ler specials"      on special_predictions for select using (true);
create policy "ler results"       on results             for select using (true);
create policy "ler config"        on app_config          for select using (true);

-- Participantes: qualquer um pode se cadastrar enquanto a Copa não começou
create policy "criar participante" on participants for insert with check (not copa_iniciada());

-- Palpites de jogos: inserir/atualizar só ANTES do início da Copa
create policy "criar palpite jogo" on predictions for insert with check (not copa_iniciada());
create policy "editar palpite jogo" on predictions for update using (not copa_iniciada()) with check (not copa_iniciada());

-- Palpites de grupo: idem
create policy "criar palpite grupo" on group_predictions for insert with check (not copa_iniciada());
create policy "editar palpite grupo" on group_predictions for update using (not copa_iniciada()) with check (not copa_iniciada());

-- Palpites especiais: idem
create policy "criar especial" on special_predictions for insert with check (not copa_iniciada());
create policy "editar especial" on special_predictions for update using (not copa_iniciada()) with check (not copa_iniciada());

-- Resultados oficiais e config: liberados para escrita (o app protege por senha de admin).
create policy "escrever results insert" on results for insert with check (true);
create policy "escrever results update" on results for update using (true) with check (true);
create policy "escrever config" on app_config for update using (true) with check (true);

-- ============================================================
-- FIM. Após rodar, vá em Project Settings > API e copie:
--   Project URL  e  anon public key  -> cole em config.js do app.
-- ============================================================
