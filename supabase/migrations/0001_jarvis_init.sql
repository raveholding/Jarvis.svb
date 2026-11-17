-- =====================================================================
--  Jarvis SVB · Esquema inicial (Supabase · PostgreSQL 15+ · pgvector)
--  Desarrollado por Vincular Business
--
--  Cómo aplicarlo: Supabase → SQL Editor → pegar todo → Run.
--  Seguridad: cada fila pertenece a auth.uid() y RLS impide ver datos ajenos.
-- =====================================================================

create extension if not exists vector;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Logs de contexto (texto YA anonimizado en el teléfono; nunca audio)
-- ---------------------------------------------------------------------
create table if not exists public.context_logs (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null default auth.uid() references auth.users(id) on delete cascade,
  occurred_at         timestamptz not null default now(),
  transcript_redacted text not null,
  context             jsonb,            -- {motion, event, ...}
  created_at          timestamptz not null default now()
);
create index if not exists context_logs_user_time_idx on public.context_logs (user_id, occurred_at desc);

-- ---------------------------------------------------------------------
-- 2. Decisiones del motor (incluye las "silence" para auditar y afinar)
-- ---------------------------------------------------------------------
create table if not exists public.decisions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  context_log_id  uuid references public.context_logs(id) on delete set null,
  created_at      timestamptz not null default now(),
  decision        text not null check (decision in ('silence','notify','speak')),
  priority        text check (priority in ('low','medium','high','critical')),
  category        text,
  confidence      real check (confidence between 0 and 1),
  headline        text,
  message         text,
  delivery        text check (delivery in ('none','feed','push','voice')),
  user_feedback   text check (user_feedback in ('useful','not_useful')),
  payload         jsonb
);
create index if not exists decisions_user_time_idx on public.decisions (user_id, created_at desc);
create index if not exists decisions_feedback_idx on public.decisions (user_id, user_feedback) where user_feedback is not null;

-- ---------------------------------------------------------------------
-- 3. Memoria a largo plazo con búsqueda semántica (768 dims = gemini-embedding-001)
-- ---------------------------------------------------------------------
create table if not exists public.memories (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind              text not null default 'fact' check (kind in ('fact','preference','pattern','task','summary','person','business')),
  content           text not null,
  importance        real not null default 0.5 check (importance between 0 and 1),
  embedding         vector(768),
  source            text default 'jarvis.svb',
  created_at        timestamptz not null default now(),
  last_accessed_at  timestamptz
);
create index if not exists memories_embedding_idx on public.memories using hnsw (embedding vector_cosine_ops);
create index if not exists memories_user_idx on public.memories (user_id, importance desc);

-- ---------------------------------------------------------------------
-- 4. Reglas de proactividad (espejo editable desde un panel web futuro)
-- ---------------------------------------------------------------------
create table if not exists public.proactivity_rules (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
  slug              text not null,
  name              text not null,
  description       text,
  keywords          text[] not null default '{}',
  condition         jsonb not null default '{}'::jsonb,  -- ej: {"hours":[9,18],"motion":["quieto"],"geofence":{...}}
  action            text not null default 'notify' check (action in ('silence','notify','speak')),
  priority          text not null default 'medium' check (priority in ('low','medium','high','critical')),
  cooldown_seconds  int not null default 240,
  enabled           boolean not null default true,
  created_at        timestamptz not null default now(),
  unique (user_id, slug)
);

-- ---------------------------------------------------------------------
-- 5. Tareas y compromisos detectados
-- ---------------------------------------------------------------------
create table if not exists public.tasks (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title               text not null,
  due_at              timestamptz,
  owner               text default 'me' check (owner in ('me','other')),
  status              text not null default 'pending' check (status in ('pending','done','dismissed')),
  source_decision_id  uuid references public.decisions(id) on delete set null,
  created_at          timestamptz not null default now()
);
create index if not exists tasks_user_status_idx on public.tasks (user_id, status, due_at);

-- ---------------------------------------------------------------------
-- 6. Resúmenes ejecutivos diarios
-- ---------------------------------------------------------------------
create table if not exists public.daily_summaries (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  summary_date  date not null,
  content       jsonb not null,
  created_at    timestamptz not null default now(),
  unique (user_id, summary_date)
);

-- ---------------------------------------------------------------------
-- 7. Integraciones: destinos y cola de webhooks (patrón outbox)
-- ---------------------------------------------------------------------
create table if not exists public.webhook_endpoints (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  url         text not null check (url like 'https://%'),
  secret      text not null default encode(gen_random_bytes(24), 'hex'),
  events      text[] not null default array['onTaskDetected','onAlertRaised','onOpportunityDetected','onSummaryGenerated','onMemoryStored'],
  enabled     boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.webhook_queue (
  id               text primary key,              -- id del evento emitido por el teléfono (idempotencia)
  user_id          uuid not null default auth.uid() references auth.users(id) on delete cascade,
  event_type       text not null,
  payload          jsonb not null,
  status           text not null default 'pending' check (status in ('pending','delivering','delivered','failed','dead')),
  attempts         int not null default 0,
  next_attempt_at  timestamptz not null default now(),
  last_error       text,
  created_at       timestamptz not null default now(),
  delivered_at     timestamptz
);
create index if not exists webhook_queue_pending_idx on public.webhook_queue (status, next_attempt_at) where status in ('pending','failed');

-- ---------------------------------------------------------------------
-- 8. Row Level Security: cada usuario solo ve y escribe lo suyo
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['context_logs','decisions','memories','proactivity_rules','tasks','daily_summaries','webhook_endpoints','webhook_queue']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "owner_all" on public.%I', t);
    execute format(
      'create policy "owner_all" on public.%I for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 9. Búsqueda semántica de memoria (llamada desde la app vía RPC)
-- ---------------------------------------------------------------------
create or replace function public.match_memories(
  query_embedding vector(768),
  match_count int default 5,
  min_similarity float default 0.55
)
returns table (id uuid, content text, kind text, importance real, similarity float)
language sql stable security invoker
set search_path = public
as $$
  select m.id, m.content, m.kind, m.importance,
         1 - (m.embedding <=> query_embedding) as similarity
  from public.memories m
  where m.user_id = auth.uid()
    and m.embedding is not null
    and 1 - (m.embedding <=> query_embedding) >= min_similarity
  order by m.embedding <=> query_embedding
  limit least(match_count, 20);
$$;

-- ---------------------------------------------------------------------
-- 10. Métrica de calidad: % de alertas útiles por categoría (para afinar el motor)
-- ---------------------------------------------------------------------
create or replace view public.decision_quality
with (security_invoker = true) as
select user_id,
       category,
       count(*) filter (where decision <> 'silence')                           as interruptions,
       count(*) filter (where user_feedback = 'useful')                        as useful,
       count(*) filter (where user_feedback = 'not_useful')                    as not_useful,
       round(100.0 * count(*) filter (where user_feedback = 'useful')
             / nullif(count(*) filter (where user_feedback is not null), 0), 1) as useful_pct
from public.decisions
group by user_id, category;

-- ---------------------------------------------------------------------
-- 11. (Opcional) Entrega server-side de webhooks con pg_net
--     Habilitá la extensión pg_net y programá con pg_cron:
--       select cron.schedule('jarvis-webhooks', '* * * * *', 'select public.dispatch_webhooks()');
-- ---------------------------------------------------------------------
-- create extension if not exists pg_net;
-- create or replace function public.dispatch_webhooks() returns void
-- language plpgsql security definer set search_path = public as $$
-- declare q record; e record;
-- begin
--   for q in select * from webhook_queue where status in ('pending','failed') and next_attempt_at <= now() limit 50
--   loop
--     for e in select * from webhook_endpoints where user_id = q.user_id and enabled and q.event_type = any(events)
--     loop
--       perform net.http_post(
--         url := e.url,
--         body := q.payload,
--         headers := jsonb_build_object('Content-Type','application/json','X-Jarvis-Event', q.event_type,
--                    'X-Jarvis-Signature', 'sha256=' || encode(hmac(q.payload::text, e.secret, 'sha256'), 'hex')));
--     end loop;
--     update webhook_queue set status = 'delivered', delivered_at = now(), attempts = attempts + 1 where id = q.id;
--   end loop;
-- end $$;
