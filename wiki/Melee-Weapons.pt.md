# Armas corpo a corpo

As armas corpo a corpo acertam à distância de um braço (o servidor aceita um golpe a cerca de 2 m). Não têm valores de dano. Cada arma tem uma **taxa de hemorragia**, o sangramento da ferida que abre, e um multiplicador de **desmaio** que entra na probabilidade de deixar a vítima inconsciente. Um golpe também retira de imediato à vítima a taxa de hemorragia vezes 100 em vida, por isso uma arma com taxa de hemorragia de 0,35 custa 35 de vida mais a hemorragia que se segue. Um golpe na cabeça duplica a taxa de hemorragia. Vê [Hemorragias e feridas](Bleeding-and-Wounds) para saber como funcionam as feridas e [Medicina](Medical) para as tratar.

![Taco de basebol](images/items/336_bat.png) ![Faca de combate](images/items/335_knifecur.png) ![Espada](images/items/339_katana.png) ![Taco com pregos](images/items/2045_cj_bbat_nails.png) ![Marreta](images/items/19631_sledgehammer1.png) ![Pá](images/items/337_shovel.png)

Os punhos também contam como arma, com taxa de hemorragia de 0,001 e multiplicador de desmaio de 0,5. Uma arma com taxa de hemorragia 0 não abre ferida nenhuma.

## Hemorragia e desmaio {#bleed-and-knockout}
As armas afiadas fazem sangrar, as armas contundentes deixam inconsciente.

| Arma | Taxa de hemorragia | Desmaio |
|:--|--:|--:|
| Motosserra | 0,93 | 10 |
| Espada | 0,44 | 1,5 |
| Espada do caraças | 0,39 | 0,15 |
| Faca de combate | 0,35 | 1,4 |
| Taco com pregos | 0,30 | 3,0 |
| Faca de cozinha | 0,29 | 0 |
| Chave de fendas | 0,24 | 0 |
| Pá | 0,21 | 4,0 |
| Ancinho | 0,18 | 1,3 |
| Garfo | 0,17 | 0 |
| Vassoura | 0,11 | 1,1 |
| Taco de basebol | 0,09 | 3,5 |
| Bengala (tamanho 3, a simples) | 0,08 | 1,25 |
| Taco de bilhar | 0,08 | 3,7 |
| Taco de golfe | 0,07 | 3,5 |
| Bengala (a bengala de andar) | 0,06 | 2,4 |
| Soqueira | 0,05 | 2,0 |
| Bastão | 0,03 | 2,4 |
| Pé de cabra | 0,03 | 1,25 |
| Marreta | 0,03 | 2,9 |
| Martelo | 0,02 | 1,3 |
| Chave de rodas | 0,01 | 1,2 |
| Tacho | 0,01 | 1,05 |
| Frigideira | 0,01 | 1,06 |
| Dildo, Flores | 0,01 | 0 |
| Espátula | 0,001 | 0 |
| Caixa de correio, Pistola de choques | 0 | - |

A Motosserra funciona a gasolina como arma: prime `F` junto a um Jerricã de gasolina no chão para a abastecer. Abater árvores para obter Troncos de madeira não precisa de gasolina nenhuma; vê [Árvores e madeira](Trees-and-Wood).

A Pistola de choques não abre ferida: carregada com uma Bateria de ferramenta, o seu próximo soco deixa a vítima inconsciente durante 60 segundos. Vê [Itens pequenos](Small-Items#stun-gun).

## Desmaios {#knockouts}
A probabilidade de desmaio cresce com o multiplicador de desmaio da arma, com o número de feridas que a vítima já tem e com a sua taxa total de hemorragia. Onde acertas conta mais do que tudo: um golpe na cabeça deixa alguém inconsciente com muito mais probabilidade do que um golpe no corpo, e um chapéu vestido reduz essa probabilidade (vê [Saúde](Health)). Os jogadores inconscientes podem ser acordados com itens [médicos](Medical) e roubados do que seguram ([Render-se e desarmar](Surrender-and-Disarm)).

Muitos itens corpo a corpo pequenos (Espátula, Garfo, Tacho e afins) não têm outro uso mas podem ser desfeitos numa [Máquina de sucata](Scrap).

Vê também [Armas de fogo](Firearms), [Coldre](Holster) e [Catálogo de itens](Item-Catalogue).
