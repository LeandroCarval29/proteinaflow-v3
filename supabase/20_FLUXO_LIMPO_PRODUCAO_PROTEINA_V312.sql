-- ProteínaFlow V3 · 3.12.0
-- Fluxo Central → Sushi Bar com mudança de estágio e Produção por proteína.
-- MIGRAÇÃO NÃO DESTRUTIVA: não apaga ou recria lançamentos existentes.
-- Pode ser executada novamente.

begin;

-- Transferência precisa poder sair de um estágio e entrar em outro.
-- Ex.: Central sai como PRÉ-LIMPO e Sushi Bar recebe como LIMPO.
alter table public.stock_movements add column if not exists lot text;
alter table public.stock_movements add column if not exists from_stage text;
alter table public.stock_movements add column if not exists to_stage text;
alter table public.stock_movements add column if not exists benefit_mode text;

update public.stock_movements
set from_stage = coalesce(from_stage, stage),
    to_stage = coalesce(to_stage, stage),
    benefit_mode = coalesce(benefit_mode, 'TRANSFER')
where from_stage is null or to_stage is null or benefit_mode is null;

create index if not exists stock_movements_unit_flow_v312
  on public.stock_movements(unit_id,event_date,protein_id,from_location,to_location);
create index if not exists stock_movements_unit_lot_v312
  on public.stock_movements(unit_id,protein_id,lot)
  where lot is not null;

-- Produção deixa de depender de item de venda para os novos lançamentos.
-- Dados antigos por item continuam preservados.
alter table public.production_batches add column if not exists production_type text;
alter table public.production_batches add column if not exists stage text;

update public.production_batches
set production_type = coalesce(
      production_type,
      case when menu_item_id is null then 'PROTEIN_CONTROL' else 'LEGACY_ITEM' end
    ),
    stage = coalesce(stage, 'CLEAN')
where production_type is null or stage is null;

-- Fotos continuam opcionais.
alter table public.production_batches alter column photo_item_path drop not null;
alter table public.production_batches alter column photo_scale_path drop not null;
alter table public.leftovers alter column photo_item_path drop not null;
alter table public.leftovers alter column photo_scale_path drop not null;

alter table public.stock_movements replica identity full;
alter table public.production_batches replica identity full;

notify pgrst,'reload schema';
commit;

select
  'PF_V312_FLUXO_OK' as status,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='stock_movements' and column_name='from_stage') as from_stage_ok,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='stock_movements' and column_name='to_stage') as to_stage_ok,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='stock_movements' and column_name='benefit_mode') as benefit_mode_ok,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='production_batches' and column_name='production_type') as production_protein_ok,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='production_batches' and column_name='stage') as production_stage_ok;
