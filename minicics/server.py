"""Servidor TN3270 e regiao do mini-CICS.

Cada conexao e um terminal. A cada tecla de atencao o servidor decide a
transacao (a pendente de um RETURN TRANSID ou a digitada na tela), cria
uma Task e guarda o que ela pediu para a proxima interacao: e o ciclo
pseudo-conversacional do CICS.
"""
import datetime
import glob
import os
import re
import socketserver
import sys
import threading
import traceback

from . import bms, config, dli, ds3270, jcl, mq
from .cics import Task
from .vsam import Store

IAC, DONT, DO, WONT, WILL, SB, SE, EOR = 255, 254, 253, 252, 251, 250, 240, 239
OPT_BINARY, OPT_TTYPE, OPT_EOR = 0, 24, 25
WANTED = (OPT_BINARY, OPT_TTYPE, OPT_EOR)

_TRANSACTION = re.compile(r'DEFINE\s+TRANSACTION\((\w+)\).*?PROGRAM\((\w+)\)', re.S)
_FILE = re.compile(r'DEFINE\s+FILE\((\w+)\).*?DSNAME\(([\w.]+)\)', re.S)


class Region(object):
    def __init__(self, carddemo=None, data_dir=None, applid='MINICICS', sysid='KIX1',
                 start=None, trace=False):
        app = self.app = config.carddemo_app(carddemo)
        self.applid, self.sysid, self.start = applid, sysid, start
        self.alarm = True
        self.data_dir = data_dir or config.DATA_DIR
        self.store_path = os.path.join(self.data_dir, 'carddemo.db')
        self.log_path = os.path.join(self.data_dir, 'minicics.log')
        self.lib_dir, self.kixtask = config.LIB_DIR, config.KIXTASK
        self.tracing = trace
        self._lock = threading.Lock()
        self._task = self._term = 0

        if not os.path.exists(self.kixtask):
            raise SystemExit('build ausente: rode "python3 -m minicics build"')
        if not os.path.exists(self.store_path):
            raise SystemExit('dados ausentes: rode "python3 -m minicics load"')
        self.programs = set(
            os.path.splitext(os.path.basename(p))[0]
            for p in glob.glob(os.path.join(self.lib_dir, '*' + config.MODULE_EXT)))
        self.maps, csd = {}, ''
        for d in config.module_dirs(app, 'bms'):
            self.maps.update(bms.load_all(d))
        for d in config.module_dirs(app, 'csd'):
            for path in sorted(glob.glob(os.path.join(d, '*'))):
                with open(path, encoding='latin-1') as f:
                    csd += f.read() + '\n'
        self.transactions = dict(_TRANSACTION.findall(csd))
        self.files = dict(_FILE.findall(csd))       # arquivo CICS -> DSN do cluster / path
        self.triggers = dict(config.MQ_TRIGGERS)    # fila MQ -> transacao
        self.ims = dli.Definitions(config.module_dirs(app, 'ims'))  # DBDs e PSBs

    def next_task_number(self):
        with self._lock:
            self._task += 1
            return self._task

    def next_termid(self):
        with self._lock:
            self._term += 1
            return 'T%03d' % self._term

    def log(self, text):
        line = '%s %s' % (datetime.datetime.now().strftime('%H:%M:%S'), text)
        print(line, file=sys.stderr)
        with self._lock, open(self.log_path, 'a') as f:
            f.write(line + '\n')

    def submit(self, lines):
        """Leitor interno (TDQ JOBS): executa o job em segundo plano."""
        def run():
            try:
                job = jcl.submit('\n'.join(lines), self.data_dir, self.app, 'INTRDR')
                self.log('job %s: %s (%s)' % (job.name, job.status(), job.log_path))
            except Exception:
                self.log('job do leitor interno: %s' % traceback.format_exc().rstrip())
        threading.Thread(target=run, daemon=True).start()

    def trace(self, text):
        if self.tracing:
            self.log('  ' + text)


class NoTerminal(object):
    """Facilidade de uma tarefa sem terminal (iniciada por gatilho de fila)."""
    termid = ''

    def send(self, data):
        pass


class TriggerMonitor(threading.Thread):
    """Faz o papel do CKTI: inicia a transacao de uma fila que recebeu mensagens."""

    def __init__(self, region, interval=0.5):
        threading.Thread.__init__(self, daemon=True)
        self.region, self.interval = region, interval
        self.seen = {}                  # fila -> id da ultima mensagem ja disparada

    def run(self):
        store = Store(self.region.store_path)
        mq.prepare(store.db)
        while True:
            try:
                depths = mq.depths(store.db)
            except Exception:
                depths = {}
            for queue, transid in self.region.triggers.items():
                count, last = depths.get(queue, (0, 0))
                if count and last > self.seen.get(queue, 0):
                    self.seen[queue] = last
                    self.start_task(queue, transid)
            threading.Event().wait(self.interval)

    def start_task(self, queue, transid):
        region = self.region
        program = region.transactions.get(transid)
        if program not in region.programs:
            region.log('gatilho da fila %s: transacao %s desconhecida' % (queue, transid))
            return
        task = Task(region, NoTerminal(), transid, program, b'', ds3270.Inbound(b''),
                    mq.trigger_message(queue, transid))
        region.log('tarefa %d %s %s iniciada pela fila %s' % (task.number, transid, program, queue))
        try:
            task.run()
        except Exception:
            region.log('tarefa %d %s: %s' % (task.number, transid,
                                              traceback.format_exc().rstrip()))


class Terminal(socketserver.BaseRequestHandler):
    """Um terminal 3270 conectado por Telnet (TN3270 classico, RFC 1576)."""

    def setup(self):
        self.region = self.server.region
        self.termid = self.region.next_termid()
        self.next_transid, self.commarea = None, b''
        self.agreed = set()             # opcoes que o cliente aceitou (WILL)

    # --- telnet -----------------------------------------------------------
    def _raw(self, *codes):
        self.request.sendall(bytes(codes))

    def send(self, data):
        """Envia um registro 3270 (o fluxo de dados de uma tela)."""
        self.request.sendall(bytes(data).replace(b'\xff', b'\xff\xff') + bytes([IAC, EOR]))

    def _records(self):
        """Interpreta o Telnet e gera os registros 3270 recebidos.

        Gera None uma vez, quando a negociacao termina.
        """
        buf, record, ready = b'', bytearray(), False
        self._raw(IAC, DO, OPT_TTYPE)
        while True:
            chunk = self.request.recv(4096)
            if not chunk:
                return
            buf += chunk
            i = 0
            while i < len(buf):
                c = buf[i]
                if c != IAC:
                    record.append(c)
                    i += 1
                    continue
                if i + 1 >= len(buf):
                    break               # comando incompleto: espera mais dados
                cmd = buf[i + 1]
                if cmd == IAC:
                    record.append(IAC)
                    i += 2
                elif cmd == EOR:
                    i += 2
                    yield bytes(record)
                    record = bytearray()
                elif cmd in (DO, DONT, WILL, WONT):
                    if i + 2 >= len(buf):
                        break
                    self._negotiate(cmd, buf[i + 2])
                    i += 3
                elif cmd == SB:
                    end = buf.find(bytes([IAC, SE]), i)
                    if end < 0:
                        break
                    if buf[i + 2:i + 4] == bytes([OPT_TTYPE, 0]):
                        self._raw(IAC, DO, OPT_EOR, IAC, WILL, OPT_EOR,
                                  IAC, DO, OPT_BINARY, IAC, WILL, OPT_BINARY)
                    i = end + 2
                else:
                    i += 2
            buf = buf[i:]
            if not ready and self.agreed.issuperset(WANTED):
                ready = True
                record = bytearray()
                yield None

    def _negotiate(self, cmd, opt):
        if opt in WANTED:
            if cmd == WILL:
                self.agreed.add(opt)
                if opt == OPT_TTYPE:
                    self._raw(IAC, SB, OPT_TTYPE, 1, IAC, SE)
            elif cmd in (WONT, DONT):
                raise ConnectionError('o cliente nao e um terminal 3270')
        elif cmd == WILL:
            self._raw(IAC, DONT, opt)
        elif cmd == DO:
            self._raw(IAC, WONT, opt)

    # --- ciclo pseudo-conversacional --------------------------------------
    def handle(self):
        self.region.log('terminal %s conectado de %s' % (self.termid, self.client_address[0]))
        try:
            for record in self._records():
                if record is None:
                    self._connected()
                else:
                    self._attention(ds3270.Inbound(record))
        except (ConnectionError, OSError) as e:
            self.region.trace('terminal %s: %s' % (self.termid, e))
        self.region.log('terminal %s desconectado' % self.termid)

    def _connected(self):
        if self.region.start:
            self._run(self.region.start, ds3270.Inbound(b''))
        else:
            self.send(ds3270.message_screen(
                'mini-CICS %s: digite uma transacao (CC00 = CardDemo) e tecle ENTER'
                % self.region.applid, alarm=False))

    def _attention(self, inbound):
        transid = self.next_transid
        if not transid:
            if inbound.aid in ds3270.SHORT_READ_AIDS:
                self.send(ds3270.text_screen(''))
                return
            transid = inbound.text.decode('latin-1').strip()[:4].upper()
            if not transid:
                self.send(ds3270.write(b'', False))
                return
        self._run(transid, inbound)

    def _run(self, transid, inbound):
        program = self.region.transactions.get(transid)
        commarea, self.next_transid, self.commarea = self.commarea, None, b''
        if program not in self.region.programs:
            self.region.log('terminal %s: transacao %s desconhecida' % (self.termid, transid))
            self.send(ds3270.message_screen(
                "DFHAC2001 Transaction '%s' is not recognized." % transid))
            return
        task = Task(self.region, self, transid, program, commarea, inbound)
        self.region.log('tarefa %d %s %s no terminal %s'
                        % (task.number, transid, program, self.termid))
        try:
            task.run()
        except (ConnectionError, OSError):
            raise
        except Exception:               # erro do proprio mini-CICS
            self.region.log('tarefa %d %s: %s' % (task.number, transid,
                                                  traceback.format_exc().rstrip()))
            self.send(ds3270.message_screen(
                'DFHAC2206 Transaction %s failed with abend AKIX. Veja %s'
                % (transid, self.region.log_path)))
            return
        self.next_transid, self.commarea = task.next_transid, task.next_commarea
        if not task.sent:
            self.send(ds3270.write(b'', False))     # so libera o teclado


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main(host='127.0.0.1', port=3270, **options):
    region = Region(**options)
    server = Server((host, port), Terminal)
    server.region = region
    TriggerMonitor(region).start()
    region.log('regiao %s em %s:%d, %d programas, %d mapas, %d transacoes'
               % (region.applid, host, port, len(region.programs), len(region.maps),
                  len(region.transactions)))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        region.log('regiao encerrada')
    finally:
        server.server_close()
