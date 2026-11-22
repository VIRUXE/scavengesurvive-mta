# Blindagem de veículos

![O Airstream rebocável atrelado a um Bobcat, com uma Botija de gás e uma Máquina de soldar ao lado](images/scenes/airstream.png)

![Painel metálico](images/items/20301_imcmptrkdrl_las_def.png) ![Máquina de soldar](images/items/20202_welder.png) ![Cilindro de gás](images/items/19816_oxygencylinder1.png) ![Rebarbadora](images/items/20206_grinder.png)

As [defesas](Defences) metálicas podem ser fixadas ao reboque **Airstream** onde se entra (ver [Veículos](Vehicles)) e soldadas com uma Máquina de soldar, de modo que a porta não possa ser forçada e o reboque não possa ser feito explodir. Nenhum outro veículo aceita blindagem por enquanto. Para a fechadura da porta do reboque em si, ver [Reparações e fechaduras](Repairing-and-Locks).

## Que defesas {#which-defences}
Só se podem soldar defesas metálicas. Os painéis do corpo assentam rentes à carcaça no sítio para onde apontas; as duas portas só vão na porta do próprio reboque, esticadas para encaixar, e abrem com ela.

| Defesa | Vai em | Pontos de vida quando nova | Gás para a soldar |
|:--|:--|--:|--:|
| Painel metálico | corpo | 5 | 2,2 kg |
| Chapa ondulada | corpo | 6 | 2,6 kg |
| Painel metálico pequeno | corpo | 5 | 2,2 kg |
| Portão metálico | corpo | 4 | 1,8 kg |
| Porta de caixote | a porta | 5 | 2,2 kg |
| Porta de navio | a porta | 9 | 4,0 kg |

Uma Rampa de madeira, um Painel isolado, uma Porta isolada ou uma Porta metálica são recusados (*Só se podem soldar defesas metálicas*), e o mesmo acontece com a Chapa ondulada enferrujada, uma chapa de 3,8 por 3 m maior do que qualquer face do reboque. Um painel traz os pontos de vida que lhe restam, por isso um painel danificado protege menos do que um novo.

## 1. Prender {#1-attach}
Segura a defesa junto ao reboque e prime `F` (a lista de teclas diz *Prender ao reboque*). Um fantasma do painel segue o sítio para onde a tua câmara olha, rente à pele do reboque e em tamanho real. Prime `F` outra vez para o fixar ali (*Prender aqui*; tens de estar a menos de 4,5 m do sítio), ou `N` para cancelar. Afastares-te também cancela.

O fantasma fica vermelho e recusa prender-se quando sobrepõe outra defesa, fica a pender para fora do reboque, tapa a porta ou aponta para uma superfície interior; uma Porta de caixote ou uma Porta de navio só encaixa na porta, e nada mais encaixa.

Um painel preso **ainda não é blindagem**: não protege nada, um Pé de cabra arranca-o outra vez em 3 segundos (*Painel arrancado*) e qualquer explosão derruba-o para o chão. Mas já pesa no reboque: 180 kg por painel, e o veículo que reboca o reboque perde 8 % da aceleração do motor por painel, nunca abaixo de 40 %.

## 2. Soldar {#2-weld}
![Gerador](images/items/20204_generator.png) ![Botija de gás](images/items/20203_gas_bottle.png)

Soldar precisa de uma **Máquina de soldar** pousada no chão, de gás ligado a ela (um Cilindro de gás ou uma Botija de gás pousados a menos de 2,5 m) e de um **Gerador** com pelo menos 5 de combustível a menos de 8 m. A Máquina de soldar, o seu maçarico e a ligação do gás estão descritos em [Ferramentas](Tools#welder-and-welding-gas), o Gerador em [Máquinas](Machines#generator); uma Máquina de soldar nas tuas mãos só diz *Pousa a Máquina de soldar e pega no maçarico*, e o gás no teu inventário não conta.

Com as mãos vazias, dá um toque em `F` na Máquina de soldar para pegar no seu **maçarico** (*Pegar no maçarico*; manter `F` levanta a Máquina de soldar). O maçarico fica preso a um cabo de 5 m: se te afastares mais, pegares em qualquer coisa, entrares num veículo ou premires `N`, ele volta ao sítio (*O maçarico voltou para a Máquina de soldar*).

Com o maçarico na mão, prime `F` no reboque: o painel preso mais próximo, a menos de 1,6 m, é soldado. O gesto demora 8 segundos, menos com a [competência](Skills) Reparação (soldar não a treina). Cada soldadura queima 0,44 kg de gás por ponto de vida que o tipo de defesa pode ter (a tabela acima) e 5 de combustível do Gerador. Gás a menos diz *O gás ligado à Máquina de soldar não chega para esta defesa*; a falta de gerador diz *A Máquina de soldar precisa de um Gerador com combustível a menos de 8 metros*.

<!-- shot:shot-welding -->

## Fortificado {#fortified}
- A porta sozinha tem 1 ponto de vida. Cada painel soldado soma os seus pontos de vida à porta.
- Enquanto houver pelo menos um painel soldado, o reboque não sofre dano e não pode explodir, e um Pé de cabra ou uma Gazua eletrónica são recusados na porta (*A porta é blindada, um pé de cabra não resulta*).
- Uma explosão é absorvida pela blindagem: todos os painéis presos mas não soldados são derrubados para o chão; os soldados absorvem o dano, primeiro os painéis da porta, e um painel gasto até 0 fica destruído. Só quando não resta nenhum painel soldado é que o ponto de vida da própria porta leva o que sobra, e perdê-lo parte a fechadura da porta (uma chave cortada para ela deixa de servir e um teclado numérico é removido). Ver [Explosivos](Explosives).

## Tirar a blindagem {#taking-armour-off}
- **Painel não soldado**: um Pé de cabra, 3 segundos. Cai no chão ao lado do reboque.
- **Painel soldado**: uma **Rebarbadora** na mão, `F` no reboque (*Rebarbar painel*): uma passagem de 20 segundos no painel soldado mais próximo. Cada passagem gasta uma carga de uma **Bateria de ferramenta** (3 cargas quando nova) e desgasta um **Disco de corte** (6 passagens quando novo; um disco gasto desaparece), ambos tirados do teu inventário ou da mala que trazes vestida. Seis passagens cortam o painel (*Rebarbagem: n de 6 passagens cortadas* depois de cada uma); cai para o chão sem soldadura, com os pontos de vida que tinha. As passagens ficam no painel, por isso o corte pode ser terminado mais tarde ou por outra pessoa. Se te afastares durante uma passagem, ela cancela-se e não se gasta nada.

![Bateria de ferramenta](images/items/20209_tool_battery.png) ![Disco de corte](images/items/20207_grind_disc.png)

## Botijas de gás no reboque {#gas-bottles-on-the-trailer}
As botijas nos dois suportes em A do Airstream estão guardadas, não em uso: para soldar com uma, tira-a e pousa-a junto à Máquina de soldar. Os suportes estão descritos em [Casas e reboques](Houses-and-Trailers#the-towable-airstream).

Ver também [Defesas](Defences), [Ferramentas](Tools) e [Reparações e fechaduras](Repairing-and-Locks).
