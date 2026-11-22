# Baterias e motores de arranque

![Bateria de carro](images/items/20208_car_battery.png) ![Motor de arranque](images/items/20269_starter_motor.png)

Duas peças debaixo do capot decidem se um motor pega: a **bateria** e o **motor de arranque**. Todos os veículos com motor debaixo de um capot têm as duas (carros, camiões, carrinhas, helicópteros e aviões); as motas, as bicicletas, os barcos e os veículos abertos sem portas (BF Injection, Bandito, Baggage...) não têm nenhuma e não precisam. Os itens são a [Bateria de carro](Car-Battery) e o [Motor de arranque](Starter-Motor); as luzes que mostram o estado deles estão no [Painel do condutor](Drivers-Dashboard).

## O capot {#the-bonnet}
Prime `F` à frente de um veículo destrancado para abrir ou fechar o capot (um trancado diz *O capot está trancado: destranca primeiro o veículo*). Quando há várias interações disponíveis, `F` abre um menu de ações partilhado. Desliza para escolher, clica para confirmar, ou prime Escape para fechar. Os itens do chão e as peças de veículo que estão por perto aparecem juntos, cada um com a etiqueta do seu alvo; as opções mudam à medida que te moves ou mudas o que seguras. Tudo o que vem a seguir faz-se com o capot aberto. As reparações também precisam dele aberto; vê [Reparações e fechaduras](Repairing-and-Locks).

## Bateria {#battery}
Um veículo encontrado no mundo tem uma carga de 15 a 100 %, mas cerca de 35 % deles aparecem sem bateria nenhuma (e cerca de 30 % sem motor de arranque, sorteado em separado), por isso encontrar um que arranque costuma obrigar a trazer peças. O motor precisa de pelo menos 10 % para rodar: abaixo disso a chave dá *A bateria está descarregada*, e um veículo sem bateria não reage. Os faróis também funcionam com a bateria: com o motor desligado só se acendem com 10 % ou mais, e apagam-se quando a carga cai abaixo disso.

| Situação | Carga |
|:--|:--|
| Estacionado, motor desligado | não se perde nada durante 24 horas depois de o motor ter trabalhado pela última vez, depois 1 % por hora |
| Faróis ligados, motor desligado | 12 % por hora desde o primeiro segundo |
| Chave deixada em ACC, motor desligado | 3 % por hora desde o primeiro segundo, somados aos dos faróis |
| Motor a trabalhar, parado | ganha 2,5 % por minuto |
| Motor a trabalhar, a conduzir (acima de 5 km/h) | ganha 10 % por minuto, por isso uma bateria vazia fica cheia ao fim de cerca de dez minutos na estrada |

Estas taxas são para uma bateria de 60 Ah. As baterias existem de 35 a 95 Ah, as pequenas com mais frequência: todas as taxas se ajustam ao tamanho, por isso uma bateria de 35 Ah descarrega e carrega cerca de 1,7 vezes mais depressa em percentagem e uma de 95 Ah cerca de 0,6 vezes mais depressa. O tamanho acompanha a bateria e aparece no nome (*Bateria de carro 45Ah (63%)*).

Uma bateria no compartimento está **apertada** (aparafusada, e o carro pode usá-la), **solta** (pousada lá, e o carro não arranca enquanto não a apertares) ou em falta. Nada do compartimento cai para o chão.

**Desapertar e apertar:** segura uma Catraca no capot aberto e prime `F`. Um menu lista só o que se aplica: *Desapertar a bateria* quando está apertada, *Apertar a bateria* quando está solta. Cada uma é um trabalho de 3 segundos, mais curto com a [perícia](Skills) Reparação. Desapertar deixa a bateria no compartimento e pára o motor se estava a trabalhar. Se só houver uma ação disponível, é executada logo; se houver várias, esperam pela tua escolha. De mãos vazias, o menu também lista os trabalhos de apertar e desapertar aplicáveis, marcados com *(Catraca)*. Equipa uma Catraca para os fazeres; escolher um de mãos vazias diz-te *Precisas de uma Catraca*.

**Tirá-la:** só uma bateria solta. De mãos vazias, toca em `F` no capot aberto e a Bateria de carro vai para as tuas mãos, com o nome com o tamanho e a carga (*Bateria de carro 45Ah (63%)*). Uma bateria apertada tem de ser desapertada primeiro.

**Montar uma:** segura uma Bateria de carro no capot aberto, prime `F` e escolhe *Colocar a bateria*. Vai para um espaço vazio, solta, e as tuas mãos ficam livres. Aperta-a no menu de ações ou o carro não arranca. Um veículo que já tenha uma recusa-a. A bateria traz a carga que tem; uma encontrada como saque tem de 15 a 100 %, e a carga mantém-se enquanto a bateria é transportada. Uma bateria descarregada continua descarregada. Trocar uma bateria descarregada por uma carregada de outro veículo é a maneira rápida de pôr um carro a andar.

**EMPs:** um [EMP](Explosives) que rebente a menos de 12 m desliga o motor e descarrega a bateria instalada a 0 %; os faróis apagam-se com ela. O carro não volta a arrancar enquanto não for montada uma bateria carregada; tirar a descarregada e voltar a pô-la não a recupera, e a carga vazia sobrevive a um reinício do servidor.

## Motor de arranque {#starter-motor}
Cada arranque do motor bem-sucedido gasta o motor de arranque. Um novo dura entre 60 e 400 arranques, à sorte; quando a vida se esgota a chave só estala (*O motor não pega: o motor de arranque está morto*). A bateria, o combustível e as luzes ficam intactos; só o arranque se perdeu. Cerca de 2 % dos veículos aparecem com o motor de arranque morto, por isso um carro que não arranca com boa bateria, combustível e um motor a funcionar provavelmente gastou o dele.

Está apertado, solto ou em falta, tal como a bateria, e as duas peças são independentes uma da outra. O motor tem de estar desligado.

**Desapertar e apertar:** o mesmo menu de ações. *Desapertar o motor de arranque* aparece quando está apertado; *Apertar o motor de arranque* quando está solto. Cada um demora 6 segundos, menos com a [perícia](Skills) Reparação. Desapertar deixa o motor no compartimento.

**Tirá-lo:** toca em `F` de mãos vazias num motor solto. Vai para as tuas mãos e guarda os arranques que lhe restavam, mesmo um morto (0 continua 0).

**Montar um:** segura um Motor de arranque no capot aberto, prime `F` e escolhe *Colocar o motor de arranque*. O espaço do arranque tem de estar vazio; um motor que ainda lá esteja, apertado ou solto, tem de sair primeiro. O item é consumido e o motor fica solto até o apertares. Um que tenha sido retirado volta a entrar com os arranques que lhe restavam; um encontrado como saque, sem vida guardada, sorteia 60 a 400 novos. Não há maneira de ver quantos arranques restam: o primeiro sinal é o estalido.

## Porque é que um carro não arranca {#why-a-car-will-not-start}
As verificações correm por esta ordem; a primeira que falha é a que te é indicada:

1. Sem bateria, bateria solta (*Aperta a bateria: o carro não pega*), ou bateria abaixo de 10 %.
2. O veículo está destruído (300 de vida ou menos) ou o depósito está vazio; vê [Veículos](Vehicles) e [Combustível](Fuel).
3. O motor de arranque está solto (*Aperta o motor de arranque: o carro não pega*), em falta ou morto. Um em falta mostra o mesmo estalido que um morto.

Cada arranque que passa as duas primeiras custa um ao motor de arranque, mesmo um arranque feito só para verificar.

Vê também [Veículos](Vehicles), [Reparações e fechaduras](Repairing-and-Locks) e [Explosivos](Explosives).
