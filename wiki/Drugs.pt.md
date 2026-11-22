# Drogas

As drogas vêm dos [Comprimidos](Medical), dos [Injetores](Medical) e da Mala de médico. Cada uma dura 5 minutos. Tomar a mesma droga outra vez soma mais 5 minutos em vez de reiniciar o temporizador, por isso as doses acumulam-se. As drogas ativas aparecem a amarelo no painel de Estado de saúde (abre o inventário com `H`), são guardadas quando sais do jogo e continuam a contagem decrescente quando voltas, e és avisado quando uma deixa de fazer efeito. Morrer limpa-as.

![Comprimidos](images/items/20283_pills.png) ![Injetor](images/items/2711_tatoo_needle.png) ![Mala de médico](images/items/20297_doctor_bag.png)

## Tomá-las {#taking-them}
Mantém premida a tecla de interação (`F`) com o item nas mãos.

- Os **Comprimidos** demoram 1 segundo e atuam sempre em ti. O tipo aparece no nome: `Comprimidos (Antibióticos)`, `Comprimidos (Analgésico)` ou `Comprimidos (LSD)`.
- Os **Injetores** demoram 1 segundo e podem ser usados em ti ou num jogador ao teu lado. O tipo aparece no nome: `Injetor (Morfina)`, `Injetor (Adrenalina)`, `Injetor (Heroína)` ou `Injetor (Vazio)`. Depois de usado, o injetor fica nas tuas mãos, agora vazio.
- A **Mala de médico** dá a droga indicada na sua etiqueta, por exemplo `Mala de médico (2/3, Morfina)`: restam duas cargas, e cada utilização gasta uma.

Os comprimidos e injetores encontrados como saque são aleatórios; os dados pela equipa ou fabricados são de Antibióticos e Vazios.

## Efeitos {#effects}
| Droga | Origem | Efeito |
|:--|:--|:--|
| Antibiótico | Comprimidos de Antibióticos, Mala de médico | os comprimidos curam uma [infeção](Infection) alimentar e, metade das vezes, uma infeção de ferida |
| Analgésico | Comprimidos de Analgésico, Mala de médico | os comprimidos restauram 10 de vida; esconde o ecrã escuro de vida baixa |
| Morfina | Injetor de Morfina, Mala de médico | restaura 0,5 de vida na maior parte dos segundos; acalma a oscilação da infeção; desfoca ligeiramente o ecrã |
| Adrenalina | Injetor de Adrenalina, Mala de médico | restaura um pouco de vida a cada segundo; esconde o ecrã escuro; acalma a oscilação da infeção; injetada num jogador inconsciente, acorda-o (não quando usada em ti) |
| Heroína | Injetor de Heroína | o céu fica noite, com um tempo fixo |
| LSD | Comprimidos de LSD | o céu fica noite, com um tempo fixo |
| Ar | Injetor vazio | custa 1 de vida em metade dos segundos e desfoca muito o ecrã |

Quando o último efeito de LSD ou Heroína passa, o céu volta à hora e ao tempo do servidor.

Um injetor vazio não é um item inofensivo: injeta ar. Confirma o nome antes de usares um noutra pessoa.
