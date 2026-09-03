# Migração para ProteínaFlow V3 sem perda de dados

O V3 não recria o banco. Ele adiciona campos ao esquema atual e usa os mesmos IDs de empresa, unidade, usuários, proteínas, lançamentos, XMLs, fotos e inventários.

## O que permanece intacto

- organizações e unidades;
- usuários e perfis;
- proteínas e custos;
- recebimentos;
- beneficiamentos históricos;
- transferências;
- produção;
- sobras;
- perdas;
- inventários;
- XMLs importados e mapeamentos;
- fichas técnicas existentes;
- evidências/fotos;
- audit log.

## Compatibilidade histórica

Beneficiamentos antigos são marcados como `LEGACY_FULL` e mantêm a semântica anterior. A nova lógica setorial é ativada pela `sector_cutover_date`. Vendas anteriores a essa data continuam sendo tratadas pela lógica legada; vendas a partir da data de corte usam Sushi Bar/Poke/Cozinha.

Novos lançamentos de Produção têm `stock_effect=false`: continuam medindo teórico x real, mas o XML é a baixa teórica oficial para não descontar a mesma proteína duas vezes.

## Implantação dos novos setores

Como o sistema antigo não sabia quanto do saldo estava fisicamente em Sushi Bar, Poke ou Cozinha, essa distribuição não é inventada. No primeiro fechamento do V3 faça inventário físico dos quatro locais. Essas contagens viram o ponto de verdade e as movimentações seguintes atualizam os saldos.
