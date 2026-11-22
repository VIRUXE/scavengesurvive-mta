# Denúncias e banimentos

O staff mantém o servidor jogável. Esta página trata de como os contactas, do que podem fazer-te e de como recorrer de um banimento. O que o servidor faz sozinho está em [Jogo limpo](Fair-Play).

## O staff {#the-staff}
`/admins` lista todas as contas de staff, o seu nível e quem está online neste momento. Níveis, do mais baixo ao mais alto: Game Master, Moderator, Administrator, Lead, Developer.

Um membro do staff **em serviço** usa uma skin de staff fixa, não sofre dano de jogadores e vê uma etiqueta com nome, vida e distância sobre todos os jogadores. Fora de serviço joga como qualquer pessoa.

## Denunciar um jogador {#reporting-a-player}
`/report` sem nada a seguir abre um menu com quatro opções: um jogador que está online, o nome de um jogador (alguém offline), o jogador que te matou por último, ou o jogador mais próximo de ti. Escolhe uma, depois escreve o motivo (até 128 caracteres). Para saltar o menu:

| Comando | Denuncia |
|:--|:--|
| `/report <nome> [motivo]` | esse jogador, online ou não (um nome parcial chega para alguém online) |
| `/report near [motivo]` | o jogador mais próximo a menos de 100 m (staff em serviço não conta) |
| `/report killer [motivo]` | quem te matou por último |

Sem um motivo na linha de comando, uma janela pede-o. *Denúncia enviada. Obrigado.* confirma-a; o staff vê-a logo se houver algum online e na sua lista de denúncias caso contrário, juntamente com o sítio onde tu (ou o jogador denunciado) estavam. Não te podes denunciar a ti próprio.

## Comunicar um bug {#reporting-a-bug}
`/bug <descrição>` (ou só `/bug`, que abre uma janela) cria um relatório de bug de até 128 caracteres. `/issues` lista os relatórios de bug abertos e abre um; os Moderators e acima podem apagar um relatório a partir daí.

## O que o staff pode fazer {#what-the-staff-can-do}
| Ação | O que vês |
|:--|:--|
| **Mensagem** | Linhas ` >  texto` no chat: uma mensagem para ti, ou um anúncio para todos. |
| **Silenciar** | *Silenciado do chat global durante N segundos, Motivo: ...* (ou para sempre). Enquanto estás silenciado não podes enviar nenhuma linha de chat nem usar voz; tentar diz-te o tempo que falta. Os silenciamentos ficam guardados na tua conta, por isso sair não os levanta. |
| **Avisar** | *Foste avisado (n/5) por: motivo.* O quinto aviso é um banimento de 24 horas. |
| **Expulsar** | *Expulso, motivo: ...* e és desligado. Manténs a tua personagem. |
| **Congelar** | *Congelado por um admin* (ou *durante N segundos*): não te podes mexer nem agir até *Já não estás congelado.* |
| **Teletransportar** | O staff pode levar-te até eles ou ir ao local onde foi feita uma denúncia. |
| **Curar** | *Foste curado pelo staff.* |
| **Observar** | Nada: um membro do staff invisível pode estar a ver-te. Se falar no chat local ou por voz local, só tu o ouves. |
| **Banir** | *Estás banido! Motivo: ...*, depois és desligado. |

## Banimentos {#bans}
Um banimento fica registado contra o teu nome, o teu endereço e o teu computador, por um tempo definido ou para sempre. Entrar enquanto está em vigor mostra `Estás banido (desde <data> por <staff>).`, o motivo e `Desbanimento: <data>` ou `Nunca`, e desliga-te; ver [Conta e início de sessão](Account-and-Login).

- Um banimento por avisos (*Getting 5 warnings*) termina sozinho passadas 24 horas.
- Um banimento dirigido a alguém que partilhava o teu endereço ou computador pode apanhar-te por engano; a mensagem ao entrar indica a conta banida, por isso toma nota.

### Recorrer {#appealing}
Contacta um Moderator ou acima (ver `/admins`, ou o Discord da comunidade) com o nome sob o qual foste banido, a data e o motivo mostrado. O staff verifica o historial por trás do banimento antes de decidir: uma coincidência por endereço partilhado é levantada e reemitida contra a pessoa certa, um banimento temporário é explicado com a sua data de fim. O membro do staff que aplicou o banimento não decide sozinho.
