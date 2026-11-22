# HUD

O ecrã mostra apenas o que a tua personagem saberia: não há mapa, nem dinheiro, nem nível de procurado, nem relógio do GTA. O HUD aparece depois de a tua personagem nascer e fica escondido no ecrã de morte.

<!-- shot:shot-hero-gameplay -->

## Em cima à direita {#top-right}
- **Barra de vida**: a barra vermelha do próprio GTA, preenchida até à tua [vida](Health).
- **Barras de sede e fome**: uma barra azul (sede) por cima de uma verde (fome), ambas com a largura da barra de vida, empilhadas entre as barras de armadura e de vida (vê [Comida e bebida](Food-and-Drink)). A partir de 30 para baixo a barra pulsa, e abaixo de 20, onde custa vida, pisca a vermelho.
- **Ícone da arma**: o ícone do GTA do que seguras. Uma arma de fogo carregada mostra `carregador/reserva` (por exemplo `10/0`) por baixo; vê [Armas de fogo](Firearms).
- **Sem barra de armadura**: os pontos de um colete vestido só aparecem no mosaico `TORSO` do inventário; vê [Colete](Armour).
- **Nome da área**: mostrado brevemente quando entras num novo bairro.
- **Mira** enquanto apontas.

O radar, o dinheiro, o relógio, as estrelas de procurado, o medidor de fôlego, o nome do veículo e a estação de rádio do HUD original estão escondidos.

## Lista de teclas (lado direito) {#key-list-right-side}
Por baixo do ícone da arma, uma coluna lista o que as tuas teclas fazem neste momento: a tecla a amarelo, a ação a branco. Segue as teclas que atribuíste (vê [Controlos](Controls)) e muda com o que seguras e o que tens perto, por exemplo:

| Situação | Linhas |
|:--|:--|
| Mãos vazias | `H Abrir inventário`; `Y Sacar arma` com uma arma no coldre; `N Retirar saco` com um saco vestido; `F Retirar algemas` junto a um jogador algemado |
| A segurar uma arma de fogo | `Y Guardar arma` (ou `Guardado`), `R Recarregar`, `N (Manter) Descarregar`, `N Largar item` ou `N Dar item` (um jogador a menos de 1,5 m), `H Abrir inventário` |
| A segurar outra coisa | `Y Guardado`, `N Largar item` / `N Dar item`, `H Abrir inventário`, mais o uso do item: `F Comer`, `F Cozinhar` (junto a uma fogueira), `F Beber`, `F Abrir bolsa a tiracolo`, `Y Vestir`, `F Vestir roupa`, `F Vestir colete`, `F Tomar comprimidos`, `F Ler bilhete`, `F Localizar telemóvel`, `F Lançar a linha`, `F Colocar escudo`, `F Desconstruir` (Pé de cabra) |
| Perto de coisas | `F Abrir` / `F (Manter) Apanhar` num saco ou caixa no chão; `F Aceder à máquina` / `F (Manter) Menu da máquina`; `F Abrir porta`, `Fechar porta` ou `Porta trancada` na porta do Airstream; `F Subir a escada`, `Agarrar a tirolesa`, `Largar`; `F Abrir caixote de provisões` / `Abrir esconderijo de armas`; a etiqueta de um botão ou portão; as linhas da [blindagem](Vehicle-Armour) (`Prender ao reboque`, `Pegar no maçarico`, `Soldar painel`, `Rebarbar painel`...) |
| A conduzir | `R Abrir rádio` (`(Manter) Abrir rádio` com uma arma de fogo na mão) e `Engatar reboque` / `Desengatar reboque` na tecla de engate quando um reboque está ao alcance ou rebocado |

A lista fica escondida enquanto uma janela está aberta e enquanto estás inconsciente.

## Em baixo à esquerda: o relógio {#bottom-left-the-watch}
Rumo, hora e frequência de rádio num oval preto; vê [Relógio](Watch).

## Em baixo à direita: o nome do veículo {#bottom-right-the-vehicles-name}
Enquanto conduzes, o nome do veículo fica no canto inferior direito. As portas, o motor, o combustível e a velocidade estão no [Painel do condutor](Drivers-Dashboard), em baixo ao centro; os danos vêem-se no próprio veículo, como fumo do motor e danos na carroçaria. Vê [Veículos](Vehicles), [Combustível](Fuel) e [Reparações e fechaduras](Repairing-and-Locks).

## Centro do ecrã {#centre-of-the-screen}
- **Texto de ação**: uma linha branca a cerca de três quartos da altura, substituída por cada nova mensagem e desaparecida ao fim de 3 segundos: `Equipado`, `Mala trancada`, `São precisas mais 2 ranhuras`, `Motor cortou`, `Ferido: cabeça  -12 PV  (a sangrar)`, `2 feridas curadas`...
- **Barra de progresso**: uma pequena barra cinzenta por cima do texto de ação enquanto decorre uma ação mantida (reparar, reabastecer, um tratamento, soldar, lançar uma linha...). É cancelada quando te mexes ou largas a tecla. A mesma barra mostra um desmaio enquanto estás inconsciente.
- **Dicas de ajuda**: texto verde à esquerda do centro com uma dica para o que estás a fazer, por vezes com uma linha azul por baixo. A dica ao entrar num veículo danificado fica 20 segundos. `/tooltips` liga e desliga-as, junto com as dicas no chat ([Chat](Chat)); a escolha fica guardada na tua conta.
- **Aviso de competência**: `+Reparação` e semelhantes a verde em baixo durante 5 segundos depois de uma ação treinar uma [competência](Skills); enquanto conduzes, fica logo acima do painel de instrumentos.
- **Barras de competências**: em baixo à direita, uma barra branca fina por [competência](Skills), com o nome à esquerda, preenchida até ao valor da competência; mostram-se as dez mais altas quando tens mais. Sobem enquanto conduzes para libertar o nome do veículo.
- **Barra de calor**: uma barra vermelha com `Sobreaquecimento!` enquanto conduzes um veículo armado e disparas a sua arma, vê [Veículos](Vehicles).
- **Escuridão**: o ecrã escurece cada vez mais abaixo de 40 de vida. Os analgésicos e a Adrenalina escondem-na, vê [Drogas](Drugs).
- **Contagem da lista branca**: `Não está na lista branca / Tempo restante mm:ss` no topo do ecrã quando a lista branca do servidor é ligada e não estás nela, vê [Conta e início de sessão](Account-and-Login).
- **Ecrã de morte**: vê [Morte](Death).

## Janelas {#windows}
- **Janelas de lista** (o inventário, sacos, malas, o menu de denúncias...): um título com `(usado/tamanho)` para os contentores, linhas com a selecionada a vermelho, uma barra de deslocamento e dois botões. `Enter` prime o botão da esquerda, `Escape` o da direita. Vê [Inventário](Inventory).
- **Caixas de mensagem e de entrada** (início de sessão, o texto de boas-vindas, bilhetes, a introdução da frequência, a linha do legista de um corpo): `Enter` e `Escape` são os dois botões; `Ctrl+V` cola num campo.
- **Janelas de informação** (`/help`, `/rules`, `/admins`, `/credits`, `/chatinfo`, `/mstats`): fecham com o botão Fechar, `Escape` ou `Enter`.
- O **painel de rádio** ([Rádio](Radio)), o **teclado numérico** ([Teclados numéricos](Keypads)) e o **painel de ajuste** dos itens colocados ([Construção](Constructing)) têm páginas próprias.
- A **caixa de chat** no canto superior esquerdo é a do MTA; vê [Chat](Chat).
