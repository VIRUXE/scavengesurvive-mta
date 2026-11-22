# Jardinagem

![Sementes](images/items/2663_cj_bs_bag.png) ![Vaso](images/items/2203_plant_pot_1.png) ![Tomate](images/items/19577_tomato1.png) ![Maçã vermelha](images/items/19575_apple1.png) ![Banana](images/items/19578_banana1.png)

A jardinagem faz crescer fruta e legumes a partir de um saco de **Sementes** num **Vaso**, com água de uma garrafa e uma Faca de combate para colher. As sementes e os vasos encontram-se como saque e em [entregas de abastecimentos](Supply-Drops).

## Sementes {#seeds}
Um saco de Sementes (tamanho 2) tem **0 a 4 sementes de um só tipo**, mostrado no nome: `Sementes (3, Tomate)` ou `Sementes (Vazio)`. Os tipos:

| Sementes | Cultura | Fases de crescimento | Água necessária |
|:--|:--|--:|--:|
| Tomate | Tomate | 4 | 0,4 L |
| Maçã | Maçã vermelha ou Maçã verde | 5 | 0,5 L |
| Limão | Limão | 5 | 0,5 L |
| Laranja | Laranja | 5 | 0,5 L |
| Banana | Banana | 6 | 0,6 L |
| Desconhecido | nada: cresce uma planta ou arbusto, mas não há colheita | 0 | - |

Mais de metade dos tipos de semente são *Desconhecido*: crescem uma planta decorativa e nada mais.

## Plantar {#planting}
1. Larga o Vaso (tamanho 4, levado com as duas mãos) onde o quiseres. Só um vaso pousado no chão faz crescer alguma coisa.
2. Segura as Sementes e prime `F` no vaso: *Sementes postas no vaso*. Uma semente sai do saco. Um saco vazio não faz nada. Sementes postas num vaso que já tem uma planta fazem-na recomeçar com a nova semente.
3. Rega-o: segura um recipiente com **Água** (uma Garrafa ou uma Lata) e prime `F` no vaso: *1 de água posta no vaso*. Cada pressão deita 0,1 L. Um recipiente vazio ou com outra coisa que não água é recusado. Com uma garrafa de água na mão perto de um vaso, `F` rega o vaso em vez de beberes da garrafa.

Um toque em `F` no vaso, de mãos vazias, mostra o estado: *Ativa*, *Tipo de semente*, *Água* e *Crescimento*, como `Crescimento: 2/4`.

## Crescer {#growing}
A cada **10 minutos** cada vaso no mundo avança uma fase:

- com água dentro, a planta bebe 1 de água e cresce 1 fase;
- sem água, definha 1 fase, e a 0 a planta morre e o vaso fica vazio outra vez.

Assim, um Tomate precisa de 4 de água e 40 minutos, uma Banana de 6 de água e uma hora. Mantém pelo menos 1 de água no vaso em todas as fases, incluindo a primeira: um vaso acabado de plantar e deixado seco está vazio 10 minutos depois. Água a mais não faz mal e gasta-se à medida que a planta bebe.

Um rebento aparece depois da primeira fase e cresce com a planta; na última fase a planta completa fica no vaso. O vaso continua a crescer enquanto estás longe e entre reinícios do servidor. As sementes *Desconhecido* mostram logo a planta; também ela morre se o vaso ficar seco.

## Colher {#harvesting}
Segura uma **Faca de combate** e prime `F` no vaso:

- uma planta crescida dá a sua colheita, que aparece no vaso, e o vaso fica vazio: *Planta colhida*;
- uma planta nova: *A planta ainda não cresceu por completo.*;
- um vaso vazio: *O vaso não tem nenhuma planta ativa.*

Uma Faca numa planta *Desconhecido* limpa-a sem colheita.

As colheitas são comida normal ([Comida e bebida](Food-and-Drink)): um Tomate dá 3 dentadas de 3 de comida e pode ser cozinhado; as maçãs e as laranjas 4 dentadas de 4,5, um Limão 4 dentadas de 4, uma Banana 3 dentadas de 5,5. As sementes de tomate dão mais pela menor quantidade de água.

## Mudar um vaso {#moving-a-pot}
Mantém `F` meio segundo no vaso, de mãos vazias, para o apanhares. Leva-se com as duas mãos e a planta vai com ele, voltando a crescer quando o vaso estiver outra vez no chão. Como outros itens de duas mãos, não vai para o inventário nem para uma mochila, mas a mala de um veículo ou uma caixa aceitam-no; vê [Inventário](Inventory).
