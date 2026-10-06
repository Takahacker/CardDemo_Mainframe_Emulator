# CardDemo Mainframe Emulator (mini-CICS)

Ambiente CICS/VSAM/3270 mínimo para rodar os programas online do
[AWS CardDemo](https://github.com/aws-samples/aws-mainframe-modernization-carddemo)
fora do mainframe, com GnuCOBOL e Python. Os fontes COBOL originais não são
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
python3 -m minicics build            # compila o kixtask e os programas
python3 -m minicics load             # cria data/carddemo.db com os dados do CardDemo
python3 -m minicics run --start CC00 # sobe a região em 127.0.0.1:3270
```

Em outro terminal:

```sh
c3270 127.0.0.1:3270
```

Usuários de exemplo: `ADMIN001` (administrador) e `USER0001` (usuário comum),
ambos com a senha `PASSWORD`. Sem `--start`, a tela abre vazia e a transação é
digitada como no CICS (`CC00` é o login). `--trace` registra cada comando
`EXEC CICS` em `data/minicics.log`; `--host` e `--port` mudam o endereço.

Para voltar aos dados originais, rode `load` de novo.

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
   responde com a ação (continuar, encerrar ou `XCTL`), o novo EIB e os valores
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
```

## Estrutura

| Caminho | Conteúdo |
| --- | --- |
| `minicics/translate.py` | Tradutor `EXEC CICS` → `CALL "KIXCMD"` e tabela de códigos `RESP` |
| `minicics/cics.py` | `Task`: ciclo de vida da tarefa, EIB e implementação dos comandos |
| `minicics/server.py` | Região (programas, mapas, transações) e servidor TN3270 |
| `minicics/vsam.py` | Catálogo, KSDS e índices alternativos (paths) sobre SQLite |
| `minicics/bms.py` | Leitor das macros `DFHMSD` / `DFHMDI` / `DFHMDF`; calcula o layout da área simbólica |
| `minicics/ds3270.py` | Montagem das telas 3270 e interpretação da leitura; conversão ASCII ↔ EBCDIC (cp037) |
| `minicics/build.py` | Build: compila o `kixtask`, traduz e compila os programas |
| `minicics/load.py` | Define os clusters e paths e carrega os dados do CardDemo |
| `minicics/config.py` | Caminhos padrão |
| `runtime/kixtask.c` | Processo da tarefa: ponto de entrada `KIXCMD`, ponte com o servidor e `CEEDAYS` |
| `cpy/` | Copybooks do sistema: `DFHAID`, `DFHBMSCA`, `DFHEIBLK` |
| `build/` | Artefatos gerados: `src/` (traduzido), `lib/` (módulos), `bin/kixtask`, `*.err` (log do `cobc`) |
| `data/` | Gerado pelo `load` e pelo servidor (fora do git): `carddemo.db`, `minicics.log`, `tdq_*.txt` |

## Comandos CICS suportados

| Grupo | Comandos |
| --- | --- |
| Controle de programa | `XCTL`, `RETURN` (com `TRANSID` / `COMMAREA`), `ABEND`, `INQUIRE PROGRAM`, `ASSIGN` |
| Data e hora | `ASKTIME`, `FORMATTIME` |
| Terminal | `SEND MAP` (`MAPONLY`, `DATAONLY`, `ERASE`, `CURSOR`, `FREEKB`, `ALARM`), `SEND TEXT`, `RECEIVE MAP`, `RECEIVE` |
| Arquivos | `READ` (`GENERIC`, `GTEQ`), `WRITE`, `REWRITE`, `DELETE`, `UNLOCK`, `STARTBR`, `READNEXT`, `READPREV`, `ENDBR` |
| Filas | `WRITEQ` (grava em `tdq_<fila>.txt`) |

Limitações conhecidas:

- `HANDLE`, `IGNORE` e `SYNCPOINT` são aceitos mas não fazem nada: a rotina de
  `HANDLE ABEND` nunca é chamada e `SYNCPOINT ROLLBACK` não desfaz gravações.
- Não há bloqueio de registros: `READ UPDATE` só memoriza o registro para o
  `REWRITE` / `DELETE` seguinte.
- `LINK` e as filas TS (`READQ`, `DELETEQ`) não existem; um verbo desconhecido
  abenda a tarefa com `AEY9`. O CardDemo online não usa nenhum deles.
- Condição sem `RESP` / `NOHANDLE` abenda com `AEI<x>`; saída anormal do
  processo vira `ASRA`. Em ambos os casos o terminal recebe a mensagem
  `DFHAC2206`.
- `CEEDAYS` aceita só máscaras com `YYYY`, `MM`, `DD` e separadores, que é o
  que o CardDemo usa.
- As opções 05, 06 (Db2) e 11 (IMS) dos menus e a transação `CDV1` apontam para
  programas que não fazem parte deste build.
- O relatório (`CORPT00C`) grava o JCL em `data/tdq_JOBS.txt`; não há quem o
  execute.

## Programas

Os 18 programas `CO*` do CardDemo, mais o subprograma `CSUTLDTC` (validação de
datas), são traduzidos e compilados em `build/`:

`COSGN00C` (login), `COMEN01C` e `COADM01C` (menus), `COACTVWC` / `COACTUPC`
(contas), `COCRDLIC` / `COCRDSLC` / `COCRDUPC` (cartões), `COTRN00C` /
`COTRN01C` / `COTRN02C` (transações), `COBIL00C` (pagamento), `CORPT00C`
(relatórios), `COUSR00C`–`COUSR03C` (usuários) e `COBSWAIT`.

## Build

`python3 -m minicics build` compila `runtime/kixtask.c` e, para cada programa,
grava o fonte traduzido em `build/src`, o módulo em `build/lib` e a saída do
`cobc` em `build/<programa>.err`. Para recompilar só alguns:
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

`python3 -m minicics load` faz o papel dos jobs de carga do CardDemo:

| Arquivo CICS | Registro | Chave | Origem |
| --- | --- | --- | --- |
| `ACCTDAT` | 300 | 11 | `data/ASCII/acctdata.txt` |
| `CARDDAT` | 150 | 16 | `data/ASCII/carddata.txt` |
| `CCXREF` | 50 | 16 | `data/ASCII/cardxref.txt` |
| `CUSTDAT` | 500 | 9 | `data/ASCII/custdata.txt` |
| `TRANSACT` | 350 | 16 | `data/ASCII/dailytran.txt` |
| `USRSEC` | 80 | 8 | registros em linha no `jcl/DUSRSECJ.jcl` |
| `CARDAIX` | path de `CARDDAT` | 11, na posição 16 | |
| `CXACAIX` | path de `CCXREF` | 11, na posição 25 | |
