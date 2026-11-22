# Máquinas

![As máquinas: Máquina de sucata, Máquina de refinação, Purificador de água e Gerador, com sucata à frente](images/scenes/scrapyard.png)

Três máquinas transformam lixo em material útil: a Máquina de sucata, a Máquina de refinação e o Purificador de água. Cada uma tem um contentor de 12 espaços e um depósito de combustível que enches com um [Jerricã de gasolina](Fuel). Constroem-se no chão, ver [Construção](Constructing), e todos os itens que fazem estão descritos em [Sucata](Scrap).

| Máquina | Aceita | Produz |
|:--|:--|:--|
| ![Máquina de sucata](images/items/920_y_generator.png) **Máquina de sucata** | Quase tudo; os itens sem valor de sucata são destruídos | Sucata, uma peça por ponto de valor de sucata (no máximo 11 por cozedura) |
| ![Máquina de refinação](images/items/943_generator_low.png) **Máquina de refinação** | Só Sucata | Um Metal refinado por cada Sucata |
| ![Purificador de água](images/items/958_cj_chip_maker.png) **Purificador de água** | Só garrafas de água do mar; hoje nada enche uma garrafa com água do mar, por isso está parado | Uma garrafa de água limpa por cada garrafa, com a mesma quantidade |

## Onde encontrar uma {#where-to-find-one}
Uma Máquina de sucata e uma Máquina de refinação estão no ferro-velho de Whetstone, a leste do Monte Chiliad (na zona de Flint County, ver [Mundo e zonas](World-and-Zones)); se uma for desmontada ou levada, é reposta quando o servidor reinicia. Podes construir a tua com uma Chave de fendas a partir das peças listadas em [Construção](Constructing). A Máquina de refinação precisa de um Painel metálico grande entre as peças, que é o que a distingue da Máquina de sucata. Uma máquina construída pode ser desmontada com um Pé de cabra e devolve as suas peças.

![As duas máquinas fixas no ferro-velho de Whetstone](images/places/scrapyard.png)

## Usar uma máquina {#using-a-machine}
- **Toca `F`** na máquina para abrir o contentor e carregá-lo. Se estiver a funcionar, em vez disso dizem-te quanto tempo falta. A Máquina de refinação e o Purificador de água recusam os itens que não aceitam.
- **Mantém `F`** para abrir o menu, que mostra a quantidade de combustível e um botão **Start**. A máquina tem de ter pelo menos um item e 3,5 unidades de combustível por cada item lá dentro; caso contrário dizem-te quanto precisa por item.
- **Mantém `F` com um Jerricã de gasolina na mão** para verter gasolina no depósito. O depósito leva 100 unidades; a barra enche enquanto mantiveres a tecla e ficares a menos de 4 m, ou até o depósito estar cheio ou o jerricã vazio.

## Cozedura {#cooking}
Uma cozedura demora 90 segundos por item lá dentro mais até 30 segundos extra, e gasta 3,5 unidades de combustível por item, retiradas do depósito quando a cozedura acaba. Uma carga completa de 12 itens precisa portanto de 42 unidades e demora 18 a 18,5 minutos. Enquanto uma máquina trabalha deita fumo, e a cozedura continua enquanto estás ausente, mesmo depois de um reinício do servidor. Quando acaba, o conteúdo do contentor é substituído pelos resultados; tira-os como de qualquer outro contentor ([Contentores e sacos](Containers-and-Bags)).

- A Máquina de sucata soma o valor de sucata de tudo o que tem lá dentro (ver [Sucata](Scrap)) e produz essa quantidade de Sucata, no máximo 11. Um item sem valor de sucata não soma nada e é destruído.
- A Máquina de refinação produz exatamente um Metal refinado por cada Sucata: 12 Sucatas dão 12 Metais refinados.
- O Purificador de água transforma cada garrafa de água do mar numa garrafa de água com a mesma quantidade, uma garrafa por garrafa.

## Gerador {#generator}
O Gerador é uma máquina só de combustível, sem contentor e sem cozedura. É uma unidade portátil: toca `F` nele de mãos vazias para o apanhar e põe-no onde precisares. Abastece-o mantendo `F` junto a ele com um Jerricã de gasolina (o mesmo depósito de 100 unidades); manter `F` de mãos vazias diz-te o combustível que tem. Alimenta a Máquina de soldar usada para montar blindagem num veículo: a Máquina de soldar puxa de um Gerador com combustível a menos de 8 m, e cada soldadura gasta 5 unidades. Ver [Ferramentas](Tools) e [Blindagem de veículos](Vehicle-Armour).
