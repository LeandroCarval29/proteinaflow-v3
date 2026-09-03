# ProteínaFlow V3 · 3.12.0

- Corrigido erro de validação XML: `parseXmlText is not defined`.
- Produção passa a ser exclusivamente por **proteína**, setor, estágio e peso; item de venda não faz parte do lançamento de Produção.
- Sobra permanece exclusivamente como posição física de **proteína** no fechamento.
- Central → Sushi Bar entra automaticamente como **LIMPO** no destino, enquanto o estoque Central é baixado do estágio pré-limpo.
- Adicionados `from_stage` e `to_stage` nas transferências para representar mudança de estágio sem distorcer o estoque.
- Sushi Bar → Poke/Cozinha permanece transferência de proteína limpa.
- Novo painel de beneficiamento automático: base pré-limpa transferida, Poke, Cozinha, perda de limpeza, quantidade limpa destinada ao Sushi Bar, rendimento final, rendimento total e custo final/kg.
- Rendimento total = rendimento pré-limpeza × rendimento da limpeza final.
- Custo final/kg = custo pré-limpo/kg ÷ rendimento final.
- Produção por proteína é apenas controle operacional (`stock_effect=false`); consumo teórico continua vindo do XML × ficha, evitando dupla baixa.
- Relatório completo recebe a aba `BENEF_AUTO`.
- Dados históricos permanecem preservados.
