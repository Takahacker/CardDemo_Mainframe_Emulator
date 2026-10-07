# CardDemo Mainframe Emulator (mini-CICS)

Ambiente CICS/VSAM/3270/JCL mínimo para rodar o
[AWS CardDemo](https://github.com/aws-samples/aws-mainframe-modernization-carddemo)
(online, batch e os módulos opcionais com Db2, IMS DB e MQ) fora do mainframe,
com GnuCOBOL e Python. Os fontes COBOL originais não são
alterados: um tradutor troca cada `EXEC CICS ... END-EXEC` por uma chamada a um
runtime que implementa a semântica do comando.

Parte do Capstone *AI-enabled COBOL Mainframe Modernization*
(Insper × Missouri S&T × Apex Systems).

## Como rodar

Requisitos: GnuCOBOL 3.2 (`cobc`, `cob-config`), Python 3 (só biblioteca
padrão), um compilador C, um emulador 3270 (`c3270`, `x3270`, `wc3270`...) e o
repositório do CardDemo clonado ao lado deste
(`../aws-mainframe-modernization-carddemo`). Para outro local, use
`--carddemo <dir>` ou `$CARDDEMO_HOME`.

```sh
python3 -m minicics build            # compila os runtimes e os programas
python3 -m minicics load             # roda os jobs de carga do CardDemo em data/
python3 -m minicics run --start CC00 # sobe a região em 127.0.0.1:3270
python3 -m minicics submit INTCALC   # executa um job batch (JCL do CardDemo ou arquivo)
python3 -m minicics mq put FILA "texto" --reply-to RESPOSTA   # põe uma mensagem numa fila MQ
```

Em outro terminal:

```sh
c3270 127.0.0.1:3270
```

Usuários de exemplo: `ADMIN001` (administrador) e `USER0001` (usuário comum),
ambos com a senha `PASSWORD`. Sem `--start`, a tela abre vazia e a transação é
digitada como no CICS (`CC00` é o login). `--trace` registra cada comando
`EXEC CICS` em `data/minicics.log`; `--host` e `--port` mudam o endereço.

Para voltar aos dados originais, rode `load` de novo (ele apaga `data/`).

## Como funciona

```
 fonte CardDemo (.cbl)                         terminal 3270
        │                                            ▲
        ▼ minicics/translate.py                      │ fluxo 3270 (EBCDIC)
 build/src/*.cbl   (EXEC CICS → CALL "KIXCMD")       │
        │                                            │
        ▼ cobc -m                                    │
 build/lib/*.dylib ──carregado por──► kixtask ◄─pipe─► Task (minicics/cics.py)
                                   (1 processo         │        │
                                    por transação)     ▼        ▼
                                                   vsam.py   bms.py / ds3270.py
                                                   (SQLite)  (mapas e telas)
```

1. **Tradução** — `translate.py` faz o papel do tradutor CICS da IBM. Cada
   comando vira `CALL "KIXCMD" USING BY CONTENT "<spec>" <parâmetros>`, onde
   `<spec>` é `VERBO|OPCAO=|FLAG|...` (`=` marca as opções que consomem um
   parâmetro). Também resolve `DFHRESP(...)`, injeta `COPY DFHEIBLK` na
   `LINKAGE SECTION` e ajusta a `PROCEDURE DIVISION USING DFHEIBLK DFHCOMMAREA`.

   ```cobol
         *KIX  EXEC CICS SEND MAP('COSGN0A') MAPSET('COSGN00') FROM(COSGN0A
              CALL "KIXCMD" USING
                  BY CONTENT "SEND|MAP=|MAPSET=|FROM=|ERASE|CURSOR"
                  BY CONTENT 'COSGN0A'
                  BY CONTENT 'COSGN00'
                  BY REFERENCE COSGN0AO
              END-CALL
   ```

2. **Execução** — cada transação roda em um processo `kixtask` próprio. Ele
   carrega o programa com `cob_call`, e a cada `KIXCMD` serializa o comando e
   seus parâmetros para o lado Python por um par de pipes (`KIX_FD_IN` /
   `KIX_FD_OUT`).
3. **Semântica** — `Task` (em `cics.py`) despacha para o método `cmd_<verbo>` e
   responde com a ação (continuar, encerrar, `XCTL`, `LINK` ou desvio de `HANDLE`), o novo EIB e os valores
   a gravar de volta nos parâmetros do COBOL.
4. **Terminal** — `server.py` fala TN3270 clássico (Telnet com `TERMINAL-TYPE`,
   `EOR` e `BINARY`). Cada conexão é um terminal; a cada tecla de atenção o
   servidor escolhe a transação (a pendente de um `RETURN TRANSID` ou a
   digitada na tela), cria uma `Task` e guarda a commarea para a próxima
   interação. A tabela transação → programa vem do `CARDDEMO.CSD`.

Protocolo do pipe (inteiros big-endian):

```
Pedido  : u32 tam | spec\0 | u16 n | n × (u8 tipo, i64 valor, u32 tam, bytes)
Resposta: u32 tam | u8 ação | EIB[85] | u16 n | n × (u16 idx, u8 tipo, dado)
          ação 2 (XCTL) acrescenta: programa[8] | u32 calen | commarea
          ação 3 (desvio de HANDLE) acrescenta: u16 índice do parágrafo
          ação 4 (LINK) acrescenta: programa[8] | u16 parâmetro da commarea
```

## Batch

`python3 -m minicics submit <job>...` faz o papel do JES: lê o JCL (de
`app/jcl`, de um módulo ou de um arquivo), expande procedimentos e símbolos,
aloca os datasets de cada passo, executa e aplica as disposições. A saída de
cada job fica em `data/jobs/J<n>.<job>.log`.

```
 JCL ──► jcl.py ──► utilitário (utilities.py: IDCAMS, SORT, IEBGENER, IEFBR14, SDSF, IKJEFT01)
            │
            └──► kixbatch <programa> ──E/S indexada (KIXFH) e EXEC SQL──► batch.py ──► vsam.py / db2.py
                      └── E/S sequencial: libcob, pelo ambiente DD_<nome>
```

- **Programas** — os `CB*` são compilados com `-fcallfh=KIXFH`: toda E/S de
  arquivo passa por `KIXFH` (`runtime/kixbatch.c`). Arquivo indexado é cluster
  VSAM e é atendido pelo Python sobre o mesmo SQLite da região online; o resto
  vai para o libcob.
- **Datasets** — cluster VSAM é uma tabela do SQLite com o DSN como nome;
  sequencial é um arquivo de registros de tamanho fixo em `data/dsn/<DSN>`,
  com LRECL/RECFM no catálogo; geração de GDG é `<BASE>.GnnnnV00`, com
  `(+1)`, `(0)` e `LIMIT`.
- **JCL** — `JOB`, `EXEC PGM=` / `PROC=` (com `PARM` e `COND`), `DD` (`DSN`,
  `DISP`, `DCB`, `SYSOUT`, `DUMMY`, in-stream, concatenação, referência
  `*.dd`), `SET`, procedimentos em linha e catalogados com substituição de
  DDs (`//PASSO.DD`), membros de `PROC`, `CNTL` e `JCL`.
- **Leitor interno** — o JCL que o `CORPT00C` grava na fila TD `JOBS` é
  submetido ao terminar em `/*EOF`; o relatório sai em
  `AWS.M2.CARDDEMO.TRANREPT(+1)`.

Ciclo batch do CardDemo, depois do `load` (que já roda o `POSTTRAN`):

```sh
python3 -m minicics submit INTCALC TRANBKP COMBTRAN CREASTMT TRANIDX
```

## Db2

O módulo `app-transaction-type-db2` (opções 5 e 6 do menu admin, `COTRTLIC` /
`COTRTUPC`, e o batch `COBTUPDT`) roda sobre o mesmo SQLite. O tradutor faz o
papel do pré-compilador: expande `EXEC SQL INCLUDE`, guarda os cursores e troca
cada comando por `CALL "KIXCMD"` com a spec `SQL|tipo|cursor|assinatura|texto`,
a `SQLCA` e as variáveis host. `db2.py` executa, converte o dialeto (esquema
como prefixo, `CAST ... AS CHAR(n)`, `FETCH FIRST`) e devolve `SQLCODE`
(0, 100, -803, -532, -811...). As tabelas são criadas e carregadas pelo job
`CREADB21`, que o `load` roda.

## IMS DB

O módulo `app-authorization-ims-db2-mq` guarda as autorizações pendentes num
banco hierárquico (`DBPAUTP0`: resumo por conta → detalhes). `dli.py` lê os
DBDs e PSBs de `<módulo>/ims` e guarda cada segmento numa linha do SQLite
cuja chave é a chave concatenada do caminho, de modo que a ordem da chave é a
ordem hierárquica.

- **Online e BMP** — o tradutor troca `EXEC DLI` por `CALL "KIXCMD"` com a spec
  `DLI|função|DIB=|PCB=|SEGMENT:nome|WHERE:campo:op=|INTO=...` e injeta o
  bloco `DLZDIB` (`DIBSTAT` etc.). Funções: `SCHD`, `TERM`, `CHKP`, `GU`,
  `GN`, `GNP`, `ISRT`, `REPL`, `DLET`.
- **Batch** — `EXEC PGM=DFSRRC00,PARM='BMP|DLI,programa,PSB'` roda o programa
  com as máscaras dos PCBs (entrando por `DLITCBL`, se existir);
  `CALL 'CBLTDLI'` com SSAs qualificados ou não, e PCBs de GSAM gravando em
  sequenciais.
- O banco começa vazio: as autorizações entram pelo MQ (abaixo) ou pelo job
  `LOADPADB`.

## MQ

As filas ficam numa tabela do SQLite e são criadas ao primeiro uso. Os
programas chamam `MQOPEN`, `MQGET`, `MQPUT`, `MQPUT1` e `MQCLOSE`
(`runtime/kixtask.c` → `mq.py`); os copybooks `CMQ*` estão em `cpy/`. A região
faz o papel do monitor de gatilhos (CKTI): uma mensagem nova numa fila de
`config.MQ_TRIGGERS` inicia a transação, que lê a mensagem de gatilho com
`EXEC CICS RETRIEVE`.

| Fila de pedido | Transação | Programa | Resposta |
| --- | --- | --- | --- |
| `AWS.M2.CARDDEMO.PAUTH.REQUEST` | `CP00` | `COPAUA0C` (autorização) | a fila do `--reply-to` |
| `CARD.DEMO.REQUEST.ACCT` | `CDRA` | `COACCT01` (consulta de conta) | `CARD.DEMO.REPLY.ACCT` |
| `CARD.DEMO.REQUEST.DATE` | `CDRD` | `CODATE01` (data do sistema) | `CARD.DEMO.REPLY.DATE` |

`python3 -m minicics mq put|get|depth` faz o papel da aplicação do outro lado
da fila. Com a região no ar:

```sh
python3 -m minicics mq put AWS.M2.CARDDEMO.PAUTH.REQUEST \
  "261007,084501,0500024453765740,SALE,0328,0100,POS,000000,+000000010.51,5411,840,05,MERCH0000000001,LOJA,SAO PAULO,SP,01310000,TRX000000000001" \
  --reply-to AWS.M2.CARDDEMO.PAUTH.REPLY
python3 -m minicics mq get AWS.M2.CARDDEMO.PAUTH.REPLY --wait 5
python3 -m minicics mq put CARD.DEMO.REQUEST.ACCT "INQA00000000002"
```

A autorização gravada aparece na opção 11 do menu (conta `00000000050`), onde
PF5 marca fraude (`EXEC CICS LINK` para o `COPAUS2C`, que grava no Db2).

## Estrutura

| Caminho | Conteúdo |
| --- | --- |
| `minicics/translate.py` | Tradutor `EXEC CICS` / `EXEC SQL` → `CALL "KIXCMD"` e tabela de códigos `RESP` |
| `minicics/cics.py` | `Task`: ciclo de vida da tarefa, EIB e implementação dos comandos |
| `minicics/server.py` | Região (programas, mapas, transações, arquivos), servidor TN3270 e monitor de gatilhos MQ |
| `minicics/vsam.py` | Catálogo, KSDS e índices alternativos (paths) sobre SQLite |
| `minicics/datasets.py` | Catálogo de datasets: clusters, sequenciais e GDGs |
| `minicics/jcl.py` | Leitor e executor de JCL |
| `minicics/utilities.py` | IDCAMS, SORT, IEBGENER, IEFBR14, SDSF, IKJEFT01 (comandos DSN) e DFSRRC00 (região IMS) |
| `minicics/batch.py` | Passo batch: roda o programa e atende a E/S indexada e o SQL |
| `minicics/db2.py` | `EXEC SQL` sobre SQLite: cursores, dialeto, `SQLCA` |
| `minicics/dli.py` | IMS DB: DBDs, PSBs, `EXEC DLI` e `CBLTDLI` sobre SQLite |
| `minicics/mq.py` | Filas MQ, chamadas MQI e o cliente de linha de comando |
| `minicics/bms.py` | Leitor das macros `DFHMSD` / `DFHMDI` / `DFHMDF`; calcula o layout da área simbólica |
| `minicics/ds3270.py` | Montagem das telas 3270 e interpretação da leitura; conversão ASCII ↔ EBCDIC (cp037) |
| `minicics/build.py` | Build: compila os runtimes, traduz e compila os programas |
| `minicics/load.py` | Cataloga os dados de entrada e roda os jobs de carga |
| `minicics/config.py` | Caminhos padrão e módulos opcionais incluídos |
| `runtime/kixtask.c` | Processo da tarefa online: `KIXCMD`, ponte com o servidor, `LINK`, MQI, `CEEDAYS`, `DSNTIAC` |
| `runtime/kixbatch.c` | Processo do passo batch: `KIXFH`, `KIXCMD` (SQL e DL/I), `CBLTDLI`, PCBs, `CEE3ABD`, `COBDATFT`, `MVSWAIT`, TIOT emulada |
| `cpy/` | Copybooks do sistema: `DFHAID`, `DFHBMSCA`, `DFHEIBLK`, `DFHDIB`, `SQLCA`, `CMQ*` |
| `build/` | Artefatos gerados: `src/` (traduzido), `lib/` (online), `batch/`, `cpy/`, `bin/`, `*.err` (log do `cobc`) |
| `data/` | Gerado (fora do git): `carddemo.db`, `dsn/`, `jobs/`, `minicics.log`, `tdq_*.txt` |

## Comandos CICS suportados

| Grupo | Comandos |
| --- | --- |
| Controle de programa | `XCTL`, `LINK`, `RETRIEVE`, `RETURN` (com `TRANSID` / `COMMAREA`), `ABEND`, `INQUIRE PROGRAM`, `ASSIGN`, `HANDLE CONDITION`, `HANDLE ABEND` (`LABEL`, `CANCEL`), `IGNORE CONDITION`, `SYNCPOINT` (`ROLLBACK`) |
| Data e hora | `ASKTIME`, `FORMATTIME` |
| Terminal | `SEND MAP` (`MAPONLY`, `DATAONLY`, `ERASE`, `CURSOR`, `FREEKB`, `ALARM`), `SEND TEXT`, `RECEIVE MAP`, `RECEIVE` |
| Arquivos | `READ` (`GENERIC`, `GTEQ`), `WRITE`, `REWRITE`, `DELETE`, `UNLOCK`, `STARTBR`, `READNEXT`, `READPREV`, `ENDBR` |
| Filas | `WRITEQ` (grava em `tdq_<fila>.txt`) |

Limitações conhecidas:

- `HANDLE CONDITION` e `HANDLE ABEND LABEL` desviam com um
  `GO TO ... DEPENDING ON RETURN-CODE` que o tradutor emite após cada comando.
  A rotina de `HANDLE ABEND` só é chamada para abends gerados por um comando
  (condição não tratada, `EXEC CICS ABEND`); uma falha do próprio programa
  (`ASRA`) encerra a tarefa direto. `HANDLE ABEND PROGRAM` e `HANDLE AID` não
  existem.
- A unidade de trabalho é uma transação do SQLite: abre na primeira gravação
  ou `READ UPDATE`, fecha no `SYNCPOINT` ou no fim da tarefa, e é desfeita por
  `SYNCPOINT ROLLBACK` ou abend. Todos os arquivos se comportam como
  recuperáveis.
- O bloqueio do `READ UPDATE` é do banco inteiro, não do registro: enquanto
  uma tarefa tem a unidade de trabalho aberta, as outras que forem gravar
  esperam (até 30 s). Leituras não esperam.
- As filas TS (`READQ`, `DELETEQ`) e o `START` não existem; um verbo
  desconhecido abenda a tarefa com `AEY9`. O CardDemo não usa nenhum deles.
- Condição sem `RESP`, `NOHANDLE` nem `HANDLE` abenda com `AEI<x>`; saída anormal do
  processo vira `ASRA`. Em ambos os casos o terminal recebe a mensagem
  `DFHAC2206`.
- `CEEDAYS` aceita só máscaras com `YYYY`, `MM`, `DD` e separadores, que é o
  que o CardDemo usa.
- IMS: só bancos com um tipo de segmento por nível (o caso do CardDemo). O
  utilitário de descarga `DFSURGU0` (job `DBPAUTP0`) não existe, e o arquivo
  `IMSDATA.DBPAUTP0.dat`, que está no formato dele, não é importado. `DLET` /
  `REPL` valem para o segmento nomeado no caminho corrente, sem exigir o
  "get hold" anterior.
- MQ: um único gerente de filas, sem prioridade, expiração nem canais. `MQGET`
  com `WAIT` não espera: sem mensagem, devolve logo `MQRC-NO-MSG-AVAILABLE`.
  Os nomes das filas de pedido do `CDRA` / `CDRD` foram escolhidos aqui, porque
  o CardDemo não os fixa.
- A transação `CDV1` não existe no CardDemo.
- Batch: IDCAMS só define clusters KSDS (o job `ESDSRRDS` falha); `FTP`,
  `TXT2PDF` e `DFHCSDUP` não existem; os jobs `FTPJCL`, `TXT2PDF1`,
  `INTRDRJ1/2` e `CBADMCDJ` não rodam. O `TRANREPT.jcl` avulso precisa do
  dataset `AWS.M2.CARDDEMO.DATEPARM`, que nenhum job cria (pelo `CORPT00C` ele
  vem in-stream). `TYPRUN=SCAN` é ignorado.
- Alguns fontes batch são ajustados no build, sem mudar o que fazem: a chave do
  arquivo de `CBEXPORT` / `CBIMPORT` entra no registro do FD, e o `CBSTM03A`,
  que lê PSA → TCB → TIOT no endereço 0, recebe blocos de controle emulados.
- Db2: só o SQL que o CardDemo usa. Valores `CHAR` são comparados sem os
  brancos à direita; cursores não sobrevivem ao fim da tarefa.

## Programas

O build cobre `app/cbl` e os módulos de `config.MODULES`. Quem tem `EXEC CICS`
é online (`build/lib`); os demais são batch (`build/batch`).

Online: `COSGN00C` (login), `COMEN01C` e `COADM01C` (menus), `COACTVWC` /
`COACTUPC` (contas), `COCRDLIC` / `COCRDSLC` / `COCRDUPC` (cartões),
`COTRN00C` / `COTRN01C` / `COTRN02C` (transações), `COBIL00C` (pagamento),
`CORPT00C` (relatórios), `COUSR00C`–`COUSR03C` (usuários), `COTRTLIC` /
`COTRTUPC` (tipos de transação, Db2), `COPAUS0C` / `COPAUS1C` / `COPAUS2C`
(autorizações pendentes, IMS e Db2), `COPAUA0C`, `COACCT01` e `CODATE01`
(disparados por fila MQ) e o subprograma `CSUTLDTC`.

Batch: `CBTRN02C` (POSTTRAN), `CBACT04C` (INTCALC), `CBSTM03A` / `CBSTM03B`
(CREASTMT), `CBTRN03C` (TRANREPT), `CBTRN01C`, `CBACT01C`–`CBACT03C`,
`CBCUS01C`, `CBEXPORT`, `CBIMPORT`, `COBSWAIT`, `COBTUPDT` (Db2) e, do IMS,
`CBPAUP0C` (expurgo), `PAUDBLOD`, `PAUDBUNL` e `DBUNLDGS`.

## Build

`python3 -m minicics build` compila `runtime/kixtask.c` e `runtime/kixbatch.c`
e, para cada programa, grava o fonte traduzido em `build/src`, o módulo em
`build/lib` ou `build/batch` e a saída do `cobc` em `build/<programa>.err`. Para recompilar só alguns:
`python3 -m minicics build COSGN00C COMEN01C`.

Os programas são compilados com `-std=ibm -fsign=EBCDIC`: o CardDemo usa
construções do dialeto IBM, e os dados trazem o sinal dos campos numéricos no
formato do mainframe (`{` = +0, `}` = -0) mesmo nos arquivos ASCII.

Os binários versionados em `build/` são macOS arm64; em outra plataforma rode
o build (no Linux os módulos saem como `.so`, o que não foi testado).

Os mapas são lidos direto dos `.bms` originais pelo servidor, sem etapa de
montagem.

## VSAM sobre SQLite

Cada cluster é uma tabela `(k BLOB PRIMARY KEY, r BLOB)`; um path de índice
alternativo é um índice sobre `substr(r, offset, tamanho)` da mesma tabela. O
catálogo fica na tabela `kix_catalog`.

```python
from minicics.vsam import Store

store = Store('carddemo.db')
store.define_cluster('USRSEC', reclen=80, keyoff=0, keylen=8)   # o que o IDCAMS DEFINE faria
store.write('USRSEC', b'ADMIN001' + b'...')
store.seek('USRSEC', b'ADMIN001', '==')   # -> (chave, chave primária, registro)
```

`python3 -m minicics load` cataloga os sequenciais de entrada
(`AWS.M2.CARDDEMO.*.PS`, a partir de `app/data/ASCII`) e roda os jobs de
inicialização do README do CardDemo: `DUSRSECJ`, `ACCTFILE`, `CARDFILE`,
`CUSTFILE`, `XREFFILE`, `CREADB21`, `TRANFILE`, `DISCGRP`, `TCATBALF`,
`TRANCATG`, `TRANTYPE`, `DEFGDGB`, `DEFGDGD`, `DALYREJS`. São eles que definem
e carregam os clusters. Por fim roda o `POSTTRAN`, que lança as 300 transações
diárias no `TRANSACT` (38 são rejeitadas, em `DALYREJS(+1)`) e atualiza os
saldos; `--no-post` deixa o `TRANSACT` só com o registro inicial.

O nome CICS de cada arquivo vem do `DEFINE FILE ... DSNAME` do CSD:

| Arquivo CICS | Cluster / path (`AWS.M2.CARDDEMO.`) | Registro | Chave |
| --- | --- | --- | --- |
| `ACCTDAT` | `ACCTDATA.VSAM.KSDS` | 300 | 11 |
| `CARDDAT` | `CARDDATA.VSAM.KSDS` | 150 | 16 |
| `CARDAIX` | `CARDDATA.VSAM.AIX.PATH` | | 11, na posição 16 |
| `CCXREF` | `CARDXREF.VSAM.KSDS` | 50 | 16 |
| `CXACAIX` | `CARDXREF.VSAM.AIX.PATH` | | 11, na posição 25 |
| `CUSTDAT` | `CUSTDATA.VSAM.KSDS` | 500 | 9 |
| `TRANSACT` | `TRANSACT.VSAM.KSDS` | 350 | 16 |
| `USRSEC` | `USRSEC.VSAM.KSDS` | 80 | 8 |
