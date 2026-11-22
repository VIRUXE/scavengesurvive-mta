# Chat

Prime `T` (a tecla de chat do MTA) para escreveres. Cada linha que envias sai pelo teu [rádio](Radio): o modo decide quem a lê. Os comandos estão em [Comandos](Commands).

## Modos {#modes}
| Modo | Mudar para ele / enviar uma linha | Quem lê | Aspeto |
|:--|:--|:--|:--|
| Local | `/l`, `/local` | jogadores a menos de 40 m de ti | azul-claro, `[Local] Nome: texto` |
| Global | `/g`, `/global` | todos no servidor que não desligaram o global, e o canal do Discord (mais abaixo) | branco, `[Global] Nome: texto` |
| Rádio | `/r` | todos sintonizados a menos de 0,05 MHz da tua frequência | laranja, `[98.12] Nome: texto` (a tua frequência) |
| Admin | só staff | a staff | a cor do cargo do membro da staff, `[Admin] Nome: texto` |

Escrever só o comando muda o teu modo (`You turn your radio on to the global frequency.`); escrevê-lo com texto envia essa linha nesse modo sem mudares. Os botões de ligar e `global`/`freq` do painel do rádio também mudam de modo: rádio desligado é chat local. Todos os logins começam em global; a tua frequência fica guardada com a tua personagem.

<!-- shot:shot-chat-radio -->

- `/me <texto>` envia uma linha de ação, `[Local] Nome texto`, aos jogadores a menos de 40 m.
- `/quiet` desliga e liga o teu recetor global. Desligado esconde todas as linhas globais, incluindo as do Discord; continuas a poder enviar linhas globais.
- `/freq <87.5-108.0>` sintoniza o rádio, `/radio` abre o painel, `/chatinfo` mostra isto no jogo.
- Uma linha com mais de 128 caracteres continua numa segunda linha.
- Enviar três linhas num segundo silencia-te durante 30 segundos (*Muted from global chat for 30 seconds for chat flooding*). Um silêncio bloqueia todos os modos e a tua voz; ver [Denúncias e banimentos](Reports-and-Bans).

## Voz {#voice}
A voz com carregar-para-falar (a tecla de voz do MTA, definida nas definições do MTA) segue as mesmas regras: os jogadores a menos de 40 m ouvem-te sempre, e em modo global ou rádio os jogadores que leriam o teu texto também te ouvem. Enquanto estás silenciado, ninguém te ouve e o jogo diz-to uma vez.

## Linhas do servidor {#lines-from-the-server}
- Quando entras, lês a linha laranja de direitos de autor e, se a staff definiu uma, `MoTD: ...` (`/motd` repete-a); todos leem `Name has joined`.
- Linhas ` >  ...` a amarelo ou branco são o servidor a falar contigo: avisos, mensagens da staff, respostas a comandos.
- As linhas `[Admin]` existem só para a staff; nunca as vês.

## Discord {#discord}
O servidor está ligado a um servidor de Discord.

- As tuas linhas de chat **global** são reencaminhadas para o canal `#in-game-chat` do Discord com o teu nome. O chat local, o chat de rádio e `/me` nunca saem do jogo.
- As mensagens escritas nesse canal do Discord aparecem no jogo como uma linha global, `[Discord] nome: texto`, para todos com o recetor global ligado.
- Entrar, sair, ser expulso ou banido e mudanças de alcunha são publicadas num canal `#join-part`.
- Quando o mundo recebe um veículo novo, o canal geral é informado de qual é e em que cidade.

## Discord Rich Presence {#discord-rich-presence}
Com o Discord aberto e o Rich Presence permitido nas definições do MTA, o teu estado no Discord mostra o nome do servidor, *Surviving*, quantos jogadores estão online e há quanto tempo jogas, com um botão **Join server** para os teus amigos. Nada sobre a tua personagem ou posição é partilhado.

Ver também [Rádio](Radio), [Comandos](Commands) e [Denúncias e banimentos](Reports-and-Bans).
