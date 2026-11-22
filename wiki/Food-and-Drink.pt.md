# Comida e bebida

Comer aumenta o teu valor de fome e beber o da sede (ambos de 0 a 100, mostrados nas barras verde e azul do HUD e como `Fome` e `Sede` no inventário). Abaixo de 20, qualquer um dos dois custa vida, e a vida regenera com o mais baixo dos dois, ver [Saúde](Health).

Ficas com o que não te serve: a comida é recusada com *Não tens fome* a partir de 99 de fome, uma bebida com *Não tens sede* a partir de 99 de sede, e uma bebida que estás a beber aos goles pára sozinha quando já tiveres bebido o suficiente. A fruta ainda desce quando tens sede, o leite e os sumos quando tens fome, e o que nem é bebida (gasolina, aguarrás) pode sempre ser bebido.

## Comer {#eating}
Segura a comida nas mãos e prime a tecla de interagir (`F`), ou escolhe `Usar` no inventário. O item inteiro é comido de uma vez e consumido, e ganhas de uma só vez as dentadas vezes a comida por dentada. A pé e com as mãos livres, a tua personagem dá uma dentada (cerca de dois segundos); num veículo come-se simplesmente.

<!-- table:food -->
| Comida | Dentadas | Comida por dentada | Pode ser cozinhada | Infeta se crua |
|:--|--:|--:|:--|:--|
| Carne | 8 | 18,12 | sim | sim |
| Piza | 6 | 18,5 | sim | não |
| Piza | 6 | 18,3 | sim | não |
| Carne | 6 | 16,7 | sim | sim |
| Caixa de piza | 6 | 16,5 | sim | não |
| Cachorro-quente | 4 | 18 | sim | sim |
| Hambúrguer | 4 | 17,5 | sim | não |
| Hambúrguer | 4 | 16,25 | sim | sim |
| Hambúrguer | 4 | 16,25 | sim | não |
| Pão de forma | 10 | 6,32 | sim | não |
| Douradinhos | 10 | 6,3 | sim | não |
| Taco mexicano | 4 | 13,75 | sim | não |
| Gelado | 12 | 4,1 | não | não |
| Gelados de pau | 12 | 3,9 | não | não |
| Fiambre | 6 | 6,12 | sim | sim |
| Carne embalada | 4 | 6,7 | sim | sim |
| Bife | 4 | 6,49 | sim | sim |
| Aperitivos de queijo | 6 | 4 | não | não |
| Bolachas com pepitas de chocolate | 6 | 4 | não | não |
| Carne seca | 4 | 6 | não | não |
| Phat Chips | 6 | 4 | não | não |
| Pretzels | 6 | 3,5 | não | não |
| Barra EgoChaser | 3 | 6 | não | não |
| Laranja | 4 | 4,5 | não | não |
| Maçã verde | 4 | 4,5 | não | não |
| Maçã vermelha | 4 | 4,5 | não | não |
| Peixe | 4 | 4,5 | sim | sim |
| Banana | 3 | 5,5 | não | não |
| Limão | 4 | 4 | não | não |
| Amendoins salgados | 3 | 5 | não | não |
| Barra Meteorite | 3 | 5 | não | não |
| Barra Zebra | 3 | 5 | não | não |
| Cereais | 6 | 2,2 | não | não |
| Cereais | 6 | 2,2 | não | não |
| Rebuçados de fruta | 4 | 3 | não | não |
| Pão | 5 | 2,34 | sim | não |
| Tomate | 3 | 3 | sim | não |
| Fatia de bolo | 1 | 2,5 | sim | não |
<!-- /table:food -->

![Hambúrguer](images/items/2703_cj_burg_1.png) ![Cachorro-quente](images/items/19346_hotdog01.png) ![Carne](images/items/2804_cj_meat_1.png)

### Comida molhada e salgada {#wet-and-salty-food}
Alguma comida também mexe na sede:

| Comida | Sede |
|:--|--:|
| Gelado | +12 |
| Barras de gelado, Laranja | +10 |
| Tomate | +8 |
| Maçã vermelha, Maçã verde | +6 |
| Limão | +5 |
| Banana | +3 |
| Phat Chips, Cheesy Puffs | -4 |
| Twisted Pretzels, Amendoins salgados | -5 |
| Carne seca | -6 |

### Comida crua e cozinhada {#raw-and-cooked-food}
A comida que pode ser cozinhada tem `(Crua)` ou `(Cozinhada)` no nome.

- Comer comida crua dá apenas **70 %** do seu valor alimentar.
- A comida marcada com "Infects when raw" na tabela acima também te dá uma [infeção alimentar](Infection).
- A comida cozinhada, e a que não pode ser cozinhada, é sempre comida por inteiro e nunca infeta.

Com comida crua nas mãos junto a uma Fogueira ou a um Grelhador, `F` põe-na ao lume em vez de a comeres. Uma Fogueira cozinha em 60 segundos e um Grelhador em 30. Ver [Fogueira e grelhador](Campfire-and-BBQ).

## Beber {#drinking}
![Garrafa](images/items/1543_cj_beer_b_2.png) ![Lata](images/items/2601_cj_juice_can.png) ![Pacote de leite](images/items/19569_milkcarton1.png) ![Sumo de laranja](images/items/19563_juicebox1.png)

Segura um recipiente com algo de beber lá dentro (uma Garrafa, uma Lata, um Pacote de leite, uma caixa de sumo, uma garrafa de vinho, etc.) e mantém `F` premido. Cada gole demora 1 segundo e leva 0,2 litros (um último gole menor dá a sua parte); continua a premir para continuar a beber. Largar a tecla, mexer-te mais do que um passo ou mudar o que seguras interrompe-o, e um recipiente vazio diz *Está vazio*. Não podes beber num veículo nem inconsciente, e só com o recipiente nas mãos: `Usar` num recipiente da lista do inventário não faz nada. O nome do recipiente mostra o que tem dentro e quanto: `Garrafa (Água 0.4/0.50)` ou `Garrafa (Vazio)`.

Um **Jerricã de gasolina** nunca se bebe: `F` com um na mão enche-o numa bomba ou despeja-o num veículo, máquina, grelhador ou Molotov vazio ([Combustível](Fuel)). A Almotolia e o frasco de Detergente podem ser bebidos, ao custo indicado abaixo.

### Recipientes {#containers}
| Recipiente | Contém | Encontra-se com |
|:--|--:|:--|
| Garrafa | 0,5 L | Água (o mais frequente), Sumo de laranja, Água com gás, Sumo de limão, Limonada ou Laranjada |
| Lata | 0,33 L | o mesmo que uma Garrafa |
| Garrafa de leite | 0,57 L | Leite |
| Pacote de leite | 1 L | Leite |
| Sumo de maçã | 1 L | Sumo de maçã |
| Sumo de laranja | 1 L | Sumo de laranja |
| Vinho | 0,75 L | Vinho tinto ou Vinho branco |
| Uísque | 1,5 L | Uísque |
| Champanhe | 1,5 L | Champanhe |
| Detergente | 0,33 L | Aguarrás |
| Almotolia | 16 L | Óleo |
| Jerricã de gasolina | 20 L | Gasolina |
| Ketchup, Mostarda | 0,5 L | nada: está sempre vazio |

Sede e fome ganhas por gole de 0,2 L:

| Líquido | Sede por gole | Fome por gole |
|:--|--:|--:|
| Água | 12 | 0 |
| Água com gás | 11 | 0 |
| Laranjada | 10 | 2,5 |
| Sumo de laranja, Sumo de maçã, Limonada | 10 | 2 |
| Leite | 8 | 4 |
| Sumo de limão | 8 | 1 |
| Vinho tinto ou branco | 4 | 0,4 |
| Champanhe | 4 | 0,2 |
| Proteína em pó | 0 | 4,5 |
| Açúcar | 0 | 0,8 |
| Bicarbonato de sódio | 0 | 0,1 |

Assim, uma Garrafa de 0,5 L de água dá 30 de sede, uma Lata 20, e um pacote de 1 L de sumo 50 de sede e 10 de fome.

Nem tudo o que enche um recipiente é uma bebida. Os destilados e a água do mar **custam** sede, o resto custa fome:

| Líquido | Por gole |
|:--|--:|
| Uísque | -3 de sede |
| Água do mar | -40 de sede |
| Gasolina, Gasóleo, Óleo | -8 de fome |
| Etanol | -44,1 de fome |
| Aguarrás, Ácido clorídrico, Mistura de termite | -101 de fome |

Nenhum dos valores pode descer abaixo de 0, mas uma penalização grande esvazia-o de imediato e pode começar a deixar-te à fome.

### Outros usos de uma garrafa {#other-uses-of-a-bottle}
- A água de uma Garrafa ou Lata rega um Vaso: `F` junto ao vaso despeja 0,1 L nele, e com um vaso ao alcance isso tem prioridade sobre beber. Ver [Jardinagem](Gardening).
- A gasolina despejada de um Jerricã de gasolina para um Molotov vazio faz um Molotov; ver [Explosivos](Explosives).
- O Purificador de água transforma garrafas de água do mar em garrafas de água; ver [Máquinas](Machines).
