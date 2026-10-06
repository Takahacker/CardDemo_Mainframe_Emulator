"""Carga inicial: define os clusters VSAM e carrega os dados do CardDemo.

Equivale aos jobs ACCTFILE, CARDFILE, XREFFILE, CUSTFILE, TRANFILE e
DUSRSECJ (IDCAMS DEFINE + REPRO). Os nomes sao os do CSD (DEFINE FILE).
"""
import os

from . import config
from .vsam import Duplicate, Store

# nome CICS, tamanho do registro, posicao da chave, tamanho da chave, origem
CLUSTERS = [
    ('ACCTDAT', 300, 0, 11, 'acctdata.txt'),
    ('CARDDAT', 150, 0, 16, 'carddata.txt'),
    ('CCXREF', 50, 0, 16, 'cardxref.txt'),
    ('CUSTDAT', 500, 0, 9, 'custdata.txt'),
    ('TRANSACT', 350, 0, 16, 'dailytran.txt'),
    ('USRSEC', 80, 0, 8, None),         # em linha no DUSRSECJ.jcl
]
# caminho de indice alternativo, cluster base, posicao da chave, tamanho
PATHS = [
    ('CARDAIX', 'CARDDAT', 16, 11),
    ('CXACAIX', 'CCXREF', 25, 11),
]


def _lines(path):
    with open(path, 'rb') as f:
        return [l for l in f.read().replace(b'\r', b'').split(b'\n') if l.strip()]


def _instream(path, ddname='SYSUT1'):
    """Registros de um 'DD *' de um JCL."""
    out, inside = [], False
    for line in _lines(path):
        if inside:
            if line.startswith(b'/*') or line.startswith(b'//'):
                break
            out.append(line[:80])
        elif line.startswith(b'//' + ddname.encode()) and b' DD ' in line and b'*' in line[11:]:
            inside = True
    return out


def main(carddemo=None, data_dir=None):
    app = config.carddemo_app(carddemo)
    data_dir = data_dir or config.DATA_DIR
    os.makedirs(data_dir, exist_ok=True)
    store = Store(os.path.join(data_dir, 'carddemo.db'))
    for name, reclen, keyoff, keylen, source in CLUSTERS:
        if source:
            records = _lines(os.path.join(app, 'data', 'ASCII', source))
        else:
            records = _instream(os.path.join(app, 'jcl', 'DUSRSECJ.jcl'))
        store.define_cluster(name, reclen, keyoff, keylen)
        store.db.execute('BEGIN')
        dups = 0
        for record in records:
            try:
                store.write(name, record.ljust(reclen))
            except Duplicate:
                dups += 1
        store.db.execute('COMMIT')
        print('%-8s %4d registros%s' % (name, store.count(name),
                                        ', %d chaves duplicadas ignoradas' % dups if dups else ''))
    for name, base, keyoff, keylen in PATHS:
        store.define_path(name, base, keyoff, keylen)
        print('%-8s caminho de %s' % (name, base))
    store.close()
