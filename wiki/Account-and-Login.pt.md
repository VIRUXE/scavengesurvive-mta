# Conta e início de sessão

A tua conta é o teu nome no MTA: o nome com que te ligas é o nome que registas, e cada ligação posterior com esse nome pede a palavra-passe. Um nome tem de 1 a 22 caracteres, só letras, dígitos e pontuação.

## Primeira entrada {#first-join}
1. **Língua.** Uma janela lista as dez línguas da interface. Escolhe a tua e prime **Continuar** (duplo clique ou `Enter` também funciona). A escolha fica guardada na conta depois de entrares; muda-a mais tarde com `/lang`.
2. **Registar.** A janela *Registar uma nova conta* pede uma palavra-passe de 4 a 32 caracteres. **Aceitar** cria a conta e inicia-te a sessão. **Sair** desliga-te.
3. **Email.** Escreve um email **válido** que possas abrir de imediato: o servidor envia-lhe um código de 6 dígitos, e não podes jogar até o escreveres na janela seguinte (ver [Confirmação do email](#email-confirmation)).
4. **Boas-vindas.** As contas novas leem o texto de boas-vindas. O único botão conta a partir de 10 até dizer **Aceitar**; fechá-la antes só a faz voltar. `/welcome` mostra-o outra vez quando quiseres.
5. A tua primeira personagem nasce; ver [Morte](Death) para o que uma personagem nova tem ao começar.

![Janela de registo](images/auth-dialog-register.jpg)

## Iniciar sessão {#logging-in}
Cada entrada posterior mostra *Inicia sessão na tua conta*. Escreve a palavra-passe e prime **Aceitar** (ou `Enter`); **Sair** (ou `Escape`) desliga-te.

![Janela de início de sessão](images/auth-dialog-login.jpg)

Uma palavra-passe errada, ou com menos de 4 caracteres, conta como tentativa: *Palavra-passe incorreta! N de 5 tentativas*. À quinta tentativa errada és desligado, e as tentativas são contadas por computador durante 10 minutos, por isso voltar a ligar não as repõe.

![Palavra-passe errada](images/auth-dialog-wrong-password.jpg)

Só uma sessão por conta: um segundo cliente a ligar-se com o teu nome é recusado (*A conta já está online*). Uma conta desativada é recusada com *Conta inativa*; fala com o staff.

O servidor pode ativar o início de sessão automático para jogadores que voltam do mesmo endereço e computador do último início de sessão; está desligado por omissão, por isso conta com a janela da palavra-passe.

Depois de entrares, a tua personagem carrega onde a deixaste, com as suas estatísticas e inventário; depois de uma morte é criada uma nova.

## Confirmação do email {#email-confirmation}
Toda a conta precisa de um email confirmado antes de poder jogar, staff incluído. As contas feitas antes disto existir são pedidas um no próximo início de sessão (também quando o servidor te inicia a sessão automaticamente).

- *Confirma o teu email* pede o endereço. Um mal formado (tem de parecer `nome@exemplo.com`, sem espaços) é recusado com o motivo, e um endereço só pode confirmar no máximo 3 contas.
- *Introduz o teu código de confirmação* espera depois pelo código de 6 dígitos do email *O teu código de confirmação do Scavenge & Survive: …*. Vê também a pasta de spam; pode demorar um minuto.
- Na caixa do código também podes escrever outro endereço (uma gralha à primeira), ou deixá-la vazia e premir **Aceitar** para receber um novo código, uma vez por minuto.
- Um código é válido durante 15 minutos e permite 5 tentativas erradas; depois disso é enviado um novo. Uma ligação recebe no máximo 5 emails: a partir daí és desligado e podes voltar a entrar mais tarde. Um endereço que escreveste mas nunca confirmaste fica memorizado, por isso o início de sessão seguinte envia um novo código diretamente para ele.
- **Sair** em qualquer das janelas desliga-te (*Saiu sem confirmar o email*).

## Comandos {#commands}
`/changepass <antiga> <nova>` muda a tua palavra-passe (a nova tem de ter 4 a 32 caracteres; uma palavra-passe antiga errada é recusada), `/lang <código>` define a tua língua (`en`, `es`, `fr`, `pt`, `ptbr`, `ru`, `ro`, `id`, `bhs` ou `cs`; as linhas ainda sem tradução aparecem em inglês), `/tooltips` liga ou desliga as dicas de ajuda e `/welcome` mostra outra vez o texto de boas-vindas. Os quatro ficam guardados na tua conta; ver [Comandos](Commands).

## Banimentos {#bans}
Quando te ligas, o servidor confere o teu nome, o teu endereço e o teu computador com a lista de banimentos. Uma coincidência mostra três linhas, `Estás banido (desde <data> por <staff>).`, `Motivo: ...` e `Desbanimento: <data>` ou `Nunca`, e desliga-te um segundo depois. Ver [Denúncias e banimentos](Reports-and-Bans) para recursos.

## Lista branca {#whitelist}
O servidor normalmente deixa entrar toda a gente. Quando o staff liga a lista branca, só os nomes da lista e as contas de staff podem jogar:

- iniciar sessão com ela ligada sem estares na lista mostra *Lista branca ativa.* e *Não estás na lista branca.* e desliga-te;
- se ela for ligada enquanto jogas, aparece uma contagem decrescente no topo do ecrã, *Não está na lista branca / Tempo restante mm:ss*, e és desligado quando chega a zero (5 minutos por omissão). Seres adicionado à lista entretanto interrompe-a.

Ver também [Primeiros passos](Getting-Started), [Morte](Death) e [Comandos](Commands).
