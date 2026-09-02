# ProteínaFlow V3.12

Versão orientada a **controle e conciliação de proteínas**. Produção e Sobra são lançamentos de proteína, não de item de venda. Os itens vendidos continuam existindo somente em **Itens & Fichas** para cruzamento com XML.

## Conciliação

`Estoque inicial + Entradas + Transferências recebidas - Transferências enviadas - Perdas - Outras baixas válidas - Estoque final físico = Consumo físico reconciliado`

O resultado é comparado a:

- **Produção apontada em kg de proteína**;
- **Consumo teórico XML = quantidade vendida × gramatura da ficha**.

O sistema mantém o mesmo Supabase e preserva os dados existentes.
