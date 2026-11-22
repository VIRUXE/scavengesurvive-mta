# Explosivos

![Explosivos à volta de um caixote: as variantes de TNT, IED e EMP e um Molotov](images/scenes/explosives.png)

![TNT com temporizador](images/items/20284_tnt_timer.png) ![TNT de proximidade](images/items/20286_tnt_prox.png) ![IED](images/items/20273_ied.png) ![EMP](images/items/343_teargas.png) ![Molotov](images/items/344_molotov.png) ![Bomba de gasolina](images/items/1650_petrolcanm.png)

Há 12 cargas: três tipos de explosão (TNT, IED e EMP) vezes quatro detonadores (temporizado, de proximidade, de fio de tropeçar e remoto por telemóvel). Fabricam-se numa [Bancada de trabalho](Workbench) com uma Chave de fendas. Um bastão de [Dinamite](Dynamite) é a décima terceira, encontrada já feita como loot: uma carga pequena com rastilho temporizado, e três bastões com uma Chave de fendas numa Bancada de trabalho fazem um TNT.

## Cargas {#charges}
| Carga | Feita com | Efeito |
|:--|:--|:--|
| TNT (média) | TNT | Uma grande explosão que fere os jogadores perto dela e danifica os itens soltos e as [defesas](Defences) ao alcance: 2 pontos de vida a cada um. |
| IED (pequena) | Uma caixa de Fogo de artifício e uma Fonte de alimentação | Uma explosão menor: 1 ponto de vida de dano. |
| EMP | Uma Unidade flutuadora | Sem explosão nem dano direto de vida aos jogadores próximos. Deixa os jogadores inconscientes durante 60 segundos a menos de 12 m e desliga os motores dos veículos. As baterias de carro instaladas ficam a 0 %, apagando os faróis e impedindo novo arranque até a bateria ser substituída. Os itens soltos e as defesas não sofrem dano. |

Os jogadores perto de uma explosão ficam feridos no torso ou numa perna e ficam normalmente inconscientes. Uma explosão destrói qualquer item solto ao alcance cujos pontos de vida se esgotem; os outros itens perdem pontos de vida. Atrás de uma [defesa](Defences), uma segunda defesa na mesma linha (a menos de 1 m) só sofre o que sobrar depois de a primeira ceder. Uma carga que rebente nas mãos ou no inventário de alguém mata-o, e uma dentro do armazenamento de um veículo destrói o veículo (os painéis blindados de um reboque sofrem o dano em vez disso). Estes efeitos de cargas transportadas ou guardadas aplicam-se também às EMP.

<!-- table:explosives -->
| Item | Carga | Detonador | Raio da explosão | Tamanho |
|:--|:--|:--|--:|--:|
| TNT com temporizador | Média | Temporizador | 8 m | 2 |
| TNT de proximidade | Média | Proximidade | 8 m | 2 |
| Dinamite | Pequena | Temporizador | 3 m | 2 |
| TNT remoto por telemóvel | Média | Rádio | 8 m | 2 |
| TNT com fio de tropeçar | Média | Movimento | 8 m | 2 |
| IED com temporizador | Pequena | Temporizador | 3 m | 2 |
| IED de proximidade | Pequena | Proximidade | 3 m | 2 |
| IED com fio de tropeçar | Pequena | Movimento | 3 m | 2 |
| IED remoto por telemóvel | Pequena | Rádio | 3 m | 2 |
| EMP com temporizador | EMP | Temporizador | 12 m | 2 |
| EMP de proximidade | EMP | Proximidade | 12 m | 2 |
| EMP com fio de tropeçar | EMP | Movimento | 12 m | 2 |
| EMP remoto por telemóvel | EMP | Rádio | 12 m | 2 |
| Bomba de gasolina | Incendiária | Temporizador | 5 m | 3 |
<!-- /table:explosives -->

"Raio da explosão" é a distância a que chegam o dano a itens e defesas e a EMP.

## Detonadores {#triggers}
Segura na carga e prime `F` para a colocar e armar. A tua personagem larga-a e planta-a durante um segundo.

| Detonador | Como funciona | Fabricado com |
|:--|:--|:--|
| Temporizado | Rebenta 5 segundos depois de armado. | Temporizador |
| Proximidade | Fica pronto após 5 segundos. Depois, qualquer jogador que chegue a menos de 6 m ativa-o, e rebenta 1 segundo depois. Isso inclui-te a ti. | Sensor de movimento |
| Fio de tropeçar | Armado de imediato. Rebenta quando alguém interage com ele (prime `F` nele). | Acelerómetro |
| Remoto por telemóvel | Fica inerte até ser sincronizado. Segura num Telemóvel e prime `F` junto à carga no chão para sincronizar os dois. Depois prime `F` com o telemóvel nas mãos para a fazer rebentar a qualquer distância. A ligação gasta-se quando rebenta. | Telemóvel |

As receitas de TNT e IED juntam o material da carga (TNT, ou um IED feito na Bancada de trabalho) à peça de detonador acima. Uma EMP junta uma Unidade flutuadora a ela. Tudo está na página da [Bancada de trabalho](Workbench).

## Molotov {#molotov}
Uma bomba incendiária de arremesso. Combina uma Garrafa com uma Ligadura suja para fazer um Molotov vazio. Larga-o, depois segura num Jerricã de gasolina com gasolina e prime `F` junto à garrafa: despejam-se 0,5 litros e passa a ser um Molotov. Apanha-o e arremessa-o. O fogo custa vida mas não abre feridas com hemorragia. Vê [Combustível](Fuel) para encher um Jerricã de gasolina.

Um Molotov, tal como uma [Granada](Grenade), o [Gás lacrimogéneo](Teargas) ou a [Bomba remota](Remote-Bomb), arremessa-se uma vez: o arremesso gasta o item e deixa-te as mãos vazias.

## Bomba de gasolina {#petrol-bomb}
Uma carga incendiária de tamanho 3 que arma como uma carga temporizada: rebenta numa explosão de fogo ao fim de 5 segundos. Não causa dano a itens e não tem receita de fabrico.

Vê também [Defesas](Defences), [Combinar](Combining) e [Render-se e desarmar](Surrender-and-Disarm).
