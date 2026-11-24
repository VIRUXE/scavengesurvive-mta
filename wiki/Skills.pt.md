# Competências

As competências tornam mais rápidas as ações que repetes. Cada competência é um valor de 0 a 1, mostrado no canto inferior direito do ecrã com o seu nome e uma barra branca fina que enche à medida que a competência cresce (as dez mais altas, quando tens mais de dez).

## Como funcionam as competências {#how-skills-work}
- **As competências persistem.** São guardadas com a tua personagem (cerca de 10 em 10 segundos enquanto mudam, e quando sais do jogo), por isso sobrevivem a saídas e a reinícios do servidor. Só a morte as repõe: uma personagem nova começa sem competências.
- A barra de uma competência aparece depois da primeira ação concluída, a começar em 0. Concluir uma ação mostra durante cinco segundos um aviso do género `+Reparação`.
- De cada vez que **concluis** uma ação ligada a uma competência, a competência fecha 2 % da distância até 1: o novo valor é `antigo + 0,02 x (1 - antigo)`. As primeiras ações contam mais, as seguintes cada vez menos.
- De cada vez que **começas** uma dessas ações, o seu tempo é cortado em metade do valor da competência: `tempo x (1 - 0,5 x competência)`. Com 1,0, um trabalho de 3 segundos demora 1,5 segundos. Nada é mais rápido do que metade do tempo.
- Podes ter até 50 competências diferentes.

| Ações necessárias a partir de 0 | A competência chega a | Nível |
|--:|--:|:--|
| 6 | 0,10 | Adequado |
| 12 | 0,20 | Intermédio |
| 20 | 0,33 | Experiente |
| 54 | 0,66 | Mestre |
| 114 | 0,90 | Mestre |

## Níveis {#levels}
Cada competência tem um nível consoante o seu valor:

| Nível | Valor da competência |
|:--|:--|
| Novato | abaixo de 0,10 |
| Adequado | 0,10 a 0,20 |
| Intermédio | 0,20 a 0,33 |
| Experiente | 0,33 a 0,66 |
| Mestre | 0,66 ou mais |

## O que treina o quê {#what-trains-what}
Os tempos são o tempo de base e o que passa a ser com a competência a 1,0.

| Competência | Treinada por | O que acelera ou melhora |
|:--|:--|:--|
| Reparação | reparar um veículo | o gesto de reparar, de 3 s para 1,5 s; também o gesto de soldar blindagem num veículo, de 8 s para 4 s (soldar não a treina) |
| Construção | construir uma [defesa](Defences), montar um Motor ou um [teclado numérico](Keypads) numa defesa, montar um teclado numérico num veículo | construir ou remover uma defesa, de 10 s para 5 s; montar um Motor ou um teclado numérico, de 6 s para 3 s (remover uma defesa é acelerado mas não treina) |
| Medicina | curar com uma Ligadura suja, uma Ligadura antisséptica, um Kit médico ou uma Mala de médico, em ti ou noutro jogador (comprimidos e injeções não contam; ver [Hemorragias e feridas](Bleeding-and-Wounds)) | o gesto de curar, de 4 s para 2 s; reanimar um jogador inconsciente, de 6 s para 3 s |
| Pesca | uma mordidela que prenda na tua linha | a espera por uma mordidela (30 a 120 s) é cortada até metade, e a probabilidade de uma mordidela apanhar um peixe sobe de 30 % para 65 % |
| Silvicultura | abater uma árvore com uma Motosserra | velocidade de corte: com 1,0 uma árvore demora metade do tempo |
| Resistência | percorrer distância a pé, ver abaixo | um salto a correr ou a sprintar vai mais longe: a sua velocidade é multiplicada por `1 + 1,3 x competência`, até 2,3 vezes |
| Força | [empurrar um veículo](Vehicles#pushing) pelo menos 3 m (ganho total a partir de 15 m); trepar: cada 5.ª parede ou vedação transposta, ou cada 15 m subidos em escadas (no máximo um ganho de trepar por 10 s) | a velocidade do empurrão: 0,8 m/s sem treino, até 1,8 m/s com 1,0, antes da vida e do peso do veículo; o veículo mais pesado que consegues empurrar: 3000 kg sem treino, até 10 000 kg com 1,0 |
| O nome de um item | [fabricar](Constructing) esse item, no chão ou numa [bancada de trabalho](Workbench) | a mesma receita da próxima vez: o gesto de construir no chão, ou os 3,6 s por ingrediente da bancada; o desmantelamento desse item com o Pé de cabra também fica mais curto, sem treinar |

### Resistência {#endurance}
A Resistência ganha uma vez por cada 500 m corridos ou em sprint, por cada 200 m a nadar e por cada 10.º salto a pé, e nunca duas vezes em 10 segundos (um marco atravessado dentro dessa janela perde-se). Andar, agachar-se, conduzir e cair não contam. Cada segundo é classificado pela distância que percorreste nele: 2,5 m ou mais é correr e 5,5 m ou mais é sprint; menos é andar, que não rende nada; agachar-se, nadar, conduzir e cair contam-se à parte, e um segundo em que te moveste mais de 25 m a pé (75 m num veículo) é ignorado.

`/mstats` abre uma janela com a distância e o tempo desta sessão para cada tipo de movimento (andar, correr, sprint, agachar-se, nadar, conduzir, cair), os teus saltos e o tempo passado inconsciente; esses contadores repõem-se quando entras no jogo, a competência não. Ver [Comandos](Commands).

### Competências de fabrico {#crafting-skills}
Cada coisa que podes fazer tem uma competência própria, com o seu nome: construir Bancadas de trabalho treina `Workbench`, fazer Motores treina `Motor`, e assim por diante. Não passam para outras receitas. Combinar dois itens do inventário é instantâneo e não treina nada; ver [Construção](Constructing), [Bancada de trabalho](Workbench) e [Combinar](Combining).
