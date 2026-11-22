# Munições

![Balas de 9mm e .50](images/items/2037_cj_pistol_ammo.png) ![Cartuchos de caçadeira](images/items/2038_ammo_box_s2.png) ![Balas .308 e .357](images/items/2039_ammo_box_s1.png) ![Balas 5.56 e 7.62](images/items/2040_ammo_box_m1.png)

As munições transportam-se em **latas**, itens que guardam um número de balas de um só tipo. Uma lata encontrada no mundo costuma estar só parcialmente cheia. Cada [arma de fogo](Firearms) usa um calibre, e cada calibre existe em vários tipos com efeitos próprios.

## Calibres {#calibres}
Cada calibre tem uma taxa de hemorragia de base, de onde parte a ferida da bala; ver a fórmula em [Armas de fogo](Firearms).

<!-- table:calibres -->
| Calibre | Hemorragia de base |
|:--|--:|
| .50 | 0,73 |
| .50 | 0,63 |
| .308 | 0,43 |
| .357 | 0,36 |
| 7.62 | 0,32 |
| Calibre 12 | 0,31 |
| 9mm | 0,25 |
| 5.56mm | 0,19 |
<!-- /table:calibres -->

## Tipos de munição {#ammunition-types}
- **Hemorragia ×** multiplica a taxa de hemorragia da ferida.
- **Desmaio ×** multiplica a probabilidade de desmaio.
- **Penetração** é a parte de um tiro que atravessa o [Colete](Armour): a hemorragia que chega a um jogador que traga colete é multiplicada por ela.
- **Balas** é quantas cabem numa lata cheia.

<!-- table:ammo -->
| Item | Tipo | Calibre | Balas | Hemorragia × | Desmaio × | Penetração |
|:--|:--|:--|--:|--:|--:|--:|
| Balas de 9mm | Ponta oca | 9mm | 20 | 1 | 1 | 0,2 |
| Balas .50 | Action Express | .50 | 28 | 1 | 1,5 | 0,9 |
| Cartuchos de caçadeira | Chumbo n.º 1 | Calibre 12 | 24 | 1,1 | 1,8 | 0,5 |
| Balas 5.56 | FMJ | 5.56mm | 30 | 1,1 | 1,2 | 0,8 |
| Balas .357 | FMJ | .357 | 10 | 1,2 | 1,1 | 0,9 |
| Foguetes | RPG | RPG | 1 | 1 | 1 | 1 |
| Balas de 9mm | FMJ | 9mm | 20 | 1,2 | 0,5 | 0,8 |
| Cartuchos de caçadeira | Dardo | Calibre 12 | 8 | 1,6 | 0,6 | 0,2 |
| Cartuchos de caçadeira | Improvisada | Calibre 12 | 14 | 1,6 | 0,4 | 0,3 |
| Balas 5.56 | Tracejante | 5.56mm | 30 | 0,9 | 1,1 | 0,5 |
| Balas 5.56 | Ponta oca | 5.56mm | 30 | 1,3 | 1,6 | 0,4 |
| Balas .357 | Tracejante | .357 | 10 | 1,2 | 1,1 | 0,6 |
| Balas 7.62 | FMJ | 7.62 | 30 | 1,3 | 1,1 | 0,9 |
| Balas .50 | BMG | .50 | 16 | 1,8 | 1,8 | 1 |
| Balas .308 | FMJ | .308 | 10 | 1,2 | 1,1 | 0,8 |
<!-- /table:ammo -->

## Carregar e descarregar {#loading-and-unloading}
- Prime `R` para recarregar a arma que tens nas mãos a partir da sua reserva.
- Mantém `N` premido durante 300 ms para descarregar a arma. Todas as balas que tem vão para uma lata nova do mesmo tipo de munição, largada aos teus pés.
- O tipo carregado numa arma aparece no seu nome, por exemplo `Desert Eagle (7/14, .357, FMJ)`. Uma arma com balas lá dentro só aceita o mesmo tipo de munição.

## Transferir munições {#transferring-ammo}
Passas balas com `F`, entre o que tens nas mãos e um item pousado no chão:

| Nas tuas mãos | No chão | As balas passam |
|:--|:--|:--|
| Uma arma | Uma lata de munições | Da lata para a arma: primeiro o carregador, depois a reserva. |
| Uma arma | Outra arma | Da outra arma para a tua. |
| Uma lata de munições | Uma arma | Da arma para a lata. |
| Uma lata de munições | Uma lata de munições | A lata do chão é toda despejada na tua. |

Dizem-te quantas balas foram transferidas. Uma lata que ficou vazia desaparece. A transferência é recusada quando:

- o calibre não corresponde: *Calibre errado para a arma*;
- a arma já tem um tipo de munição diferente: *Já está carregado nesta arma um tipo de munição diferente*;
- duas latas são de tipos diferentes: *Não é possível misturar tipos de munição nas latas*.

Uma arma só aceita o que cabe no seu carregador e na sua reserva; o resto fica na lata.

## Sucata {#scrap}
Qualquer lata pode ser desfeita numa Máquina de sucata, dando 1 peça de [sucata](Scrap).

Ver também [Armas de fogo](Firearms) e [Explosivos](Explosives).
