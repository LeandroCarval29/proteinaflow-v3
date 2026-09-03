# ProteínaFlow V3 · 3.12.0

Versão focada em conciliação diária de proteínas, com Produção e Sobra por proteína, XML corrigido e beneficiamento final inferido automaticamente.

## Fluxo operacional

1. Recebimento: proteína inteira no Estoque Central.
2. Beneficiamento: pré-limpeza manual no Central (inteiro → pré-limpo).
3. Transferência Central → Sushi Bar: sai do Central como pré-limpo e entra no Sushi Bar com status **LIMPO**.
4. Transferências Sushi Bar → Poke/Cozinha: distribuição de proteína limpa.
5. Perdas de limpeza no Sushi Bar entram no cálculo do rendimento final.
6. Sobra/Inventário registra a posição física final por proteína.
7. XML cruza vendas × fichas técnicas para calcular consumo teórico e CMV.

## Instalação

- Preserve o `assets/config.js` que já funciona no seu ambiente. Ele não está incluído no pacote.
- Se ainda não executou o backend de XML, execute `supabase/19_FECHAMENTO_ANALISE_XML_V311.sql`.
- Execute `supabase/20_FLUXO_LIMPO_PRODUCAO_PROTEINA_V312.sql`.
- Publique os demais arquivos no repositório `proteinaflow-v3`.

## Correção XML

A V3.12 inclui a função `parseXmlText`, ausente na V3.11 e responsável pelo erro `parseXmlText is not defined` durante a validação do ZIP.
