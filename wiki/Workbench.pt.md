# Bancada de trabalho

![A Bancada de trabalho com uma Chave inglesa, um Martelo, uma Chave de fendas, uma Máquina de soldar, Sucata e Metal refinado](images/scenes/workbench.png)

![Bancada de trabalho](images/items/936_cj_df_worktop_2.png)

Uma bancada de trabalho é uma mesa de trabalho com um contentor de 16 ranhuras. É onde se fazem os itens complexos: eletrónica, motores, peças de bombas, material de serralharia e painéis metálicos. As receitas simples fazem-se por [Combinação](Combining), e os itens grandes por [Construção](Constructing).

## Usar uma bancada de trabalho {#using-a-workbench}
1. Põe os ingredientes dentro da bancada (abre-se como uma caixa, ver [Contentores e sacos](Containers-and-Bags)). Ela tem de ter exatamente os ingredientes de uma receita e mais nada; qualquer item a mais faz com que nenhuma receita corresponda.
2. Equipa a ferramenta que a receita pede ([Chave de fendas](Tools) ou [Martelo](Tools)).
3. Põe-te junto à bancada e prime a tecla de interação (`F`), ou escreve `/craft`. Se o conteúdo não corresponder a nenhuma receita, a bancada limita-se a abrir.
4. Viras-te para a bancada e trabalhas durante 3,6 segundos por ingrediente (encurtado pela [competência](Skills)). Tirar um item da bancada enquanto trabalhas cancela o fabrico.
5. Os ingredientes são gastos e o resultado fica em cima da bancada.

<!-- shot:shot-crafting-window -->

Fazer coisas treina a competência com o nome do resultado.

## Encontrar e construir uma {#finding-and-building-one}
Onze bancadas de trabalho estão em sítios fixos, a maior parte no campo; se uma for desmontada ou levada, é reposta quando o servidor reinicia. A lista e o mapa estão em [Mundo e zonas](World-and-Zones#fixed-items). Podes construir a tua com um Martelo a partir de 2 Metal refinado e 4 Troncos de madeira, ver [Construção](Constructing) (os troncos vêm das [árvores](Trees-and-Wood)). Segura um Pé de cabra para desmontar uma.

## Receitas {#recipes}
Todos os ingredientes são gastos. A ferramenta é segurada, não consumida.

### Eletrónica e peças {#electronics-and-parts}
| Resultado | Ferramenta | Ingredientes |
|:--|:--|:--|
| Fonte de alimentação | Chave de fendas | Bateria de carro, Caixa de fusíveis |
| Motor | Chave de fendas | Fonte de alimentação, Temporizador |
| Motor de arranque | Chave de fendas | Unidade flutuadora, Motor |
| Unidade flutuadora | Chave de fendas | Recetor, Pistola de choques |
| Unidade de armazenamento | Chave de fendas | Disco rígido, Temporizador |
| Unidade de E/S | Chave de fendas | Teclado numérico, Telemóvel |
| Condensador de fluxo | Chave de fendas | Unidade flutuadora, Fonte de alimentação |
| Interface de dados | Chave de fendas | Unidade de E/S, Unidade de armazenamento |
| Interface de hacking | Chave de fendas | Interface de dados, Condensador de fluxo |
| Teclado numérico avançado | Chave de fendas | Unidade de E/S, Fonte de alimentação |
| Localizador | Chave de fendas | Interface de dados, Telemóvel, Fonte de alimentação, Recetor |

### Metalurgia {#metalwork}
| Resultado | Ferramenta | Ingredientes |
|:--|:--|:--|
| Painel metálico | Martelo | 4x Metal refinado |
| Cilindro de gás | Martelo | Painel metálico, 2x Metal refinado |

### Serralharia {#locksmith}
| Resultado | Ferramenta | Ingredientes |
|:--|:--|:--|
| Kit de serralheiro | Chave de fendas | Chave, Motor |
| Gazua eletrónica | Chave de fendas | Condensador de fluxo, Kit de serralheiro, Fonte de alimentação, 2x Metal refinado |

Ver [Reparações e fechaduras](Repairing-and-Locks) para saber o que fazem.

### Explosivos {#explosives}
As bombas fazem-se em dois passos: primeiro uma carga (TNT, IED ou EMP), depois um detonador. Ver [Explosivos](Explosives) para saber o que fazem.

| Resultado | Ferramenta | Ingredientes |
|:--|:--|:--|
| IED | Chave de fendas | Fogo de artifício, Fonte de alimentação |
| TNT com temporizador | Chave de fendas | TNT, Temporizador |
| TNT com fio de tropeçar | Chave de fendas | TNT, Acelerómetro |
| TNT de proximidade | Chave de fendas | TNT, Sensor de movimento |
| TNT remoto por telemóvel | Chave de fendas | TNT, Telemóvel |
| IED com temporizador | Chave de fendas | IED, Temporizador |
| IED com fio de tropeçar | Chave de fendas | IED, Acelerómetro |
| IED de proximidade | Chave de fendas | IED, Sensor de movimento |
| IED remoto por telemóvel | Chave de fendas | IED, Telemóvel |
| EMP com temporizador | Chave de fendas | Unidade flutuadora, Temporizador |
| EMP com fio de tropeçar | Chave de fendas | Unidade flutuadora, Acelerómetro |
| EMP de proximidade | Chave de fendas | Unidade flutuadora, Sensor de movimento |
| EMP remoto por telemóvel | Chave de fendas | Unidade flutuadora, Telemóvel |
