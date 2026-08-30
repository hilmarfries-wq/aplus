create extension if not exists pgcrypto;
create extension if not exists unaccent with schema extensions;

create table if not exists public.tests (
 id uuid primary key default gen_random_uuid(), teacher_id uuid not null references auth.users(id) on delete cascade,
 code text not null unique check (code ~ '^[A-Z0-9-]{4,24}$'), title text not null, class_name text,
 section text not null default 'Alle Bereiche', direction text not null check(direction in('de-fr','fr-de','mixed')),
 question_count integer not null check(question_count between 1 and 200), include_extra boolean not null default false,
 time_limit_minutes integer check(time_limit_minutes between 1 and 180),
 grading_scale jsonb not null default '[{"min":95,"grade":"1+"},{"min":90,"grade":"1"},{"min":85,"grade":"2+"},{"min":75,"grade":"2"},{"min":65,"grade":"3"},{"min":50,"grade":"4"},{"min":0,"grade":"5"}]'::jsonb,
 questions jsonb not null, active boolean not null default true, created_at timestamptz not null default now(), closes_at timestamptz
);
create table if not exists public.attempts (
 id uuid primary key default gen_random_uuid(), test_id uuid not null references public.tests(id) on delete cascade,
 attempt_token uuid not null unique default gen_random_uuid(), student_name text not null check(char_length(student_name) between 1 and 100),
 class_name text, started_at timestamptz not null default now(), submitted_at timestamptz, result_id uuid
);
create table if not exists public.results (
 id uuid primary key default gen_random_uuid(), test_id uuid not null references public.tests(id) on delete cascade,
 teacher_id uuid not null references auth.users(id) on delete cascade, student_name text not null, class_name text,
 correct_count integer not null, total_count integer not null, percent integer not null, grade text not null,
 duration_seconds integer not null, answers jsonb not null, mistakes jsonb not null, submitted_at timestamptz not null default now()
);
alter table public.tests enable row level security; alter table public.attempts enable row level security; alter table public.results enable row level security;
drop policy if exists "teachers own tests" on public.tests; create policy "teachers own tests" on public.tests for all to authenticated using((select auth.uid())=teacher_id) with check((select auth.uid())=teacher_id);
drop policy if exists "teachers read own results" on public.results; create policy "teachers read own results" on public.results for select to authenticated using((select auth.uid())=teacher_id);
revoke all on public.attempts from anon,authenticated; revoke insert,update,delete on public.results from anon,authenticated;
grant select,insert,update,delete on public.tests to authenticated; grant select on public.results to authenticated;

create or replace function public.grade_for(scale jsonb,pct integer) returns text language sql immutable as $$ select coalesce((select x->>'grade' from jsonb_array_elements(scale)x where pct>=(x->>'min')::integer order by (x->>'min')::integer desc limit 1),'–'); $$;
create or replace function public.norm_answer(v text) returns text language sql immutable as $$ select regexp_replace(lower(extensions.unaccent(coalesce(v,''))),'[^a-z0-9 ]','','g'); $$;

create or replace function public.start_public_test(p_code text,p_student_name text,p_class_name text default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare t public.tests; a public.attempts; pq jsonb; dl timestamptz;
begin
 select * into t from public.tests where code=upper(trim(p_code)) and active=true and(closes_at is null or closes_at>now()); if not found then raise exception 'Test nicht gefunden oder geschlossen'; end if;
 if char_length(trim(p_student_name))<1 then raise exception 'Name fehlt'; end if;
 insert into public.attempts(test_id,student_name,class_name) values(t.id,trim(p_student_name),nullif(trim(p_class_name),'')) returning * into a;
 select jsonb_agg(jsonb_build_object('id',q->>'id','prompt',q->>'prompt')) into pq from jsonb_array_elements(t.questions)q;
 dl:=case when t.time_limit_minutes is null then null else a.started_at+make_interval(mins=>t.time_limit_minutes) end;
 return jsonb_build_object('attempt_token',a.attempt_token,'title',t.title,'time_limit_minutes',t.time_limit_minutes,'deadline',dl,'questions',coalesce(pq,'[]'::jsonb),'started_at',a.started_at);
end; $$;

create or replace function public.submit_public_test(p_attempt_token uuid,p_answers jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare a public.attempts; t public.tests; q jsonb; given text; expected text; correct integer:=0; total integer:=0; pct integer; final_grade text; duration integer; mistake_list jsonb:='[]'::jsonb; rr public.results;
begin
 select * into a from public.attempts where attempt_token=p_attempt_token for update; if not found or a.submitted_at is not null then raise exception 'Ungültiger oder bereits verwendeter Versuch'; end if;
 select * into t from public.tests where id=a.test_id; duration:=greatest(0,extract(epoch from(now()-a.started_at))::integer);
 if t.time_limit_minutes is not null and duration>(t.time_limit_minutes*60+15) then raise exception 'Zeitlimit überschritten'; end if;
 for q in select * from jsonb_array_elements(t.questions) loop total:=total+1; given:=public.norm_answer(p_answers->>(q->>'id')); expected:=public.norm_answer(q->>'answer'); if given=expected then correct:=correct+1; else mistake_list:=mistake_list||jsonb_build_array(jsonb_build_object('id',q->>'id','prompt',q->>'prompt','given',coalesce(p_answers->>(q->>'id'),''),'expected',q->>'answer')); end if; end loop;
 if total=0 then raise exception 'Test enthält keine Fragen'; end if; pct:=round(correct::numeric/total*100); final_grade:=public.grade_for(t.grading_scale,pct);
 insert into public.results(test_id,teacher_id,student_name,class_name,correct_count,total_count,percent,grade,duration_seconds,answers,mistakes) values(t.id,t.teacher_id,a.student_name,a.class_name,correct,total,pct,final_grade,duration,p_answers,mistake_list) returning * into rr;
 update public.attempts set submitted_at=now(),result_id=rr.id where id=a.id;
 return jsonb_build_object('correct',correct,'total',total,'percent',pct,'grade',final_grade,'duration_seconds',duration,'mistakes',mistake_list);
end; $$;
grant execute on function public.start_public_test(text,text,text) to anon,authenticated; grant execute on function public.submit_public_test(uuid,jsonb) to anon,authenticated;