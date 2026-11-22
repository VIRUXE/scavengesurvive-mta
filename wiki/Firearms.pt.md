# Armas de fogo

![Todas as armas de fogo dispostas em filas, com munições pelo meio](images/scenes/arsenal.png)

![M9](images/items/346_colt45.png) ![Desert Eagle](images/items/348_desert_eagle.png) ![Caçadeira](images/items/349_chromegun.png) ![MP5](images/items/353_mp5lng.png) ![M16](images/items/356_m4.png) ![Espingarda de precisão](images/items/358_sniper.png)

Cada arma de fogo usa um **calibre** de [munições](Ammunition). Uma arma tem um carregador (as balas carregadas nela) e pode levar balas de reserva. O nome no inventário mostra ambos: `M9 (10/7, 9mm, Ponta oca)` é uma pistola com 10 no carregador e 7 de reserva, carregada com balas de 9mm de Ponta oca.

## Armas {#weapons}
"Carregadores de reserva" é quantos carregadores extra de balas a arma pode ter de reserva. A "velocidade à saída do cano" decide quanto dano a bala ainda faz a distância.

<!-- table:weapons -->
| Arma | Calibre | Carregador | Carregadores extra | Tamanho | Velocidade à boca |
|:--|:--|--:|--:|--:|--:|
| M9 | 9mm | 10 | 1 | 1 | 330 m/s |
| M9 SD | 9mm | 10 | 1 | 1 | 295 m/s |
| Desert Eagle | .357 | 7 | 2 | 1 | 420 m/s |
| Caçadeira | Calibre 12 | 6 | 1 | 3 | 475 m/s |
| Caçadeira de canos serrados | Calibre 12 | 2 | 6 | 2 | 265 m/s |
| Spas 12 | Calibre 12 | 6 | 1 | 4 | 480 m/s |
| Mac 10 | 9mm | 32 | 1 | 2 | 376 m/s |
| MP5 | 9mm | 30 | 1 | 4 | 400 m/s |
| WASR-3 | 5.56mm | 30 | 1 | 5 | 943 m/s |
| M16 | 5.56mm | 30 | 1 | 5 | 948 m/s |
| Tec 9 | 9mm | 36 | 1 | 2 | 360 m/s |
| Espingarda | .357 | 5 | 1 | 5 | 829 m/s |
| Espingarda de precisão | .357 | 5 | 1 | 5 | 864 m/s |
| RPG | RPG | 1 | 0 | 6 | 0 m/s |
| Lança-mísseis térmico | RPG | 1 | 0 | 6 | 0 m/s |
| Metralhadora rotativa | 5.56mm | 100 | 1 | 7 | 853 m/s |
| Máquina fotográfica | Rolo fotográfico | 24 | 4 | 2 | 1337 m/s |
| AK-47 | 7.62 | 30 | 1 | 5 | 715 m/s |
| M77-RM | .357 | 1 | 9 | 5 | 823 m/s |
| Bafo de Cão | .50 | 1 | 9 | 2 | 888,8 m/s |
| Model 70 | .308 | 1 | 9 | 5 | 860,6 m/s |
| The Len-Knocks | .50 | 1 | 4 | 5 | 938,5 m/s |
<!-- /table:weapons -->

## Carregar {#loading}
- Segura a arma e fica por cima de uma lata de munições ou de outra arma no chão, depois prime `F`: as balas passam para a tua arma, primeiro o carregador e depois a reserva. Vê [Munições](Ammunition).
- `R` recarrega da reserva para o carregador. Uma arma recarrega sozinha quando o carregador esvazia e há balas na reserva.
- Mantém `N` durante 300 ms para descarregar a arma: todas as suas balas caem como uma lata de munições.
- Uma arma não pode ter dois tipos de munição ao mesmo tempo.
- `Y` guarda a arma ou mete-a no coldre; vê [Coldre](Holster).
- Uma arma largada no chão ou posta numa mesa fica deitada de lado, na horizontal; num [Estojo de arma](Furniture) fica de pé no suporte.

## Dano {#damage}
Um tiro abre um ferimento cuja taxa de hemorragia depende da velocidade da bala quando chega, por isso diminui com a distância:

<!-- shot:shot-combat-tracers -->

`speed = muzzle velocity - distance ^ (1 - muzzle velocity / 11300)`

`bleed = calibre rate x speed / 1000 x ammo bleed multiplier`

As taxas dos calibres estão na página das [Munições](Ammunition) e os multiplicadores de munição na sua tabela. O tiro tira de uma vez à vítima a taxa de hemorragia vezes 100 em vida, e um tiro na cabeça duplica a hemorragia. Alguns exemplos, calculados com a fórmula:

| Tiro | Taxa de hemorragia |
|:--|--:|
| M9, Ponta oca, 10 m | cerca de 0,08 |
| M16, FMJ, 50 m | cerca de 0,19 |
| Model 70, FMJ, 100 m | cerca de 0,41 |
| The Len-Knocks, BMG, 100 m | cerca de 0,99 |

Os ferimentos, a hemorragia e os desmaios estão explicados em [Hemorragias e feridas](Bleeding-and-Wounds). As balas com um multiplicador de desmaio mais alto deixam inconsciente com mais frequência.

### Alcance {#range}
Um tiro só conta dentro do alcance da arma (mais 5 m de tolerância):

| Armas | Alcance |
|:--|--:|
| Desert Eagle, M9, M9 SD, Dog's Breath | 35 m |
| Caçadeira, Caçadeira de canos serrados, Spas 12 | 40 m |
| Mac 10, MP5, Tec 9 | 45 m |
| AK-47, WASR-3 | 70 m |
| Metralhadora rotativa | 75 m |
| M16 | 90 m |
| Espingarda, M77-RM | 100 m |
| Espingarda de precisão, Model 70, The Len-Knocks | 320 m |

A Desert Eagle e a Dog's Breath só conseguem ferir o mesmo alvo uma vez a cada 0,8 s; as outras armas, uma vez a cada 0,1 s.

## Colete e Escudo {#armour-and-the-shield}
Um [Colete](Armour) vestido deixa passar só uma fração da hemorragia de um tiro no peito (a penetração da munição) e vai-se gastando com isso; um [Escudo](Small-Items#shield) seguro nas mãos bloqueia os tiros de frente e, às costas, os tiros por trás.

Vê também [Armas corpo a corpo](Melee-Weapons), [Explosivos](Explosives), [Aimshout](Aimshout) e [Render-se e desarmar](Surrender-and-Disarm).
