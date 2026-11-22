# Lançamentos de provisões

![Um lançamento de provisões: o caixote sob o paraquedas, com o saque a espalhar-se](images/scenes/supply-drop.png)

Os lançamentos de provisões e os esconderijos de armas são pontos quentes de saque que o servidor cria enquanto corre. Ambos são anunciados no chat, ambos atraem combates, e ambos são um contentor que abres como uma mala ou uma caixa ([Contentores e sacos](Containers-and-Bags)). Funcionam com temporizadores próprios e não contam para os limites de escassez que regem o saque e os veículos normais, ver [Saque e reaparecimento](Loot-and-Respawn).

## Lançamentos de provisões {#supply-drops}
Um caixote cai do céu num ponto predefinido do mapa. O chat anuncia-o quando começa a cair, dizendo o nome do sítio onde vai aterrar; em metade das vezes o tipo do lançamento fica escondido e aparece como *Unknown*:

> [EBS]: LANÇAMENTO DE PROVISÕES: "Armas militares" CHEGADA A: "<nome do local>"

O caixote deixa um rasto de fumo ao cair; o lançamento demora entre dois minutos e meio e cinco, menos onde o ponto de aterragem é alto. Quem estiver onde ele aterra é empurrado para longe, e o sítio continua a fumegar durante 3 minutos. Depois de cair, o caixote leva uma etiqueta flutuante *Supply Crate* e fica onde aterrou até o lançamento seguinte o substituir (conteúdo incluído); sobrevive a um reinício do servidor.

<!-- shot:shot-supply-drop-live -->

Chega-te ao caixote (a cerca de 3 m) e prime `F` para abrir os seus 32 espaços. Um lançamento tem de 4 a 19 itens sorteados da tabela do seu tipo; o que não couber fica de fora.

### Tipos {#types}
Há cinco tipos. Um tipo só cai enquanto houver jogadores suficientes online, e cada um tem o seu temporizador: depois de um lançamento desse tipo, o seguinte é devido passado o intervalo mais uma espera extra aleatória. Dois lançamentos nunca ficam a menos de 10 minutos um do outro. Quando mais do que um tipo é devido, cai o primeiro desta lista. Um sítio não volta a ser usado durante 24 horas.

| Tipo | Jogadores necessários | Intervalo | Extra aleatório | Conteúdo |
|:--|--:|--:|--:|:--|
| Comida e medicamentos | 3 | 15 min | até 10 min | Ferramentas (chave inglesa, chave de fendas, martelo, pé de cabra), jerricãs de gasolina, isqueiros, madeira, sementes, vasos, comida e bebida, sacos e mochilas, kits médicos, ligaduras antissépticas, malas de médico, comprimidos |
| Armas de baixa qualidade | 4 | 40 min | até 20 min | Facas, bastões, pistolas, caçadeiras, Mac 10, espingarda M77-RM e as suas munições |
| Armas militares | 6 | 70 min | até 30 min | Pistolas, caçadeiras, MP5, M16, AK-47, espingardas, sniper, RPG, lança-chamas, minigun e munições pesadas |
| Provisões industriais | 5 | 33 min | até 15 min | Motosserras, caixas, eletrónica (bateria de carro, caixa de fusíveis, sensores, teclado, motor, recetor), painéis metálicos, portões e portas, rampas de madeira, botijas de gás, rebarbadora, bateria de ferramenta, discos de desbaste |
| Ordnance Supplies | 8 | 3 h | até 3 h | Cargas de TNT e IED e as bombas e minas já feitas, bombas EMP e unidades flutuadoras; ver [Explosivos](Explosives) |

Quando o servidor arranca, todos os tipos já são devidos, exceto pela espera extra aleatória.

### Locais de aterragem {#landing-places}
Um lançamento aterra num de 36 sítios com nome, e o chat diz qual.

| Zona | Sítios |
|:--|:--|
| Bone County | Bone County Canyons, Fort Carson, Verdant Meadows, Bone County East |
| Flint County | Mount Chilliad, Angel Pine, The Farm Flint County, Back-o-Beyond, Flint County Fallen Tree, Flint Range |
| Los Santos | Los Santos Pier, Los Santos Market Station, Los Santos Verdant Bluffs, Los Santos North Car Park, Los Santos Airport, Los Santos Jefferson Motel, Los Santos Docks |
| Las Venturas | Las Venturas Stadium, Las Venturas Airport, Las Venturas South Industrial, Las Venturas North Strip Motel, Las Venturas East Shopping Mall, Las Venturas East Building Roof |
| Red County | Blueberry, Dillimore, Montgomery, Fisher's Lagoon |
| San Fierro | San Fierro Country Club, San Fierro Hospital, San Fierro Driving School, San Fierro Square, San Fierro Promenade, San Fierro Airport |
| Tierra Robada | Tierra Robada North Freeway, Tierra Robada Midland, Tierra Robada South |

## Esconderijos de armas {#weapons-caches}
Um esconderijo de armas é um caixote de equipamento militar que aparece de repente no chão, sem caixote a cair, num sítio escondido.

- Um esconderijo novo é criado a cada 25 a 35 minutos enquanto nenhum outro esconderijo estiver ativo e houver pelo menos 4 jogadores online. Nunca aparece a menos de 500 m de um jogador.
- O servidor envia três sinais no chat, com 200 segundos de intervalo:

  > [EBS]: SINAL DE ESCONDERIJO DE ARMAS: RUMO: 142.0DEG DISTÂNCIA: 612.3M

  O rumo é em graus no sentido dos ponteiros do relógio a partir do norte, a distância em metros, medidos a partir de um ponto de referência que não é nomeado. Usa mais do que um sinal para descobrir onde fica.
- O caixote leva uma etiqueta flutuante *Esconderijo de armas*, tem de 22 a 32 itens da tabela de Armas militares e abre como um caixote de provisões (`F`, 32 espaços).
- Tal como o caixote de provisões, um esconderijo fica até o esconderijo seguinte o substituir, e o mesmo sítio não é usado duas vezes em 24 horas.

## Dicas {#tips}
- Os lançamentos atraem multidões: os outros jogadores leem o mesmo chat. Leva uma saída.
- Os lançamentos industriais trazem peças de construção, ver [Construção](Constructing) e [Defesas](Defences).

## Mapa {#map}
Pontos de aterragem dos lançamentos de provisões (estrelas) e sítios dos esconderijos de armas (pontos).

<a href="images/map/drops.png" target="_blank" rel="noopener noreferrer" title="Ver o mapa em tamanho real; Ctrl/Cmd-clique ou clique com o botão do meio para abrir num novo separador"><img src="images/map/drops.png" alt="Mapa"></a>
