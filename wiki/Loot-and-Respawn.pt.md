# Saque e reaparecimento

O saque e os veículos não são repostos quando o servidor reinicia. O mundo fica guardado na base de dados, e depois de um reinício há o mesmo stock que havia antes. O saque novo e os veículos novos voltam através de um **sistema de escassez**: cada categoria tem uma capacidade fixa, e os novos aparecimentos só podem repor o que falta, a um ritmo lento.

## A ideia {#the-idea}
- Cada zona de saque e a frota de veículos têm uma **capacidade**. Só pode aparecer algo novo enquanto o mundo tiver menos do que essa capacidade.
- **Tudo o que existe conta** para ela: itens no chão, itens em contentores e em malas de veículos, itens que os jogadores trazem e veículos que os jogadores estacionaram. Os itens gastos, destruídos ou apodrecidos libertam a sua parte.
- Acumular é, por isso, escassez deliberada: um grande stock abranda o reaparecimento em todo o servidor. Continua sempre a pingar saque novo, por isso quem chega de novo encontra algo dentro de uma hora.
- Nada aparece perto de jogadores (ver abaixo).

## Saque {#loot}
### Onde e quando um ponto de saque é sorteado {#where-and-when-a-loot-point-rolls}
O saque está em cerca de 11 000 pontos fixos espalhados pelas sete zonas do mapa; que zona tem o quê, e onde ficam os pontos militares, policiais e médicos, está em [Mundo e zonas](World-and-Zones). Os pontos não são enchidos no arranque do servidor. De 5 em 5 minutos cada zona ganha novo crédito de aparecimento (ver abaixo) e gasta-o de imediato em pontos escolhidos ao acaso em toda a zona, estejam os jogadores onde estiverem. Um ponto só pode ser sorteado se se verificar tudo isto:

- o seu **tempo de espera** já passou (ver abaixo);
- nenhum dos itens que ali apareceram antes continua lá (foram todos apanhados, destruídos ou apodreceram);
- **nenhum jogador está a menos de 150 m** do ponto, para o saque nunca aparecer à tua frente. Os jogadores dentro de um interior ou no tutorial não contam.

Cada sorteio tenta 3 a 5 ranhuras no ponto (3 em muitos deles), e cada ranhura só produz um item com a probabilidade própria do ponto, de 5 a 35 % consoante o ponto e 20 % num ponto típico. A maior parte dos sorteios deixa por isso um item ou nada, e alguns deixam vários; os itens saem da tabela de saque do ponto, cada tipo no máximo uma vez por sorteio, e nunca mais de 6. Um sorteio maior do que o crédito que resta é cortado.

### Tempo de espera {#cooldown}
Depois de um ponto ser sorteado, espera 6 horas, com uma variação até 50 % (3 a 9 horas), antes de poder ser sorteado outra vez, mesmo que o sorteio não tenha deixado nada. A espera conta a partir do sorteio, não da recolha, por isso um ponto esvaziado tarde pode ser sorteado logo a seguir.

### Capacidade e reposição {#capacity-and-refill}
- A capacidade de uma zona é de 0,3 itens por ponto de saque da zona, mais um quarto por cada jogador online depois do primeiro.
- De 5 em 5 minutos cada zona ganha novo crédito de aparecimento a partir do seu défice (capacidade menos itens existentes):
  - 10 % do défice por hora, mas nunca menos de 2 % da capacidade por hora enquanto houver algum défice;
  - o crédito nunca ultrapassa o défice, e as frações transitam de um ciclo para o seguinte.
- O crédito é colocado logo; nada dele fica guardado para mais tarde.

O resultado: um mapa vazio enche em cerca de um dia, e uma zona movimentada que foi saqueada fica pobre durante horas, porque o saque novo cai ao acaso em toda a zona. Quanto mais o mapa é consumido ou destruído, mais depressa ganha crédito de volta, mas uma zona cheia de itens transportados e guardados quase só ganha o pinga-pinga de 2 %.

### Desaparecimento {#despawn}
O saque em que ninguém toca desaparece do seu ponto ao fim de 24 horas, e a sua parte volta para a zona. Apanhar um item cancela o temporizador de desaparecimento. Os itens do cadáver de um jogador desaparecem ao fim de 120 minutos se ninguém os apanhar. Os itens destruídos, comidos ou gastos libertam a sua parte logo.

### Com que vêm os itens encontrados {#what-found-items-come-with}
- Uma arma vem com um carregador aleatório: nos pontos de saque militares e policiais, nos veículos da polícia e militares e nos lançamentos de armas, 30 % vêm vazias, 20 % parcialmente carregadas e 50 % cheias; noutros sítios uma arma encontrada vem, no máximo, parcialmente carregada ([Armas de fogo](Firearms)).
- Uma lata de munições nunca está cheia nem vazia ([Munições](Ammunition)).
- As garrafas, latas e pacotes têm uma quantidade aleatória de um dos seus líquidos ou aparecem vazios; uma Botija de gás tem de 0,5 a 11 kg de propano.
- Os comprimidos, as Malas de médico e os Auto-injetores vêm com conteúdo aleatório ([Medicina](Medical)).
- Uma Caixa em forma de coração encontrada como saque traz quatro itens lá dentro.

## Veículos {#vehicles}
### O primeiro sorteio e os reinícios {#the-first-roll-and-restarts}
Quando o servidor não tem veículo nenhum, cada ponto de aparecimento de veículos é sorteado uma vez (4 % de probabilidade por ponto por omissão, e depois a probabilidade de aparecimento do próprio tipo de veículo, ver [Veículos](Vehicles)). A capacidade da frota é três vezes o número de veículos desse sorteio. A partir daí, os reinícios reconstroem os veículos a partir da base de dados, onde estavam, com o seu combustível, danos e conteúdo da mala.

### Reposição {#refill}
De 5 em 5 minutos a frota ganha veículos novos pela mesma regra do saque: 10 % do défice (capacidade menos veículos existentes) por hora, no mínimo 2 % da capacidade por hora, com as frações a transitar. Um veículo novo é colocado num ponto de aparecimento aleatório que:

- já não está em tempo de espera;
- não tem nenhum veículo parado em cima;
- não tem nenhum jogador a menos de 150 m.

O tipo de veículo continua a ser sorteado com a sua probabilidade de aparecimento, por isso os tipos comuns voltam muito mais vezes do que os raros.

### Tempo de espera de um ponto de aparecimento {#cooldown-of-a-spawn-point}
Um ponto de aparecimento fica em espera durante 6 horas, com uma variação até um terço (cerca de 4 a 8 horas), quando:

- um veículo aparece nele;
- o seu veículo explode ainda no ponto;
- o seu veículo é conduzido a mais de 100 m de distância (verificado uma vez por minuto).

### Veículos abandonados e destroços {#abandoned-vehicles-and-wrecks}
- Um veículo que foi levado do seu ponto de aparecimento e depois **não é usado durante 3 dias** é removido, com a mala e tudo o que está lá dentro. Usá-lo é entrar, abrir a mala, engatá-lo como reboque, ou usar ou estar dentro do Airstream onde se entra.
- Um veículo com **fechadura personalizada** (um Kit de serralheiro, um Cadeado e corrente, um Cadeado de combinação e corrente, ou um teclado numa porta do Airstream; vê [Reparações e fechaduras](Repairing-and-Locks)) nunca é removido por esta regra, nem um afundado. Trancar as portas com `/lock` não conta: um veículo só trancado é removido como qualquer outro. Partir a fechadura personalizada torna-o removível outra vez.
- Um veículo que nunca saiu do seu ponto de aparecimento não é removido por esta regra.
- Um veículo destruído (explodido) desaparece 30 segundos depois.
- Os veículos estacionados contam para a capacidade enquanto existirem, por isso ter muitos carros abranda os novos aparecimentos para toda a gente.

## Outros reaparecimentos {#other-respawns}
Estes não usam o orçamento de escassez:

- **Caixas, caixotes e sacos** que fazem parte do mapa (cerca de 2800) são repostos de 15 em 15 minutos em qualquer sítio que tenha perdido o item, a não ser que haja um jogador a menos de 60 m. Voltam cheios: os sacos do lixo com lixo, os pacotes e caixas de cartão com tralha, os caixotes com ferragens, o caixote de fruta com fruta e o caixote de armas com munições e, de vez em quando, uma arma. Ver [Contentores e sacos](Containers-and-Bags).
- **As árvores** abatidas com uma Motosserra voltam a crescer 3 semanas depois, mesmo através de reinícios; ver [Árvores e madeira](Trees-and-Wood).
- **As bancadas de trabalho, as máquinas do ferro-velho e os outros itens fixos** que são desmontados ou levados voltam ao sítio quando o servidor reinicia; ver [Mundo e zonas](World-and-Zones).
- **Os lançamentos de abastecimentos e os depósitos de armas** seguem temporizadores e números de jogadores próprios e não contam para a capacidade de nenhuma zona; ver [Lançamentos de provisões](Supply-Drops).

## Mapas {#maps}
Densidade dos pontos de saque, e todos os pontos de aparecimento de veículos por grupo.

<a href="images/map/loot.png" target="_blank" rel="noopener noreferrer" title="Ver o mapa em tamanho real; Ctrl/Cmd-clique ou clique com o botão do meio para abrir noutro separador"><img src="images/map/loot.png" alt="Mapas"></a>

<a href="images/map/vehicles.png" target="_blank" rel="noopener noreferrer" title="Ver o mapa em tamanho real; Ctrl/Cmd-clique ou clique com o botão do meio para abrir noutro separador"><img src="images/map/vehicles.png" alt="Mapas"></a>
