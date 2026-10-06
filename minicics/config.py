"""Caminhos padrao do mini-CICS."""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD_DIR = os.path.join(ROOT, 'build')
DATA_DIR = os.path.join(ROOT, 'data')
CPY_DIR = os.path.join(ROOT, 'cpy')
RUNTIME_SRC = os.path.join(ROOT, 'runtime', 'kixtask.c')

SRC_DIR = os.path.join(BUILD_DIR, 'src')
LIB_DIR = os.path.join(BUILD_DIR, 'lib')
KIXTASK = os.path.join(BUILD_DIR, 'bin', 'kixtask')
MODULE_EXT = '.dylib' if sys.platform == 'darwin' else '.so'


def carddemo_app(path=None):
    """Diretorio app/ do CardDemo: argumento, $CARDDEMO_HOME ou repositorio vizinho."""
    home = path or os.environ.get('CARDDEMO_HOME') or os.path.join(
        os.path.dirname(ROOT), 'aws-mainframe-modernization-carddemo')
    app = os.path.join(home, 'app')
    if not os.path.isdir(os.path.join(app, 'cbl')):
        raise SystemExit('CardDemo nao encontrado em %s (use --carddemo ou $CARDDEMO_HOME)' % home)
    return app
