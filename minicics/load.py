"""Carga inicial: roda os jobs de inicializacao do CardDemo.

Os sequenciais de entrada (AWS.M2.CARDDEMO.*.PS) sao catalogados a partir
de app/data/ASCII; a definicao e a carga dos clusters VSAM ficam por conta
dos proprios JCLs (IDCAMS DEFINE + REPRO), na ordem do README do CardDemo.
Por fim o POSTTRAN lanca as transacoes diarias, como no primeiro ciclo
batch: e ele que popula o TRANSACT e atualiza os saldos.
"""
import os
import shutil

from . import config, db2, jcl
from .datasets import Catalog

HLQ = 'AWS.M2.CARDDEMO.'
# sequencial de entrada, tamanho do registro, arquivo em app/data/ASCII
SEEDS = [
    ('ACCTDATA.PS', 300, 'acctdata.txt'),
    ('CARDDATA.PS', 150, 'carddata.txt'),
    ('CARDXREF.PS', 50, 'cardxref.txt'),
    ('CUSTDATA.PS', 500, 'custdata.txt'),
    ('DALYTRAN.PS', 350, 'dailytran.txt'),
    ('DISCGRP.PS', 50, 'discgrp.txt'),
    ('TCATBALF.PS', 50, 'tcatbal.txt'),
    ('TRANCATG.PS', 60, 'trancatg.txt'),
    ('TRANTYPE.PS', 60, 'trantype.txt'),
]
# "Initialize the Environment" do README, mais o GDG dos rejeitados
# (CREADB21 cria e carrega as tabelas Db2 do modulo de tipos de transacao)
INIT_JOBS = ['DUSRSECJ', 'CLOSEFIL', 'ACCTFILE', 'CARDFILE', 'CUSTFILE', 'XREFFILE',
             'CREADB21', 'TRANFILE', 'DISCGRP', 'TCATBALF', 'TRANCATG', 'TRANTYPE',
             'OPENFIL', 'DEFGDGB', 'DEFGDGD', 'DALYREJS']
POST_JOBS = ['POSTTRAN']


def _lines(path):
    with open(path, 'rb') as f:
        return [l for l in f.read().replace(b'\r', b'').split(b'\n') if l.strip()]


def seed(catalog, app):
    for name, lrecl, source in SEEDS:
        catalog.write(HLQ + name, _lines(os.path.join(app, 'data', 'ASCII', source)), lrecl)
    # Registro inicial do TRANSACT: so existe em EBCDIC (um registro em branco).
    with open(os.path.join(app, 'data', 'EBCDIC', HLQ + 'DALYTRAN.PS.INIT'), 'rb') as f:
        catalog.write(HLQ + 'DALYTRAN.PS.INIT', [f.read().decode('cp037').encode('latin-1')], 350)


def main(carddemo=None, data_dir=None, post=True):
    app = config.carddemo_app(carddemo)
    data_dir = data_dir or config.DATA_DIR
    os.makedirs(data_dir, exist_ok=True)
    for name in ('carddemo.db', 'dsn', 'jobs'):     # recomeca do zero
        path = os.path.join(data_dir, name)
        if os.path.isdir(path):
            shutil.rmtree(path)
        elif os.path.exists(path):
            os.remove(path)
    catalog = Catalog(data_dir)
    seed(catalog, app)
    failed = 0
    for name in INIT_JOBS + (POST_JOBS if post else []):
        with open(jcl.find_job(app, name), encoding='latin-1') as f:
            job = jcl.submit(f.read(), data_dir, app, name, catalog)
        print('%-8s %s' % (name, job.status()))
        if not job.ok():
            failed += 1
            for step, program, result in job.results:
                print('  %-8s %-8s %s' % (step, program, result))
            print('  log: %s' % job.log_path)
    # Tabelas Db2 dos modulos que nao tem job de criacao (AUTHFRDS)
    db2.prepare(catalog.store.db)
    for d in config.module_dirs(app, 'ddl'):
        for path in sorted(p for p in os.listdir(d) if 'TRN' not in p.upper()):
            with open(os.path.join(d, path), encoding='latin-1') as f:
                db2.run_script(catalog.store.db, f.read().splitlines(), lambda text: None)
    print()
    for name in catalog.store.names():
        path = catalog.store.path(name)
        print('%-44s %s' % (name, '%5d registros' % catalog.store.count(name)
                            if path.primary else 'caminho de ' + path.base[len(HLQ):]))
    catalog.close()
    if failed:
        raise SystemExit('%d job(s) de carga com erro' % failed)
