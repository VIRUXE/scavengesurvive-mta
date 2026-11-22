# Hemorragias e feridas

Cada golpe que faz sangue deixa uma ferida e aumenta a tua taxa de hemorragia, e uma hemorragia por tratar é a causa de morte mais comum. Esta página trata das feridas, da taxa de hemorragia, do que os outros jogadores vêem e de como a parar; os itens em si estão em [Medicina](Medical).

## Feridas {#wounds}
Um golpe que faz sangue soma uma ferida à tua contagem. As feridas vêm de:

- balas e golpes corpo a corpo (vê [Armas de fogo](Firearms) e [Armas corpo a corpo](Melee-Weapons)): um tiro na cabeça duplica a hemorragia e faz cair o chapéu e a máscara, um [Colete](Armour) vestido amortece um tiro no peito, e um Escudo pode travar um tiro por completo;
- quedas grandes: uma ferida numa perna, mais provável e mais grave quanto mais forte for a aterragem. Uma queda curta não faz nada;
- ser atropelado ou abalroado por um veículo: uma ferida no tronco ou numa perna cuja hemorragia cresce com a velocidade do veículo (cerca de 0,04 a 50 km/h). Acima de 55 km/h também podes ficar inconsciente, mais tempo quanto mais rápido for o veículo. O condutor fica com o crédito, e com a morte;
- explosões: uma ferida no tronco ou numa perna, com hemorragia até 0,5 mesmo junto à explosão, e uma probabilidade muito alta de ficares inconsciente. Vê [Explosivos](Explosives).

Afogar-te não deixa ferida: cada golpe de água custa até 10 de vida e deixa-te inconsciente durante 1,5 a 3 segundos. O fogo só custa vida, um décimo do que as chamas tirariam.

Cada ferida aparece como texto de ação, `Ferido: <parte do corpo>  -N PV`, com `(a sangrar)` quando somou à tua taxa de hemorragia; o painel Estado de saúde do inventário conta as tuas feridas por parte do corpo.

As feridas não saram sozinhas. Tornam mais provável ficares inconsciente (vê [Saúde](Health)) e atrasam a velocidade a que uma hemorragia coagula. Um Kit médico ou uma Mala de médico remove feridas, as mais antigas primeiro: não podes escolher a parte do corpo a tratar, por isso uma ferida na perna só desaparece depois de as feridas anteriores terem desaparecido.

Podes ter no máximo 32 feridas. A 33.ª mata-te, por muita vida que tenhas.

As tuas feridas ficam guardadas com a tua personagem: sair do jogo não as cura. Morrer limpa-as.

## Taxa de hemorragia {#bleed-rate}
Cada ferida soma à tua taxa de hemorragia, um número de 0 a 1 que não passa de 1. Cada arma, tipo de munição e parte do corpo tem a sua própria hemorragia; um tiro na cabeça duplica-a. Um [Colete](Armour) vestido reduz a hemorragia dos tiros no peito.

Enquanto a taxa for superior a 0:

- a cada segundo há 70 % de probabilidade de perderes vida igual à taxa (uma taxa de 0,1 custa cerca de 0,07 de vida por segundo);
- não regeneras vida;
- a cada segundo há 50 % de probabilidade de a taxa descer um pouco sozinha. Desce mais depressa quanto menor for a tua vida e mais devagar quantas mais feridas tiveres.

O painel Estado de saúde no inventário mostra a taxa como `Hemorragia: 0.00`. Está a verde quando marca 0.00 e a vermelho caso contrário.

## O que os outros vêem {#what-others-see}
Uma personagem a sangrar espirra sangue do peito e deixa uma poça de sangue aos pés a cada segundo enquanto a hemorragia se vê. Se se vê, é sorteado de novo a cada segundo: quanto maior a taxa, mais vezes, e a 0,1 ou mais vê-se sempre. Um rasto guarda as últimas 15 poças do seu dono, a mais antiga substituída pela mais recente; as poças ficam no chão onde caíram, toda a gente vê o mesmo rasto, e ele fica durante 10 minutos depois de o dono sair do servidor. Os jogadores em veículos, e a staff em serviço, não espirram nem deixam poças.

## Balas tracejantes {#tracers}
As balas tracejantes (a munição *Tracer* dos calibres 5.56 e .357, vê [Munições](Ammunition)) desenham um rasto luminoso atrás de cada tiro que toda a gente vê: aparece 2 m depois do cano e voa a 800 m/s até onde a bala cai, com 6 m de comprimento. Denunciam onde está um atirador.

## Parar a hemorragia {#stopping-the-bleed}
Mantém a tecla de interação (`F`) com o item nas mãos, em ti ou num jogador a teu lado (a menos de 1,5 m). Manter demora 4 segundos (6 segundos num paciente inconsciente) e cancela-se se largares ou te afastares. A perícia [Medicina](Medical) encurta-o.

| Item | Efeito na hemorragia |
|:--|:--|
| Ligadura suja | reduz a taxa; 33 % de probabilidade de dar ao paciente uma [infeção da ferida](Infection) |
| Ligadura antisséptica | reduz a taxa e cura uma infeção da ferida; nunca infeta |
| Kit médico | reduz a taxa e remove feridas |
| Mala de médico | pára a hemorragia por completo e remove feridas |

![Ligadura suja](images/items/20299_dirty_bandage.png) ![Ligadura antisséptica](images/items/20298_bandage.png) ![Kit médico](images/items/20296_medkit.png) ![Mala de médico](images/items/20297_doctor_bag.png)

Uma ligadura reduz uma hemorragia pequena quase a nada e uma grande só um pouco, por isso uma hemorragia séria precisa de várias ligaduras ou de um Kit médico. Uma taxa abaixo de 0,005 conta como parada. Uma ligadura gasta-se quando resulta; se não houver hemorragia, não se gasta.

Os Kits médicos removem 1 a 2 feridas de ti e 2 a 3 de outro jogador. As Malas de médico removem 1 a 2 de ti e 3 a 5 de outro jogador.
