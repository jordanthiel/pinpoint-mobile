-- Relational golf storage. Old snapshots are retained, read-only, for rollback/audit.
alter table public.rounds rename to rounds_legacy_snapshot;
revoke all on public.rounds_legacy_snapshot from anon, authenticated;
create table public.golf_sync_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 cursor bigint not null default 0,
 legacy_revision bigint,
 migrated_at timestamptz,
 migration_counts jsonb
);
-- Convert both historic Swift numeric dates and the ISO dates used by Supabase.
create function public.golf_date(value jsonb) returns timestamptz language sql immutable as $$
 select case when value is null or value = 'null'::jsonb then null
 when jsonb_typeof(value) = 'number' then to_timestamp((value #>> '{}')::double precision + 978307200)
 else (value #>> '{}')::timestamptz end
$$;
revoke all on function public.golf_date(jsonb) from public;
create table public.rounds (
 user_id uuid not null references auth.users(id) on delete cascade, id uuid not null,
 position integer not null default 0 check(position >= 0),
 revision bigint not null check(revision > 0), deleted_at timestamptz,
 updated_at timestamptz not null default now(), extras jsonb not null default '{}',
 course_id uuid not null,
 course_name text not null,
 tee_name text not null,
 round_type text not null,
 scoring_mode text not null,
 current_hole_number integer not null,
 status text not null,
 started_at timestamptz not null,
 finished_at timestamptz,
 wind_mph double precision,
 wind_from_degrees double precision,
 recap text,
 course_rating text,
 course_holes jsonb not null,
 saved_hole_numbers jsonb,
 companion_command_ids jsonb,
 swing_candidates jsonb,
 primary key (user_id, id), check(status in ('active','finished','unfinished')), check(current_hole_number between 1 and 18)
);
create index rounds_sync_idx on public.rounds(user_id, revision);
create table public.hole_scores (
 user_id uuid not null references auth.users(id) on delete cascade, id uuid not null, round_id uuid not null,
 position integer not null default 0 check(position >= 0),
 revision bigint not null check(revision > 0), deleted_at timestamptz,
 updated_at timestamptz not null default now(), extras jsonb not null default '{}',
 hole_number integer not null,
 score integer,
 putts integer,
 penalty_strokes integer not null,
 penalties_by_shot jsonb,
 fairway_hit boolean,
 is_complete boolean not null,
 pin_position jsonb not null,
 tee_latitude double precision,
 tee_longitude double precision,
 first_putt_feet double precision,
 first_putt_position jsonb,
 dismissed_shot_suggestions integer,
 dictation_transcript text,
 analysis_note text,
 primary key (user_id, round_id, id), foreign key(user_id, round_id) references public.rounds(user_id, id) on delete cascade, check(hole_number between 1 and 18), check(score is null or score > 0), check(putts is null or putts >= 0), check(penalty_strokes >= 0)
);
create index hole_scores_sync_idx on public.hole_scores(user_id, revision);
create table public.shots (
 user_id uuid not null references auth.users(id) on delete cascade, id uuid not null, round_id uuid not null, hole_id uuid not null,
 position integer not null default 0 check(position >= 0),
 revision bigint not null check(revision > 0), deleted_at timestamptz,
 updated_at timestamptz not null default now(), extras jsonb not null default '{}',
 shot_number integer not null,
 club text,
 lie text not null,
 distance_to_pin_yards double precision,
 carry_yards double precision,
 traveled_yards double precision,
 mapped_distance_yards double precision,
 remaining_feet double precision,
 club_was_suggested boolean,
 start_latitude double precision,
 start_longitude double precision,
 end_latitude double precision,
 end_longitude double precision,
 contact text,
 shape text,
 quality text,
 include_in_true_distance boolean not null,
 source text not null,
 taken_at timestamptz not null,
 note text,
 observations jsonb,
 primary key (user_id, round_id, id), foreign key(user_id, round_id, hole_id) references public.hole_scores(user_id, round_id, id) on delete cascade, check(shot_number > 0), check(start_latitude between -90 and 90), check(end_latitude between -90 and 90), check(start_longitude between -180 and 180), check(end_longitude between -180 and 180), check((start_latitude is null) = (start_longitude is null)), check((end_latitude is null) = (end_longitude is null))
);
create index shots_sync_idx on public.shots(user_id, revision);
create table public.clubs (
 user_id uuid not null references auth.users(id) on delete cascade, id uuid not null,
 position integer not null default 0 check(position >= 0),
 revision bigint not null check(revision > 0), deleted_at timestamptz,
 updated_at timestamptz not null default now(), extras jsonb not null default '{}',
 club text not null,
 nickname text,
 carry_yards double precision not null,
 primary key (user_id, id), check(carry_yards >= 0)
);
create index clubs_sync_idx on public.clubs(user_id, revision);
create table public.practice_sessions (
 user_id uuid not null references auth.users(id) on delete cascade, id uuid not null,
 position integer not null default 0 check(position >= 0),
 revision bigint not null check(revision > 0), deleted_at timestamptz,
 updated_at timestamptz not null default now(), extras jsonb not null default '{}',
 practiced_at timestamptz not null,
 focus text not null,
 made integer not null,
 attempts integer not null,
 note text,
 primary key (user_id, id), check(attempts > 0), check(made between 0 and attempts)
);
create index practice_sessions_sync_idx on public.practice_sessions(user_id, revision);
alter table public.golf_sync_accounts enable row level security;
create policy golf_sync_accounts_owner_read on public.golf_sync_accounts for select to authenticated using (auth.uid() = user_id);
revoke all on public.golf_sync_accounts from anon, authenticated;
grant select on public.golf_sync_accounts to authenticated;
alter table public.rounds enable row level security;
create policy rounds_owner_read on public.rounds for select to authenticated using (auth.uid() = user_id);
revoke all on public.rounds from anon, authenticated;
grant select on public.rounds to authenticated;
alter table public.hole_scores enable row level security;
create policy hole_scores_owner_read on public.hole_scores for select to authenticated using (auth.uid() = user_id);
revoke all on public.hole_scores from anon, authenticated;
grant select on public.hole_scores to authenticated;
alter table public.shots enable row level security;
create policy shots_owner_read on public.shots for select to authenticated using (auth.uid() = user_id);
revoke all on public.shots from anon, authenticated;
grant select on public.shots to authenticated;
alter table public.clubs enable row level security;
create policy clubs_owner_read on public.clubs for select to authenticated using (auth.uid() = user_id);
revoke all on public.clubs from anon, authenticated;
grant select on public.clubs to authenticated;
alter table public.practice_sessions enable row level security;
create policy practice_sessions_owner_read on public.practice_sessions for select to authenticated using (auth.uid() = user_id);
revoke all on public.practice_sessions from anon, authenticated;
grant select on public.practice_sessions to authenticated;
create index shots_club_analysis_idx on public.shots(user_id, club, taken_at) where deleted_at is null;
create index hole_scores_round_idx on public.hole_scores(user_id, round_id, hole_number) where deleted_at is null;
-- Internal serializer reconstructs a single app record from typed SQL fields.
create function public.golf_record_data(kind text, row_data jsonb) returns jsonb
language plpgsql immutable set search_path = public, pg_temp as $$
begin
 case kind
 when 'round' then return coalesce(row_data->'extras','{}') || jsonb_strip_nulls(jsonb_build_object('id', upper(row_data->>'id'), 'courseID', upper(row_data->>'course_id'), 'courseName', row_data->'course_name', 'teeName', row_data->'tee_name', 'roundType', row_data->'round_type', 'scoringMode', row_data->'scoring_mode', 'currentHoleNumber', row_data->'current_hole_number', 'status', row_data->'status', 'startedAt', extract(epoch from (row_data->>'started_at')::timestamptz) - 978307200, 'finishedAt', extract(epoch from (row_data->>'finished_at')::timestamptz) - 978307200, 'windMph', row_data->'wind_mph', 'windFromDegrees', row_data->'wind_from_degrees', 'recap', row_data->'recap', 'courseRating', row_data->'course_rating', 'holesSnapshot', row_data->'course_holes', 'savedHoleNumbers', row_data->'saved_hole_numbers', 'companionCommandIDs', row_data->'companion_command_ids', 'swingCandidates', row_data->'swing_candidates'));
 when 'hole' then return coalesce(row_data->'extras','{}') || jsonb_strip_nulls(jsonb_build_object('id', upper(row_data->>'id'), 'holeNumber', row_data->'hole_number', 'recordedScore', row_data->'score', 'recordedPutts', row_data->'putts', 'penaltyStrokes', row_data->'penalty_strokes', 'penaltiesByShot', row_data->'penalties_by_shot', 'recordedFairwayHit', row_data->'fairway_hit', 'isComplete', row_data->'is_complete', 'pinPosition', row_data->'pin_position', 'teeLatitude', row_data->'tee_latitude', 'teeLongitude', row_data->'tee_longitude', 'firstPuttFeet', row_data->'first_putt_feet', 'firstPuttPosition', row_data->'first_putt_position', 'dismissedShotSuggestions', row_data->'dismissed_shot_suggestions', 'dictateTranscript', row_data->'dictation_transcript', 'analysisNote', row_data->'analysis_note'));
 when 'shot' then return coalesce(row_data->'extras','{}') || jsonb_strip_nulls(jsonb_build_object('id', upper(row_data->>'id'), 'number', row_data->'shot_number', 'club', row_data->'club', 'lie', row_data->'lie', 'distanceToPinBeforeYards', row_data->'distance_to_pin_yards', 'carryYards', row_data->'carry_yards', 'traveledYards', row_data->'traveled_yards', 'mappedDistanceYards', row_data->'mapped_distance_yards', 'remainingFeet', row_data->'remaining_feet', 'clubWasSuggested', row_data->'club_was_suggested', 'start', case when row_data->'start_latitude' <> 'null'::jsonb then jsonb_build_object('latitude',row_data->'start_latitude','longitude',row_data->'start_longitude') else null end, 'end', case when row_data->'end_latitude' <> 'null'::jsonb then jsonb_build_object('latitude',row_data->'end_latitude','longitude',row_data->'end_longitude') else null end, 'contact', row_data->'contact', 'shape', row_data->'shape', 'quality', row_data->'quality', 'includeInTrueDistance', row_data->'include_in_true_distance', 'source', row_data->'source', 'timestamp', extract(epoch from (row_data->>'taken_at')::timestamptz) - 978307200, 'note', row_data->'note', 'observations', row_data->'observations'));
 when 'club' then return coalesce(row_data->'extras','{}') || jsonb_strip_nulls(jsonb_build_object('id', upper(row_data->>'id'), 'club', row_data->'club', 'nickname', row_data->'nickname', 'carryYards', row_data->'carry_yards'));
 when 'practice' then return coalesce(row_data->'extras','{}') || jsonb_strip_nulls(jsonb_build_object('id', upper(row_data->>'id'), 'date', extract(epoch from (row_data->>'practiced_at')::timestamptz) - 978307200, 'focus', row_data->'focus', 'made', row_data->'made', 'attempts', row_data->'attempts', 'note', row_data->'note'));
 else raise exception 'Unknown golf record type';
 end case;
end; $$;
revoke all on function public.golf_record_data(text,jsonb) from public;
-- All mutations go through the revision-checked batch RPC below.
create function public.golf_write_record(owner_id uuid, item jsonb, version bigint) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare d jsonb := item->'data'; rid uuid := (item->>'id')::uuid; parent_id uuid := (item->>'round_id')::uuid;
begin
 case item->>'kind'
 when 'round' then
 if coalesce((item->>'deleted')::boolean,false) then
 update public.rounds set deleted_at=now(),revision=version,updated_at=now() where user_id = owner_id and id = rid;
update public.hole_scores set deleted_at=now(),revision=version,updated_at=now() where user_id=owner_id and round_id=rid and deleted_at is null;
update public.shots set deleted_at=now(),revision=version,updated_at=now() where user_id=owner_id and round_id=rid and deleted_at is null;
 else
 insert into public.rounds (user_id,id,position,revision,deleted_at,updated_at,extras,course_id,course_name,tee_name,round_type,scoring_mode,current_hole_number,status,started_at,finished_at,wind_mph,wind_from_degrees,recap,course_rating,course_holes,saved_hole_numbers,companion_command_ids,swing_candidates) values (owner_id,rid,coalesce((item->>'position')::integer,0),version,null,now(),d - array['id','holeScores','shots','scoringMode','startedAt','windMph','recap','courseRating','roundType','savedHoleNumbers','teeName','courseID','windFromDegrees','companionCommandIDs','finishedAt','swingCandidates','holesSnapshot','status','currentHoleNumber','courseName'],(d #>> '{courseID}')::uuid,(d #>> '{courseName}')::text,(d #>> '{teeName}')::text,(d #>> '{roundType}')::text,(d #>> '{scoringMode}')::text,(d #>> '{currentHoleNumber}')::integer,(d #>> '{status}')::text,public.golf_date(d #> '{startedAt}'),public.golf_date(d #> '{finishedAt}'),(d #>> '{windMph}')::double precision,(d #>> '{windFromDegrees}')::double precision,(d #>> '{recap}')::text,(d #>> '{courseRating}')::text,nullif(d #> '{holesSnapshot}', 'null'::jsonb),nullif(d #> '{savedHoleNumbers}', 'null'::jsonb),nullif(d #> '{companionCommandIDs}', 'null'::jsonb),nullif(d #> '{swingCandidates}', 'null'::jsonb)) on conflict (user_id,id) do update set position=excluded.position,revision=excluded.revision,deleted_at=excluded.deleted_at,updated_at=excluded.updated_at,extras=excluded.extras,course_id=excluded.course_id,course_name=excluded.course_name,tee_name=excluded.tee_name,round_type=excluded.round_type,scoring_mode=excluded.scoring_mode,current_hole_number=excluded.current_hole_number,status=excluded.status,started_at=excluded.started_at,finished_at=excluded.finished_at,wind_mph=excluded.wind_mph,wind_from_degrees=excluded.wind_from_degrees,recap=excluded.recap,course_rating=excluded.course_rating,course_holes=excluded.course_holes,saved_hole_numbers=excluded.saved_hole_numbers,companion_command_ids=excluded.companion_command_ids,swing_candidates=excluded.swing_candidates;
 end if;
 when 'hole' then
 if coalesce((item->>'deleted')::boolean,false) then
 update public.hole_scores set deleted_at=now(),revision=version,updated_at=now() where user_id = owner_id and id = rid and round_id = parent_id;
update public.shots set deleted_at=now(),revision=version,updated_at=now() where user_id=owner_id and round_id=parent_id and hole_id=rid and deleted_at is null;
 else
 insert into public.hole_scores (user_id,id,position,revision,deleted_at,updated_at,extras,round_id,hole_number,score,putts,penalty_strokes,penalties_by_shot,fairway_hit,is_complete,pin_position,tee_latitude,tee_longitude,first_putt_feet,first_putt_position,dismissed_shot_suggestions,dictation_transcript,analysis_note) values (owner_id,rid,coalesce((item->>'position')::integer,0),version,null,now(),d - array['id','holeScores','shots','analysisNote','dismissedShotSuggestions','penaltyStrokes','recordedScore','teeLongitude','penaltiesByShot','holeNumber','recordedFairwayHit','pinPosition','teeLatitude','firstPuttFeet','firstPuttPosition','recordedPutts','isComplete','dictateTranscript'],parent_id,(d #>> '{holeNumber}')::integer,(d #>> '{recordedScore}')::integer,(d #>> '{recordedPutts}')::integer,(d #>> '{penaltyStrokes}')::integer,nullif(d #> '{penaltiesByShot}', 'null'::jsonb),(d #>> '{recordedFairwayHit}')::boolean,(d #>> '{isComplete}')::boolean,nullif(d #> '{pinPosition}', 'null'::jsonb),(d #>> '{teeLatitude}')::double precision,(d #>> '{teeLongitude}')::double precision,(d #>> '{firstPuttFeet}')::double precision,nullif(d #> '{firstPuttPosition}', 'null'::jsonb),(d #>> '{dismissedShotSuggestions}')::integer,(d #>> '{dictateTranscript}')::text,(d #>> '{analysisNote}')::text) on conflict (user_id,round_id,id) do update set position=excluded.position,revision=excluded.revision,deleted_at=excluded.deleted_at,updated_at=excluded.updated_at,extras=excluded.extras,hole_number=excluded.hole_number,score=excluded.score,putts=excluded.putts,penalty_strokes=excluded.penalty_strokes,penalties_by_shot=excluded.penalties_by_shot,fairway_hit=excluded.fairway_hit,is_complete=excluded.is_complete,pin_position=excluded.pin_position,tee_latitude=excluded.tee_latitude,tee_longitude=excluded.tee_longitude,first_putt_feet=excluded.first_putt_feet,first_putt_position=excluded.first_putt_position,dismissed_shot_suggestions=excluded.dismissed_shot_suggestions,dictation_transcript=excluded.dictation_transcript,analysis_note=excluded.analysis_note;
 end if;
 when 'shot' then
 if coalesce((item->>'deleted')::boolean,false) then
 update public.shots set deleted_at=now(),revision=version,updated_at=now() where user_id = owner_id and id = rid and round_id = parent_id;
 else
 insert into public.shots (user_id,id,position,revision,deleted_at,updated_at,extras,round_id,hole_id,shot_number,club,lie,distance_to_pin_yards,carry_yards,traveled_yards,mapped_distance_yards,remaining_feet,club_was_suggested,start_latitude,start_longitude,end_latitude,end_longitude,contact,shape,quality,include_in_true_distance,source,taken_at,note,observations) values (owner_id,rid,coalesce((item->>'position')::integer,0),version,null,now(),d - array['id','holeScores','shots','club','distanceToPinBeforeYards','source','carryYards','clubWasSuggested','observations','contact','end','traveledYards','shape','includeInTrueDistance','lie','mappedDistanceYards','start','timestamp','note','remainingFeet','quality','number'],parent_id,(item->>'hole_id')::uuid,(d #>> '{number}')::integer,(d #>> '{club}')::text,(d #>> '{lie}')::text,(d #>> '{distanceToPinBeforeYards}')::double precision,(d #>> '{carryYards}')::double precision,(d #>> '{traveledYards}')::double precision,(d #>> '{mappedDistanceYards}')::double precision,(d #>> '{remainingFeet}')::double precision,(d #>> '{clubWasSuggested}')::boolean,(d #>> '{start,latitude}')::double precision,(d #>> '{start,longitude}')::double precision,(d #>> '{end,latitude}')::double precision,(d #>> '{end,longitude}')::double precision,(d #>> '{contact}')::text,(d #>> '{shape}')::text,(d #>> '{quality}')::text,(d #>> '{includeInTrueDistance}')::boolean,(d #>> '{source}')::text,public.golf_date(d #> '{timestamp}'),(d #>> '{note}')::text,nullif(d #> '{observations}', 'null'::jsonb)) on conflict (user_id,round_id,id) do update set position=excluded.position,revision=excluded.revision,deleted_at=excluded.deleted_at,updated_at=excluded.updated_at,extras=excluded.extras,shot_number=excluded.shot_number,club=excluded.club,lie=excluded.lie,distance_to_pin_yards=excluded.distance_to_pin_yards,carry_yards=excluded.carry_yards,traveled_yards=excluded.traveled_yards,mapped_distance_yards=excluded.mapped_distance_yards,remaining_feet=excluded.remaining_feet,club_was_suggested=excluded.club_was_suggested,start_latitude=excluded.start_latitude,start_longitude=excluded.start_longitude,end_latitude=excluded.end_latitude,end_longitude=excluded.end_longitude,contact=excluded.contact,shape=excluded.shape,quality=excluded.quality,include_in_true_distance=excluded.include_in_true_distance,source=excluded.source,taken_at=excluded.taken_at,note=excluded.note,observations=excluded.observations;
 end if;
 when 'club' then
 if coalesce((item->>'deleted')::boolean,false) then
 update public.clubs set deleted_at=now(),revision=version,updated_at=now() where user_id = owner_id and id = rid;
 else
 insert into public.clubs (user_id,id,position,revision,deleted_at,updated_at,extras,club,nickname,carry_yards) values (owner_id,rid,coalesce((item->>'position')::integer,0),version,null,now(),d - array['id','holeScores','shots','club','carryYards','nickname'],(d #>> '{club}')::text,(d #>> '{nickname}')::text,(d #>> '{carryYards}')::double precision) on conflict (user_id,id) do update set position=excluded.position,revision=excluded.revision,deleted_at=excluded.deleted_at,updated_at=excluded.updated_at,extras=excluded.extras,club=excluded.club,nickname=excluded.nickname,carry_yards=excluded.carry_yards;
 end if;
 when 'practice' then
 if coalesce((item->>'deleted')::boolean,false) then
 update public.practice_sessions set deleted_at=now(),revision=version,updated_at=now() where user_id = owner_id and id = rid;
 else
 insert into public.practice_sessions (user_id,id,position,revision,deleted_at,updated_at,extras,practiced_at,focus,made,attempts,note) values (owner_id,rid,coalesce((item->>'position')::integer,0),version,null,now(),d - array['id','holeScores','shots','made','focus','date','note','attempts'],public.golf_date(d #> '{date}'),(d #>> '{focus}')::text,(d #>> '{made}')::integer,(d #>> '{attempts}')::integer,(d #>> '{note}')::text) on conflict (user_id,id) do update set position=excluded.position,revision=excluded.revision,deleted_at=excluded.deleted_at,updated_at=excluded.updated_at,extras=excluded.extras,practiced_at=excluded.practiced_at,focus=excluded.focus,made=excluded.made,attempts=excluded.attempts,note=excluded.note;
 end if;
 else raise exception 'Unknown golf record type';
 end case;
end; $$;
revoke all on function public.golf_write_record(uuid,jsonb,bigint) from public;
-- Flat wire view; foreign keys/ownership and analytical fields live in tables.
create view public.golf_records with (security_invoker=true) as
select user_id, 'round'::text kind, id, null::uuid round_id, null::uuid hole_id, position, revision, deleted_at is not null deleted, case when deleted_at is null then public.golf_record_data('round',to_jsonb(t)) else '{}'::jsonb end data from public.rounds t
union all
select user_id, 'hole'::text kind, id, round_id round_id, null::uuid hole_id, position, revision, deleted_at is not null deleted, case when deleted_at is null then public.golf_record_data('hole',to_jsonb(t)) else '{}'::jsonb end data from public.hole_scores t
union all
select user_id, 'shot'::text kind, id, round_id round_id, hole_id hole_id, position, revision, deleted_at is not null deleted, case when deleted_at is null then public.golf_record_data('shot',to_jsonb(t)) else '{}'::jsonb end data from public.shots t
union all
select user_id, 'club'::text kind, id, null::uuid round_id, null::uuid hole_id, position, revision, deleted_at is not null deleted, case when deleted_at is null then public.golf_record_data('club',to_jsonb(t)) else '{}'::jsonb end data from public.clubs t
union all
select user_id, 'practice'::text kind, id, null::uuid round_id, null::uuid hole_id, position, revision, deleted_at is not null deleted, case when deleted_at is null then public.golf_record_data('practice',to_jsonb(t)) else '{}'::jsonb end data from public.practice_sessions t;
grant execute on function public.golf_record_data(text,jsonb) to authenticated;
revoke all on public.golf_records from anon,authenticated;
grant select on public.golf_records to authenticated;

-- A per-user clock orders commits, not conflicts. Each changed record carries
-- its own revision; editing another hole never invalidates an unchanged shot.
create function public.pull_golf_records(after_cursor bigint default 0) returns jsonb
language sql stable security invoker set search_path = public, pg_temp as $$
 select jsonb_build_object('cursor',coalesce(a.cursor,0),'records',coalesce((
   select jsonb_agg(to_jsonb(r) - 'user_id' order by r.revision,r.kind,r.round_id,r.id)
   from public.golf_records r where r.user_id=auth.uid()
     and r.revision > after_cursor and r.revision <= coalesce(a.cursor,0)
 ),'[]'::jsonb))
 from (select 1) seed left join public.golf_sync_accounts a on a.user_id=auth.uid()
$$;
revoke all on function public.pull_golf_records(bigint) from public,anon;
grant execute on function public.pull_golf_records(bigint) to authenticated;

create function public.commit_golf_records(changes jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare owner_id uuid := auth.uid(); item jsonb; old public.golf_records;
 next_version bigint; table_name text; deleted boolean;
begin
 if owner_id is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if jsonb_typeof(changes) is distinct from 'array' then raise exception 'Expected record array' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(changes) c group by c->>'kind',c->>'round_id',c->>'id' having count(*)>1) then
   raise exception 'Duplicate record in batch' using errcode='22023';
 end if;
 insert into public.golf_sync_accounts(user_id) values(owner_id) on conflict do nothing;
 select cursor+1 into next_version from public.golf_sync_accounts where user_id=owner_id for update;
 for item in select value from jsonb_array_elements(changes) loop
   if item->>'kind' is null or item->>'kind' not in ('round','hole','shot','club','practice') or item->>'id' is null
      or (item->>'expected_revision')::bigint is null or (item->>'expected_revision')::bigint < 0 then
     raise exception 'Invalid record identity or revision' using errcode='22023';
   end if;
   if (item->>'kind' in ('round','club','practice') and ((item->>'round_id') is not null or (item->>'hole_id') is not null))
      or (item->>'kind' = 'hole' and ((item->>'round_id') is null or (item->>'hole_id') is not null))
      or (item->>'kind' = 'shot' and ((item->>'round_id') is null or (item->>'hole_id') is null)) then
     raise exception 'Invalid parent identity' using errcode='22023';
   end if;
   select * into old from public.golf_records where user_id=owner_id and kind=item->>'kind'
     and id=(item->>'id')::uuid and round_id is not distinct from (item->>'round_id')::uuid;
   if coalesce(old.revision,0) <> (item->>'expected_revision')::bigint then
     return jsonb_build_object('accepted',false);
   end if;
   deleted := coalesce((item->>'deleted')::boolean,false);
   if old.deleted and not deleted then return jsonb_build_object('accepted',false); end if;
   if not deleted and ((item->'data'->>'id')::uuid is distinct from (item->>'id')::uuid) then
     raise exception 'Payload ID mismatch' using errcode='22023';
   end if;
   if old.id is not null and old.hole_id is distinct from (item->>'hole_id')::uuid then
     raise exception 'A shot cannot change parent holes' using errcode='22023';
   end if;
 end loop;
 -- Parents first, then children. A batch is one transaction and one cursor.
 for item in select value from jsonb_array_elements(changes)
   order by case value->>'kind' when 'round' then 0 when 'hole' then 1 when 'shot' then 2 else 3 end
 loop
   if not coalesce((item->>'deleted')::boolean,false) then
     if item->>'kind' in ('hole','shot') and not exists(select 1 from public.rounds
        where user_id=owner_id and id=(item->>'round_id')::uuid and deleted_at is null) then
       raise exception 'Active parent round required' using errcode='23503';
     end if;
     if item->>'kind'='shot' and not exists(select 1 from public.hole_scores
        where user_id=owner_id and round_id=(item->>'round_id')::uuid and id=(item->>'hole_id')::uuid and deleted_at is null) then
       raise exception 'Active parent hole required' using errcode='23503';
     end if;
   end if;
   perform public.golf_write_record(owner_id,item,next_version);
 end loop;
 if jsonb_array_length(changes)>0 then
   update public.golf_sync_accounts set cursor=next_version where user_id=owner_id;
 end if;
 return jsonb_build_object('accepted',true);
end; $$;
revoke all on function public.commit_golf_records(jsonb) from public,anon;
grant execute on function public.commit_golf_records(jsonb) to authenticated;

-- Migration-only flattening. The archive remains untouched after verification.
create function public.import_golf_snapshot(owner_id uuid, snapshot jsonb, source_revision bigint) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare r jsonb; h jsonb; s jsonb; c jsonb; p jsonb; hi integer; si integer; ci integer;
 expected_counts jsonb; actual_counts jsonb; expected_score bigint; actual_score bigint;
begin
 if jsonb_typeof(snapshot->'rounds') is distinct from 'array' then raise exception 'Invalid legacy rounds'; end if;
 insert into public.golf_sync_accounts(user_id,cursor,legacy_revision) values(owner_id,1,source_revision);
 for r in select value from jsonb_array_elements(snapshot->'rounds') loop
   perform public.golf_write_record(owner_id,jsonb_build_object('kind','round','id',r->'id','data',r - 'holeScores'),1);
   hi:=0;
   for h in select value from jsonb_array_elements(r->'holeScores') loop
     perform public.golf_write_record(owner_id,jsonb_build_object('kind','hole','id',h->'id','round_id',r->'id','position',hi,'data',h - 'shots'),1);
     hi:=hi+1; si:=0;
     for s in select value from jsonb_array_elements(h->'shots') loop
       perform public.golf_write_record(owner_id,jsonb_build_object('kind','shot','id',s->'id','round_id',r->'id','hole_id',h->'id','position',si,'data',s),1);
       si:=si+1;
     end loop;
   end loop;
 end loop;
 ci:=0;
 for c in select value from jsonb_array_elements(coalesce(snapshot->'bag'->'clubs','[]')) loop
   perform public.golf_write_record(owner_id,jsonb_build_object('kind','club','id',c->'id','position',ci,'data',c),1); ci:=ci+1;
 end loop;
 ci:=0;
 for p in select value from jsonb_array_elements(coalesce(snapshot->'practice','[]')) loop
   perform public.golf_write_record(owner_id,jsonb_build_object('kind','practice','id',p->'id','position',ci,'data',p),1); ci:=ci+1;
 end loop;
 select jsonb_build_object(
   'rounds',jsonb_array_length(snapshot->'rounds'),
   'holes',(select count(*) from jsonb_array_elements(snapshot->'rounds') rr(value) cross join lateral jsonb_array_elements(rr.value->'holeScores') hh(value)),
   'shots',(select count(*) from jsonb_array_elements(snapshot->'rounds') rr(value) cross join lateral jsonb_array_elements(rr.value->'holeScores') hh(value) cross join lateral jsonb_array_elements(hh.value->'shots') ss(value)),
   'clubs',jsonb_array_length(coalesce(snapshot->'bag'->'clubs','[]')),
   'practice',jsonb_array_length(coalesce(snapshot->'practice','[]'))) into expected_counts;
 select jsonb_build_object('rounds',(select count(*) from public.rounds where user_id=owner_id),
   'holes',(select count(*) from public.hole_scores where user_id=owner_id),
   'shots',(select count(*) from public.shots where user_id=owner_id),
   'clubs',(select count(*) from public.clubs where user_id=owner_id),
   'practice',(select count(*) from public.practice_sessions where user_id=owner_id)) into actual_counts;
 select coalesce(sum((hh.value->>'recordedScore')::integer),0) into expected_score from jsonb_array_elements(snapshot->'rounds') rr(value) cross join lateral jsonb_array_elements(rr.value->'holeScores') hh(value);
 select coalesce(sum(score),0) into actual_score from public.hole_scores where user_id=owner_id;
 if actual_counts <> expected_counts or actual_score <> expected_score then raise exception 'Golf migration verification failed'; end if;
 update public.golf_sync_accounts set migrated_at=now(),migration_counts=actual_counts || jsonb_build_object('score_total',actual_score) where user_id=owner_id;
end; $$;
revoke all on function public.import_golf_snapshot(uuid,jsonb,bigint) from public;

do $$
declare source record;
begin
 for source in select user_id,payload,revision from public.golf_sync_state loop
   perform public.import_golf_snapshot(source.user_id,source.payload,source.revision);
 end loop;
 -- Older per-round payloads are imported only if no account snapshot supersedes them.
 for source in select user_id,jsonb_build_object('rounds',jsonb_agg(payload),'bag',jsonb_build_object('clubs','[]'::jsonb),'practice','[]'::jsonb) payload
   from public.rounds_legacy_snapshot where payload ? 'id' and payload ? 'holeScores'
   and user_id not in (select user_id from public.golf_sync_accounts) group by user_id loop
   perform public.import_golf_snapshot(source.user_id,source.payload,0);
 end loop;
end; $$;

-- Old clients must not overwrite archived snapshots after the cutover.
create or replace function public.sync_golf_state(expected_revision bigint, new_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin raise exception 'Upgrade Pinpoint to use record sync' using errcode='55000'; end; $$;
