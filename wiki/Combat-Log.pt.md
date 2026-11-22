# Desligar em combate

Desligar em combate (combat log) é sair do jogo durante uma luta para escapar a ser morto e perder os teus itens. O servidor conta isso como uma morte.

## A janela de combate {#the-combat-window}
Quando outro jogador te fere, abre-se uma janela de 30 segundos (o servidor pode mudar a duração). Enquanto está aberta o relógio do teu HUD fica vermelho, e volta a branco quando a janela fecha ou quando o jogador que te acertou sai.

Se te desligares, saíres ou perderes a ligação com a janela aberta **e o jogador que te acertou ainda estiver online**:

- toda a gente vê `<nome> desligou-se em combate!` no chat;
- a tua personagem morre no momento: os teus itens, equipamento vestido e o que tinhas nas mãos caem onde estavas, exatamente como numa morte normal (vê [Morte](Death));
- o teu próximo início de sessão começa uma nova personagem, e as tuas [competências](Skills) desaparecem.

## O que não conta {#what-does-not-count}
- Seres expulso ou banido pela staff: a tua personagem é guardada normalmente.
- Dano que não veio de um jogador (uma queda, a fome) não faz o relógio ficar vermelho. Só interessa se um jogador te tiver acertado antes, caso em que mantém essa janela a correr.
- Se o atacante já saiu do servidor, não há ninguém de quem fugir e a tua personagem é guardada normalmente.
- Morrer primeiro por outros meios: uma personagem morta não pode desligar-se em combate.

## Ligações perdidas {#lost-connections}
Uma ligação interrompida conta como sair: a verificação faz-se quando o servidor repara que já não estás, e qualquer golpe de um jogador nos últimos 30 segundos (cujo atacante ainda esteja online) mata a personagem.
