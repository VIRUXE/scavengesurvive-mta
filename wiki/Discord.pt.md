# Discord

O servidor está ligado ao servidor de Discord da comunidade de duas maneiras: uma ponte de chat que leva linhas entre o jogo e o Discord, e a Rich Presence, que mostra aos teus amigos que estás a jogar.

## A ponte de chat {#the-chat-bridge}
O que passa do jogo para o Discord:

- As tuas linhas de chat **global** (`/g`), publicadas no canal `#in-game-chat` com o teu nome. O chat local, o chat de rádio e o `/me` nunca saem do jogo, nem a voz.
- **Entradas e saídas**: entrar, sair, ser expulso ou banido e mudanças de alcunha vão para um canal `#join-part`.
- **Mortes**: cada morte de uma personagem é publicada com o nome, quem a matou quando foi um jogador, a causa e a hora.
- **Veículos novos**: quando o mundo recebe um veículo novo através do reabastecimento por escassez ([Saque e reaparecimento](Loot-and-Respawn)), o canal geral é informado do que é e em que cidade (Los Santos, San Fierro ou Las Venturas), nada mais preciso.
- Os itens criados por comandos de staff e o loot que o mundo faz reaparecer são publicados em canais próprios, para o staff.

Os códigos de cor são retirados do texto retransmitido, e uma linha retransmitida nunca menciona ninguém no Discord.

O que passa do Discord para o jogo:

- Uma mensagem escrita em `#in-game-chat` aparece para todos os que têm o recetor global ligado, como linha global: `[Discord] nome: texto`. O `/quiet` esconde-as juntamente com o resto do chat global ([Chat](Chat)).

Mais nada entra: ninguém no Discord pode executar comandos do jogo nem ler o chat local.

## Comandos do bot {#bot-commands}
O bot responde a alguns comandos de barra em qualquer canal do servidor de Discord:

- `/connect`: como entrar no servidor.
- `/ip`: o endereço do servidor.
- `/wiki`: a wiki dos jogadores.
- `/site`: o site.
- `/rules`: as regras ([Jogo limpo](Fair-Play)).
- `/help`: lista estes comandos.

Respondem em inglês, exceto em `#br-huehuehue`, onde as respostas (e as ligações, para a wiki em português) são em português do Brasil.

Se a ponte estiver em baixo durante algum tempo, o jogo continua; as linhas enviadas entretanto simplesmente não são retransmitidas.

## Rich Presence {#rich-presence}
Com o Discord aberto no teu computador e a Rich Presence permitida nas definições do MTA, o teu estado no Discord mostra:

- o nome do servidor,
- *Surviving*,
- quantos jogadores estão online em relação à capacidade do servidor, atualizado a cada 15 segundos,
- há quanto tempo estás no servidor,
- um botão **Join server** que liga um amigo diretamente ao servidor (vê [Entrar no servidor](Joining-the-Server)).

Nada sobre a tua personagem, a tua posição, os teus itens ou o teu chat é partilhado. O estado desaparece quando sais.

Vê também [Chat](Chat), [Entrar no servidor](Joining-the-Server) e [Denúncias e banimentos](Reports-and-Bans).
