"""Build: compila os runtimes e os programas online e batch do CardDemo.

Os fontes vem de app/cbl e dos modulos opcionais (config.MODULES). Quem
tem EXEC CICS e online: o fonte traduzido vai para build/src e o modulo
para build/lib. Os demais sao batch: vao para build/batch, compilados com
-fcallfh=KIXFH. A saida do cobc fica em build/<programa>.err.
"""
import glob
import os
import re
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
    # Fora do macOS o executavel precisa exportar KIXCMD / KIXFH para os modulos.
    export = [] if sys.platform == 'darwin' else ['-rdynamic']
    for source, target in ((config.RUNTIME_SRC, config.KIXTASK),
                           (config.BATCH_SRC, config.KIXBATCH)):
        subprocess.check_call(['cc'] + _cob_config('--cflags') + ['-w'] + export
                              + ['-o', target, source] + _cob_config('--libs'))


def _sources(app):
    """{programa: caminho do fonte}, da aplicacao base e dos modulos opcionais."""
    found = {}
    for d in config.module_dirs(app, 'cbl'):
        for path in sorted(glob.glob(os.path.join(d, '*'))):
            if path.lower().endswith('.cbl'):
                found.setdefault(os.path.splitext(os.path.basename(path))[0].upper(), path)
    return found


def _includes(app):
    out = ['-I', config.BATCH_CPY_DIR, '-I', config.CPY_DIR]
    for sub in ('cpy', 'cpy-bms'):
        for d in config.module_dirs(app, sub):
            out += ['-I', d]
    return out


def _copybooks(app):
    """Copia para build/cpy os copybooks com TAB (um TAB vale uma coluna no host)."""
    os.makedirs(config.BATCH_CPY_DIR, exist_ok=True)
    for d in config.module_dirs(app, 'cpy'):
        for path in glob.glob(os.path.join(d, '*')):
            with open(path, encoding='latin-1') as f:
                text = f.read()
            if '\t' in text:
                with open(os.path.join(config.BATCH_CPY_DIR, os.path.basename(path)), 'w',
                          encoding='latin-1') as f:
                    f.write(text.replace('\t', ' '))


def _sql_include(app):
    """Busca de membros de EXEC SQL INCLUDE: DCLGEN, copybooks e a SQLCA."""
    def find(name):
        dirs = config.module_dirs(app, 'dcl') + [config.CPY_DIR] + config.module_dirs(app, 'cpy')
        for d in dirs:
            for path in glob.glob(os.path.join(d, '*')):
                if os.path.splitext(os.path.basename(path))[0].upper() == name:
                    with open(path, encoding='latin-1') as f:
                        return f.read().replace('\t', ' ')
        return None
    return find


def _batch_source(name, text):
    """Ajustes para o GnuCOBOL aceitar o fonte batch sem mudar o que ele faz."""
    if name in ('CBEXPORT', 'CBIMPORT'):
        # A chave do arquivo de exportacao (KEYS(4 28)) esta declarada fora
        # do registro do FD; o GnuCOBOL exige que ela faca parte dele.
        text = re.sub(r'(?m)^(\s+01\s+(EXPORT-(?:OUT|IN)PUT-RECORD)\s+)PIC X\(500\)\.',
                      lambda m: '%s.\n           05 FILLER PIC X(28).\n'
                                '           05 KIX-EXPORT-KEY PIC X(4).\n'
                                '           05 FILLER PIC X(468).' % m.group(1).rstrip(),
                      text)
        text = text.replace('RECORD KEY IS EXPORT-SEQUENCE-NUM', 'RECORD KEY IS KIX-EXPORT-KEY')
    if name == 'CBSTM03A':
        # O programa le a PSA no endereco 0 e faz aritmetica de ponteiro em
        # um binario de 4 bytes: troca pela PSA emulada (KIXPSA, kixbatch.c)
        # e por um binario do tamanho do ponteiro nativo.
        text = text.replace('01  BUMP-TIOT               PIC S9(08) BINARY VALUE ZERO.',
                            '01  BUMP-TIOT               PIC S9(18) COMP-5 VALUE ZERO.')
        text = text.replace('           SET ADDRESS OF PSA-BLOCK   TO PSAPTR.',
                            "           CALL 'KIXPSA' USING PSAPTR\n"
                            '           SET ADDRESS OF PSA-BLOCK   TO PSAPTR.')
    return text


def _compile(app, name, text, target_dir, extra):
    target = os.path.join(config.SRC_DIR, name + '.cbl')
    with open(target, 'w', encoding='latin-1') as f:
        f.write(text)
    # -fsign=EBCDIC: os dados do CardDemo trazem o sinal no formato do
    # mainframe ('{' = +0, '}' = -0) mesmo nos arquivos ASCII.
    cmd = (['cobc', '-m', '-std=ibm', '-fsign=EBCDIC', '-A', '-w'] + extra + _includes(app)
           + ['-o', os.path.join(target_dir, name + config.MODULE_EXT), target])
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    with open(os.path.join(config.BUILD_DIR, name + '.err'), 'wb') as f:
        f.write(proc.stdout)
    if proc.returncode:
        return 'cobc: veja build/%s.err' % name
    return None


def build_batch(app, name, source):
    """Compila um programa batch; devolve None ou a mensagem de erro."""
    with open(source, encoding='latin-1') as f:
        text = _batch_source(name, f.read().replace('\t', ' '))
    text = '\n'.join(line[:72] for line in text.splitlines()) + '\n'
    try:
        if re.search(r'EXEC\s+(SQL|DLI)', text):
            text = translate(text, cics=False, include=_sql_include(app))
    except TranslateError as e:
        return 'traducao: %s' % e
    return _compile(app, name, text, config.BATCH_DIR, ['-fcallfh=KIXFH'])


def build_program(app, name, source):
    """Traduz e compila um programa online; devolve None ou a mensagem de erro."""
    with open(source, encoding='latin-1') as f:
        try:
            text = translate(f.read(), include=_sql_include(app))
        except TranslateError as e:
            return 'traducao: %s' % e
    return _compile(app, name, text, config.LIB_DIR, [])


def main(carddemo=None, programs=None):
    app = config.carddemo_app(carddemo)
    for d in (config.SRC_DIR, config.LIB_DIR, config.BATCH_DIR):
        os.makedirs(d, exist_ok=True)
    print('kixtask, kixbatch')
    build_runtime()
    _copybooks(app)
    sources = _sources(app)
    online = set(SUBPROGRAMS)
    for name, path in sources.items():
        with open(path, encoding='latin-1') as f:
            if re.search(r'EXEC\s+CICS', f.read()):
                online.add(name)
    names = [n.upper() for n in programs] if programs else (
        sorted(online, key=lambda n: (n not in SUBPROGRAMS, n)) + sorted(set(sources) - online))
    failed = 0
    for name in names:
        if name not in sources:
            error = 'fonte nao encontrado'
        elif name in online:
            error = build_program(app, name, sources[name])
        else:
            error = build_batch(app, name, sources[name])
        print('%-8s %s %s' % (name, 'online' if name in online else 'batch ', error or 'ok'))
        failed += bool(error)
    if failed:
        raise SystemExit('%d programa(s) com erro' % failed)
