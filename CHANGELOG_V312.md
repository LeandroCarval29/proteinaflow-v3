# ProteínaFlow V3.12 — Produção e Sobra por Proteína + Conciliação

- Produção não possui mais item de venda: registra **proteína + setor + estágio + kg produzido/preparado**.
- Sobra continua exclusivamente como **proteína física de fechamento** e vira checkpoint de estoque.
- Itens e fichas técnicas foram retirados da Produção e movidos para o módulo **Itens & Fichas**.
- Nova conciliação em 3 vias: **Consumo Físico Reconciliado × Produção Apontada × Consumo Teórico XML**.
- Perdas registradas são descontadas explicitamente na equação física.
- Produção não baixa estoque novamente; o XML continua sendo a referência teórica por venda/ficha.
- Análise por período preservada, partindo da última posição física anterior e acumulando todas as movimentações.
- Relatórios de Produção, CMV, Resumo e Conciliação atualizados para kg de proteína.
- Registros históricos por item permanecem preservados como `LEGACY_ITEM`.
