# Medicina

![Material médico: Ligaduras suja e antisséptica, um Kit médico, uma Mala de médico, Comprimidos e um Injetor](images/scenes/medical.png)

Os itens médicos estancam hemorragias, fecham feridas, curam infeções e aplicam [drogas](Drugs). Segura no item e mantém `F` premido: corre uma barra de progresso, e largar a tecla cancela-a. Se outro jogador estiver a menos de 1,5 m de ti, tratas esse jogador; caso contrário, tratas-te a ti. Os comprimidos são sempre tomados por ti.

![Ligadura suja](images/items/20299_dirty_bandage.png) ![Ligadura antisséptica](images/items/20298_bandage.png) ![Kit médico](images/items/20296_medkit.png) ![Mala de médico](images/items/20297_doctor_bag.png) ![Comprimidos](images/items/20283_pills.png) ![Injetor](images/items/2711_tatoo_needle.png)

## Tempo de tratamento {#treatment-time}
| Paciente | Tempo |
|:--|--:|
| Tu, ou outro jogador que esteja acordado | 4 s |
| Um jogador inconsciente | 6 s |
| Tomar comprimidos ou usar um injetor | 1 s |

A [competência de Medicina](Skills) encurta os tempos da ligadura, do kit médico e da mala. O tratamento é cancelado se te moveres mais de 0,8 m, se o paciente se afastar mais de 2,5 m, se mudares o item que tens nas mãos, ou se um de vós morrer ou sair.

## Itens {#items}
| Item | Tamanho | Efeito |
|:--|--:|:--|
| Ligadura suja | 2 | Reduz a taxa de hemorragia e é gasta. Uma vez em cada três a ferida fica infetada. Não faz nada quando não há hemorragia. |
| Ligadura antisséptica | 2 | Reduz a taxa de hemorragia como uma ligadura e cura uma [infeção da ferida](Infection). É gasta se fez uma das duas coisas. Uma personagem criada depois de uma morte começa com uma (vê [Morte](Death)). |
| Kit médico | 1 | Reduz a taxa de hemorragia e fecha feridas: 1 a 2 em ti, 2 a 3 noutra pessoa. É gasto. |
| Mala de médico | 3 | Estanca por completo a hemorragia, cura a infeção da ferida e fecha feridas: 1 a 2 em ti, 3 a 5 noutra pessoa. Tem até 3 cargas e é gasta com a última. Cada carga também aplica a droga da mala (antibiótico, analgésico, morfina ou adrenalina). |
| Comprimidos | 1 | Os antibióticos curam uma infeção alimentar e, metade das vezes, uma infeção de ferida. Os analgésicos dão 10 de vida. O LSD é um alucinogénio. O tipo aparece no nome, por exemplo `Comprimidos (LSD)`. |
| Injetor | 1 | Morfina, adrenalina ou heroína, indicada no nome. A adrenalina acorda um jogador inconsciente (não a ti). Depois disso o injetor fica vazio, e um injetor vazio injeta ar. |

## Quanto ajuda uma ligadura {#how-much-a-bandage-helps}
As ligaduras e o Kit médico reduzem a taxa de hemorragia numa fração que depende de quão alta ela está: uma hemorragia de 0,5 desce para cerca de 0,38, enquanto uma de 0,1 desce para cerca de 0,02. Uma taxa que desça abaixo de 0,005 pára por completo. Uma hemorragia muito forte quase não melhora com uma ligadura, por isso liga cedo e muitas vezes. O painel Estado de saúde no [inventário](Inventory) mostra a taxa atual.

Cada ferida que tens torna um desmaio mais provável (vê [Hemorragias e feridas](Bleeding-and-Wounds)), por isso fechá-las com um Kit médico ou uma Mala de médico também reduz essa probabilidade.

## Fazer uma ligadura {#making-a-bandage}
Combina uma Faca de combate (mantida) com Roupa para cortar uma Ligadura suja; vê [Combinar](Combining). As ligaduras também são ingrediente de um Molotov (vê [Explosivos](Explosives)).

Vê também [Saúde](Health), [Infeção](Infection) e [Drogas](Drugs).
