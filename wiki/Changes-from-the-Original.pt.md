# Mudanças face ao original

O Scavenge & Survive Reborn é uma adaptação do Scavenge & Survive do Southclaws, do SA-MP para o Multi Theft Auto. O jogo é o mesmo; isto é o que um jogador que conheça o original vai notar.

## Novidades {#new-here}
- **Reaparecimento por escassez**: o loot e os veículos voltam a encher até um orçamento, os itens acumulados contam contra ele e nada reaparece a menos de 150 m de um jogador ([Saque e reaparecimento](Loot-and-Respawn)).
- **Painel do condutor** com luzes de aviso, conta-rotações e voltímetro ([Painel do condutor](Drivers-Dashboard)).
- **Baterias de carro** que descarregam, recarregam, saem de debaixo do capô e ficam inutilizadas por um EMP, e **motores de arranque** que se gastam ([Baterias e motores de arranque](Car-Batteries-and-Starters)).
- O capô tem de estar aberto para reparar, é preciso uma Chave inglesa para as rodas, e um carro sem rodas fica imobilizado ao fim de 2 segundos ([Reparações e fechaduras](Repairing-and-Locks)).
- **Peças de veículos**: em todos os carros e camiões o capot, a mala ou o taipal, as portas e os para-choques saem, voltam a encaixar-se e soltam-se quando estão frouxos ([Peças de veículos](Vehicle-Salvage-Parts)).
- Uma **caravana Airstream rebocável** com porta, fechadura e carga que vai atrás, o único veículo que aceita **blindagem soldada** ([Reboques e rebocar](Trailers-and-Towing), [Blindagem de veículos](Vehicle-Armour)).
- **Edifícios onde se pode entrar**: uma quinta, uma casa de betão no deserto, o motel de Fort Carson (24 quartos e o escritório), nove modelos de caravana (143 colocações) e cabanas de madeira com interiores, janelas envidraçadas, portas giratórias e loot; as casas ocas do original ganharam 75 janelas envidraçadas e portas de entrada encaixadas ([Casas e reboques](Houses-and-Trailers)).
- Um modelo de **fogão de campismo** (ainda não cozinha), os passadiços do telhado do **Fort Defiance** refeitos como modelos a sério (o resto do forte não mudou) e **vedações de arame** que se partem, nos bloqueios de estrada.
- **Nove chapéus cortados das personagens do próprio GTA** que qualquer skin pode usar, e 22 skins com a cabeça descoberta por baixo de um chapéu ([Roupa e chapéus](Clothes-and-Hats)).
- As **caixas e caixotes do próprio GTA** são contentores, e qualquer número de jogadores pode olhar para dentro de um ao mesmo tempo ([Contentores e sacos](Containers-and-Bags)).
- As portas das defesas giram numa dobradiça a sério ([Defesas](Defences)).
- Uma **ponte com o Discord** e **Rich Presence** ([Discord](Discord)), e um **indicador de voz** ([Voz](Voice)).
- **Pré-visualizações 3D em direto** do teu equipamento nos mosaicos do inventário ([Inventário](Inventory)).
- **Nomes dos itens traduzidos** para todos os idiomas ([Idiomas](Languages)).
- `/report near`, `/report killer` e `/bug` ([Denúncias e banimentos](Reports-and-Bans)).

## Alterado {#changed}
- Cada item é uma linha na base de dados: nada se perde num reinício, as gravações são imediatas, não há gravação automática de 60 segundos, nem reinício de 5 horas, nem novo sorteio ([Saque e reaparecimento](Loot-and-Respawn)).
- O HUD e o inventário foram refeitos a partir de gravações da versão SA-MP ([HUD](HUD), [Inventário](Inventory)).
- Os 221 mapas (23 211 objetos) são construídos no teu cliente em cerca de 1,3 segundos ao entrares.
- Corrigiram-se erros do original: a sexta skin de arranque inalcançável, a ligadura que infetava quem tratava, o céu de Heroína na seringa, as competências não guardadas, a acumulação de drogas, o Ar e a Adrenalina aplicados duas vezes.
- A skin de arranque é sorteada entre os 29 tipos de roupa; chapéus e máscaras servem em todas as 310 skins humanas ([Roupa e chapéus](Clothes-and-Hats), [Máscaras](Masks)).
- Uma morte larga tudo num anel de 9 posições a 1,5 m, cada item virado para um lado ao acaso e nunca atrás de uma parede ([Morte](Death)).
- Uma fogueira só aceita comida crua e pode voltar a cozinhar ([Fogueira e grelhador](Campfire-and-BBQ)).
- Uma ligadura antisséptica só é gasta, e só se dá XP de Medicina, quando o tratamento resultou ([Medicina](Medical)).
- As competências fecham 2 % da diferença por ação, e a Reparação encurta as esperas ([Competências](Skills)).
- O dano das explosões atravessa defesas empilhadas ([Explosivos](Explosives)); as máquinas dão uma saída por entrada ([Máquinas](Machines)); as plantas crescem um passo a cada 10 minutos ([Jardinagem](Gardening)).
- O Cacifo só abre pela frente, dentro de 60°; um Estojo de arma ou um Armário mantém a sua exposição ([Mobiliário](Furniture)).
- O paraquedas funciona, os traçantes são linhas no mundo, os reboques engatam de forma nativa e uma tirolesa é uma só linha ([Paraquedas](Parachute), [Armas de fogo](Firearms), [Escadas e tirolesas](Ladders-and-Ziplines)).
- 46 conjuntos de fabrico: 5 por combinação, 13 por construção, 28 na bancada de trabalho ([Bancada de trabalho](Workbench)).
- Banimentos por nome, IP e número de série com durações, silenciamentos persistentes, alcunhas por IP e número de série, e o serviço de staff mantém a personagem ([Denúncias e banimentos](Reports-and-Bans)).
- Chat sem ids de jogador nem balões, rádio sintonizado por frequência num painel ([Chat](Chat), [Rádio](Radio)); `/tooltips` guardado por conta ([Comandos](Commands)); os pontos de largada de abastecimento descansam 24 horas ([Lançamentos de provisões](Supply-Drops)).
- As palavras-passe são hashes bcrypt; nada foi importado das contas do original ([Conta e início de sessão](Account-and-Login)).
- Dez idiomas com todos os textos da interface preenchidos ([Idiomas](Languages)); cada porta de entrada está ajustada à sua ombreira ([Casas e reboques](Houses-and-Trailers)).

## Ainda não existe ou foi abandonado {#not-here-yet-or-dropped}
- As soluções de contorno do SA-MP (ecrã panorâmico, anti-ninja, colisão de motas), o MapAndreas, os mundos alternativos, os filterscripts e o runner em Go.
- Alguns comandos de staff: `/country`, `/allcountry`, `/delete`, `/setpinglimit`, `/gmx`, `/loadfs` e mais alguns; `/hudscale` e `/restartinfo`.
- Árvores selvagens: os ficheiros de colocação não estavam disponíveis.
- O conteúdo de Natal.
- Pendente: verificações que precisam de dois clientes ao mesmo tempo, e lacunas na interface (o retrato da skin no painel do corpo, as opções Largar e Mover para o saco).
