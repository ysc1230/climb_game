-- 작업 6B 문제 공유(docs/superpowers/specs/2026-11-19-6-editor-design.md §4·§5).
-- 익명 로그인(auth.uid()) 기준. 앱에는 공개 키(publishable)만 넣는다. 쓰기는 모두 아래 함수(security definer)로만 한다.

create extension if not exists pgcrypto;

create table public.routes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$'),
  author uuid not null default auth.uid(),
  author_name text not null check (char_length(author_name) between 1 and 12),
  local_id text not null,                       -- 만든 기기의 route_id(U_…). 같은 사람이 다시 올리면 같은 행을 고친다
  name text not null check (char_length(name) between 1 and 20),
  grade text not null check (grade ~ '^V[0-7]$'),
  data jsonb not null check (pg_column_size(data) <= 32768),
  schema int not null default 1,
  version int not null default 1,
  visibility text not null check (visibility in ('public', 'link')),
  stars int not null default 0,
  clears int not null default 0,
  reports int not null default 0,
  hidden boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (author, local_id)
);
create index routes_public_stars on public.routes (stars desc, created_at desc) where visibility = 'public' and not hidden;
create index routes_public_new on public.routes (created_at desc) where visibility = 'public' and not hidden;

create table public.clears (
  route_id uuid references public.routes on delete cascade,
  user_id uuid not null default auth.uid(),
  version int not null,
  created_at timestamptz not null default now(),
  primary key (route_id, user_id)
);

create table public.stars (
  route_id uuid references public.routes on delete cascade,
  user_id uuid not null default auth.uid(),
  primary key (route_id, user_id)
);

create table public.reports (
  route_id uuid references public.routes on delete cascade,
  user_id uuid not null default auth.uid(),
  reason text not null default '' check (char_length(reason) <= 200),
  created_at timestamptz not null default now(),
  primary key (route_id, user_id)
);

alter table public.routes enable row level security;
alter table public.clears enable row level security;
alter table public.stars enable row level security;
alter table public.reports enable row level security;

-- 목록: 공개이면서 숨김이 아닌 것만. 코드로 여는 것은 get_route_by_code 함수로(링크 공개 포함).
create policy routes_read_public on public.routes for select to anon, authenticated using (visibility = 'public' and not hidden);
create policy routes_read_own on public.routes for select to authenticated using (author = auth.uid());
create policy stars_read_own on public.stars for select to authenticated using (user_id = auth.uid());
create policy clears_read_own on public.clears for select to authenticated using (user_id = auth.uid());
-- 직접 쓰기 정책은 두지 않는다(모든 쓰기는 아래 함수).

-- 공유 코드: 헷갈리는 0/O/1/I를 뺀 32글자 6자리.
create or replace function public._new_code() returns text language plpgsql as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  c text;
begin
  loop
    c := '';
    for i in 1..6 loop
      c := c || substr(alphabet, 1 + floor(random() * 32)::int, 1);
    end loop;
    exit when not exists (select 1 from public.routes where code = c);
  end loop;
  return c;
end $$;

-- 올리기: 새로 올리거나(같은 local_id면) 고친다. 한 사람 하루 20번. 고친 판이면 별·완등 수는 두고 version을 바꾼다.
create or replace function public.publish_route(p_local_id text, p_name text, p_author_name text, p_grade text,
    p_data jsonb, p_version int, p_visibility text) returns table (code text, id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  uid uuid := auth.uid();
  r public.routes;
begin
  if uid is null then raise exception 'login required'; end if;
  if (select count(*) from public.routes where author = uid and updated_at > now() - interval '1 day') >= 20 then
    raise exception 'daily limit';
  end if;
  select * into r from public.routes where author = uid and local_id = p_local_id;
  if found then
    update public.routes set name = p_name, author_name = p_author_name, grade = p_grade, data = p_data,
      schema = coalesce((p_data->>'schema')::int, 1), version = p_version, visibility = p_visibility, updated_at = now()
      where routes.id = r.id;
    return query select r.code, r.id;
  else
    return query insert into public.routes (code, author, author_name, local_id, name, grade, data, schema, version, visibility)
      values (public._new_code(), uid, p_author_name, p_local_id, p_name, p_grade, p_data,
        coalesce((p_data->>'schema')::int, 1), p_version, p_visibility)
      returning routes.code, routes.id;
  end if;
end $$;

-- 코드로 하나 읽기(링크 공개도). 숨김은 만든 사람만.
create or replace function public.get_route_by_code(p_code text) returns setof public.routes
language sql security definer set search_path = public stable as $$
  select * from public.routes where code = upper(p_code) and (not hidden or author = auth.uid()) limit 1;
$$;

-- 완등 기록(별 자격·완등 수).
create or replace function public.record_clear(p_route uuid, p_version int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  insert into public.clears (route_id, user_id, version) values (p_route, auth.uid(), p_version)
    on conflict (route_id, user_id) do update set version = excluded.version;
  update public.routes set clears = (select count(*) from public.clears where route_id = p_route) where id = p_route;
end $$;

-- 별 주기·거두기: 완등한 사람만.
create or replace function public.set_star(p_route uuid, p_on boolean) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  if p_on then
    if not exists (select 1 from public.clears where route_id = p_route and user_id = auth.uid()) then
      raise exception 'clear required';
    end if;
    insert into public.stars (route_id, user_id) values (p_route, auth.uid()) on conflict do nothing;
  else
    delete from public.stars where route_id = p_route and user_id = auth.uid();
  end if;
  select count(*) into n from public.stars where route_id = p_route;
  update public.routes set stars = n where id = p_route;
  return n;
end $$;

-- 신고: 한 사람 한 번, 3건이면 숨김.
create or replace function public.report_route(p_route uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  insert into public.reports (route_id, user_id, reason) values (p_route, auth.uid(), left(coalesce(p_reason, ''), 200))
    on conflict do nothing;
  select count(*) into n from public.reports where route_id = p_route;
  update public.routes set reports = n, hidden = (n >= 3) where id = p_route;
end $$;

-- 함수는 기본으로 모두(public)에게 실행 권한이 있어 먼저 거둔다.
revoke all on function public._new_code() from public, anon, authenticated;
revoke all on function public.publish_route(text, text, text, text, jsonb, int, text) from public, anon;
revoke all on function public.get_route_by_code(text) from public;
revoke all on function public.record_clear(uuid, int) from public, anon;
revoke all on function public.set_star(uuid, boolean) from public, anon;
revoke all on function public.report_route(uuid, text) from public, anon;
grant execute on function public.publish_route(text, text, text, text, jsonb, int, text) to authenticated;
grant execute on function public.get_route_by_code(text) to anon, authenticated;
grant execute on function public.record_clear(uuid, int) to authenticated;
grant execute on function public.set_star(uuid, boolean) to authenticated;
grant execute on function public.report_route(uuid, text) to authenticated;
