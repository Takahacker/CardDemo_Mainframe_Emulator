# Plano de métricas de performance

Como pretendemos usar o mini-CICS para gerar uma linha de base de performance
do CardDemo em COBOL e compará-la com a versão modernizada (C# em cloud, com
SQL Server externo).

> **Estado:** plano. Nada do que está descrito aqui foi implementado ainda.

## Objetivo e limite

Queremos comparar performance, e não só a correção da transpilação. Não temos
orçamento para rodar um mainframe, então a comparação que conseguimos defender
é:

> a mesma carga de negócio, executada pelo COBOL original em runtime emulado e
> pela stack modernizada.

Não é "mainframe contra cloud". Os tempos medidos aqui são do emulador, e todo
resultado de tempo deve ser apresentado como "COBOL em runtime emulado".

## Por que o emulador serve de linha de base

- O COBOL do CardDemo não é alterado; o tradutor só troca cada `EXEC CICS` por
  `CALL "KIXCMD"`.
- Todo comando passa por um único ponto em Python (`Task._serve`, em
  `minicics/cics.py`), então dá para contar e cronometrar tudo sem tocar nos
  programas.
- O padrão de acesso a dados (quais arquivos, em que ordem, quantos registros)
  é o mesmo que o programa teria em um CICS real.

## O que vamos medir

### 1. Métricas independentes de hardware

Contagens por interação. Valem para qualquer ambiente em que o mesmo COBOL
rode, e são a parte mais forte da comparação.

| Métrica | Lado emulador | Lado moderno |
| --- | --- | --- |
| Acessos a dados | `READ`, `WRITE`, `REWRITE`, `DELETE`, `STARTBR`, `READNEXT`, `READPREV` por arquivo | queries por tabela, round trips ao SQL Server |
| Registros tocados | registros lidos e gravados | linhas lidas e gravadas, leituras lógicas |
| Volume | bytes por arquivo, tamanho da commarea | bytes de requisição, resposta e resultado SQL |
| Tela | bytes do fluxo 3270 de entrada e saída | bytes do payload HTTP |
| Encadeamento | sequência de `XCTL` e `RETURN TRANSID` | chamadas entre serviços |

### 2. Métricas relativas sob a mesma carga

Tempos e capacidade. Só comparam com os dois sistemas na mesma classe de
máquina, e valem como razão e como curva, não como valor absoluto.

- latência p50, p95 e p99 por interação e por jornada;
- vazão máxima e degradação com 1, 10, 50 e 100 usuários simultâneos;
- taxa de erro e de abend;
- CPU e memória por interação.

### 3. Métricas só do destino

Sem par no legado; respondem se a solução nova aguenta.

- Query Store e DMVs do SQL Server (planos, esperas, bloqueios);
- custo de cloud por mil transações;
- comportamento com volume de dados 10x e 100x o do CardDemo.

## Onde instrumentar

Uma interação começa quando o terminal envia uma tecla de atenção e termina
quando a resposta 3270 sai. O tempo total é decomposto assim:

| Componente | Ponto no código | O que representa |
| --- | --- | --- |
| `total` | `Terminal._run` em `minicics/server.py` | tempo de resposta visto pelo usuário |
| `spawn` | `subprocess.Popen` em `Task.run` até o primeiro `KIXCMD` | criação do `kixtask` e carga do módulo; custo do emulador, sem equivalente no CICS |
| `comando` | cada `cmd_<verbo>` despachado por `Task._serve` | tempo e bytes de cada comando CICS |
| `arquivo` | `Store.seek`, `Store.write` e `Store.delete` em `minicics/vsam.py` | tempo de E/S, arquivo, chave e registros |
| `terminal` | `SEND` / `RECEIVE` e `ds3270` | montagem e leitura das telas |
| `cobol` | `total` menos os demais | tempo dentro do programa COBOL |

O `spawn` é medido justamente para poder ser descontado: a comparação usa
`total - spawn` como tempo de aplicação.

O `--trace` atual já passa por esses pontos, mas registra só hora em segundos e
texto livre em `data/minicics.log`. A instrumentação nova grava em arquivo
próprio e estruturado.

## Registro por interação

Um registro por tarefa, em JSON Lines, fazendo o papel do registro SMF 110 do
CICS. Formato pretendido:

```json
{
  "run": "2026-10-06T14:00-baseline-10u",
  "jornada": "pagar_fatura", "passo": 3, "usuario_virtual": 7,
  "tarefa": 1842, "transid": "CB00", "programa": "COBIL00C", "aid": "ENTER",
  "inicio": "2026-10-06T14:00:12.345678",
  "ms": {"total": 41.2, "spawn": 28.0, "cobol": 2.1, "arquivo": 9.0, "terminal": 2.1},
  "arquivos": {"ACCTDAT": {"read": 1, "rewrite": 1, "bytes_lidos": 300, "bytes_gravados": 300}},
  "comandos": {"READ": 1, "REWRITE": 1, "SEND": 1, "RETURN": 1},
  "bytes": {"tela_entrada": 38, "tela_saida": 1920, "commarea": 160},
  "resultado": "ok"
}
```

O sistema moderno emite o mesmo esquema, trocando `arquivos` por tabelas e
`comandos` por queries. Os campos `run`, `jornada`, `passo` e `usuario_virtual`
são a chave do join entre os dois lados.

## Geração de carga

- **Jornadas** descritas em termos de negócio, independentes de interface:
  login, consultar conta, listar e detalhar transações, incluir transação,
  pagar fatura, atualizar conta e cartão, manutenção de usuários.
- **Dois drivers** para o mesmo roteiro: um 3270 (`s3270` ou `py3270`) para o
  emulador e um HTTP para o sistema novo.
- **Dados idênticos** no início de cada rodada (`python3 -m minicics load` de um
  lado, restauração do banco do outro).
- **Rodadas** com 1, 10, 50 e 100 usuários virtuais, com aquecimento descartado
  e pelo menos três repetições por nível.
- **Tempo de pensar** fixo e igual nos dois lados, para a carga ser a mesma.

## Como comparar

1. Rodar a mesma jornada, com a mesma semente e os mesmos dados, nos dois
   sistemas.
2. Juntar os registros por `jornada` + `passo`.
3. Comparar contagens diretamente (acessos, registros, bytes).
4. Comparar tempos como razão moderno / emulador, usando `total - spawn` no
   lado emulador, e como curva de latência por número de usuários.

Duas configurações de banco no lado emulador:

| Configuração | Banco do emulador | O que isola |
| --- | --- | --- |
| Ponta a ponta (resultado principal) | SQLite local, como hoje | efeito total da migração, incluindo a rede até o SQL Server |
| Controle | o mesmo SQL Server do sistema novo | diferença só da camada de aplicação |

## Limitações que afetam as medições

| Limitação do emulador | Efeito na medição | Tratamento |
| --- | --- | --- |
| Um processo `kixtask` por tarefa | infla a latência e limita a vazão | medir `spawn` e descontar; avaliar reaproveitar processos |
| `READ UPDATE` não bloqueia registro | sob concorrência o emulador parece melhor do que um CICS seria | implementar bloqueio antes das rodadas de 50+ usuários, ou restringir a conclusão a carga sem conflito |
| `SYNCPOINT` é no-op | sem custo de log nem de rollback | declarar no relatório |
| VSAM sobre SQLite, uma conexão por tarefa | E/S sem CI/CA split, buffers LSR ou string wait | usar contagens, não tempo de E/S, como base da comparação |
| Só os programas online | batch fica fora | escopo restrito ao online |
| Sem SMF, RMF ou MIPS | nenhuma métrica nativa de mainframe | o registro por interação substitui o SMF 110 |

## Referência a mainframe real

Dois caminhos sem custo para dar ordem de grandeza, ambos a confirmar:

- **Modelo analítico:** multiplicar as contagens de comandos pelo custo de CPU
  por comando publicado nos relatórios de performance do CICS da IBM.
  Apresentar como estimativa, não como medição.
- **Acesso acadêmico:** verificar se o IBM Z Academic Initiative ou o Z Xplore
  permitem rodar o CardDemo em uma região CICS. Poucas medições reais já
  calibrariam o modelo.

## Etapas

1. Instrumentar o mini-CICS e gravar o registro por interação.
2. Escrever as jornadas e o driver 3270.
3. Rodar a linha de base e validar as contagens contra o `--trace`.
4. Definir o mesmo esquema de registro no sistema moderno e o driver HTTP.
5. Rodar as duas configurações (ponta a ponta e controle) e gerar o comparativo.
6. Tratar bloqueio de registros, se as rodadas concorrentes forem entrar no
   resultado.

## Decisões em aberto

- Rodar os dois sistemas em qual classe de VM.
- Implementar bloqueio de registros ou limitar o escopo a carga sem conflito.
- Reaproveitar processos `kixtask` ou apenas descontar o `spawn`.
- Quais jornadas e qual mistura representam a carga "típica".
