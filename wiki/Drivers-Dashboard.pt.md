# Painel do condutor

Enquanto conduzes um veículo com motor e depósito de combustível, aparece no fundo do ecrã, ao centro, um painel de instrumentos: uma caixa escura com um velocímetro e um conta-rotações, um indicador de combustível e um voltímetro entre eles, uma fila de luzes de aviso por baixo e o interruptor da ignição ao lado. Acende-se conforme o estado do veículo em que estás e mostra o que acontece quando rodas a chave, por isso cada maneira de o arranque falhar tem um aspeto diferente. Só o condutor o vê. O canto inferior direito ([HUD](HUD)) mostra apenas o nome do veículo; os danos vêem-se no próprio carro, como fumo do motor e amolgadelas.

<!-- shot:shot-dashboard -->

O que se descreve abaixo é o painel do carro e do camião. Os outros tipos de veículo têm um painel próprio, listado em [Outros veículos](#other-vehicles); o interruptor da ignição, a retroiluminação, o teste das lâmpadas e a forma como um arranque ou uma paragem decorrem são iguais em todos. Uma bicicleta não tem nenhum.

## Os mostradores {#the-dials}
- **Velocímetro** (esquerda): km/h numa escala de 240 graus, numerada de 20 em 20 km/h (de 40 em 40 nos veículos mais rápidos). O fim da escala acompanha a velocidade máxima do veículo, de 120 até 320 km/h. Um mostrador digital verde por baixo do ponteiro indica a velocidade em números.
- **Conta-rotações** (direita): de 0 a 7 mil rpm, a vermelho a partir das 6000, mais ou menos. O ponteiro segue a tua velocidade dentro da mudança engrenada, subindo em cada mudança e caindo quando passas à seguinte; parado e com o acelerador premido sobe um pouco. Atrasa-se em relação ao motor e desce mais depressa do que sobe. Com o motor desligado fica em zero.
- **Indicador de combustível** (centro, à esquerda): de `E` a `F`, a vermelho no último oitavo. O ponteiro estabiliza ao fim de cerca de um segundo, como um mostrador amortecido.
- **Voltímetro** (centro, à direita): de 8 a 16 V, a vermelho abaixo de 10,5 V. Mostra 14,1 V enquanto o motor trabalha e carrega a bateria. Com o motor desligado indica a tensão em repouso da bateria, de 11,6 V vazia a 12,7 V cheia, e desce enquanto o motor de arranque roda. Os veículos sem bateria (motas, barcos, os veículos abertos sem portas) marcam como se a deles estivesse sempre cheia.

As marcações são iluminadas pela retroiluminação: cinzento-escuro até a chave ir para ACC ou o motor trabalhar, mais ténue em ACC e forte enquanto o motor trabalha. Com o painel às escuras, todos os ponteiros ficam no batente. Sem bateria debaixo do capot, o painel está morto.

## As luzes {#the-lamps}
Da esquerda para a direita, por baixo dos mostradores pequenos, cada uma com o símbolo de um painel a sério. Uma luz está cinzento-escura até se acender.

| Luz | Cor | Acende-se quando |
|:--|:--|:--|
| bateria | vermelha | a luz de carga: o alternador não está a carregar enquanto o motor trabalha |
| motor | âmbar | o veículo está gasto (650 de vida ou menos); vermelha quando está destruído (300 ou menos) |
| bomba de combustível | âmbar | o depósito está a 15 % ou menos; vermelha a 5 % ou menos, ou vazio |
| faróis | verde | os faróis estão ligados |
| porta | verde / vermelha | está sempre acesa: verde com as portas destrancadas, vermelha com elas trancadas |

Os limiares são os que contam quando conduzes: abaixo de 450 de vida o motor pode cortar em andamento, com 300 ou menos não arranca, abaixo de 10 % a bateria não o faz rodar. Vê [Veículos](Vehicles), [Combustível](Fuel) e [Baterias e motores de arranque](Car-Batteries-and-Starters).

## O interruptor da ignição {#the-ignition-switch}
Um cilindro cromado fica logo à esquerda do painel. Com a chave fora (`OFF`) é um cilindro vazio com uma ranhura preta; com a chave dentro, a cabeça de latão atravessa o cilindro e roda com ele, e ao desligares volta a `OFF` antes de sair. Três marcas ficam à volta, `OFF`, `ACC` e `START`, da esquerda para a direita, como num cilindro verdadeiro, e a chave roda para aquela em que está; a marca acesa é cinzenta, âmbar ou vermelha conforme o caso. A chave vai a `START` enquanto o motor de arranque roda, depois volta a `ACC` e fica lá enquanto o motor trabalha, com a marca a verde. Ao entrares num carro, a chave já está onde o estado do carro diz que deve estar.

## Rodar a chave {#turning-the-key}
A chave tem duas posições antes do motor. Com o motor desligado, um toque em `Y` como condutor roda-a para **ACC**: o painel acorda com o teste das lâmpadas de 0,7 segundos, e um segundo toque desliga-o outra vez. Se mantiveres `Y` premido 0,3 segundos, passa por ACC e põe o motor a rodar; um arranque que falha deixa a chave em ACC. Premir `Y` com o motor a trabalhar pára-o e tira a chave por completo. ACC gasta a bateria devagar (vê [Baterias e motores de arranque](Car-Batteries-and-Starters)) e continua ligado quando sais, tal como os faróis.

Cada volta da chave tem um som que acompanha o que o painel mostra, ouvido pelo condutor: um estalido de relé para ACC; um zumbido do motor de arranque que acelera quando o motor pega; um tremelique fraco do solenoide com a bateria descarregada; um estalido seco a cada tentativa com o motor de arranque morto; um rangido irregular com o motor destruído; uma rotação regular que nunca pega com o depósito vazio; e um estremecimento que abranda e acaba num estalido quando o motor cala. Sem bateria não há som nenhum.

Ao rodar, o arranque decorre assim:

- **Pega.** Todas as luzes se acendem durante 0,7 segundos, o teste das lâmpadas, o motor de arranque roda, o ponteiro apanha e estabiliza em ralenti.
- **Sem bateria.** Não acontece nada: o painel continua às escuras.
- **Bateria descarregada** (abaixo de 10 %). A retroiluminação pisca, o solenoide do motor de arranque estala e o ponteiro das rotações treme a cada estalido enquanto o voltímetro desce. O texto de ação diz *A bateria está descarregada*.
- **Motor destruído** (300 de vida ou menos). As lâmpadas são testadas, o motor de arranque range de forma irregular durante 2 segundos e a luz do motor fica acesa 4 segundos.
- **Depósito vazio.** As lâmpadas são testadas, o motor de arranque roda de forma regular durante 2 segundos e nunca pega, e a luz do combustível fica acesa 4 segundos.
- **Motor de arranque morto.** O motor só estala e a mensagem di-lo; vê [Baterias e motores de arranque](Car-Batteries-and-Starters).

A bateria é verificada primeiro, depois os danos e o combustível, depois o motor de arranque, por isso um carro com a bateria descarregada não mostra nada sobre as outras avarias enquanto não tiver carga.

## Quando o motor cala {#stalling}
Quando o motor morre debaixo de ti, o ponteiro das rotações cai, a luz do motor acende-se durante um segundo e meio (não com o depósito vazio, que não é avaria) e a luz da causa pisca a vermelho durante 4 segundos: a do combustível com o depósito vazio, a do motor por danos, uma paragem simples, ou uma bateria retirada ou descarregada por um [EMP](Explosives).

## Outros veículos {#other-vehicles}
Cada um tem o interruptor da ignição na extremidade esquerda e acende-se com a chave como o do carro.

- **Motas**: dois casulos cromados num suporte. O velocímetro, com o mostrador digital, no grande, o conta-rotações no pequeno, e entre eles o nível de combustível numa fila de oito barras LCD (a última fica vermelha e pisca a 15 % ou menos) por cima de três luzes: motor, combustível e faróis. Uma mota não tem luz de porta nem voltímetro.
- **Barcos**: uma consola de leme azul-marinho com aro de latão e mostradores de fundo branco. O log à esquerda lê em **nós**, com a escala a acompanhar a velocidade máxima do barco; o conta-rotações está à direita. Entre eles, uma faixa de bússola desliza por baixo de uma linha vermelha fixa (`N`, `E`, `S`, `W` e as dezenas de graus pelo meio: `3` são 30 graus), por cima do indicador de combustível e das luzes do motor, do combustível e dos faróis.
- **Helicópteros**: um painel plano. Uma faixa de bússola corre por cima de cinco instrumentos: velocidade no ar em nós (de 0 a 120, a verde na gama normal), o horizonte artificial (céu azul sobre terreno castanho, inclinando-se com a tua inclinação lateral e descendo quando o nariz sobe), o altímetro em pés acima do nível do mar (o ponteiro longo dá uma volta por 1000 pés, o curto uma por 10 000 pés, com o valor em dígitos), a velocidade vertical em milhares de pés por minuto (nivelado às nove horas, para cima numa subida) e a velocidade do rotor em percentagem, com uma faixa verde de 90 a 110. À direita, o indicador de combustível fica por cima de um painel de legendas: `ENG`, `FUEL`, `LTS` e `DOOR` acendem-se como as luzes do carro, e `ROTOR` pisca a vermelho enquanto o motor trabalha e o rotor roda abaixo de 80 %, devagar demais para voar.
- **Aviões**: o mesmo painel, com velocidade no ar até 180 nós, o horizonte, o altímetro, um giroscópio direcional (o cartão da bússola roda por baixo de um avião fixo) e a velocidade vertical. À direita, o indicador de combustível e um indicador de rotações do motor, que sobe com o acelerador, ficam por cima das legendas; `GEAR` está verde com o trem de aterragem em baixo e apagado com ele recolhido.
- **Carros desportivos**: um painel baixo de carbono com um rebordo vermelho. O conta-rotações é o mostrador grande ao meio, até 9, com a mudança numa janela na face (`R` em marcha-atrás) e uma luz de mudança que pisca a vermelho quando o ponteiro chega ao vermelho no topo de uma mudança. O velocímetro fica mais pequeno à esquerda; o indicador de combustível, o voltímetro e as cinco luzes ficam à direita. Nenhum veículo do mundo o usa ainda.

Os instrumentos de voo e de bússola são mecânicos e continuam a marcar com a chave desligada; só a retroiluminação e os dígitos precisam de energia.
