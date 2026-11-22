# Nuvem tóxica

De poucas em poucas horas forma-se um banco de gás venenoso fora de uma das margens do mapa, que o atravessa à deriva. Vê-lo chegar. O que fazes a seguir é contigo: sair do caminho, subir acima dele, pôr uma máscara ou fechar-te num sítio estanque.

<!-- shot:toxic-cloud-horizon -->

## A nuvem {#the-cloud}

- Cerca de um quilómetro de largura, verde-amarelada, assente no chão como uma parede. Vê-se a quilómetros de distância, e os montes e os edifícios tapam-na como a qualquer outra coisa.
- Desloca-se em linha reta a passo de corrida (8 m/s) e leva cerca de 17 minutos a atravessar o mapa. Passa por cima de um mesmo ponto em dois minutos, no máximo.
- Forma-se uma nova a cada três a quatro horas. Não há aviso.
- O mapa (`F11`) e o radar mostram onde está, como uma mancha verde-amarelada.
- O gás é pesado. Tem a força toda até 110 m acima do nível do mar e desaparece aos 150 m, por isso uma montanha ou um telhado alto ficam acima dele. A orla é mais fina do que o meio.

Lá dentro o nevoeiro fecha-se a poucas dezenas de metros e tudo toma a cor do gás.

<!-- shot:toxic-cloud-inside -->

## Veneno {#poison}

Respirar o gás faz subir o teu nível de **Veneno**, mostrado a vermelho ou a âmbar no painel Estado de saúde do [inventário](Inventory). Sem proteção nenhuma, o meio da nuvem acrescenta cerca de 1 % por segundo.

| Veneno | O que acontece |
|:--|:--|
| a partir de 15 % | Tosses, tanto mais vezes quanto mais alto estiver. A imagem ganha um tom verde e desfoca nas margens. |
| a partir de 40 % | Perdes saúde, devagar ao início. |
| a partir de 80 % | Perdes saúde depressa: a 100 %, uma personagem saudável morre em cerca de um minuto. |

Ao ar limpo desce 1 % a cada dez segundos, por isso uma dose completa leva cerca de 17 minutos a passar. Fica guardado com a personagem: sair do jogo não o limpa. Um corpo morto pelo gás di-lo a quem o inspecionar ([Morte](Death)).

## Máscaras {#masks}

Uma máscara posta na cara ([Máscaras](Masks)) deixa parte do gás de fora.

| Máscara | Deixa de fora | Desgaste |
|:--|:--|:--|
| Lenço de cabeça | 15 % | nunca |
| [Máscara de pó](Dust-Mask) | 50 % | Descartável: cerca de 5 minutos de gás denso, depois desfaz-se. |
| [Respirador de meia face](Half-Respirator) | 85 % | O filtro dura cerca de 15 minutos de gás denso. |
| [Máscara de gás](Gas-Mask) | 97 % | O filtro dura cerca de 20 minutos de gás denso. |

- Uma máscara só se gasta enquanto respiras gás através dela, mais depressa com gás mais denso. O que resta aparece a seguir ao nome: `Máscara de gás (filtro 63%)`.
- Com o filtro gasto, um respirador ou uma máscara de gás só deixa de fora 10 % e custa mais a respirar. Pega num [Filtro](Filter) e usa-o com a máscara posta para colocar um novo; o velho é deitado fora.
- As vedações da própria máscara também se gastam, muito mais devagar (cerca de dez filtros). Uma máscara com menos de metade da vedação deixa passar gás.
- Uma máscara que encontres já foi usada: o filtro e a vedação estão algures entre meio gastos e novos.

### Respirar {#breathing}

Quanto melhor uma máscara protege, mais custa respirar através dela, com gás ou sem ele. Limita o tempo que consegues correr a fundo antes de teres de recuperar o fôlego:

| Máscara | Corrida | Depois descanso |
|:--|:--|:--|
| Lenço de cabeça | cerca de 2 minutos | 4 s |
| Máscara de pó | 44 s | 5 s |
| Respirador de meia face | 19 s | 7 s |
| Máscara de gás | 12 s | 8 s |
| qualquer das duas, filtro gasto | 9 a 12 s | 8 a 10 s |

Ouves-te a respirar através dela, mais alto e mais depressa quanto mais ofegante estiveres, com um silvo quando o filtro está gasto. Os jogadores ao teu lado ouvem ao de leve um respirador ou uma máscara de gás.

## Abrigo {#shelter}

Debaixo de um telhado, o que conta é o quanto o sítio está aberto ao ar de fora. O gás lá dentro segue o gás lá fora através das aberturas:

- **Estanque** (o ar não tem por onde sair: uma divisão fechada, uma base selada): não entra gás, por mais tempo que a nuvem fique por cima.
- **Com fugas** (uma porta aberta, um painel de parede em falta, uma janela partida): enche-se, devagar por uma fresta pequena e depressa por uma grande, e esvazia-se igualmente devagar depois de a nuvem passar. Sai enquanto areja.
- **Aberto** (um alpendre, um telheiro, um hangar de frente aberta): pouco melhor do que estar na rua.
- **Sem telhado** é ar livre, seja o que for que tenhas à volta: o gás desce para dentro de um pátio.

Vê-se a acontecer: fios de gás entram por cada abertura e espalham-se pelo chão.

<!-- shot:toxic-cloud-seeping -->

Os interiores do próprio jogo (aqueles onde entras por um marcador amarelo) são selados.

## Veículos {#vehicles}

A cabina de um veículo conta como uma divisão pequena:

- **Em bom estado, com todas as portas fechadas**: deixa entrar muito pouco. Atravessar a nuvem a conduzir custa-te uns poucos por cento.
- **Uma porta danificada** já não veda: cada uma deixa entrar bastante mais.
- **Uma porta aberta ou em falta, ou o para-brisas partido**: o mesmo que estar na rua.
- **Motas, moto-quatro, barcos e carros descapotáveis** não dão abrigo nenhum.

## No HUD {#on-the-hud}

Duas barras juntam-se à sede, à fome, ao colete e à saúde, por cima delas:

- **Proteção** (amarela), enquanto tiveres uma máscara posta ou houver uma nuvem no mapa. Está tão cheia quanto estás protegido nesse momento, máscara e abrigo juntos, por isso podes pôr à prova uma divisão ou um carro antes de a nuvem chegar. Pisca a vermelho enquanto estiveres a respirar gás.
- **Veneno** (roxa), enquanto tiveres algum. Enche à medida que o veneno se acumula e esvazia à medida que passa, treme enquanto estás a apanhar mais, e pisca a vermelho a partir de 40 %, quando começa a tirar saúde.

## Resistência ao veneno {#poison-resistance}

Sobreviver ao gás desenvolve uma [competência](Skills). Cada 10 % de veneno que apanhas sobe a **Resistência ao veneno** um degrau, os primeiros os maiores, e corta o veneno que apanhas até um quarto no nível Mestre. Perde-se com a personagem.

## Equipa {#staff}

`/toxic` diz a um membro da equipa (nível 4) onde está a nuvem; `/toxic here` forma uma por cima dele, `/toxic cross` manda uma atravessar o mapa e `/toxic stop` acaba com ela. A equipa em serviço não apanha veneno.

Vê também [Máscaras](Masks), [Saúde](Health), [Competências](Skills) e [Mundo e zonas](World-and-Zones).
