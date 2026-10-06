"""Build: compila o kixtask e traduz/compila os programas online do CardDemo.

Para cada app/cbl/CO*.cbl grava o fonte traduzido em build/src, o modulo
em build/lib e a saida do cobc em build/<programa>.err.
"""
import glob
import os
import shlex
import subprocess
import sys

from . import config
from .translate import TranslateError, translate

# Chamados por CALL pelos programas online (validacao de datas).
SUBPROGRAMS = ['CSUTLDTC']


def _cob_config(flag):
    return shlex.split(subprocess.check_output(['cob-config', flag]).decode())


def build_runtime():
    os.makedirs(os.path.dirname(config.KIXTASK), exist_ok=True)
    # Fora do macOS o executavel precisa exportar KIXCMD para os modulos.
    export = [] if sys.platform == 'darwin' else ['-rdynamic']
    cmd = (['cc'] + _cob_config('--cflags') + ['-w'] + export
           + ['-o', config.KIXTASK, config.RUNTIME_SRC] + _cob_config('--libs'))
    subprocess.check_call(cmd)


def build_program(app, name):
    """Traduz e compila um programa; devolve None ou a mensagem de erro."""
    source = os.path.join(app, 'cbl', name + '.cbl')
    target = os.path.join(config.SRC_DIR, name + '.cbl')
    with open(source, encoding='latin-1') as f:
        try:
            text = translate(f.read())
        except TranslateError as e:
            return 'traducao: %s' % e
    with open(target, 'w', encoding='latin-1') as f:
        f.write(text)
    # -fsign=EBCDIC: os dados do CardDemo trazem o sinal no formato do
    # mainframe ('{' = +0, '}' = -0) mesmo nos arquivos ASCII.
    cmd = ['cobc', '-m', '-std=ibm', '-fsign=EBCDIC', '-A', '-w', '-I', config.CPY_DIR,
           '-I', os.path.join(app, 'cpy'), '-I', os.path.join(app, 'cpy-bms'),
           '-o', os.path.join(config.LIB_DIR, name + config.MODULE_EXT), target]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    with open(os.path.join(config.BUILD_DIR, name + '.err'), 'wb') as f:
        f.write(proc.stdout)
    if proc.returncode:
        return 'cobc: veja build/%s.err' % name
    return None


def main(carddemo=None, programs=None):
    app = config.carddemo_app(carddemo)
    for d in (config.SRC_DIR, config.LIB_DIR):
        os.makedirs(d, exist_ok=True)
    print('kixtask')
    build_runtime()
    names = programs or SUBPROGRAMS + sorted(
        os.path.splitext(os.path.basename(p))[0]
        for p in glob.glob(os.path.join(app, 'cbl', 'CO*.cbl')))
    failed = 0
    for name in names:
        error = build_program(app, name.upper())
        print('%-8s %s' % (name.upper(), error or 'ok'))
        failed += bool(error)
    if failed:
        raise SystemExit('%d programa(s) com erro' % failed)
