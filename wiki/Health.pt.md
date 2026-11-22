# Saúde

A tua personagem tem três medidores: saúde, fome e sede. Todos são guardados com a personagem e mostrados no HUD e no painel Estado de saúde do inventário (abre-o com `H`).

A saúde vai de 0 a 100. A 0 morres. Uma personagem acabada de criar pela primeira vez começa com 90 de saúde e 80 de fome e sede; uma personagem criada depois de uma morte começa com 100 de saúde e 40 de fome e sede.

## Regeneração {#regeneration}
A saúde regenera uma vez por segundo, mas só enquanto **não estás a sangrar**. A quantidade depende do **mais baixo** entre a fome e a sede, por isso um estômago cheio não serve de nada a uma personagem com sede:

| O mais baixo entre fome e sede | Saúde por segundo (sem hemorragia) |
|--:|--:|
| 100 | cerca de 0,19 |
| 50 | cerca de 0,10 |
| 20 | cerca de 0,04 |

Uma [infeção de ferida](Infection) reduz a regeneração para metade. A [Morfina e a Adrenalina](Drugs) somam saúde por cima disso.

## Fome {#hunger}
A fome desce a cada segundo, tanto mais depressa quanto mais depressa te moves:

| Atividade | Fome perdida por segundo |
|:--|--:|
| Parado | 0,004 |
| A andar ou a correr devagar (até cerca de 13 km/h) | 0,0048 |
| A correr (até cerca de 19 km/h) | 0,0072 |
| A fazer sprint (mais rápido) | 0,0088 |
| Num veículo | 0,0008 |

Uma [infeção alimentar](Infection) acrescenta 0,004 por segundo. Vê [Comida e bebida](Food-and-Drink) para saberes como voltar a enchê-la.

Abaixo de 20 de fome começas a passar fome e perdes `(20 - fome) / 30` de saúde por segundo, até cerca de 0,67 por segundo com 0 de fome. A fome é uma causa de morte.

## Sede {#thirst}
A sede desce da mesma maneira, mais uma vez e meia mais depressa: 0,006 por segundo parado, 0,0072 a andar, 0,0108 a correr, 0,0132 em sprint e 0,0012 num veículo. Uma barra cheia dura cerca de quatro horas e meia parado e pouco mais de duas horas em sprint.

Abaixo de 20 de sede perdes `(20 - sede) / 30` de saúde por segundo, além do que a fome te tira. A desidratação é uma causa de morte. A partir de 30, ambas as necessidades fazem-se sentir antes de magoar: o ecrã esmorece e fica desfocado, os sprints ficam mais curtos e a barra no HUD começa a pulsar (pisca a vermelho abaixo de 20).

## Maneiras de perder saúde {#ways-to-lose-health}
- [Hemorragias e feridas](Bleeding-and-Wounds): cada ferimento soma à tua taxa de hemorragia, que retira saúde a cada segundo.
- Fome e desidratação, como acima.
- A droga Ar (de uma seringa vazia) custa 1 de saúde em metade dos segundos; vê [Drogas](Drugs).
- O veneno do gás da [Nuvem tóxica](Toxic-Cloud): a partir de 40 % de veneno tira saúde, depressa a partir de 80 %.
- Pouca saúde escurece o ecrã. Os [Analgésicos e a Adrenalina](Drugs) escondem a escuridão.

## Inconsciência {#unconsciousness}
Um ferimento pode deixar-te inconsciente. Não te podes mover, disparar nem usar itens enquanto estás desmaiado; o desmaio dura de 1,5 a 120 segundos, e um segundo desmaio enquanto ainda estás inconsciente soma-se ao tempo (nunca além de 120 segundos). A probabilidade e a duração crescem com o número de ferimentos que tens, com a tua taxa de hemorragia e com o quão baixa está a tua saúde, e dependem de onde foste atingido: um tiro na cabeça é de longe o que mais provavelmente te desmaia, as pernas o que menos. Um chapéu posto reduz em 60 % a probabilidade de desmaio de um tiro na cabeça.

O painel Estado de saúde mostra a tua probabilidade atual como "% Inconsciente".

Enquanto estás inconsciente, outros jogadores podem:

- tirar-te o item das mãos com a tecla de interação (vê [Render-se e desarmar](Surrender-and-Disarm));
- acordar-te de imediato injetando-te uma [seringa](Drugs) de Adrenalina.

## Cura {#healing}
Pára primeiro a hemorragia e depois cura-te. As Ligaduras, os Kits médicos e as Malas de médico estão explicados em [Medicina](Medical); em resumo:

- A **Ligadura** e a **Ligadura antisséptica** reduzem a taxa de hemorragia.
- O **Kit médico** reduz a taxa de hemorragia e remove ferimentos.
- A **Mala de médico** pára a hemorragia, remove ferimentos e dá uma droga.
- Comer e beber mantêm a fome e a sede em alta, o que mantém a regeneração rápida.

## Morte {#death}
A 0 de saúde a tua personagem morre para sempre: tudo o que levava cai à volta de um corpo e a personagem seguinte começa do zero, competências incluídas. Vê [Morte](Death). Sair a meio de um combate conta como morrer: vê [Desligar em combate](Combat-Log).
