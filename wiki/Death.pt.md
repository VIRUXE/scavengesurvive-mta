# Morte

![Tronco](images/items/2907_kmb_deadtorso.png)

Tens uma só personagem. Quando a sua [vida](Health) chega a 0, morre para sempre: tudo o que carregava cai no chão, fica um corpo para trás, e a personagem seguinte começa do nada. Ficar inconsciente não é morrer (ver [Saúde](Health)); sair a meio de um combate é tratado como tal (ver [Desligar em combate](Combat-Log)).

## Formas de morrer {#ways-to-die}
- Sangrar até à morte por causa de [ferimentos](Bleeding-and-Wounds), ou morrer à fome (fome abaixo de 20, ver [Saúde](Health)).
- Balas, lâminas, punhos, explosões, fogo, uma queda, afogamento, ser atropelado.
- A [droga](Drugs) Air de um injetor vazio.

## O que acontece quando morres {#what-happens-when-you-die}
1. A tua personagem cai. Um segundo e meio depois aparece o **ecrã de morte**: a câmara sobe devagar sobre o corpo durante meio minuto enquanto o ecrã escurece, com `ESTÁS MORTO!` e um botão `>Jogar novamente<` ao centro. O resto do HUD fica escondido.
2. Tudo o que seguravas, vestias e carregavas cai onde caíste: o item nas mãos, a tua mochila (com tudo o que tem dentro), o chapéu, a máscara e o [colete](Armour), e todos os itens do teu inventário. Aterram num anel de 9 posições a 1,5 m à volta do corpo, uma a cada 40 graus, cada uma virada para um lado aleatório; um décimo item partilha a primeira posição, e assim por diante. Uma posição atrás de uma parede é puxada para 1 m, depois 0,5 m do corpo, e para cima do próprio corpo se nem aí estiver livre, por isso morrer encostado a uma parede nunca põe os teus itens dentro dela nem do outro lado. Um item **Roupa** com a roupa em que morreste fica 1 m a este do corpo (ver [Roupa e chapéus](Clothes-and-Hats)).
3. Fica um **corpo** onde morreste: um item Tronco com o teu nome e a causa da morte (abaixo).
4. Os itens largados desaparecem passados 120 minutos se ninguém os apanhar, como qualquer loot (ver [Saque e reaparecimento](Loot-and-Respawn)). Qualquer pessoa os pode levar, incluindo quem te matou. O teu rasto de sangue também fica por algum tempo.

<!-- shot:shot-death-screen -->

Clicar em `>Jogar novamente<` cria a tua próxima personagem. As tuas [competências](Skills) perdem-se com a antiga.

## O corpo {#the-body}
O corpo fica no chão como um item chamado *Tronco*. Junto a ele, com as mãos vazias:

- toca em `F` para o **investigar**: uma janela com o nome do jogador morto mostra a frase do médico-legista;
- mantém `F` para o **apanhar**. É levado nos dois braços como uma caixa (não podes entrar num veículo com ele), por isso um corpo pode ser movido ou escondido.

Com uma **Faca de combate** na mão, `F` no corpo **aproveita-o**: uma pressão de 3 segundos que deixa uma **Carne** crua no corpo, uma vez por corpo, e só no prazo de um dia após a morte (*O corpo está demasiado decomposto para ser aproveitado* depois disso). Cozinha a carne antes de a comeres, ver [Fogueira e grelhador](Campfire-and-BBQ) e [Comida e bebida](Food-and-Drink).

### A frase do médico-legista {#the-coroners-line}
| Como morreu a personagem | O que diz o corpo |
|:--|:--|
| Punhos ou uma arma contundente | Foi espancada até à morte. |
| Uma faca | Sofreu pequenas lacerações no tronco, possivelmente de uma faca. |
| Uma katana | Lacerações grandes cobrem o tronco e a cabeça, parece uma espada muito afiada. |
| Uma motosserra | Há pedaços por todo o lado, provavelmente sofreu uma motosserra no tronco. |
| Tiros | Morreu de perda de sangue causada pelo que parecem balas. |
| Uma explosão | Sofreu uma concussão enorme devido a uma explosão. |
| Fogo | O corpo inteiro está carbonizado e queimado. |
| Um spray ou um extintor | Foi pulverizada e sufocada por uma substância de alta pressão. |
| Uma queda | A maioria dos ossos está partida, parece que caiu de uma grande altura. |
| Afogamento | Afogou-se. |
| Sangrar até à morte, ou atropelamento por um condutor | Sangrou até à morte. |
| Fome | Morreu de fome. |
| Qualquer outra coisa (a droga Air, uma colisão sem ninguém ao volante) | Morreu por uma razão desconhecida. |

## A tua próxima personagem {#your-next-character}
`>Jogar novamente<` faz nascer uma nova personagem num de 14 pontos de aparecimento à beira de água, nunca o mesmo do teu último, com roupa aleatória de um género aleatório: a costa oceânica a oeste de San Fierro (Ocean Flats e a costa a sul) e de Whetstone, a costa sul de Flint County, as margens de rios e lagoas de Red County, e as margens de Tierra Robada e da baía no canto sudoeste de Bone County.

| Personagem | Vida | Fome | Começa com |
|:--|--:|--:|:--|
| A tua primeira | 90 | 80 | uma Faca de combate |
| Todas as seguintes a uma morte | 100 | 40 | uma Ligadura antisséptica |

Mais nada se mantém: nem itens, nem competências. A tua conta, língua e palavra-passe ficam intactas; os itens da tua personagem antiga continuam no chão onde morreu, por isso voltar para os buscar é uma opção, para ti e para todos os outros.

`/dropall` larga tudo da mesma forma sem morreres, com as mãos no ar; ver [Render-se e desarmar](Surrender-and-Disarm) e [Comandos](Commands).

## Mapa {#map}
As praias onde uma personagem nova pode acordar.

<a href="images/map/spawns.png" target="_blank" rel="noopener noreferrer" title="Ver o mapa em tamanho completo; Ctrl/Cmd+clique ou clique com o botão do meio para abrir num novo separador"><img src="images/map/spawns.png" alt="Mapa"></a>

Ver também [Saúde](Health), [Desligar em combate](Combat-Log) e [Primeiros passos](Getting-Started).
