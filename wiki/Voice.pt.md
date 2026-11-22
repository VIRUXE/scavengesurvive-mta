# Voz

O servidor usa o chat de voz integrado do MTA. Mantém a tecla de voz do MTA (premir para falar, definida nas definições do MTA, nas teclas) e fala; larga para parar. Não é preciso levar nem ligar nada no jogo, e não há nenhum comando de voz próprio.

## Quem te ouve {#who-hears-you}
A voz segue o teu modo de [chat](Chat):

| O teu rádio está em | Quem te ouve |
|:--|:--|
| Local (`/l`) | jogadores a menos de 40 m |
| Global (`/g`) | jogadores a menos de 40 m, e toda a gente que leria o teu texto global |
| Rádio (`/r`) | jogadores a menos de 40 m, e todos os que estejam sintonizados a 0,05 MHz da tua frequência ([Rádio](Radio)) |

Os jogadores a menos de 40 m ouvem-te sempre, seja qual for o modo. O público é verificado de novo a cada meio segundo enquanto falas, por isso quem se aproxima ou sintoniza a meio da frase apanha o resto.

Enquanto estás silenciado ([Denúncias e banimentos](Reports-and-Bans)), premir a tecla não faz nada e o jogo avisa-te uma vez por silenciamento: *Estás silenciado: ninguém ouve a tua voz até o silêncio terminar.* Antes de iniciares sessão, a voz também está desligada.

## O indicador de fala {#the-talking-indicator}
<!-- shot:shot-voice-indicator -->

Enquanto alguém que consegues ouvir está a falar, aparece à esquerda do ecrã, centrado na vertical, um bloco de linhas:

- Quando **tu** falas, a linha de cima é o teu indicador: uma barra verde, um ícone de altifalante a pulsar e `TALKING [LOCAL]`, `TALKING [GLOBAL]` ou `TALKING [98.12]` com a tua frequência no modo rádio, para saberes sempre quem está do outro lado. Atrás dele o servidor conta quem te ouve, `TALKING [LOCAL] - 3 hear you`, e mantém a contagem atualizada enquanto falas. Quando ninguém está ao alcance, a linha fica vermelha e diz `NOBODY HEARS YOU [LOCAL]`: aproxima-te, ou muda para global ou para uma frequência partilhada. A contagem não tem nomes, por isso nunca te diz quem está a ouvir.
- Por baixo, uma linha por jogador a falar: a tua linha em amarelo como `Nome (You)`, as dos outros na cor do nome atrás de uma barra azul. A tua linha vem primeiro, depois as dos outros pela ordem em que começaram a falar.

Por cima da cabeça de cada jogador a falar a menos de 40 m flutua um ícone de altifalante, verde para ti e na cor do nome do jogador para os outros. Só é desenhado enquanto tens linha de visão limpa para ele, nunca através de uma parede, e encolhe com a distância. Os jogadores mortos não mostram nada. As linhas e os ícones desaparecem assim que a tecla é largada.

Vê também [Chat](Chat), [Rádio](Radio) e [Denúncias e banimentos](Reports-and-Bans).
