# Defesas

![Uma parede de defesa: uma Porta metálica entre Painéis metálicos, com o seu Teclado numérico e um Pé de cabra no chão](images/scenes/doorway.png)

As defesas são as paredes, portas e portões com que os jogadores constroem bases. Há 11 tipos. Cada uma começa como um item normal que deixas cair; uma ferramenta transforma-o numa defesa fixa e sólida que ninguém pode apanhar.

![Porta metálica](images/items/18553_count_ammundoor.png) ![Painel metálico](images/items/20301_imcmptrkdrl_las_def.png) ![Portão metálico](images/items/19303_pd_jail_door02.png) ![Porta de caixote](images/items/20302_container_door_def.png) ![Chapa ondulada](images/items/2904_warehouse_door1.png) ![Porta de navio](images/items/20303_freight_sfw_door_def.png) ![Porta isolada](images/items/19398_wall046.png) ![Painel isolado](images/items/19371_wall019.png) ![Painel metálico pequeno](images/items/19843_metalpanel1.png) ![Rampa de madeira](images/items/5153_stuntramp7_las2.png) ![Large Frame](images/items/19157_metallightbars1.png)

<!-- table:defences -->
| Defesa | Pontos de vida | Tamanho | Pode ser movida depois de colocada |
|:--|--:|--:|:--|
| Large Frame | 12 | 20 | não |
| Porta de navio | 9 | 10 | sim |
| Painel isolado | 7 | 8 | não |
| Porta isolada | 7 | 10 | não |
| Rampa de madeira | 7 | 11 | não |
| Chapa ondulada | 6 | 10 | sim |
| Chapa ondulada enferrujada | 5 | 10 | sim |
| Painel metálico | 5 | 10 | sim |
| Painel metálico pequeno | 5 | 11 | sim |
| Porta de caixote | 5 | 9 | sim |
| Portão metálico | 4 | 10 | sim |
| Porta metálica | 2 | 9 | não |
<!-- /table:defences -->

"Pontos de vida" é o dano de explosão que uma defesa aguenta antes de se partir (vê [Explosivos](Explosives)). Uma carga média causa 2, uma pequena 1. A Large Frame constrói-se com 4 de Metal refinado e uma Marreta ([Construção](Constructing)) e fica deitada.

## Construir {#building}
1. Deixa cair o item de defesa no sítio onde o queres.
2. Fica a menos de 3 m, virado para ele, com um **Martelo** na mão e prime `F`: escolhe **Construir de pé** (uma parede ou porta) ou **Construir deitado** (um chão ou rampa) e depois fica quieto cerca de 10 segundos. A [competência de Construção](Skills) encurta o tempo. Se te afastares ou trocares de ferramenta antes de acabar, a construção é cancelada.
3. A defesa fica construída (*Defesa construída*) e abre-se o painel de ajuste, com uma seta amarela na defesa a indicar a sua **frente**; vê *Ajustar a posição* mais abaixo.

Só o Martelo constrói defesas (no original usava-se uma Chave de fendas para paredes e um Martelo para chãos); depois de construída, a defesa mantém essa posição até ser movida por um motor.

## Ajustar a posição {#nudging-into-place}
Logo a seguir a construíres uma defesa (e depois da maior parte dos itens construídos no chão, vê [Construção](Constructing)) aparece, à direita do ecrã, um painel de oito botões com que podes deslocar um pouco o item:

- `LALT` (a tecla de andar) mostra o rato; o botão comprido passa a dizer *Mover* e volta a escondê-lo para poderes andar.
- `^`, `v`, `<` e `>` movem o item 5 cm por clique (mantém o botão premido para continuar a deslocar); `L` e `R` rodam-no 2 graus.
- O item nunca vai além de 1,5 m do sítio onde foi construído (*Demasiado longe da posição de construção original*) e não se move enquanto alguém, tu incluído, estiver a menos de 2,2 m dele (*Não é possível mover o item com jogadores por perto*; o outro jogador é avisado para se afastar). Afasta-te primeiro.
- *Concluído* ou `Enter` termina (*Ajustes concluídos*). Morrer, entrar num veículo, clicar no painel a mais de 10 m de distância, largar ou guardar um item, ou abrir o inventário também o termina, e o item fica onde está.

Numa defesa, a seta amarela mostra a sua frente: o lado a partir do qual um Pé de cabra não a consegue desmontar e não se pode instalar um Motor nem um Teclado numérico. Uma Fogueira e um Poste de terreno não abrem painel.

## Desmontar uma defesa {#taking-one-down}
Segura um **Pé de cabra** e mantém `F` na defesa durante 10 segundos. Tens de estar atrás dela, do lado de dentro: pela frente és avisado de que só podes remover uma defesa pelo interior. A defesa volta a ser um item normal (e qualquer motor ou teclado nela perde-se).

## Portas e portões {#doors-and-gates}
Algumas defesas podem receber um **Motor**. Atrás da defesa, segura o Motor e mantém `F` cerca de 6 segundos: o Motor é gasto e a defesa passa a alternar entre as suas duas posições (de pé e deitada) sempre que alguém prime `F` nela. Mexe-se cerca de 1,5 segundos depois e espera enquanto alguém estiver a menos de 4 m. Sem Motor, premir `F` numa defesa construída não faz nada.

Defesas que aceitam Motor: Portão metálico, Painel metálico, Painel metálico pequeno, Porta de caixote, Chapa ondulada, Chapa ondulada enferrujada e Porta de navio. A Porta metálica, a Porta isolada, o Painel isolado, a Rampa de madeira e a Large Frame não aceitam.

Uma defesa com Motor pode depois receber um [Teclados numéricos](Keypads), que a tranca com um código de 4 dígitos.

A **Large Frame** é diferente: premir `F` nela coloca ou retira um painel de cobertura sobre a estrutura.

## Poste de terreno {#plot-pole}
![Poste de terreno](images/items/3221_drv_in_spkrs.png)

Um Poste de terreno marca um território reclamado. Constrói-se no chão com uma Chave de fendas a partir de um Cilindro de gás, uma Unidade flutuadora, uma Fonte de alimentação e um Recetor (20 segundos, vê [Construção](Constructing)). Enquanto estiver de pé, todos os que chegam a menos de 20 m dele são avisados com *A entrar em território reclamado* e, à saída, *A sair de território reclamado*. É só isso que o poste faz hoje: não impede ninguém de construir, desmontar ou apanhar o que quer que seja dentro do círculo, por isso quem protege continuam a ser as defesas. A reclamação dura enquanto o poste estiver no mundo; termina quando é apanhado (`F`, como qualquer item) ou desmontado com um Pé de cabra (30 segundos, as peças caem). O poste não tem painel de ajuste.

## Notas {#notes}
- Os explosivos danificam as defesas: cada explosão retira pontos de vida a todas as defesas ao alcance, vê [Explosivos](Explosives).
- Um motor faz-se na [Bancada de trabalho](Workbench) com uma Fonte de alimentação e um Temporizador.
- Uma defesa construída mantém a sua posição e o seu teclado depois de reinícios do servidor.
