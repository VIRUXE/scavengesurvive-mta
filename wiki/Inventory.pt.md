# Inventário

Abre o inventário com `H` (reatribuível nas definições de teclas do MTA). É o ecrã onde geres tudo o que carregas.

## Disposição {#layout}
- **Centro:** uma lista dos itens do teu inventário, com o título `Inventário (usado/tamanho)`. Cada linha lê-se `[tamanho]Nome`; as ranhuras livres lêem-se `<Vazio>`.
- **Esquerda:** o painel Estado de saúde: uma contagem de feridas para cada uma de sete partes do corpo (Cabeça, Torso, Braço D, Braço E, Virilha, Perna D, Perna E), a vermelho onde foste atingido por último; `Hemorragia` (a vermelho, a menos que diga 0.00); `Fome` em percentagem (amarelo abaixo de 50, vermelho abaixo de 20); `Infeção alim.` e `Infeção ferida` quando tens uma [infeção](Infection); cada [droga](Drugs) ativa; e, no rodapé, a tua probabilidade de ficares inconsciente com a próxima ferida.
- **Direita:** seis mosaicos de equipamento, `HEAD`, `FACE`, `HAND`, `HOLSTER`, `TORSO` e `BACK`, cada um com um modelo 3D vivo, a rodar, do item que tem e o seu nome por baixo (`<EMPTY>` caso contrário). O mosaico `HAND` mostra o que seguras com o seu tamanho, por exemplo `(03) MEAT (UNCOOKED)`; `TORSO` mostra os pontos do colete, `ARMOUR (73)`. Clica num mosaico preenchido para tirar o item, clica num mosaico vazio enquanto seguras um item compatível para o vestir, clica em `HAND` para guardar o item que seguras e clica em `BACK` para passar ao conteúdo do saco vestido. Vê [Roupa e chapéus](Clothes-and-Hats), [Colete](Armour) e [Coldre](Holster).
- Linhas extra no fundo da lista: o teu saco vestido (`Saco pequeno >`, `Mochila >` ...) e `Rádio` (vê [Rádio](Radio)). Abrir a mala de um veículo ou um contentor mostra o seu conteúdo ao lado do teu, com `O meu inventário >` para voltar.

<!-- shot:shot-inventory -->

## Capacidade {#capacity}
O teu inventário tem **6 ranhuras**. Cada item ocupa tantas ranhuras como o seu tamanho (um item de tamanho 3 ocupa 3 ranhuras); vê [Tamanhos dos itens](Item-Sizes) e [Catálogo de itens](Item-Catalogue). Os itens demasiado grandes para guardar, como os caixotes grandes, só podem ser levados nas mãos, num veículo ou numa caixa.

Um saco vestido acrescenta as suas próprias ranhuras. Quando o inventário está cheio, os itens vão para o saco; vê [Contentores e sacos](Containers-and-Bags) para os tamanhos.

## Mãos {#hands}
Seguras um item de cada vez. Prime `F` para pegar nas mãos no item mais próximo a menos de 2 m; um item atrás de uma parede ou de uma porta fechada não conta. Depois:

| Tecla | Ação |
|:--|:--|
| `F` (manter 500 ms) | Apanha um saco ou uma caixa que esteja ali com tudo o que tem dentro (um toque abre-o), ou um Cartaz, um corpo ou um Vaso (um toque lê-o ou inspeciona-o) |
| `Y` | Guardar: no inventário, depois no saco se o inventário estiver cheio. Uma arma que possa ir ao coldre vai para o coldre, um saco é vestido, um paraquedas vai para as costas |
| `N` | Largar o item. Com outro jogador a menos de 1,5 m, o item é-lhe entregue |
| `N` (manter 300 ms) | Descarregar uma arma de fogo e largar a sua lata de munições |
| `N` com as mãos vazias | Tirar um paraquedas vestido, ou então o teu saco vestido, para as mãos |
| `Y` com as mãos vazias | Sacar a arma que tens no coldre |

Se o item não couber nem no inventário nem no saco, manténs-o nas mãos e és avisado de que são precisas mais ranhuras.

## Itens grandes {#big-items}
Alguns itens levam-se com as duas mãos, com uma animação de levantar e uma pose de transporte: rodas, as caixas, caixotes, cartões e sacos do lixo espalhados pelo mapa, painéis metálicos e portas, o BBQ, a Máquina de soldar, o Gerador, o Cilindro de gás, o Vaso, os Dados, uma Fogueira, um corpo e mais alguns. Nunca entram no teu inventário nem num saco (*Demasiado grande para guardar, vai num veículo ou numa caixa*), e não consegues entrar num veículo enquanto seguras um. Larga-o, entrega-o, ou mete-o numa mala ou numa caixa com `Y` enquanto a lista desse contentor estiver aberta.

## Entregar itens {#handing-items-over}
Com um item na mão e outro jogador a menos de 1,5 m, `N` entrega-lho em vez de o largar. As mãos dele têm de estar vazias, e nenhum de vós pode estar algemado, inconsciente, com as mãos no ar ou em serviço de staff. Vês *Entregaste* e ele vê *Entregaram-te um item*. Um saco ou uma caixa passa com o seu conteúdo.

## Ações do inventário {#inventory-actions}
Escolhe uma linha para obteres uma lista de ações:

- **Equipar** pega no item com as mãos (têm de estar vazias).
- **Usar** usa-o onde está, por exemplo para comer comida ou ler um bilhete.
- **Vestir** põe um chapéu, uma máscara, um colete, uma arma de coldre ou roupa.
- **Combinar** aparece quando seguras alguma coisa: vê [Combinar](Combining).
- **Mover para ...** envia o item para o saco, a mala ou o contentor abertos, ou de volta para o inventário.
- Com algo nas mãos, uma linha `<Vazio>` oferece **Guardar em ...** para a lista em que está.

## Nomes dos itens {#item-names}
Alguns nomes trazem o seu estado: a comida lê-se `(Cozinhado)` ou `(Cru)`; uma bebida `Garrafa (Água 0.4/0.50)` ou `(Vazia)`; uma arma de fogo as suas balas e munições, `M9 (10/7, 9mm, Ponta oca)`; um Bilhete as suas primeiras palavras ou `(Em branco)`; uma Pistola de choques `(Carregada)` ou `(Descarregada)`; as Sementes a sua quantidade e tipo; uma Botija de gás os seus quilogramas; uma Bateria de carro a sua carga, `Bateria de carro (82%)`; uma Chave o tipo de veículo para que foi cortada, `Chave de carro`, `Chave de barco`, `Chave de reboque`; um Cadeado e corrente `(Cortado)` ou `(Intacto)`; um Código o seu dígito; a Roupa o conjunto que contém; os Comprimidos e os Injetores a sua droga.

## Itens no chão {#items-on-the-ground}
![Um cachorro-quente no chão com a sua etiqueta](images/world-item-hotdog.jpg)

Os itens que estão no mundo são mostrados a menos de 150 m de ti. A menos de 4 m cada um mostra o seu nome numa etiqueta amarela (maior a menos de 3 m), escondida enquanto houver uma parede entre ti e ele; uma defesa construída mostra os seus pontos de vida a partir dos 10 m, e o texto de um Cartaz lê-se a 25 m. Apanhar um item mostra uma dica sobre ele durante 20 segundos; `/tooltips` liga e desliga as dicas.

## Largar tudo {#dropping-everything}
`/dropall` larga tudo o que carregas, vestes e seguras num anel à tua volta e levanta-te as mãos, sem te matar; uma morte larga tudo da mesma maneira, mais um item de Roupa e um corpo. Vê [Morte](Death) e [Render-se e desarmar](Surrender-and-Disarm).

Vê também [Tamanhos dos itens](Item-Sizes), [Contentores e sacos](Containers-and-Bags) e [Coldre](Holster).
