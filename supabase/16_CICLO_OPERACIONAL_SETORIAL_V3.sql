-- ProteínaFlow V3 · 3.8.0 · Ciclo operacional por setores
-- MIGRAÇÃO NÃO DESTRUTIVA. NÃO APAGA nenhum lançamento, usuário, empresa, produto, XML ou foto.
-- Execute UMA VEZ no mesmo projeto Supabase que já contém os dados atuais.

begin;

alter table public.menu_items add column if not exists sales_sector text not null default 'SUSHI_BAR';
alter table public.menu_items add column if not exists sector_review_required boolean not null default false;
alter table public.menu_items add column if not exists sector_source text not null default 'AUTO';
alter table public.menu_item_proteins add column if not exists source_sector text;

alter table public.processing_batches add column if not exists operation_type text;
alter table public.processing_batches add column if not exists input_stage text;
alter table public.processing_batches add column if not exists output_stage text;
alter table public.processing_batches add column if not exists input_kg numeric(12,3);
alter table public.processing_batches add column if not exists output_kg numeric(12,3);
alter table public.processing_batches add column if not exists from_location text;
alter table public.processing_batches add column if not exists to_location text;
alter table public.processing_batches add column if not exists stage_loss_kg numeric(12,3);
alter table public.processing_batches add column if not exists stage_yield_pct numeric(8,5);
alter table public.processing_batches add column if not exists input_cost_kg numeric(14,4);
alter table public.processing_batches add column if not exists output_cost_kg numeric(14,4);

alter table public.production_batches add column if not exists stock_effect boolean not null default true;
alter table public.inventory_counts add column if not exists theoretical_before_kg numeric(14,3);
alter table public.inventory_counts add column if not exists variance_kg numeric(14,3);
alter table public.inventory_counts add column if not exists variance_value numeric(16,2);
alter table public.analytics_settings add column if not exists sector_cutover_date date;
insert into public.analytics_settings(org_id) select id from public.organizations on conflict(org_id) do nothing;
update public.analytics_settings set sector_cutover_date=current_date where sector_cutover_date is null;

-- Preserva lançamentos históricos de beneficiamento com semântica antiga.
update public.processing_batches set
 operation_type=coalesce(operation_type,'LEGACY_FULL'),
 input_stage=coalesce(input_stage,'WHOLE'),
 output_stage=coalesce(output_stage,'CLEAN'),
 input_kg=coalesce(input_kg,whole_kg),
 output_kg=coalesce(output_kg,clean_kg),
 from_location=coalesce(from_location,location),
 to_location=coalesce(to_location,location),
 stage_loss_kg=coalesce(stage_loss_kg,total_loss_kg),
 stage_yield_pct=coalesce(stage_yield_pct,yield_total_pct),
 input_cost_kg=coalesce(input_cost_kg,cost_kg),
 output_cost_kg=coalesce(output_cost_kg,nullif(clean_cost_kg,0),case when clean_kg>0 then whole_kg*cost_kg/clean_kg else cost_kg end)
where operation_type is null or input_kg is null or output_kg is null;

-- Default inteligente por produto já cadastrado.
-- Precedência escolhida para evitar erros comuns: POKE/BOWL no nome → Poke;
-- sushi explícito no nome → Sushi Bar; itens quentes/Mex → Cozinha;
-- depois são usados família/contexto como indício. Configurações manuais nunca são sobrescritas.
update public.menu_items set sales_sector = case
  when upper(coalesce(name,'')) ~ '(POKE|BOWL)' then 'POKE'
  when upper(coalesce(name,'')) ~ '(SASHIMI|SUSHI|NIGIRI|URAMAKI|HOSSOMAKI|TEMAKI|JOY|HOT ROLL|HOTROLL|HAND ROLL|SUSHIDOG|ONIGIRI|COMBINADO|COMB[ ._-]|BRISA|BRIZA|CEVICHE|TARTAR)' then 'SUSHI_BAR'
  when upper(coalesce(name,'')) ~ '(YAKISOBA|YAKISSOBA|GUIOZA|GYOZA|HARUMAKI|ROLINHO|FRANGO|CHICKEN|KATSU|BURGER|QUICHE|MASSA|COZINHA|LULA|CAMARAO EMPAN|CAMARÃO EMPAN|TEMPURA|TEMPURÁ|ESPETO|TENDER|FALAFEL|BURRITO|TACO|NACHO|QUESADILLA|MEX|BATATA FRITA|BATATA-FRITA)' then 'KITCHEN'
  when upper(coalesce(family,'')) ~ '(POKE|BOWL)' then 'POKE'
  when upper(coalesce(contexts,'')) like '%POKE KAUAI%' and upper(coalesce(contexts,'')) not like '%SUSHI / JAPONÊS%' and upper(coalesce(contexts,'')) not like '%RODÍZIO%' then 'POKE'
  when upper(coalesce(family,'')) like '%SUSHI / JAPONÊS%' or upper(coalesce(contexts,'')) like '%SUSHI / JAPONÊS%' then 'SUSHI_BAR'
  else 'SUSHI_BAR' end
where coalesce(sector_source,'AUTO')='AUTO';

-- Itens genéricos/rodízios ficam utilizáveis, mas são sinalizados para revisão do administrador.
update public.menu_items set sector_review_required = case
  when upper(coalesce(name,'')||' '||coalesce(family,'')||' '||coalesce(contexts,'')) ~ '(RODIZIO|RODÍZIO|RDZ|EXECUTIVO|PREMIUM)'
   and upper(coalesce(name,'')) !~ '(POKE|BOWL|SASHIMI|SUSHI|NIGIRI|URAMAKI|HOSSOMAKI|TEMAKI|JOY|HOT ROLL|HOTROLL|HAND ROLL|SUSHIDOG|ONIGIRI|COMBINADO|BRISA|BRIZA|CEVICHE|TARTAR|YAKISOBA|YAKISSOBA|GUIOZA|GYOZA|HARUMAKI|ROLINHO|FRANGO|CHICKEN|KATSU|BURGER|QUICHE|LULA|TEMPURA|TEMPURÁ|ESPETO|FALAFEL|BURRITO|TACO|NACHO|QUESADILLA|BATATA FRITA|BATATA-FRITA)'
  then true else false end
where coalesce(sector_source,'AUTO')='AUTO';

-- source_sector NULL = herda automaticamente o setor do item. Só é preenchido quando o administrador quiser uma exceção por proteína.

create or replace function public.pf_upsert_menu_item_v3(
  p_id uuid,p_code text,p_name text,p_family text,p_contexts text,p_default_protein_id uuid,
  p_standard_grams numeric,p_standard_status text,p_sales_sector text,p_reason text
) returns jsonb language plpgsql security definer set search_path=public,auth as $fn$
declare v_org uuid;v_unit uuid;v_role text;v_old jsonb;v_new jsonb;v_id uuid;v_code text;v_sector text;
begin
 if auth.uid() is null then raise exception 'PF_AUTH: sessão não autenticada'; end if;
 select org_id,default_unit_id,role into v_org,v_unit,v_role from public.memberships where user_id=auth.uid() and active order by created_at desc limit 1;
 if v_role not in ('SUPER_ADMIN','ADMIN') then raise exception 'PF_FORBIDDEN: somente ADMIN/SUPER_ADMIN'; end if;
 if coalesce(length(trim(p_name)),0)<2 then raise exception 'PF_NAME: informe o produto'; end if;
 if p_default_protein_id is null then raise exception 'PF_PROTEIN: selecione a proteína'; end if;
 v_sector:=upper(coalesce(p_sales_sector,'SUSHI_BAR'));
 if v_sector not in ('SUSHI_BAR','POKE','KITCHEN') then raise exception 'PF_SECTOR: setor inválido'; end if;
 v_code:=upper(nullif(trim(coalesce(p_code,'')),''));
 if p_id is null then
   if v_code is null then v_code:='PF-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)); end if;
   insert into public.menu_items(org_id,code,name,family,contexts,default_protein_id,standard_grams,standard_status,active,sales_sector,sector_review_required,sector_source)
   values(v_org,v_code,trim(p_name),nullif(trim(coalesce(p_family,'')),''),nullif(trim(coalesce(p_contexts,'')),''),p_default_protein_id,coalesce(p_standard_grams,0),coalesce(p_standard_status,'OK'),true,v_sector,false,'MANUAL')
   returning id into v_id;
   select to_jsonb(x) into v_new from public.menu_items x where x.id=v_id;
   insert into public.audit_log(org_id,unit_id,user_id,table_name,action,record_id,new_data,reason) values(v_org,v_unit,auth.uid(),'menu_items','INSERT',v_id::text,v_new,p_reason);
 else
   select to_jsonb(x) into v_old from public.menu_items x where x.id=p_id and x.org_id=v_org;
   if v_old is null then raise exception 'PF_NOT_FOUND: item não localizado'; end if;
   if v_code is null then select code into v_code from public.menu_items where id=p_id; end if;
   update public.menu_items set code=v_code,name=trim(p_name),family=nullif(trim(coalesce(p_family,'')),''),contexts=nullif(trim(coalesce(p_contexts,'')),''),default_protein_id=p_default_protein_id,standard_grams=coalesce(p_standard_grams,0),standard_status=coalesce(p_standard_status,'OK'),sales_sector=v_sector,sector_review_required=false,sector_source='MANUAL' where id=p_id and org_id=v_org;
   v_id:=p_id;select to_jsonb(x) into v_new from public.menu_items x where x.id=v_id;
   insert into public.audit_log(org_id,unit_id,user_id,table_name,action,record_id,old_data,new_data,reason) values(v_org,v_unit,auth.uid(),'menu_items','UPDATE',v_id::text,v_old,v_new,p_reason);
 end if;
 return v_new;
end $fn$;
grant execute on function public.pf_upsert_menu_item_v3(uuid,text,text,text,text,uuid,numeric,text,text,text) to authenticated;

create or replace function public.pf_upsert_menu_component_v3(
 p_menu_item_id uuid,p_protein_id uuid,p_standard_grams numeric,p_stage text default 'CLEAN',p_source_sector text default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,auth as $fn$
declare v_org uuid;v_unit uuid;v_role text;v_old jsonb;v_new jsonb;v_id uuid;v_sector text;
begin
 if auth.uid() is null then raise exception 'PF_AUTH: sessão não autenticada'; end if;
 select org_id,default_unit_id,role into v_org,v_unit,v_role from public.memberships where user_id=auth.uid() and active order by created_at desc limit 1;
 if v_role not in ('SUPER_ADMIN','ADMIN') then raise exception 'PF_FORBIDDEN: somente ADMIN/SUPER_ADMIN'; end if;
 v_sector:=nullif(upper(trim(coalesce(p_source_sector,''))),'');
 if v_sector is not null and v_sector not in ('SUSHI_BAR','POKE','KITCHEN') then raise exception 'PF_SECTOR: setor inválido'; end if;
 select to_jsonb(x) into v_old from public.menu_item_proteins x where x.menu_item_id=p_menu_item_id and x.protein_id=p_protein_id;
 insert into public.menu_item_proteins(org_id,menu_item_id,protein_id,standard_grams,stage,source_sector,notes,active,created_by,updated_at)
 values(v_org,p_menu_item_id,p_protein_id,coalesce(p_standard_grams,0),upper(coalesce(p_stage,'CLEAN')),v_sector,p_notes,true,auth.uid(),now())
 on conflict(menu_item_id,protein_id) do update set standard_grams=excluded.standard_grams,stage=excluded.stage,source_sector=excluded.source_sector,notes=excluded.notes,active=true,updated_at=now()
 returning id into v_id;
 select to_jsonb(x) into v_new from public.menu_item_proteins x where x.id=v_id;
 insert into public.audit_log(org_id,unit_id,user_id,table_name,action,record_id,old_data,new_data,reason) values(v_org,v_unit,auth.uid(),'menu_item_proteins',case when v_old is null then 'INSERT' else 'UPDATE' end,v_id::text,v_old,v_new,'Ficha V3: proteína + setor');
 return v_new;
end $fn$;
grant execute on function public.pf_upsert_menu_component_v3(uuid,uuid,numeric,text,text,text) to authenticated;

alter table public.menu_items replica identity full;
alter table public.menu_item_proteins replica identity full;
alter table public.processing_batches replica identity full;
alter table public.inventory_counts replica identity full;
alter table public.production_batches replica identity full;

notify pgrst,'reload schema';
commit;

select 'PROTEINAFLOW_V3_OK' status,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='menu_items' and column_name='sales_sector') menu_sector_ok,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='menu_items' and column_name='sector_source') sector_defaults_idempotent_ok,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='processing_batches' and column_name='operation_type') processing_flow_ok,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='inventory_counts' and column_name='variance_kg') inventory_variance_ok,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='production_batches' and column_name='stock_effect') no_double_count_ok,
 to_regprocedure('public.pf_upsert_menu_item_v3(uuid,text,text,text,text,uuid,numeric,text,text,text)') is not null item_rpc_ok,
 to_regprocedure('public.pf_upsert_menu_component_v3(uuid,uuid,numeric,text,text,text)') is not null component_rpc_ok;
