# CardDemo Mainframe Emulator (mini-CICS)

Ambiente CICS/VSAM/3270 mínimo para rodar os programas online do
[AWS CardDemo](https://github.com/aws-samples/aws-mainframe-modernization-carddemo)
fora do mainframe, com GnuCOBOL e Python. Os fontes COBOL originais não são
alterados: um tradutor troca cada `EXEC CICS ... END-EXEC` por uma chamada a um
runtime que implementa a semântica do comando.

Parte do Capstone *AI-enabled COBOL Mainframe Modernization*
(Insper × Missouri S&T × Apex Systems).

> **Estado atual:** o repositório contém o tradutor, o runtime da tarefa, a
> implementação dos comandos CICS, o VSAM sobre SQLite, o leitor de BMS e o
> fluxo de dados 3270. **Ainda não estão versionados** o servidor
> (`minicics/server.py`, citado em `runtime/kixtask.c`, que define a região e
> atende os terminais TN3270), o script de build e a carga dos arquivos VSAM.
> Sem eles não dá para abrir uma sessão de terminal ponta a ponta.

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
| `minicics/vsam.py` | Catálogo, KSDS e índices alternativos (paths) sobre SQLite |
| `minicics/bms.py` | Leitor das macros `DFHMSD` / `DFHMDI` / `DFHMDF`; calcula o layout da área simbólica |
| `minicics/ds3270.py` | Montagem das telas 3270 e interpretação da leitura; conversão ASCII ↔ EBCDIC (cp037) |
| `runtime/kixtask.c` | Processo da tarefa: ponto de entrada `KIXCMD` e ponte com o servidor |
| `cpy/` | Copybooks do sistema: `DFHAID`, `DFHBMSCA`, `DFHEIBLK` |
| `build/` | Artefatos gerados: `src/` (traduzido), `lib/` (módulos), `bin/kixtask`, `*.err` (log do `cobc`) |

## Comandos CICS suportados

| Grupo | Comandos |
| --- | --- |
| Controle de programa | `XCTL`, `RETURN` (com `TRANSID` / `COMMAREA`), `ABEND`, `INQUIRE PROGRAM`, `ASSIGN` |
| Data e hora | `ASKTIME`, `FORMATTIME` |
| Terminal | `SEND MAP` (`MAPONLY`, `DATAONLY`, `ERASE`, `CURSOR`, `FREEKB`, `ALARM`), `SEND TEXT`, `RECEIVE MAP`, `RECEIVE` |
| Arquivos | `READ` (`GENERIC`, `GTEQ`), `WRITE`, `REWRITE`, `DELETE`, `UNLOCK`, `STARTBR`, `READNEXT`, `READPREV`, `ENDBR` |
| Filas | `WRITEQ` (grava em `tdq_<fila>.txt`) |

Limitações conhecidas:

- `HANDLE`, `IGNORE` e `SYNCPOINT` são aceitos mas não fazem nada.
- `DELETE` sem `RIDFLD` não está implementado (abend `AEY9`).
- `LINK` e as filas TS (`READQ`, `DELETEQ`) não existem; um verbo desconhecido
  abenda a tarefa com `AEY9`.
- Condição sem `RESP` / `NOHANDLE` abenda com `AEI<x>`; saída anormal do
  processo vira `ASRA`. Em ambos os casos o terminal recebe a mensagem
  `DFHAC2206`.

## Programas

Os 18 programas online do CardDemo estão traduzidos e compilados em `build/`:

`COSGN00C` (login), `COMEN01C` e `COADM01C` (menus), `COACTVWC` / `COACTUPC`
(contas), `COCRDLIC` / `COCRDSLC` / `COCRDUPC` (cartões), `COTRN00C` /
`COTRN01C` / `COTRN02C` (transações), `COBIL00C` (pagamento), `CORPT00C`
(relatórios), `COUSR00C`–`COUSR03C` (usuários) e `COBSWAIT`.

Todos compilam sem erros; os `.err` registram apenas avisos de dialeto do
`cobc` e do linker.

## Build

Requisitos: GnuCOBOL 3.2 (`cobc`, `cob-config`), Python 3 (só biblioteca
padrão), um compilador C e o repositório do CardDemo clonado ao lado deste
(`../aws-mainframe-modernization-carddemo`).

Os binários em `build/` são macOS arm64. Em outra plataforma, gere de novo:

```sh
CARDDEMO=../aws-mainframe-modernization-carddemo/app

# 1. runtime da tarefa
cc $(cob-config --cflags) -o build/bin/kixtask runtime/kixtask.c $(cob-config --libs)

# 2. traduzir e compilar um programa
python3 - <<'EOF'
from minicics.translate import translate
src = open('../aws-mainframe-modernization-carddemo/app/cbl/COSGN00C.cbl', encoding='latin-1').read()
open('build/src/COSGN00C.cbl', 'w', encoding='latin-1').write(translate(src))
EOF
cobc -m -I cpy -I $CARDDEMO/cpy -I $CARDDEMO/cpy-bms \
     -o build/lib/COSGN00C.dylib build/src/COSGN00C.cbl
```

No Linux a extensão do módulo é `.so`. O `kixtask` não roda sozinho: ele espera
ser iniciado pelo servidor, com `KIX_FD_IN`, `KIX_FD_OUT` e
`COB_LIBRARY_PATH` apontando para `build/lib`.

Os mapas são lidos direto dos `.bms` originais, sem etapa de montagem:

```python
from minicics import bms
maps = bms.load_all('../aws-mainframe-modernization-carddemo/app/bms')  # {(mapset, mapa): Map}
```

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

Os programas rodam em ASCII, então os registros devem ser carregados a partir
de `app/data/ASCII` do CardDemo.
