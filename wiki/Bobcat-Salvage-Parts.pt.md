# Peças do Bobcat

![Bobcat](images/vehicles/422_bobcat.png)

A pick-up Bobcat é o único veículo cuja carroçaria se desmonta. O capot, o taipal, duas portas e dois para-choques são itens: uma Catraca tira-os, um acidente arranca-os, e uma peça na mão volta a ser montada num Bobcat a que falte. Nenhum outro veículo tem peças amovíveis por enquanto.

<!-- shot:shot-bobcat-salvage -->

## As peças {#the-parts}
Doze itens, um *Good* (intacto) e um *Bad* (danificado) de cada peça. Uma peça intacta está inteira ou só amolgada; uma danificada está partida e pendurada, com os vidros estilhaçados nas portas.

| Peça | Itens |
|:--|:--|
| Capot | Capô Bobcat (intacto), Capô Bobcat (danificado) |
| Taipal | Taipal traseiro Bobcat (intacto), Taipal traseiro Bobcat (danificado) |
| Porta esquerda | Porta esquerda Bobcat (intacta), Porta esquerda Bobcat (danificada) |
| Porta direita | Porta direita Bobcat (intacta), Porta direita Bobcat (danificada) |
| Para-choques dianteiro | Para-choques dianteiro Bobcat (intacto), Para-choques dianteiro Bobcat (danificado) |
| Para-choques traseiro | Para-choques traseiro Bobcat (intacto), Para-choques traseiro Bobcat (danificado) |

Todas as peças têm tamanho 6 e levam-se nas duas mãos como um caixote: nunca vão para uma mochila nem para o inventário, não podes entrar num veículo enquanto seguras uma, e viajam numa mala ou numa caixa ([Inventário](Inventory)). Todas as doze aparecem como saque em pontos industriais (estaleiros, armazéns, oficinas), as danificadas duas vezes mais do que as intactas; nunca se encontram dentro de malas de veículos.

## Tirar uma peça {#taking-a-part-off}
1. Segura uma **Catraca** ([Catraca](Ratchet)).
2. Põe-te a menos de 1,8 m da peça. O veículo tem de estar destrancado, parado e com o motor desligado. A lista de teclas diz `(Hold) Remove Left Door` ou a peça de que estás mais perto.
3. Mantém `F` durante meio segundo (um toque no capot é antes a reparação de um motor ligeiramente avariado, feita pela Catraca). Segue-se uma espera de 4 segundos, mais curta com a [competência](Skills) Reparação. Uma peça que ainda esteja no Bobcat tem a espera antes da bateria, incluindo o capot.

A peça cai no chão ao lado do seu encaixe: um item intacto se estava inteira ou amolgada, um danificado se estava partida. Andar mais de 0,8 m, mudar o que seguras, entrar num veículo ou morrer cancela a espera, e só uma pessoa de cada vez pode trabalhar num veículo. Um encaixe que já esteja vazio diz que já não há ali nenhuma peça para tirar.

## Pôr uma peça {#putting-a-part-on}
Segura a peça, põe-te junto ao seu encaixe num Bobcat e prime `F` (`Install Bobcat body part` na lista de teclas). O encaixe tem de estar **vazio**: para substituir uma porta amolgada, tiras primeiro a velha. A espera de 4 segundos tem as mesmas regras de cancelamento. Uma peça intacta deixa o encaixe como novo, uma danificada deixa-o amolgado e pendurado, mas no veículo.

Uma peça posta à mão fica apenas **solta**: *Body part fitted loosely, tighten it with a Ratchet or it will shake off*. Segura uma Catraca junto a ela e mantém `F` (`(Hold) Tighten Left Door`): 3 segundos, e *Body part tightened*. Apertar treina a competência Reparação. Uma peça apertada fica no sítio até uma Catraca a tirar ou um acidente a arrancar.

## As peças soltas caem {#loose-parts-shake-off}
Conduz com uma peça solta e ela sai sozinha:

- acima de 15 km/h há uma probabilidade a cada segundo de uma peça solta voar, a crescer com a velocidade até ser quase certa aos 75 km/h;
- travar a fundo (perder 25 km/h num segundo) lança de uma vez todas as peças soltas.

Uma peça que se solta é atirada para a frente do veículo, até 12 m, e aterra como o item que era, intacto ou danificado.

## Danos de acidente {#crash-damage}
Quando um acidente arranca uma peça, ela cai ao chão ao lado do encaixe como um item **danificado**, por isso um destroço pode ser desmontado para obter peças mesmo sem Catraca. As peças que já faltavam quando o veículo apareceu nunca caem.

Ver também [Veículos](Vehicles), [Reparações e fechaduras](Repairing-and-Locks) e [Ferramentas](Tools).
