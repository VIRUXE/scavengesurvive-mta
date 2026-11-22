# Colete

![Colete](images/items/19515_swatagrey.png)

O **Colete** (tamanho 4) é uma peça que se veste no tronco. Absorve parte de cada bala que te acerta no peito e vai-se gastando com isso. Para os painéis metálicos soldados a um veículo, ver [Blindagem de veículos](Vehicle-Armour).

## Vesti-lo {#wearing-it}
O colete tem uma textura de tecido cinzento-escuro mais nítida, com a trama visível, costuras reforçadas e correias gastas.

Segura o Colete e prime `F`, escolhe `Vestir` nele no [inventário](Inventory), ou clica no quadrado vazio `TORSO` enquanto o seguras. Clica no quadrado para o tirar outra vez; vestir uma segunda peça troca a primeira. Os outros jogadores veem o colete na tua personagem. Cai no chão com tudo o resto quando morres ou usas `/dropall`.

## Colete especial {#special-armour}

![Colete especial](images/items/1242_bodyarmour.png)


Podes encontrar o Colete especial em pontos de saque militares e, mais raramente, em pontos de saque policiais. O esconderijo de San Fierro que se abre com o código também contém um Colete especial, de tecido azul-ardósia, com **100 a 149** pontos iniciais. Usa a mesma ranhura de tronco e segue as mesmas regras de dano.

## Pontos {#points}
Cada peça de Colete tem entre **25 e 99 pontos**, sorteados quando é feita ou encontrada. Uma barra mesmo por cima da barra de vida no [HUD](HUD) mostra-os (cheia a partir de 100), e o número exacto aparece na legenda do quadrado `TORSO`, por exemplo `COLETE (73)`. Só desce.

## O que trava {#what-it-stops}
O Colete funciona contra **tiros no peito** de uma arma de fogo carregada com munição. Nada mais lhe toca, e não protege mais nada: um tiro na cabeça, num braço, na virilha ou numa perna, um soco, uma arma corpo a corpo, uma queda, um fogo ou uma explosão magoam-te como se não tivesses colete.

Quando uma bala te acerta no peito:

- a hemorragia que ela causa é multiplicada pela **penetração** da munição (ver [Munições](Ammunition)), por isso só essa fração chega até ti e começa uma [ferida](Bleeding-and-Wounds);
- o colete perde `(pontos + 10) x (hemorragia que passou x 10)` pontos.

Uma bala de baixa penetração é travada quase por completo e custa pouco ao colete; uma bala de alta penetração passa na maior parte e mesmo assim desgasta-o. Quando os pontos chegam a **0 o Colete é destruído**: o quadrado esvazia e o tiro seguinte entra por inteiro.

| Penetração | Munição |
|:--|:--|
| 0,2 | 9mm Hollow Point, 12g Flechette |
| 0,3 | 12g Improvised |
| 0,4 | 5.56 Hollow Point |
| 0,5 | 12g No. 1, 5.56 Tracer |
| 0,6 | .357 Tracer |
| 0,8 | 9mm FMJ, 5.56 FMJ, .308 FMJ |
| 0,9 | .357 FMJ, 7.62 FMJ, .50 Action Express |
| 1,0 | .50 BMG, RPG |

Exemplo prático: um colete com 60 pontos leva um tiro no peito que causaria uma hemorragia de 0,30 com 9mm Hollow Point (penetração 0,2). Sangras 0,06 em vez de 0,30, e o colete perde (60 + 10) x (0,06 x 10) = 42 pontos, ficando com 18.

## Chapéus {#hats}
Um chapéu é o equivalente para a cabeça: não muda o dano, mas reduz em 60 % a probabilidade de um tiro na cabeça te deixar inconsciente; ver [Roupa e chapéus](Clothes-and-Hats).

Ver também [Hemorragias e feridas](Bleeding-and-Wounds), [Armas de fogo](Firearms) e [Blindagem de veículos](Vehicle-Armour).
