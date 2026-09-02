-- ProteínaFlow V3 · 3.12.0
-- Produção e Sobra 100% por PROTEÍNA + suporte à conciliação em 3 vias.
-- MIGRAÇÃO NÃO DESTRUTIVA: preserva todos os lançamentos anteriores.
-- Pode ser executada novamente.

begin;

-- Produção passa a aceitar apontamento de proteína, sem item de venda.
alter table public.production_batches add column if not exists production_kind text;
alter table public.production_batches add column if not exists production_operation text;
alter table public.production_batches add column if not exists stage text;
alter table public.production_batches add column if not exists produced_protein_kg numeric(12,3);

-- Fotos permanecem disponíveis, porém opcionais.
alter table public.production_batches alter column photo_item_path drop not null;
alter table public.production_batches alter column photo_scale_path drop not null;
alter table public.leftovers alter column photo_item_path drop not null;
alter table public.leftovers alter column photo_scale_path drop not null;

-- Classifica somente o histórico; não transforma registros antigos em produção de proteína.
update public.production_batches
   set production_kind = 'LEGACY_ITEM'
 where production_kind is null
   and menu_item_id is not null;

update public.production_batches
   set production_kind = 'PROTEIN',
       produced_protein_kg = coalesce(produced_protein_kg,actual_use_kg),
       stage = coalesce(stage,'CLEAN'),
       production_operation = coalesce(production_operation,'PREPARACAO'),
       stock_effect = false
 where production_kind is null
   and menu_item_id is null;

alter table public.production_batches alter column production_kind set default 'PROTEIN';
alter table public.production_batches alter column stage set default 'CLEAN';
alter table public.production_batches alter column production_operation set default 'PREPARACAO';

create index if not exists production_batches_unit_protein_period_v312
  on public.production_batches(unit_id,event_date,protein_id,location);

create index if not exists production_batches_protein_mode_v312
  on public.production_batches(unit_id,event_date,protein_id)
  where production_kind='PROTEIN';

-- Sobra continua sendo exclusivamente posição física de proteína no fechamento.
alter table public.leftovers add column if not exists stage text;
alter table public.leftovers add column if not exists closing_balance boolean not null default false;
create index if not exists leftovers_closing_protein_v312
  on public.leftovers(unit_id,event_date,protein_id,location,stage)
  where closing_balance=true;

alter table public.production_batches replica identity full;
alter table public.leftovers replica identity full;
notify pgrst,'reload schema';
commit;

select
 'PF_V312_PRODUCAO_PROTEINA_OK' as status,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='production_batches' and column_name='production_kind') as production_kind_ok,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='production_batches' and column_name='produced_protein_kg') as production_kg_ok,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='production_batches' and column_name='stage') as production_stage_ok,
 exists(select 1 from information_schema.columns where table_schema='public' and table_name='leftovers' and column_name='closing_balance') as sobra_checkpoint_ok;
