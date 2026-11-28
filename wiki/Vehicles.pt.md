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
|  | Veículo | Tipo | Grupo | Depósito | Espaços na mala | Probabilidade de aparecer |
|:--|:--|:--|:--|--:|--:|--:|
| ![](images/vehicles/476_rustler.png) | Rustler | avião | Civil | 88 L | 15 | 0,8 |
| ![](images/vehicles/472_coastg.png) | Coastguard | barco | Polícia | 120 L | 24 | 35 |
| ![](images/vehicles/473_dinghy.png) | Dinghy | barco | Civil | 81 L | 10 | 64 |
| ![](images/vehicles/595_launch.png) | Launch | barco | Militar | 213 L | 26 | 40 |
| ![](images/vehicles/484_marquis.png) | Marquis | barco | Civil | 900 L | 100 | 50 |
| ![](images/vehicles/453_reefer.png) | Reefer | barco | Civil | 245 L | 48 | 60 |
| ![](images/vehicles/446_squalo.png) | Squalo | barco | Civil | 50 L | 28 | 20 |
| ![](images/vehicles/454_tropic.png) | Tropic | barco | Civil | 260 L | 44 | 55 |
| ![](images/vehicles/539_vortex.png) | Vortex | barco | Único | 45 L | 4 | 0,1 |
| ![](images/vehicles/510_mtbike.png) | Mountain Bike | bicicleta | Civil | 0 L | 2 | 8 |
| ![](images/vehicles/578_dft30.png) | APC-30 | camião | Único | 60 L | 0 | 0,1 |
|  | Airstream | camião | Civil | 0 L | 0 | 3 |
| ![](images/vehicles/416_ambulan.png) | Ambulance | camião | Médico | 80 L | 70 | 30 |
| ![](images/vehicles/591_artict3.png) | Articulated | camião | Industrial | 0 L | 100 | 18 |
| ![](images/vehicles/424_bfinject.png) | BF Injection | camião | Civil | 40 L | 24 | 15 |
| ![](images/vehicles/568_bandito.png) | Bandito | camião | Único | 48 L | 15 | 0,1 |
| ![](images/vehicles/433_barracks.png) | Barracks | camião | Militar | 200 L | 100 | 3 |
| ![](images/vehicles/422_bobcat.png) | Bobcat | camião | Civil | 60 L | 40 | 76 |
| ![](images/vehicles/498_boxville.png) | Boxville | camião | Industrial | 75 L | 70 | 55 |
| ![](images/vehicles/578_dft30.png) | DFT-30 | camião | Industrial | 60 L | 0 | 35 |
| ![](images/vehicles/573_duneride.png) | Duneride | camião | Civil | 180 L | 85 | 10 |
| ![](images/vehicles/427_enforcer.png) | Enforcer | camião | Polícia | 90 L | 64 | 10 |
| ![](images/vehicles/528_fbitruck.png) | FBI Truck | camião | Polícia | 80 L | 45 | 3 |
| ![](images/vehicles/407_firetruk.png) | Firetruck | camião | Médico | 115 L | 65 | 0,5 |
| ![](images/vehicles/455_flatbed.png) | Flatbed | camião | Industrial | 70 L | 100 | 15 |
| ![](images/vehicles/579_huntley.png) | Huntley | camião | Civil | 70 L | 50 | 57 |
| ![](images/vehicles/508_journey.png) | Journey | camião | Civil | 60 L | 76 | 10 |
| ![](images/vehicles/403_linerun.png) | Linerunner | camião | Industrial | 120 L | 12 | 15 |
| ![](images/vehicles/500_mesa.png) | Mesa | camião | Civil | 77 L | 48 | 70 |
| ![](images/vehicles/470_patriot.png) | Patriot | camião | Militar | 94 L | 50 | 22 |
| ![](images/vehicles/489_rancher.png) | Rancher | camião | Civil | 110 L | 52 | 44 |
| ![](images/vehicles/599_copcarru.png) | Ranger | camião | Polícia | 110 L | 48 | 30 |
| ![](images/vehicles/432_rhino.png) | Rhino | camião | Militar | 1900 L | 12 | 0,01 |
| ![](images/vehicles/515_rdtrain.png) | Roadpain | camião | Único | 210 L | 0 | 1,4 |
| ![](images/vehicles/440_rumpo.png) | Rumpo | camião | Industrial | 55 L | 80 | 45 |
| ![](images/vehicles/543_sadler.png) | Sadler | camião | Civil | 60 L | 40 | 34 |
| ![](images/vehicles/495_sandking.png) | Sandking | camião | Único | 120 L | 46 | 3,5 |
| ![](images/vehicles/578_dft30.png) | Steamroller | camião | Único | 60 L | 0 | 0,1 |
| ![](images/vehicles/611_utiltr1.png) | Trailer | camião | Industrial | 0 L | 50 | 20 |
| ![](images/vehicles/403_linerun.png) | Truckfort | camião | Único | 265 L | 76 | 1,1 |
| ![](images/vehicles/583_tug.png) | Tug | camião | Industrial | 10 L | 8 | 10 |
| ![](images/vehicles/478_walton.png) | Walton | camião | Civil | 60 L | 46 | 40 |
| ![](images/vehicles/456_yankee.png) | Yankee | camião | Industrial | 60 L | 80 | 40 |
| ![](images/vehicles/554_yosemite.png) | Yosemite | camião | Civil | 60 L | 44 | 70 |
| ![](images/vehicles/485_baggage.png) | Baggage | carro | Industrial | 14,5 L | 8 | 35,5 |
| ![](images/vehicles/496_blistac.png) | Blista Compact | carro | Civil | 40 L | 38 | 68 |
| ![](images/vehicles/504_bloodra.png) | Bloodring Banger | carro | Único | 65 L | 32 | 0,5 |
| ![](images/vehicles/542_clover.png) | Clover | carro | Civil | 62 L | 34 | 75 |
| ![](images/vehicles/480_comet.png) | Comet | carro | Civil | 50 L | 20 | 10 |
| ![](images/vehicles/573_duneride.png) | Doomride | carro | Único | 180 L | 80 | 0,5 |
| ![](images/vehicles/418_moonbeam.png) | Moonbeam | carro | Civil | 60 L | 65 | 30 |
| ![](images/vehicles/596_copcarla.png) | Police Car | carro | Polícia | 78 L | 42 | 80 |
| ![](images/vehicles/597_copcarsf.png) | Police Car | carro | Polícia | 70 L | 42 | 80 |
| ![](images/vehicles/598_copcarvg.png) | Police Car | carro | Polícia | 75 L | 42 | 80 |
| ![](images/vehicles/479_regina.png) | Regina | carro | Civil | 74 L | 48 | 75 |
| ![](images/vehicles/475_sabre.png) | Sabre | carro | Civil | 60 L | 24 | 17 |
| ![](images/vehicles/475_sabre.png) | Scimitar | carro | Único | 56 L | 24 | 3,3 |
| ![](images/vehicles/405_sentinel.png) | Sentinel | carro | Civil | 58,8 L | 42 | 78 |
| ![](images/vehicles/560_sultan.png) | Sultan | carro | Civil | 65 L | 40 | 15 |
| ![](images/vehicles/549_tampa.png) | Tampa | carro | Civil | 58 L | 38 | 64 |
| ![](images/vehicles/487_maverick.png) | Maverick | helicóptero | Civil | 240 L | 32 | 1 |
| ![](images/vehicles/447_seaspar.png) | Seasparrow | helicóptero | Civil | 96 L | 10 | 0,31 |
| ![](images/vehicles/462_faggio.png) | Faggio | mota | Civil | 8 L | 10 | 45 |
| ![](images/vehicles/463_freeway.png) | Freeway | mota | Civil | 19 L | 15 | 8 |
| ![](images/vehicles/523_copbike.png) | HPV1000 | mota | Polícia | 60 L | 15 | 45 |
| ![](images/vehicles/468_sanchez.png) | Sanchez | mota | Civil | 10 L | 8 | 15 |
| ![](images/vehicles/586_wayfarer.png) | Wayfarer | mota | Civil | 47 L | 15 | 10 |
<!-- /table:vehicles -->

## Mapa {#map}
Todos os pontos de aparecimento de veículos, coloridos por grupo.

<a href="images/map/vehicles.png" target="_blank" rel="noopener noreferrer" title="Ver o mapa em tamanho real; Ctrl/Cmd-clique ou clique com o botão do meio para abrir num novo separador"><img src="images/map/vehicles.png" alt="Mapa"></a>
