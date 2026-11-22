# Caça aos códigos e puzzles

Espalhados pelo mapa há portões, portas e lugares trancados que só abrem quando resolves alguma coisa: encontrar as peças de um código, trazer uma peça em falta ou seguir uma pista. Todos usam o mesmo tipo de **botão**: um ponto no mundo que mostra a sua indicação na lista de teclas quando estás a menos de 1,5 m (*Ativar*, *Enter*, *Use the lift*, ...). Prime aí a tecla de interação (`F`). Se um item estiver mais perto de ti do que o botão, o `F` apanha o item, por isso chega-te mesmo ao botão. As portas e os portões são iguais para todos: o que um jogador abre fica aberto para todos.

## Portões e portas {#gates-and-doors}
| Onde | O quê |
|:--|:--|
| Chinatown, San Fierro | Dois portões de enrolar, cada um com um botão (*Ativar*) de cada lado. O portão sobe em cerca de 3 segundos e volta a descer 3 segundos depois de aberto. |
| Base naval de Easter Basin, San Fierro | A cancela do portão (*Ativar portão*) levanta-se quando a premes e fica levantada até alguém a premir de novo. |
| K.A.C.C. Military Fuels, Las Venturas | Um botão (*Ativar*) abre os dois portões do complexo em cerca de 8 segundos; fecham-se outra vez 3 segundos depois. O teclado no poste é só decoração, não é preciso código. |
| Área restrita, Bone County | Doze portas com teclado e códigos aleatórios, ver [Área 69](Area-69). |

## Caça aos códigos {#code-hunt}
![Código](images/items/1898_clicker.png)

Em Queens, San Fierro, um armazém está fechado por trás de uma porta com teclado. O servidor inventa um código novo de quatro dígitos sempre que arranca e esconde quatro itens **Código** por San Fierro, um dígito cada, em quatro de oito sítios possíveis: Calton Heights, Paradiso (junto ao churrasco fixo), Esplanade North, Downtown, Queens, Doherty, Missionary Hill e o Aeroporto de Easter Bay. O dígito faz parte do nome do item, por exemplo *Code (7)*. Os sítios mudam de um arranque para o seguinte, e os itens Código de um código anterior são removidos do mundo; um que tenhas levado contigo mantém o dígito antigo e já não serve de nada.

![A entrada do armazém de Queens, com o teclado ao lado do portão da garagem](images/places/queens-lockup.png)

1. Reúne os quatro itens Código ([Inventário](Inventory)).
2. Prime `F` no teclado do armazém (*Interagir*) e introduz os quatro dígitos. A ordem não é dada, mas com quatro dígitos conhecidos há no máximo 24 ordens a experimentar; um código errado é recusado (*Incorrect passcode*), e o teclado aceita uma tentativa a cada 2 segundos.
3. O código certo abre o armazém até o servidor reiniciar. O botão da porta, do lado de fora (*Go inside*), leva-te então lá para dentro, onde há alguns pontos de saque, e o botão lá dentro (*Leave*) traz-te de volta cá para fora. Antes de o código ser introduzido, a porta só te diz que está trancada eletronicamente.

Uma Interface de hacking não faz nada aqui (só funciona na [Área 69](Area-69)). Quem souber o código pode entrar, por isso guarda os dígitos para ti.

## Estação de rádio do Monte Chiliad {#mount-chiliad-radio-station}
Um portão e uma porta guardam a estação de rádio no cume do Monte Chiliad.

- O botão do portão (*Ativar*) abre-o, e fica aberto até ser premido outra vez.
- O teclado da porta está morto: `F` na porta (*Use*) de mãos vazias só diz *The keypad seems broken*. Uma **Caixa de fusíveis** está a poucos metros. Segura-a e prime `F` na porta: a caixa de fusíveis gasta-se, o teclado fica com energia, e a partir daí `F` na porta abre-a e fecha-a.
- Se segurares antes a **Bateria** que lá está, o teclado entra em curto-circuito: uma chuva de faíscas, o teclado cai do suporte, e a porta fica morta até o servidor reiniciar.
- Qualquer outro item na mão não faz nada na porta.

![A estação do cume e o seu portão](images/places/chiliad-station.png)

## O rancho e a pedreira {#the-ranch-and-the-quarry}
1. Num rancho no sudeste de Tierra Robada há um computador sem disco rígido (*Use*): diz-te que falta o disco e acha isso muito suspeito. O **Disco rígido** está ao lado. Segura-o e prime `F` no computador: entra ao fim de uns segundos. `F` outra vez lê o diário no ecrã, que diz que o dono fugiu para casa de um amigo no Chiliad e escondeu lá uma chave; `F` mais uma vez sai do ecrã.
2. A **Chave** está num barracão nas encostas ocidentais do Monte Chiliad.
3. No fundo da Hunter Quarry, em Bone County, uma porta (*Enter*) não cede: *There's no way you can get through here without a key. Perhaps you should search the shed?* Segura a Chave e prime `F`: *You have unlocked the mystery door!* A chave não se gasta, e a porta fica destrancada até o servidor reiniciar. A partir daí, `F` na porta leva-te para baixo, para as cavernas.

## As cavernas {#the-caves}
A porta da pedreira dá para um mundo de cavernas à parte. Não tem pontos de saque, mas as suas passagens saem por todo o mapa. Cada passagem é um botão marcado *Enter* (ou *Climb up the ladder* / *Climb down the ladder*), e depois de cada salto ficas imóvel durante um segundo.

- A caverna 1, onde chegas, tem um elevador (*Use the lift*) com um botão em cima e outro em baixo; a viagem demora cerca de 19 segundos.
- Passagens ligam a caverna 1 à caverna 2, e a caverna 2 à caverna 3.
- Da caverna 3 uma passagem leva a uma linha de metro. Na estação, outra passagem leva ao subsolo de Fort Claw, cuja porta (*Ativar*, um botão de cada lado) fecha 3 segundos depois de aberta; daí, um *Enter* sai em Blueberry, Red County.
- No extremo dos túneis do metro, uma escada (*Climb up the ladder*) sai de um alçapão em Ganton, Los Santos; o alçapão é um botão *Climb down the ladder* para o caminho de volta.
- Uma porta marcada *Locked* nos túneis do metro nunca abre.

## Dicas {#tips}
- As peças dos puzzles têm de ser as do seu próprio sítio: uma Caixa de fusíveis, Bateria, Disco rígido ou Chave de outro lado não conta. Se uma desaparecer, o mundo repõe-na no próximo reinício do servidor.
- Os [Teclados numéricos](Keypads) construídos pelos jogadores são outra coisa; os teclados daqui são fixos no mundo.
- Vê [Escadas e tirolesas](Ladders-and-Ziplines) para as outras funcionalidades `F` do mundo e [Mundo e zonas](World-and-Zones) para o mapa.

## Mapa {#map}
Os locais dos puzzles à superfície.

<a href="images/map/puzzles.png" target="_blank" rel="noopener noreferrer" title="Ver o mapa em tamanho real; Ctrl/Cmd-clique ou clique com o botão do meio para abrir num novo separador"><img src="images/map/puzzles.png" alt="Mapa"></a>
