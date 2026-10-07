"""Caminhos padrao do mini-CICS."""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD_DIR = os.path.join(ROOT, 'build')
DATA_DIR = os.path.join(ROOT, 'data')
CPY_DIR = os.path.join(ROOT, 'cpy')
RUNTIME_SRC = os.path.join(ROOT, 'runtime', 'kixtask.c')
BATCH_SRC = os.path.join(ROOT, 'runtime', 'kixbatch.c')

SRC_DIR = os.path.join(BUILD_DIR, 'src')
LIB_DIR = os.path.join(BUILD_DIR, 'lib')
BATCH_DIR = os.path.join(BUILD_DIR, 'batch')         # modulos dos programas batch
BATCH_CPY_DIR = os.path.join(BUILD_DIR, 'cpy')
KIXTASK = os.path.join(BUILD_DIR, 'bin', 'kixtask')
KIXBATCH = os.path.join(BUILD_DIR, 'bin', 'kixbatch')
MODULE_EXT = '.dylib' if sys.platform == 'darwin' else '.so'


# Modulos opcionais do CardDemo (subdiretorios de app/) incluidos no build
MODULES = ['app-transaction-type-db2', 'app-authorization-ims-db2-mq', 'app-vsam-mq']

# Filas MQ com gatilho: uma mensagem nova inicia a transacao (como o CKTI).
# As dos programas CDRA / CDRD nao tem nome fixado pelo CardDemo.
MQ_TRIGGERS = {
    'AWS.M2.CARDDEMO.PAUTH.REQUEST': 'CP00',
    'CARD.DEMO.REQUEST.ACCT': 'CDRA',
    'CARD.DEMO.REQUEST.DATE': 'CDRD',
}


def module_dirs(app, sub):
    """Diretorios `sub` (cbl, bms, jcl...) da aplicacao base e dos modulos."""
    dirs = [os.path.join(app, sub)] + [os.path.join(app, m, sub) for m in MODULES]
    return [d for d in dirs if os.path.isdir(d)]


def carddemo_app(path=None):
    """Diretorio app/ do CardDemo: argumento, $CARDDEMO_HOME ou repositorio vizinho."""
    home = path or os.environ.get('CARDDEMO_HOME') or os.path.join(
        os.path.dirname(ROOT), 'aws-mainframe-modernization-carddemo')
    app = os.path.join(home, 'app')
    if not os.path.isdir(os.path.join(app, 'cbl')):
        raise SystemExit('CardDemo nao encontrado em %s (use --carddemo ou $CARDDEMO_HOME)' % home)
    return app
