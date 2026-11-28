# Veículos

![Veículos comuns: Sentinel, Bobcat, Rumpo, Sanchez, Moonbeam e Yosemite](images/scenes/vehicles.png)

![Bobcat](images/vehicles/422_bobcat.png)

Há carros, camiões, motas, barcos e alguns aviões espalhados pelo mapa. São a forma mais rápida de te deslocares e as malas levam muita coisa, mas precisam de [combustível](Fuel), podem ficar danificados e ser [reparados](Repairing-and-Locks), e podem estar trancados.

## Condução {#driving}
`Y` liga ou desliga o motor (só o condutor), `N` muda as luzes, `R` abre o [rádio](Radio), `/lock` ou o controlo de sub-missão do GTA tranca as portas por dentro, e a tecla de fogo secundário do veículo (`LCtrl` / `Num 0`) engata um reboque; todas seguem as tuas teclas definidas, ver [Controlos](Controls). Não podes entrar num veículo enquanto carregas um item volumoso (uma roda, um painel, uma caixa) nem enquanto estás a reparar ou a abastecer.

O motor não arranca com o depósito vazio, com a bateria descarregada ou em falta (mais abaixo), nem quando o veículo está muito avariado (vida abaixo de 300). Abaixo de 450 de vida o motor pode falhar enquanto conduzes a mais de 30 km/h, tanto mais vezes quanto pior o estado. Com o motor a trabalhar o depósito esvazia-se devagar, mais depressa em velocidade e conforme o consumo de cada tipo; com o depósito vazio o motor pára. Quando entras como condutor, uma dica diz-te quão avariado está o veículo e que ferramenta o repara.

Quatro páginas aprofundam o assunto: [Painel do condutor](Drivers-Dashboard) para as luzes de aviso, o conta-rotações e o voltímetro que o condutor vê, [Baterias e motores de arranque](Car-Batteries-and-Starters) para o que mantém o motor a rodar, [Peças de veículos](Vehicle-Salvage-Parts) para as portas, o capot, a mala e os para-choques que saem de todos os carros e voltam a ser montados, e [Reboques e rebocar](Trailers-and-Towing) para o engate e o Airstream.

## Bateria {#battery}
![Bateria de carro](images/items/20208_car_battery.png)

Todos os veículos com motor debaixo de um capot têm bateria: carros, camiões, carrinhas, helicópteros e aviões. Motas, bicicletas, barcos e os veículos abertos sem portas (BF Injection, Bandito, Baggage...) não têm nem precisam.

- Um veículo encontrado no mundo tem uma carga de 15 a 100 %. Abaixo de 10 % o motor não pega (*The battery is flat*) e um veículo sem bateria não arranca de todo.
- **Estacionado**: não se perde nada durante 24 horas depois de o motor ter funcionado pela última vez; depois disso a carga desce 1 % por hora.
- **A andar**: o motor carrega a bateria, 10 % por minuto a conduzir (acima de 5 km/h) e um quarto disso em ralenti, por isso uma bateria vazia fica cheia ao fim de uns dez minutos na estrada.
- **Faróis** deixados acesos com o motor desligado gastam 12 % por hora desde o primeiro segundo; abaixo de 10 % apagam-se. Com o motor desligado, as luzes só acendem com a bateria a 10 % ou mais.

O **capot** de um veículo destrancado abre-se e fecha-se com um toque em `F` à frente, de mãos vazias (um veículo trancado diz *The bonnet is locked: unlock the vehicle first*). Com o capot aberto:

- um toque em `F` de mãos vazias levanta uma bateria **solta** para as tuas mãos (com a carga na etiqueta, *Car Battery (63%)*), ou um motor de arranque solto. Uma peça apertada fica no compartimento até ser desapertada.
- um toque em `F` com uma Bateria de carro na mão põe-na solta num espaço vazio. O mesmo toque com um Motor de arranque põe-no solto.
- prime `F` com uma **Catraca** para ver as ações disponíveis: reparar o motor quando se aplica a faixa dessa ferramenta, desapertar uma bateria apertada ou apertar uma solta, e o mesmo para o motor de arranque. Quando há várias ações disponíveis, um menu partilhado inclui os itens do chão próximos e as ações do veículo. Roda para escolher e clica para confirmar; Escape fecha-o. O motor não arranca enquanto uma peça solta não for apertada.

Uma Bateria de carro (tamanho 2) mantém a carga enquanto a carregas; uma encontrada como saque tem 15 a 100 %, e uma descarregada continua descarregada. Trocar uma bateria descarregada por uma carregada de outro veículo é a maneira rápida de pôr um carro a andar. Ver [Baterias e motores de arranque](Car-Batteries-and-Starters).

## EMPs e baterias de carro {#emps-and-car-batteries}
Um [EMP](Explosives) desliga motores num raio de 12 m. O seu novo efeito sobre baterias também descarrega para 0 % uma Bateria de carro instalada e apaga os faróis. O carro não volta a arrancar enquanto não montares uma bateria carregada; tirar a bateria descarregada e voltar a instalá-la não lhe devolve a carga. A carga em zero sobrevive a um reinício normal do servidor.

## Tipos e aparecimento {#types-and-spawning}
Cada veículo pertence a um **grupo** (Civil, Industrial, Médico, Militar, Polícia ou Único), a um **tipo** (carro, camião, mota, bicicleta, helicóptero, avião ou barco) e a um tamanho (pequeno, médio ou grande). Os pontos de aparecimento estão ligados a um grupo e aos tipos e tamanhos permitidos aí. Cada tipo tem a sua **probabilidade de aparecimento**: a percentagem com que um dado veículo é permitido quando um ponto o escolhe. Tipos raros como o Rhino quase nunca se veem. Os pisos do stand de automóveis de Doherty, em San Fierro, só têm carros civis comuns.

- Cada ponto de aparecimento tem uma probabilidade de ter um veículo (12 % por omissão, o triplo dos 4 % originais).
- Quase todos os veículos aparecem danificados (vida sobretudo entre 300 e 500 em 1000), com painéis, portas, luzes e pneus partidos ao acaso.
- Muitos estão depenados: cerca de 40 % dos carros e camiões não têm de uma a quatro rodas, cerca de 35 % dos veículos não têm bateria e cerca de 30 % não têm motor de arranque (ver [Baterias e motores de arranque](Car-Batteries-and-Starters)).
- Quase todos os depósitos estão praticamente vazios; cerca de um veículo em dez tem mais de um litro ou assim.
- Um veículo com uma porta danificada e um depósito está trancado metade das vezes.
- Um veículo levado do seu ponto de aparecimento e depois não usado durante 3 dias é removido com a mala, a não ser que tenha uma fechadura personalizada (`/lock` sozinho não o salva), um destroço desaparece 30 segundos depois de explodir, e os veículos novos regressam devagar através do sistema de escassez, nunca a menos de 150 m de um jogador; ver [Saque e reaparecimento](Loot-and-Respawn).

## Mala {#trunk}
Vai à traseira de um veículo destrancado e prime `F` para abrir a mala. Funciona como um [contentor](Containers-and-Bags): o número de espaços na tabela abaixo conta-se em tamanhos de itens ([Tamanhos dos itens](Item-Sizes)). Uma mala trancada pode ser arrombada, ver [Reparações e fechaduras](Repairing-and-Locks). Uma mala de 0 espaços quer dizer que o veículo não tem.

Uma mala aberta fica aberta: prime `F` outra vez na traseira, de mãos vazias, para a fechar. Não fecha enquanto alguém ainda estiver a mexer nela, e és avisado disso.

## Porta-luvas {#glovebox}
Os carros e os camiões de cabine têm um porta-luvas no tablier. Senta-te no lugar do condutor ou do passageiro da frente e prime `F` para o abrir; sair fecha-o. É um [contentor](Containers-and-Bags) pequeno de 4 espaços que só aceita itens de tamanho 1 (comprimidos, bilhetes, um telemóvel, uma faca, uma pistola), por isso tudo o que for maior é recusado. A tranca do veículo não interessa, já estás lá dentro. Um veículo recém-aparecido pode ter até dois itens pequenos lá dentro. Motas, barcos, aeronaves, tanques, reboques e o Airstream não têm.

## Reboques {#trailers}
Um veículo com engate pode rebocar um reboque da mesma classe de tamanho. Só alguns têm um de origem (o Utility reboca o seu Trailer, o Tractor o Airstream, o Tug e o Baggage os carrinhos do aeroporto, o Linerunner e o Petrol o reboque Articulated); todos os outros carros e pick-ups precisam de uma [barra de reboque](Tow-Bar) aparafusada na traseira, que lhes dá o engate pequeno para o Trailer e o Airstream. Dá marcha-atrás junto ao reboque e prime a tecla de fogo secundário; prime-a outra vez para o largar. Enquanto conduzes um veículo com engate, a lista de teclas mostra `Hitch trailer` quando há um reboque livre ao alcance (o comprimento dos dois veículos mais um metro, de centro a centro) e `Unhitch trailer` enquanto reboca; só o condutor pode engatar. Um reboque arrancado num acidente fica solto até o engatares de novo, mas um reboque que se solta de um camião vazio volta a engatar-se sozinho.

O Airstream é uma caravana onde se entra, com porta e fechadura, espaço para carga que viaja com ela, dois suportes para botijas de gás e um casco que aceita [Blindagem de veículos](Vehicle-Armour), que abranda o veículo que reboca. Está descrito em [Casas e reboques](Houses-and-Trailers), juntamente com os reboques espalhados pelo mapa onde se pode entrar mas que não se rebocam.

## Empurrar {#pushing}
Correr ou andar contra um veículo estacionado não o move. Para mover um sem o conduzir, põe-te à frente ou atrás dele de mãos vazias e escolhe `Push` na lista de interação (`F`), depois anda contra ele: pões as duas mãos nele e ele rola em linha reta ao longo do seu comprimento, para a frente a partir da traseira ou para trás a partir da frente, enquanto continuas a andar. Só podes empurrar um carro, quad, reboque ou avião ligeiro vazio que mais ninguém esteja a empurrar, e só até ao peso que a tua [Força](Skills) permite: 3000 kg sem treino, a subir por igual até 10 000 kg com a Força no máximo (6500 kg com 0,5), por isso os camiões pesados precisam de alguém forte; motas, barcos e helicópteros não se movem à mão. `Stop pushing` na mesma lista, sair pela ponta ou pelo lado, saltar, apontar ou alguém entrar para dentro acaba com isso.

A velocidade é `(0.8 + Strength) x (0.4 + 0.6 x health / 100)` metros por segundo, vezes um fator de peso de `√(1400 / mass)` mantido entre 0,35 e 1,3: um jogador sem treino e com a vida cheia move um carro de 1400 kg a 0,8 m/s, um Mestre a 1,8 m/s, e um muito ferido a menos de metade disso. Um empurrão que moveu o veículo pelo menos 3 m treina a [Força](Skills), com ganho completo a partir dos 15 m.

## Sobreaquecimento {#overheating}
A arma do Rhino sobreaquece. Uma barra de calor vermelha aparece na parte de baixo do ecrã enquanto o conduzes. Com o motor a trabalhar, cada tiro acrescenta 20 de calor, e o calor desce 10 por segundo em qualquer altura. Acima de 32 a barra diz *Overheating!*; acima de 40 uma explosão rebenta no veículo e o calor recomeça do zero, por isso dispara em rajadas curtas.

## Todos os veículos {#all-vehicles}
O depósito está em litros, a mala em espaços, a probabilidade de aparecimento em percentagem.

<!-- table:vehicles -->
|  | Veículo | Tipo | Grupo | Roda | Depósito | Espaços na mala | Probabilidade de aparecer |
|:--|:--|:--|:--|:--|--:|--:|--:|
|  | AT-400 | avião | Civil |  | 1200 L | 60 | 1,5 |
|  | Andromada | avião | Civil |  | 1400 L | 80 | 1 |
|  | Beagle | avião | Civil |  | 160 L | 24 | 4 |
|  | Cropduster | avião | Civil |  | 70 L | 0 | 4 |
|  | Dodo | avião | Civil |  | 90 L | 16 | 4 |
|  | Hydra | avião | Civil |  | 220 L | 0 | 0,6 |
|  | Nevada | avião | Civil |  | 400 L | 48 | 3 |
|  | RC Baron | avião | Civil |  | 4 L | 0 | 0 |
| ![](images/vehicles/476_rustler.png) | Rustler | avião | Civil |  | 88 L | 0 | 2 |
|  | Shamal | avião | Civil |  | 700 L | 40 | 2 |
|  | Skimmer | avião | Civil |  | 80 L | 0 | 4 |
|  | Stuntplane | avião | Civil |  | 60 L | 0 | 3 |
| ![](images/vehicles/472_coastg.png) | Coastguard | barco | Civil |  | 120 L | 24 | 7 |
| ![](images/vehicles/473_dinghy.png) | Dinghy | barco | Civil |  | 81 L | 10 | 64 |
|  | Jetmax | barco | Civil |  | 70 L | 14 | 8 |
| ![](images/vehicles/595_launch.png) | Launch | barco | Civil |  | 213 L | 26 | 7 |
| ![](images/vehicles/484_marquis.png) | Marquis | barco | Civil |  | 900 L | 100 | 50 |
|  | Predator | barco | Civil |  | 120 L | 20 | 6 |
| ![](images/vehicles/453_reefer.png) | Reefer | barco | Civil |  | 245 L | 48 | 60 |
|  | Speeder | barco | Civil |  | 70 L | 16 | 8 |
| ![](images/vehicles/446_squalo.png) | Squalo | barco | Civil |  | 50 L | 28 | 20 |
| ![](images/vehicles/454_tropic.png) | Tropic | barco | Civil |  | 260 L | 44 | 55 |
| ![](images/vehicles/539_vortex.png) | Vortex | barco | Civil |  | 45 L | 4 | 1,5 |
|  | BMX | bicicleta | Civil |  | 0 L | 1 | 10 |
|  | Bike | bicicleta | Civil |  | 0 L | 1 | 12 |
| ![](images/vehicles/510_mtbike.png) | Mountain Bike | bicicleta | Civil |  | 0 L | 2 | 8 |
| ![](images/vehicles/578_dft30.png) | APC-30 | camião | Único | [Roda de camião](Truck-Wheel) | 60 L | 0 | 0,3 |
|  | Airstream | camião | Civil | [Roda de carrinha ligeira](Light-Van-Wheel) | 0 L | 0 | 3 |
| ![](images/vehicles/416_ambulan.png) | Ambulance | camião | Médico | [Roda de carrinha ligeira](Light-Van-Wheel) | 80 L | 70 | 30 |
| ![](images/vehicles/591_artict3.png) | Articulated | camião | Industrial | [Roda de camião](Truck-Wheel) | 0 L | 100 | 1 |
|  | Articulated Trailer | camião | Industrial | [Roda de camião](Truck-Wheel) | 0 L | 100 | 4 |
|  | Articulated Trailer 2 | camião | Industrial | [Roda de camião](Truck-Wheel) | 0 L | 100 | 3 |
| ![](images/vehicles/424_bfinject.png) | BF Injection | camião | Civil | [Roda todo-o-terreno](Offroad-Wheel) | 40 L | 24 | 15 |
|  | Baggage Box A | camião | Industrial | [Roda de jante de aço](Steel-Rim-Wheel) | 0 L | 20 | 8 |
|  | Baggage Box B | camião | Industrial | [Roda de jante de aço](Steel-Rim-Wheel) | 0 L | 20 | 6 |
| ![](images/vehicles/568_bandito.png) | Bandito | camião | Único | [Roda todo-o-terreno](Offroad-Wheel) | 48 L | 15 | 0,3 |
| ![](images/vehicles/433_barracks.png) | Barracks | camião | Militar | [Roda de camião](Truck-Wheel) | 200 L | 100 | 3 |
|  | Benson | camião | Industrial | [Roda de camião ligeiro](Light-Truck-Wheel) | 100 L | 80 | 10 |
|  | Berkley RC Van | camião | Único | [Roda de carrinha ligeira](Light-Van-Wheel) | 50 L | 28 | 2 |
| ![](images/vehicles/422_bobcat.png) | Bobcat | camião | Civil | [Roda de camião ligeiro](Light-Truck-Wheel) | 60 L | 40 | 76 |
|  | BoxBurg | camião | Industrial | [Roda de carrinha ligeira](Light-Van-Wheel) | 70 L | 60 | 8 |
| ![](images/vehicles/498_boxville.png) | Boxville | camião | Industrial | [Roda de carrinha ligeira](Light-Van-Wheel) | 75 L | 70 | 55 |
|  | Burrito | camião | Civil | [Roda de carrinha ligeira](Light-Van-Wheel) | 65 L | 60 | 26 |
|  | Bus | camião | Civil | [Roda de camião](Truck-Wheel) | 150 L | 40 | 6 |
|  | Camper | camião | Civil | [Roda de carrinha ligeira](Light-Van-Wheel) | 80 L | 70 | 6 |
|  | Cement Truck | camião | Industrial | [Roda de camião](Truck-Wheel) | 120 L | 10 | 5 |
|  | Coach | camião | Civil | [Roda de camião](Truck-Wheel) | 160 L | 36 | 5 |
|  | Combine | camião | Industrial | [Roda de trator](Tractor-Wheel) | 80 L | 20 | 2 |
| ![](images/vehicles/578_dft30.png) | DFT-30 | camião | Industrial | [Roda de camião](Truck-Wheel) | 60 L | 0 | 35 |
|  | Dozer | camião | Industrial | [Roda de máquina pesada](Heavy-Plant-Wheel) | 40 L | 0 | 2 |
|  | Dumper | camião | Industrial | [Roda de máquina pesada](Heavy-Plant-Wheel) | 200 L | 20 | 4 |
| ![](images/vehicles/573_duneride.png) | Duneride | camião | Civil | [Roda de camião](Truck-Wheel) | 180 L | 85 | 10 |
| ![](images/vehicles/427_enforcer.png) | Enforcer | camião | Polícia | [Roda de camião](Truck-Wheel) | 90 L | 64 | 10 |
|  | FBI Rancher | camião | Polícia | [Roda de camião ligeiro](Light-Truck-Wheel) | 100 L | 48 | 6 |
| ![](images/vehicles/528_fbitruck.png) | FBI Truck | camião | Polícia | [Roda de camião](Truck-Wheel) | 80 L | 45 | 3 |
| ![](images/vehicles/407_firetruk.png) | Firetruck | camião | Médico | [Roda de camião](Truck-Wheel) | 115 L | 65 | 0,5 |
|  | Firetruck LA | camião | Médico | [Roda de camião](Truck-Wheel) | 115 L | 60 | 2 |
| ![](images/vehicles/455_flatbed.png) | Flatbed | camião | Industrial | [Roda de camião](Truck-Wheel) | 70 L | 100 | 15 |
|  | Forklift | camião | Industrial | [Roda de jante de aço](Steel-Rim-Wheel) | 12 L | 0 | 8 |
|  | Hotdog | camião | Civil | [Roda de carrinha ligeira](Light-Van-Wheel) | 50 L | 24 | 3 |
| ![](images/vehicles/579_huntley.png) | Huntley | camião | Civil | [Roda de jante de liga leve](Alloy-Wheel) | 70 L | 50 | 57 |
| ![](images/vehicles/508_journey.png) | Journey | camião | Civil | [Roda de carrinha ligeira](Light-Van-Wheel) | 60 L | 76 | 10 |
|  | Landstalker | camião | Civil | [Roda de jante de liga leve](Alloy-Wheel) | 80 L | 48 | 30 |
| ![](images/vehicles/403_linerun.png) | Linerunner | camião | Industrial | [Roda de camião](Truck-Wheel) | 120 L | 12 | 5 |
| ![](images/vehicles/500_mesa.png) | Mesa | camião | Civil | [Roda todo-o-terreno](Offroad-Wheel) | 77 L | 48 | 70 |
|  | Monster | camião | Único | [Roda de monster truck](Monster-Truck-Wheel) | 90 L | 12 | 2 |
|  | Monster A | camião | Único | [Roda de monster truck](Monster-Truck-Wheel) | 90 L | 8 | 1,5 |
|  | Monster B | camião | Único | [Roda de monster truck](Monster-Truck-Wheel) | 90 L | 8 | 1,5 |
|  | Mr Whoopee | camião | Civil | [Roda de carrinha ligeira](Light-Van-Wheel) | 50 L | 30 | 3 |
|  | Mule | camião | Industrial | [Roda de camião ligeiro](Light-Truck-Wheel) | 80 L | 70 | 22 |
|  | Newsvan | camião | Civil | [Roda de carrinha ligeira](Light-Van-Wheel) | 60 L | 40 | 6 |
|  | Packer | camião | Industrial | [Roda de camião](Truck-Wheel) | 140 L | 16 | 6 |
| ![](images/vehicles/470_patriot.png) | Patriot | camião | Militar | [Roda todo-o-terreno](Offroad-Wheel) | 94 L | 50 | 22 |
|  | Petrol | camião | Industrial | [Roda de camião](Truck-Wheel) | 200 L | 12 | 6 |
|  | Petrol Trailer | camião | Industrial | [Roda de camião](Truck-Wheel) | 0 L | 40 | 4 |
|  | Picador | camião | Civil | [Roda de camião ligeiro](Light-Truck-Wheel) | 60 L | 40 | 22 |
|  | Pony | camião | Civil | [Roda de carrinha ligeira](Light-Van-Wheel) | 60 L | 55 | 28 |
| ![](images/vehicles/489_rancher.png) | Rancher | camião | Civil | [Roda de camião ligeiro](Light-Truck-Wheel) | 110 L | 52 | 44 |
|  | Rancher Lure | camião | Civil | [Roda de camião ligeiro](Light-Truck-Wheel) | 90 L | 46 | 20 |
| ![](images/vehicles/599_copcarru.png) | Ranger | camião | Polícia | [Roda de camião ligeiro](Light-Truck-Wheel) | 110 L | 48 | 30 |
| ![](images/vehicles/432_rhino.png) | Rhino | camião | Militar | [Roda de camião](Truck-Wheel) | 1900 L | 12 | 1 |
| ![](images/vehicles/515_rdtrain.png) | Roadpain | camião | Único | [Roda de camião](Truck-Wheel) | 210 L | 0 | 1,4 |
| ![](images/vehicles/440_rumpo.png) | Rumpo | camião | Industrial | [Roda de carrinha ligeira](Light-Van-Wheel) | 55 L | 80 | 45 |
|  | S.W.A.T. | camião | Polícia | [Roda de camião](Truck-Wheel) | 100 L | 50 | 3 |
| ![](images/vehicles/543_sadler.png) | Sadler | camião | Civil | [Roda de camião ligeiro](Light-Truck-Wheel) | 60 L | 40 | 34 |
|  | Sadler Damaged | camião | Civil | [Roda de camião ligeiro](Light-Truck-Wheel) | 55 L | 36 | 20 |
| ![](images/vehicles/495_sandking.png) | Sandking | camião | Único | [Roda todo-o-terreno](Offroad-Wheel) | 120 L | 46 | 3,5 |
|  | Securicar | camião | Industrial | [Roda de camião](Truck-Wheel) | 70 L | 50 | 6 |
|  | Slamvan | camião | Civil | [Roda de camião ligeiro](Light-Truck-Wheel) | 60 L | 36 | 6 |
| ![](images/vehicles/578_dft30.png) | Steamroller | camião | Único | [Roda de camião](Truck-Wheel) | 60 L | 0 | 0,3 |
|  | Sweeper | camião | Industrial | [Roda de jante de aço](Steel-Rim-Wheel) | 20 L | 4 | 6 |
|  | Tow Truck | camião | Industrial | [Roda de camião ligeiro](Light-Truck-Wheel) | 70 L | 20 | 8 |
|  | Tractor | camião | Industrial | [Roda de trator](Tractor-Wheel) | 40 L | 8 | 6 |
| ![](images/vehicles/611_utiltr1.png) | Trailer | camião | Industrial | [Roda de camião](Truck-Wheel) | 0 L | 50 | 20 |
|  | Trashmaster | camião | Industrial | [Roda de camião](Truck-Wheel) | 110 L | 40 | 8 |
| ![](images/vehicles/403_linerun.png) | Truckfort | camião | Único | [Roda de camião](Truck-Wheel) | 265 L | 76 | 1,1 |
| ![](images/vehicles/583_tug.png) | Tug | camião | Industrial | [Roda de jante de aço](Steel-Rim-Wheel) | 10 L | 8 | 10 |
|  | Tug Stairs | camião | Industrial | [Roda de jante de aço](Steel-Rim-Wheel) | 0 L | 8 | 4 |
|  | Utility | camião | Industrial | [Roda de camião ligeiro](Light-Truck-Wheel) | 60 L | 40 | 16 |
| ![](images/vehicles/478_walton.png) | Walton | camião | Civil | [Roda de camião ligeiro](Light-Truck-Wheel) | 60 L | 46 | 40 |
| ![](images/vehicles/456_yankee.png) | Yankee | camião | Industrial | [Roda de camião](Truck-Wheel) | 60 L | 80 | 40 |
| ![](images/vehicles/554_yosemite.png) | Yosemite | camião | Civil | [Roda de camião ligeiro](Light-Truck-Wheel) | 60 L | 44 | 70 |
|  | Admiral | carro | Civil | [Roda de berlina](Saloon-Wheel) | 60 L | 40 | 22 |
|  | Alpha | carro | Civil | [Roda desportiva](Sport-Wheel) | 55 L | 20 | 4 |
| ![](images/vehicles/485_baggage.png) | Baggage | carro | Industrial | [Roda de carro pequeno](Small-Car-Wheel) | 14,5 L | 8 | 35,5 |
|  | Banshee | carro | Civil | [Roda desportiva](Sport-Wheel) | 55 L | 20 | 5 |
|  | Blade | carro | Civil | [Roda clássica](Classic-Wheel) | 55 L | 28 | 10 |
| ![](images/vehicles/496_blistac.png) | Blista Compact | carro | Civil | [Roda de carro pequeno](Small-Car-Wheel) | 40 L | 38 | 68 |
| ![](images/vehicles/504_bloodra.png) | Bloodring Banger | carro | Único | [Roda clássica](Classic-Wheel) | 65 L | 32 | 0,5 |
|  | Bravura | carro | Civil | [Roda de berlina](Saloon-Wheel) | 50 L | 34 | 36 |
|  | Broadway | carro | Civil | [Roda clássica](Classic-Wheel) | 55 L | 28 | 8 |
|  | Buccaneer | carro | Civil | [Roda clássica](Classic-Wheel) | 55 L | 30 | 12 |
|  | Buffalo | carro | Civil | [Roda desportiva](Sport-Wheel) | 60 L | 30 | 6 |
|  | Bullet | carro | Civil | [Roda desportiva](Sport-Wheel) | 55 L | 16 | 2 |
|  | Cabbie | carro | Civil | [Roda clássica](Classic-Wheel) | 52 L | 34 | 22 |
|  | Caddy | carro | Industrial | [Roda de jante de aço](Steel-Rim-Wheel) | 12 L | 4 | 8 |
|  | Cadrona | carro | Civil | [Roda de carro pequeno](Small-Car-Wheel) | 50 L | 32 | 30 |
|  | Cheetah | carro | Civil | [Roda desportiva](Sport-Wheel) | 55 L | 16 | 2 |
| ![](images/vehicles/542_clover.png) | Clover | carro | Civil | [Roda clássica](Classic-Wheel) | 62 L | 34 | 75 |
|  | Club | carro | Civil | [Roda de carro pequeno](Small-Car-Wheel) | 48 L | 22 | 8 |
| ![](images/vehicles/480_comet.png) | Comet | carro | Civil | [Roda desportiva](Sport-Wheel) | 50 L | 20 | 5 |
| ![](images/vehicles/573_duneride.png) | Doomride | carro | Único | [Roda de camião](Truck-Wheel) | 180 L | 80 | 0,5 |
|  | Elegant | carro | Civil | [Roda de berlina](Saloon-Wheel) | 60 L | 40 | 22 |
|  | Elegy | carro | Civil | [Roda desportiva](Sport-Wheel) | 55 L | 24 | 5 |
|  | Emperor | carro | Civil | [Roda de berlina](Saloon-Wheel) | 55 L | 36 | 32 |
|  | Esperanto | carro | Civil | [Roda clássica](Classic-Wheel) | 55 L | 34 | 28 |
|  | Euros | carro | Civil | [Roda desportiva](Sport-Wheel) | 52 L | 22 | 5 |
|  | Feltzer | carro | Civil | [Roda desportiva](Sport-Wheel) | 55 L | 22 | 5 |
|  | Flash | carro | Civil | [Roda de carro pequeno](Small-Car-Wheel) | 50 L | 22 | 6 |
|  | Fortune | carro | Civil | [Roda de berlina](Saloon-Wheel) | 52 L | 30 | 24 |
|  | Glendale | carro | Civil | [Roda clássica](Classic-Wheel) | 55 L | 36 | 34 |
|  | Glendale Damaged | carro | Civil | [Roda clássica](Classic-Wheel) | 50 L | 32 | 20 |
|  | Greenwood | carro | Civil | [Roda de berlina](Saloon-Wheel) | 55 L | 36 | 28 |
|  | Hermes | carro | Civil | [Roda clássica](Classic-Wheel) | 55 L | 30 | 12 |
|  | Hotknife | carro | Civil | [Roda clássica](Classic-Wheel) | 50 L | 16 | 2 |
|  | Hotring Racer | carro | Único | [Roda de competição](Racing-Wheel) | 50 L | 8 | 1,5 |
|  | Hotring Racer A | carro | Único | [Roda de competição](Racing-Wheel) | 50 L | 8 | 1,5 |
|  | Hotring Racer B | carro | Único | [Roda de competição](Racing-Wheel) | 50 L | 8 | 1,5 |
|  | Hustler | carro | Civil | [Roda clássica](Classic-Wheel) | 50 L | 24 | 6 |
|  | Infernus | carro | Civil | [Roda desportiva](Sport-Wheel) | 60 L | 18 | 2 |
|  | Intruder | carro | Civil | [Roda de berlina](Saloon-Wheel) | 55 L | 36 | 26 |
|  | Jester | carro | Civil | [Roda desportiva](Sport-Wheel) | 52 L | 22 | 5 |
|  | Kart | carro | Civil | [Roda de kart](Kart-Wheel) | 8 L | 0 | 2 |
|  | Majestic | carro | Civil | [Roda de berlina](Saloon-Wheel) | 55 L | 32 | 12 |
|  | Manana | carro | Civil | [Roda de carro pequeno](Small-Car-Wheel) | 48 L | 32 | 40 |
|  | Merit | carro | Civil | [Roda de jante de liga leve](Alloy-Wheel) | 58 L | 38 | 22 |
| ![](images/vehicles/418_moonbeam.png) | Moonbeam | carro | Civil | [Roda de carrinha ligeira](Light-Van-Wheel) | 60 L | 65 | 30 |
|  | Mower | carro | Civil | [Roda de jante de aço](Steel-Rim-Wheel) | 8 L | 0 | 4 |
|  | Nebula | carro | Civil | [Roda de berlina](Saloon-Wheel) | 55 L | 34 | 26 |
|  | Oceanic | carro | Civil | [Roda clássica](Classic-Wheel) | 55 L | 32 | 26 |
|  | Perennial | carro | Civil | [Roda de carro pequeno](Small-Car-Wheel) | 55 L | 40 | 40 |
|  | Phoenix | carro | Civil | [Roda desportiva](Sport-Wheel) | 55 L | 22 | 5 |
| ![](images/vehicles/596_copcarla.png) | Police Car | carro | Polícia | [Roda de berlina](Saloon-Wheel) | 78 L | 42 | 80 |
| ![](images/vehicles/597_copcarsf.png) | Police Car | carro | Polícia | [Roda de berlina](Saloon-Wheel) | 70 L | 42 | 80 |
| ![](images/vehicles/598_copcarvg.png) | Police Car | carro | Polícia | [Roda de berlina](Saloon-Wheel) | 75 L | 42 | 80 |
|  | Premier | carro | Civil | [Roda de berlina](Saloon-Wheel) | 58 L | 38 | 26 |
|  | Previon | carro | Civil | [Roda de carro pequeno](Small-Car-Wheel) | 55 L | 34 | 8 |
|  | Primo | carro | Civil | [Roda de berlina](Saloon-Wheel) | 52 L | 34 | 30 |
|  | RC Bandit | carro | Civil |  | 4 L | 0 | 0 |
|  | RC Cam | carro | Civil |  | 4 L | 0 | 0 |
|  | RC Tiger | carro | Civil |  | 4 L | 0 | 0 |
| ![](images/vehicles/479_regina.png) | Regina | carro | Civil | [Roda de berlina](Saloon-Wheel) | 74 L | 48 | 75 |
|  | Remington | carro | Civil | [Roda clássica](Classic-Wheel) | 55 L | 28 | 10 |
|  | Romero | carro | Civil | [Roda clássica](Classic-Wheel) | 55 L | 36 | 6 |
| ![](images/vehicles/475_sabre.png) | Sabre | carro | Civil | [Roda clássica](Classic-Wheel) | 60 L | 24 | 12 |
|  | Savanna | carro | Civil | [Roda clássica](Classic-Wheel) | 58 L | 32 | 10 |
| ![](images/vehicles/475_sabre.png) | Scimitar | carro | Único | [Roda clássica](Classic-Wheel) | 56 L | 24 | 3,3 |
| ![](images/vehicles/405_sentinel.png) | Sentinel | carro | Civil | [Roda de jante de liga leve](Alloy-Wheel) | 58,8 L | 42 | 78 |
|  | Solair | carro | Civil | [Roda de berlina](Saloon-Wheel) | 60 L | 42 | 30 |
|  | Stafford | carro | Civil | [Roda de jante de liga leve](Alloy-Wheel) | 60 L | 38 | 8 |
|  | Stallion | carro | Civil | [Roda clássica](Classic-Wheel) | 55 L | 28 | 12 |
|  | Stratum | carro | Civil | [Roda desportiva](Sport-Wheel) | 55 L | 36 | 18 |
|  | Stretch | carro | Civil | [Roda de jante de liga leve](Alloy-Wheel) | 70 L | 30 | 3 |
| ![](images/vehicles/560_sultan.png) | Sultan | carro | Civil | [Roda desportiva](Sport-Wheel) | 65 L | 40 | 6 |
|  | Sunrise | carro | Civil | [Roda de berlina](Saloon-Wheel) | 55 L | 34 | 24 |
|  | Super GT | carro | Civil | [Roda desportiva](Sport-Wheel) | 55 L | 16 | 2 |
|  | Tahoma | carro | Civil | [Roda de berlina](Saloon-Wheel) | 55 L | 34 | 22 |
| ![](images/vehicles/549_tampa.png) | Tampa | carro | Civil | [Roda clássica](Classic-Wheel) | 58 L | 38 | 64 |
|  | Taxi | carro | Civil | [Roda de berlina](Saloon-Wheel) | 55 L | 36 | 18 |
|  | Tornado | carro | Civil | [Roda clássica](Classic-Wheel) | 55 L | 28 | 10 |
|  | Turismo | carro | Civil | [Roda desportiva](Sport-Wheel) | 55 L | 16 | 2 |
|  | Uranus | carro | Civil | [Roda desportiva](Sport-Wheel) | 52 L | 24 | 6 |
|  | Vincent | carro | Civil | [Roda de berlina](Saloon-Wheel) | 55 L | 36 | 26 |
|  | Virgo | carro | Civil | [Roda clássica](Classic-Wheel) | 55 L | 32 | 24 |
|  | Voodoo | carro | Civil | [Roda clássica](Classic-Wheel) | 58 L | 30 | 14 |
|  | Washington | carro | Civil | [Roda de jante de liga leve](Alloy-Wheel) | 60 L | 40 | 24 |
|  | Willard | carro | Civil | [Roda de berlina](Saloon-Wheel) | 52 L | 34 | 28 |
|  | Windsor | carro | Civil | [Roda clássica](Classic-Wheel) | 58 L | 34 | 8 |
|  | ZR-350 | carro | Civil | [Roda desportiva](Sport-Wheel) | 55 L | 22 | 5 |
|  | Cargobob | helicóptero | Civil |  | 480 L | 36 | 1,5 |
|  | Hunter | helicóptero | Civil |  | 280 L | 0 | 0,8 |
|  | Leviathan | helicóptero | Civil |  | 500 L | 40 | 1,5 |
| ![](images/vehicles/487_maverick.png) | Maverick | helicóptero | Civil |  | 240 L | 32 | 2,5 |
|  | News Chopper | helicóptero | Civil |  | 160 L | 12 | 3 |
|  | Police Maverick | helicóptero | Civil |  | 180 L | 16 | 1 |
|  | RC Goblin | helicóptero | Civil |  | 4 L | 0 | 0 |
|  | RC Raider | helicóptero | Civil |  | 4 L | 0 | 0 |
|  | Raindance | helicóptero | Civil |  | 420 L | 30 | 1 |
| ![](images/vehicles/447_seaspar.png) | Seasparrow | helicóptero | Civil |  | 96 L | 0 | 1 |
|  | Sparrow | helicóptero | Civil |  | 70 L | 0 | 3 |
|  | BF-400 | mota | Civil |  | 12 L | 4 | 6 |
|  | FCR-900 | mota | Civil |  | 16 L | 4 | 4 |
| ![](images/vehicles/462_faggio.png) | Faggio | mota | Civil |  | 8 L | 10 | 45 |
| ![](images/vehicles/463_freeway.png) | Freeway | mota | Civil |  | 19 L | 15 | 8 |
| ![](images/vehicles/523_copbike.png) | HPV1000 | mota | Polícia |  | 60 L | 15 | 45 |
|  | NRG-500 | mota | Civil |  | 14 L | 4 | 3 |
|  | PCJ-600 | mota | Civil |  | 14 L | 6 | 6 |
|  | Pizzaboy | mota | Civil |  | 8 L | 4 | 12 |
|  | Quad | mota | Civil |  | 14 L | 6 | 8 |
| ![](images/vehicles/468_sanchez.png) | Sanchez | mota | Civil |  | 10 L | 8 | 15 |
| ![](images/vehicles/586_wayfarer.png) | Wayfarer | mota | Civil |  | 47 L | 15 | 10 |
<!-- /table:vehicles -->

## Mapa {#map}
Todos os pontos de aparecimento de veículos, coloridos por grupo.

<a href="images/map/vehicles.png" target="_blank" rel="noopener noreferrer" title="Ver o mapa em tamanho real; Ctrl/Cmd-clique ou clique com o botão do meio para abrir num novo separador"><img src="images/map/vehicles.png" alt="Mapa"></a>
