-- ProteínaFlow V3 · 3.11.0
-- Importação XML robusta por RPC + vínculos de importação.
-- MIGRAÇÃO NÃO DESTRUTIVA: não apaga XMLs, vendas, estoque, inventários ou usuários.
-- Pode ser executada novamente.

begin;


-- 1) SOBRA = posição física de proteína no fechamento (não item de venda).
alter table public.leftovers add column if not exists stage text;
alter table public.leftovers add column if not exists closing_balance boolean not null default false;
alter table public.leftovers alter column photo_item_path drop not null;
alter table public.leftovers alter column photo_scale_path drop not null;
create index if not exists leftovers_unit_closing_date_idx_v311
  on public.leftovers(unit_id,event_date,protein_id,location)
  where closing_balance=true;

-- 2) Garante a estrutura de mapeamento fiscal usada pela análise.
create table if not exists public.fiscal_item_mappings (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  fiscal_code text not null,
  fiscal_name text,
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.fiscal_item_mappings add column if not exists org_id uuid;
alter table public.fiscal_item_mappings add column if not exists fiscal_code text;
alter table public.fiscal_item_mappings add column if not exists fiscal_name text;
alter table public.fiscal_item_mappings add column if not exists menu_item_id uuid;
alter table public.fiscal_item_mappings add column if not exists active boolean default true;
alter table public.fiscal_item_mappings add column if not exists created_by uuid;
alter table public.fiscal_item_mappings add column if not exists created_at timestamptz default now();
alter table public.fiscal_item_mappings add column if not exists updated_at timestamptz default now();

do $idx$
begin
  if not exists (
    select 1 from public.fiscal_item_mappings
    where org_id is not null and fiscal_code is not null
    group by org_id,fiscal_code having count(*)>1
  ) then
    execute 'create unique index if not exists fiscal_item_mappings_org_code_uq on public.fiscal_item_mappings(org_id,fiscal_code)';
  end if;
end
$idx$;

alter table public.fiscal_item_mappings enable row level security;
grant select,insert,update,delete on public.fiscal_item_mappings to authenticated;

do $map_policy$
begin
  if to_regprocedure('public.is_member(uuid)') is not null and to_regprocedure('public.is_admin(uuid)') is not null then
    execute 'drop policy if exists fiscal_item_mappings_select on public.fiscal_item_mappings';
    execute 'drop policy if exists fiscal_item_mappings_insert on public.fiscal_item_mappings';
    execute 'drop policy if exists fiscal_item_mappings_update on public.fiscal_item_mappings';
    execute 'drop policy if exists fiscal_item_mappings_delete on public.fiscal_item_mappings';
    execute 'create policy fiscal_item_mappings_select on public.fiscal_item_mappings for select to authenticated using (public.is_member(org_id))';
    execute 'create policy fiscal_item_mappings_insert on public.fiscal_item_mappings for insert to authenticated with check (public.is_admin(org_id))';
    execute 'create policy fiscal_item_mappings_update on public.fiscal_item_mappings for update to authenticated using (public.is_admin(org_id)) with check (public.is_admin(org_id))';
    execute 'create policy fiscal_item_mappings_delete on public.fiscal_item_mappings for delete to authenticated using (public.is_admin(org_id))';
  end if;
end
$map_policy$;


create table if not exists public.sales_imports (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  unit_id uuid not null references public.units(id) on delete cascade,
  filename text not null,
  period_start date,
  period_end date,
  documents_count integer not null default 0,
  lines_count integer not null default 0,
  cancelled_count integer not null default 0,
  net_sales numeric(16,2) not null default 0,
  status text not null default 'IMPORTED',
  imported_by uuid not null references auth.users(id),
  imported_at timestamptz not null default now()
);

create table if not exists public.sales_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  unit_id uuid not null references public.units(id) on delete cascade,
  import_id uuid references public.sales_imports(id) on delete set null,
  event_date date not null,
  document_key text not null,
  document_number text,
  line_no integer not null,
  item_code text,
  item_name text not null,
  qty numeric(14,3) not null default 0,
  unit_price numeric(16,4) not null default 0,
  gross_value numeric(16,2) not null default 0,
  discount_value numeric(16,2) not null default 0,
  net_value numeric(16,2) not null default 0,
  cancelled boolean not null default false,
  menu_item_id uuid references public.menu_items(id) on delete set null,
  matched_by text,
  raw_source text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.sales_import_links (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  unit_id uuid not null references public.units(id) on delete cascade,
  import_id uuid not null references public.sales_imports(id) on delete cascade,
  document_key text not null,
  line_no integer not null,
  created_at timestamptz not null default now(),
  unique(import_id,document_key,line_no)
);

-- Corrige instalações parciais sem excluir dados.
alter table public.sales_import_links add column if not exists org_id uuid;
alter table public.sales_import_links add column if not exists unit_id uuid;
alter table public.sales_import_links add column if not exists import_id uuid;
alter table public.sales_import_links add column if not exists document_key text;
alter table public.sales_import_links add column if not exists line_no integer;
alter table public.sales_import_links add column if not exists created_at timestamptz default now();

alter table public.sales_imports add column if not exists org_id uuid;
alter table public.sales_imports add column if not exists unit_id uuid;
alter table public.sales_imports add column if not exists filename text;
alter table public.sales_imports add column if not exists period_start date;
alter table public.sales_imports add column if not exists period_end date;
alter table public.sales_imports add column if not exists documents_count integer default 0;
alter table public.sales_imports add column if not exists lines_count integer default 0;
alter table public.sales_imports add column if not exists cancelled_count integer default 0;
alter table public.sales_imports add column if not exists net_sales numeric(16,2) default 0;
alter table public.sales_imports add column if not exists status text default 'IMPORTED';
alter table public.sales_imports add column if not exists imported_by uuid;
alter table public.sales_imports add column if not exists imported_at timestamptz default now();

alter table public.sales_lines add column if not exists org_id uuid;
alter table public.sales_lines add column if not exists unit_id uuid;
alter table public.sales_lines add column if not exists import_id uuid;
alter table public.sales_lines add column if not exists event_date date;
alter table public.sales_lines add column if not exists document_key text;
alter table public.sales_lines add column if not exists document_number text;
alter table public.sales_lines add column if not exists line_no integer;
alter table public.sales_lines add column if not exists item_code text;
alter table public.sales_lines add column if not exists item_name text;
alter table public.sales_lines add column if not exists qty numeric(14,3) default 0;
alter table public.sales_lines add column if not exists unit_price numeric(16,4) default 0;
alter table public.sales_lines add column if not exists gross_value numeric(16,2) default 0;
alter table public.sales_lines add column if not exists discount_value numeric(16,2) default 0;
alter table public.sales_lines add column if not exists net_value numeric(16,2) default 0;
alter table public.sales_lines add column if not exists cancelled boolean default false;
alter table public.sales_lines add column if not exists menu_item_id uuid;
alter table public.sales_lines add column if not exists matched_by text;
alter table public.sales_lines add column if not exists raw_source text;
alter table public.sales_lines add column if not exists created_by uuid;
alter table public.sales_lines add column if not exists created_at timestamptz default now();

create index if not exists sales_lines_unit_doc_line_idx_v311 on public.sales_lines(unit_id,document_key,line_no);
create index if not exists sales_lines_unit_date_idx_v311 on public.sales_lines(unit_id,event_date);
create index if not exists sales_imports_unit_period_idx_v311 on public.sales_imports(unit_id,period_start,period_end);
create index if not exists sales_import_links_unit_doc_line_idx_v311 on public.sales_import_links(unit_id,document_key,line_no);
create index if not exists sales_import_links_import_idx_v311 on public.sales_import_links(import_id);

-- Mantém os vínculos de importações antigas conhecidos pelo campo import_id.
insert into public.sales_import_links(org_id,unit_id,import_id,document_key,line_no)
select sl.org_id,sl.unit_id,sl.import_id,sl.document_key,sl.line_no
from public.sales_lines sl
join public.sales_imports si on si.id=sl.import_id
where sl.import_id is not null
  and sl.org_id is not null
  and sl.unit_id is not null
  and sl.document_key is not null
  and sl.line_no is not null
  and not exists (
    select 1 from public.sales_import_links l
    where l.import_id=sl.import_id and l.document_key=sl.document_key and l.line_no=sl.line_no
  );

alter table public.sales_imports enable row level security;
alter table public.sales_lines enable row level security;
alter table public.sales_import_links enable row level security;
grant select,insert,update,delete on public.sales_imports,public.sales_lines,public.sales_import_links to authenticated;

-- Políticas são recriadas apenas quando as funções do núcleo existem.
do $policy$
begin
  if to_regprocedure('public.is_member(uuid)') is not null and to_regprocedure('public.is_admin(uuid)') is not null then
    execute 'drop policy if exists sales_imports_select on public.sales_imports';
    execute 'drop policy if exists sales_imports_insert on public.sales_imports';
    execute 'drop policy if exists sales_imports_update on public.sales_imports';
    execute 'drop policy if exists sales_imports_delete on public.sales_imports';
    execute 'create policy sales_imports_select on public.sales_imports for select to authenticated using (public.is_member(org_id))';
    execute 'create policy sales_imports_insert on public.sales_imports for insert to authenticated with check (public.is_admin(org_id))';
    execute 'create policy sales_imports_update on public.sales_imports for update to authenticated using (public.is_admin(org_id)) with check (public.is_admin(org_id))';
    execute 'create policy sales_imports_delete on public.sales_imports for delete to authenticated using (public.is_admin(org_id))';

    execute 'drop policy if exists sales_lines_select on public.sales_lines';
    execute 'drop policy if exists sales_lines_insert on public.sales_lines';
    execute 'drop policy if exists sales_lines_update on public.sales_lines';
    execute 'drop policy if exists sales_lines_delete on public.sales_lines';
    execute 'create policy sales_lines_select on public.sales_lines for select to authenticated using (public.is_member(org_id))';
    execute 'create policy sales_lines_insert on public.sales_lines for insert to authenticated with check (public.is_admin(org_id))';
    execute 'create policy sales_lines_update on public.sales_lines for update to authenticated using (public.is_admin(org_id)) with check (public.is_admin(org_id))';
    execute 'create policy sales_lines_delete on public.sales_lines for delete to authenticated using (public.is_admin(org_id))';

    execute 'drop policy if exists sales_import_links_select on public.sales_import_links';
    execute 'drop policy if exists sales_import_links_insert on public.sales_import_links';
    execute 'drop policy if exists sales_import_links_update on public.sales_import_links';
    execute 'drop policy if exists sales_import_links_delete on public.sales_import_links';
    execute 'create policy sales_import_links_select on public.sales_import_links for select to authenticated using (public.is_member(org_id))';
    execute 'create policy sales_import_links_insert on public.sales_import_links for insert to authenticated with check (public.is_admin(org_id))';
    execute 'create policy sales_import_links_update on public.sales_import_links for update to authenticated using (public.is_admin(org_id)) with check (public.is_admin(org_id))';
    execute 'create policy sales_import_links_delete on public.sales_import_links for delete to authenticated using (public.is_admin(org_id))';
  end if;
end $policy$;

create or replace function public.pf_create_sales_import_v311(
  p_filename text,
  p_period_start date,
  p_period_end date,
  p_documents_count integer,
  p_lines_count integer,
  p_cancelled_count integer,
  p_net_sales numeric
) returns uuid
language plpgsql
security definer
set search_path=public,auth
as $fn$
declare
  v_org uuid; v_unit uuid; v_role text; v_id uuid;
begin
  if auth.uid() is null then raise exception 'PF_AUTH: sessão não autenticada'; end if;
  select m.org_id,m.default_unit_id,m.role into v_org,v_unit,v_role
  from public.memberships m
  where m.user_id=auth.uid() and m.active
  order by m.created_at desc limit 1;
  if v_org is null or v_unit is null then raise exception 'PF_MEMBERSHIP: usuário sem empresa/unidade ativa'; end if;
  if v_role not in ('SUPER_ADMIN','ADMIN') then raise exception 'PF_FORBIDDEN: somente ADMIN/SUPER_ADMIN importa XML'; end if;
  if coalesce(length(trim(p_filename)),0)=0 then raise exception 'PF_FILE: nome do ZIP inválido'; end if;

  insert into public.sales_imports(
    org_id,unit_id,filename,period_start,period_end,documents_count,lines_count,
    cancelled_count,net_sales,status,imported_by,imported_at
  ) values(
    v_org,v_unit,trim(p_filename),p_period_start,p_period_end,coalesce(p_documents_count,0),
    coalesce(p_lines_count,0),coalesce(p_cancelled_count,0),coalesce(p_net_sales,0),
    'PROCESSING',auth.uid(),now()
  ) returning id into v_id;
  return v_id;
end $fn$;

grant execute on function public.pf_create_sales_import_v311(text,date,date,integer,integer,integer,numeric) to authenticated;

create or replace function public.pf_import_sales_lines_v311(
  p_import_id uuid,
  p_rows jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public,auth
as $fn$
declare
  v_org uuid; v_unit uuid; v_role text;
  v_import_org uuid; v_import_unit uuid;
  v jsonb; v_line_id uuid; v_menu uuid;
  v_inserted integer:=0; v_existing integer:=0; v_links integer:=0; v_total integer:=0;
  v_document_key text; v_line_no integer;
begin
  if auth.uid() is null then raise exception 'PF_AUTH: sessão não autenticada'; end if;
  select m.org_id,m.default_unit_id,m.role into v_org,v_unit,v_role
  from public.memberships m
  where m.user_id=auth.uid() and m.active
  order by m.created_at desc limit 1;
  if v_org is null or v_unit is null then raise exception 'PF_MEMBERSHIP: usuário sem empresa/unidade ativa'; end if;
  if v_role not in ('SUPER_ADMIN','ADMIN') then raise exception 'PF_FORBIDDEN: somente ADMIN/SUPER_ADMIN importa XML'; end if;

  select si.org_id,si.unit_id into v_import_org,v_import_unit
  from public.sales_imports si where si.id=p_import_id;
  if v_import_org is null then raise exception 'PF_IMPORT: importação não localizada'; end if;
  if v_import_org<>v_org or v_import_unit<>v_unit then raise exception 'PF_FORBIDDEN: importação pertence a outra unidade'; end if;

  for v in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb))
  loop
    v_total:=v_total+1;
    v_document_key:=nullif(trim(v->>'document_key'),'');
    v_line_no:=coalesce((v->>'line_no')::integer,0);
    if v_document_key is null or v_line_no<=0 then
      raise exception 'PF_XML_ROW: chave/linha fiscal inválida no registro %',v_total;
    end if;
    v_menu:=null;
    if nullif(v->>'menu_item_id','') is not null then v_menu:=(v->>'menu_item_id')::uuid; end if;

    select sl.id into v_line_id
    from public.sales_lines sl
    where sl.unit_id=v_unit and sl.document_key=v_document_key and sl.line_no=v_line_no
    order by sl.created_at nulls last,sl.id limit 1;

    if v_line_id is null then
      insert into public.sales_lines(
        org_id,unit_id,import_id,event_date,document_key,document_number,line_no,
        item_code,item_name,qty,unit_price,gross_value,discount_value,net_value,cancelled,
        menu_item_id,matched_by,raw_source,created_by,created_at
      ) values(
        v_org,v_unit,p_import_id,(v->>'event_date')::date,v_document_key,nullif(v->>'document_number',''),v_line_no,
        nullif(v->>'item_code',''),coalesce(nullif(v->>'item_name',''),'ITEM SEM DESCRIÇÃO'),
        coalesce((v->>'qty')::numeric,0),coalesce((v->>'unit_price')::numeric,0),
        coalesce((v->>'gross_value')::numeric,0),coalesce((v->>'discount_value')::numeric,0),
        coalesce((v->>'net_value')::numeric,0),coalesce((v->>'cancelled')::boolean,false),
        v_menu,nullif(v->>'matched_by',''),nullif(v->>'raw_source',''),auth.uid(),now()
      ) returning id into v_line_id;
      v_inserted:=v_inserted+1;
    else
      update public.sales_lines
      set
        cancelled=coalesce((v->>'cancelled')::boolean,cancelled),
        menu_item_id=coalesce(menu_item_id,v_menu),
        matched_by=case when menu_item_id is null and v_menu is not null then nullif(v->>'matched_by','') else matched_by end,
        import_id=coalesce(import_id,p_import_id)
      where id=v_line_id;
      v_existing:=v_existing+1;
    end if;

    if not exists (
      select 1 from public.sales_import_links l
      where l.import_id=p_import_id and l.document_key=v_document_key and l.line_no=v_line_no
    ) then
      insert into public.sales_import_links(org_id,unit_id,import_id,document_key,line_no)
      values(v_org,v_unit,p_import_id,v_document_key,v_line_no);
      v_links:=v_links+1;
    end if;
  end loop;

  return jsonb_build_object(
    'ok',true,'total',v_total,'inserted',v_inserted,'existing',v_existing,'links',v_links
  );
end $fn$;

grant execute on function public.pf_import_sales_lines_v311(uuid,jsonb) to authenticated;

create or replace function public.pf_finish_sales_import_v311(p_import_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,auth
as $fn$
declare
  v_org uuid; v_unit uuid; v_role text; v_count integer:=0;
begin
  if auth.uid() is null then raise exception 'PF_AUTH: sessão não autenticada'; end if;
  select m.org_id,m.default_unit_id,m.role into v_org,v_unit,v_role
  from public.memberships m where m.user_id=auth.uid() and m.active order by m.created_at desc limit 1;
  if v_role not in ('SUPER_ADMIN','ADMIN') then raise exception 'PF_FORBIDDEN'; end if;
  update public.sales_imports set status='IMPORTED'
  where id=p_import_id and org_id=v_org and unit_id=v_unit;
  if not found then raise exception 'PF_IMPORT: importação não localizada'; end if;
  select count(*)::integer into v_count from public.sales_import_links where import_id=p_import_id;
  return jsonb_build_object('ok',true,'linked_lines',v_count);
end $fn$;

grant execute on function public.pf_finish_sales_import_v311(uuid) to authenticated;

create or replace function public.pf_fail_sales_import_v311(p_import_id uuid)
returns boolean
language plpgsql
security definer
set search_path=public,auth
as $fn$
declare v_org uuid; v_unit uuid; v_role text;
begin
  select m.org_id,m.default_unit_id,m.role into v_org,v_unit,v_role
  from public.memberships m where m.user_id=auth.uid() and m.active order by m.created_at desc limit 1;
  if v_role not in ('SUPER_ADMIN','ADMIN') then return false; end if;
  update public.sales_imports set status='ERROR'
  where id=p_import_id and org_id=v_org and unit_id=v_unit;
  return found;
end $fn$;

grant execute on function public.pf_fail_sales_import_v311(uuid) to authenticated;


-- Apaga UM lote importado. Linhas que também pertencem a outro ZIP permanecem.
create or replace function public.pf_delete_sales_import(p_import_id uuid,p_reason text)
returns jsonb
language plpgsql
security definer
set search_path=public,auth
as $fn$
declare
  v_org uuid; v_unit uuid; v_role text;
  v_import_org uuid; v_import_unit uuid; v_old jsonb;
  v_removed_lines integer:=0; v_removed_links integer:=0; v_preserved_shared integer:=0;
  v_reason text;
begin
  if auth.uid() is null then raise exception 'PF_AUTH: sessao nao autenticada'; end if;
  select m.org_id,m.default_unit_id,m.role into v_org,v_unit,v_role
  from public.memberships m where m.user_id=auth.uid() and m.active
  order by m.created_at desc limit 1;
  if v_org is null then raise exception 'PF_MEMBERSHIP: usuario sem empresa ativa'; end if;
  if v_role not in ('SUPER_ADMIN','ADMIN') then raise exception 'PF_FORBIDDEN: somente ADMIN/SUPER_ADMIN pode apagar XML'; end if;
  v_reason:=trim(coalesce(p_reason,''));
  if length(v_reason)<3 then raise exception 'PF_REASON: informe o motivo'; end if;

  select si.org_id,si.unit_id,to_jsonb(si)
  into v_import_org,v_import_unit,v_old
  from public.sales_imports si where si.id=p_import_id;
  if v_old is null then raise exception 'PF_NOT_FOUND: importacao XML nao localizada'; end if;
  if v_import_org<>v_org or v_import_unit<>v_unit then raise exception 'PF_FORBIDDEN: importacao pertence a outra empresa/unidade'; end if;

  -- Se a linha fiscal também pertence a outro ZIP, transfere o import_id principal para outro lote.
  with shared as (
    select l.document_key,l.line_no,min(o.import_id::text)::uuid replacement_import_id
    from public.sales_import_links l
    join public.sales_import_links o
      on o.unit_id=l.unit_id
     and o.document_key=l.document_key
     and o.line_no=l.line_no
     and o.import_id<>l.import_id
    where l.import_id=p_import_id
    group by l.document_key,l.line_no
  )
  update public.sales_lines sl
     set import_id=shared.replacement_import_id
    from shared
   where sl.unit_id=v_import_unit
     and sl.document_key=shared.document_key
     and sl.line_no=shared.line_no
     and sl.import_id=p_import_id;
  get diagnostics v_preserved_shared=row_count;

  -- Exclui somente as linhas que deixariam de pertencer a qualquer importação válida.
  with mine as materialized (
    select document_key,line_no
    from public.sales_import_links
    where import_id=p_import_id
  )
  delete from public.sales_lines sl
  using mine m
  where sl.unit_id=v_import_unit
    and sl.document_key=m.document_key
    and sl.line_no=m.line_no
    and not exists(
      select 1 from public.sales_import_links other
      where other.unit_id=v_import_unit
        and other.document_key=m.document_key
        and other.line_no=m.line_no
        and other.import_id<>p_import_id
    );
  get diagnostics v_removed_lines=row_count;

  select count(*)::integer into v_removed_links
  from public.sales_import_links where import_id=p_import_id;

  -- ON DELETE CASCADE remove os links daquele lote.
  delete from public.sales_imports
  where id=p_import_id and org_id=v_org and unit_id=v_unit;

  begin
    insert into public.audit_log(org_id,unit_id,user_id,table_name,action,record_id,old_data,new_data,reason)
    values(v_org,v_unit,auth.uid(),'sales_imports','DELETE',p_import_id::text,v_old,
      jsonb_build_object('deleted_import',true,'removed_lines',v_removed_lines,'removed_links',v_removed_links,'preserved_shared_lines',v_preserved_shared),v_reason);
  exception when others then null;
  end;

  return jsonb_build_object('ok',true,'import_id',p_import_id,'removed_lines',v_removed_lines,'removed_links',v_removed_links,'preserved_shared_lines',v_preserved_shared);
end
$fn$;
grant execute on function public.pf_delete_sales_import(uuid,text) to authenticated;

-- Apaga TODAS as importações XML da unidade ativa e todas as linhas fiscais correspondentes.
create or replace function public.pf_delete_all_sales_imports(p_reason text)
returns jsonb
language plpgsql
security definer
set search_path=public,auth
as $fn$
declare
  v_org uuid; v_unit uuid; v_role text; v_reason text;
  v_removed_lines integer:=0; v_removed_imports integer:=0; v_removed_links integer:=0;
begin
  if auth.uid() is null then raise exception 'PF_AUTH: sessao nao autenticada'; end if;
  select m.org_id,m.default_unit_id,m.role into v_org,v_unit,v_role
  from public.memberships m where m.user_id=auth.uid() and m.active
  order by m.created_at desc limit 1;
  if v_org is null then raise exception 'PF_MEMBERSHIP: usuario sem empresa ativa'; end if;
  if v_role not in ('SUPER_ADMIN','ADMIN') then raise exception 'PF_FORBIDDEN: somente ADMIN/SUPER_ADMIN pode apagar XML'; end if;
  v_reason:=trim(coalesce(p_reason,''));
  if length(v_reason)<3 then raise exception 'PF_REASON: informe o motivo'; end if;

  select count(*)::integer into v_removed_links from public.sales_import_links where org_id=v_org and unit_id=v_unit;
  select count(*)::integer into v_removed_imports from public.sales_imports where org_id=v_org and unit_id=v_unit;

  delete from public.sales_lines where org_id=v_org and unit_id=v_unit;
  get diagnostics v_removed_lines=row_count;

  delete from public.sales_imports where org_id=v_org and unit_id=v_unit;
  -- links somem por cascade; explicitamente limpa órfãos por segurança.
  delete from public.sales_import_links where org_id=v_org and unit_id=v_unit;

  begin
    insert into public.audit_log(org_id,unit_id,user_id,table_name,action,record_id,old_data,new_data,reason)
    values(v_org,v_unit,auth.uid(),'sales_imports','DELETE_ALL',v_unit::text,null,
      jsonb_build_object('deleted_all_xml',true,'removed_imports',v_removed_imports,'removed_lines',v_removed_lines,'removed_links',v_removed_links),v_reason);
  exception when others then null;
  end;

  return jsonb_build_object('ok',true,'removed_imports',v_removed_imports,'removed_lines',v_removed_lines,'removed_links',v_removed_links);
end
$fn$;
grant execute on function public.pf_delete_all_sales_imports(text) to authenticated;

-- Diagnóstico único da estrutura XML V3.11.
create or replace function public.pf_xml_health_v311()
returns jsonb
language plpgsql
security definer
set search_path=public,auth
as $fn$
declare
  v_org uuid; v_unit uuid; v_role text;
begin
  if auth.uid() is null then raise exception 'PF_AUTH: sessão não autenticada'; end if;
  select m.org_id,m.default_unit_id,m.role into v_org,v_unit,v_role
  from public.memberships m
  where m.user_id=auth.uid() and m.active
  order by m.created_at desc limit 1;
  if v_org is null or v_unit is null then raise exception 'PF_MEMBERSHIP: usuário sem empresa/unidade ativa'; end if;
  return jsonb_build_object(
    'ready',true,
    'role',v_role,
    'org_id',v_org,
    'unit_id',v_unit,
    'imports_table',to_regclass('public.sales_imports') is not null,
    'lines_table',to_regclass('public.sales_lines') is not null,
    'links_table',to_regclass('public.sales_import_links') is not null,
    'mappings_table',to_regclass('public.fiscal_item_mappings') is not null,
    'closing_balance_column',exists(
      select 1 from information_schema.columns
      where table_schema='public' and table_name='leftovers' and column_name='closing_balance'
    ),
    'create_rpc',to_regprocedure('public.pf_create_sales_import_v311(text,date,date,integer,integer,integer,numeric)') is not null,
    'batch_rpc',to_regprocedure('public.pf_import_sales_lines_v311(uuid,jsonb)') is not null,
    'finish_rpc',to_regprocedure('public.pf_finish_sales_import_v311(uuid)') is not null,
    'delete_one_rpc',to_regprocedure('public.pf_delete_sales_import(uuid,text)') is not null,
    'delete_all_rpc',to_regprocedure('public.pf_delete_all_sales_imports(text)') is not null
  );
end
$fn$;
grant execute on function public.pf_xml_health_v311() to authenticated;

alter table public.fiscal_item_mappings replica identity full;

alter table public.sales_imports replica identity full;
alter table public.sales_lines replica identity full;
alter table public.sales_import_links replica identity full;
notify pgrst,'reload schema';
commit;

select
  'V311_XML_IMPORT_ROBUSTO_OK' as status,
  to_regclass('public.sales_imports') is not null as imports_table_ok,
  to_regclass('public.sales_lines') is not null as lines_table_ok,
  to_regclass('public.sales_import_links') is not null as links_table_ok,
  to_regprocedure('public.pf_create_sales_import_v311(text,date,date,integer,integer,integer,numeric)') is not null as create_rpc_ok,
  to_regprocedure('public.pf_import_sales_lines_v311(uuid,jsonb)') is not null as batch_rpc_ok,
  to_regprocedure('public.pf_finish_sales_import_v311(uuid)') is not null as finish_rpc_ok,
  to_regprocedure('public.pf_xml_health_v311()') is not null as health_rpc_ok,
  to_regprocedure('public.pf_delete_sales_import(uuid,text)') is not null as delete_one_ok,
  to_regprocedure('public.pf_delete_all_sales_imports(text)') is not null as delete_all_ok,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='leftovers' and column_name='closing_balance') as sobra_fechamento_ok,
  to_regclass('public.fiscal_item_mappings') is not null as mappings_ok;
