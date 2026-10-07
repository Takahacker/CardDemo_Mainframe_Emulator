"""Um passo batch: executa um programa COBOL e atende sua E/S indexada.

O programa roda no processo kixbatch (runtime/kixbatch.c). Arquivos
sequenciais sao abertos pelo proprio libcob, pelo ambiente DD_<nome>; cada
operacao em arquivo indexado chega aqui pelo pipe e e atendida sobre o
mesmo vsam.Store da regiao online.
"""
import os
import struct
import subprocess

from . import db2, dli
from .cics import pack_update, unpack_request
from .vsam import Duplicate, NotFound, Path

OPEN_OPS = {0xFA00: 'INPUT', 0xFA01: 'OUTPUT', 0xFA02: 'I-O', 0xFA03: 'EXTEND',
            0xFA04: 'INPUT', 0xFA05: 'OUTPUT', 0xFA08: 'INPUT'}
CLOSE_OPS = set(range(0xFA80, 0xFA87))
READ_NEXT_OPS = {0xFAF5, 0xFA8D, 0xFAD8, 0xFAD9}
READ_PREV_OPS = {0xFAF9, 0xFA8C, 0xFADE, 0xFADF}
READ_KEY_OPS = {0xFAF6, 0xFA8E, 0xFADA, 0xFADB}
START_OPS = {0xFAE8: '==', 0xFAE9: '==', 0xFAEA: '>', 0xFAEB: '>=', 0xFAFE: '<', 0xFAFF: '<='}
OP_WRITE, OP_REWRITE, OP_DELETE = 0xFAF3, 0xFAF4, 0xFAF7

ABEND_EXIT = 134                        # codigo de saida do CEE3ABD (kixbatch.c)


class OpenFile(object):
    """Um arquivo indexado aberto pelo programa."""

    def __init__(self, store, dsn, mode):
        self.store, self.dsn, self.mode = store, dsn, mode
        self.base = store.path(store.path(dsn).base)
        self.path = self.base           # caminho da chave de referencia
        self.pos = None                 # (chave, chave primaria) do ultimo registro lido
        self.pending = None             # linha posicionada pelo START, ainda nao lida

    def use_key(self, pos, length):
        if (pos, length) == (self.base.keyoff, self.base.keylen):
            path = self.base
        else:
            path = Path(self.dsn, self.base.name, self.base.reclen, pos, length, False)
        if (path.keyoff, path.primary) != (self.path.keyoff, self.path.primary):
            self.pos = self.pending = None
        self.path = path

    def start(self, key, op):
        row = self.store.seek(self.path, key, '>=' if op == '==' else op)
        if row and op == '==' and not row[0].startswith(key):
            row = None
        self.pending, self.pos = row, None
        return row

    def step(self, forward):
        if self.pending:
            row, self.pending = self.pending, None
        elif self.pos is None:
            row = self.store.seek(self.path, b'' if forward else b'\xff' * self.path.keylen,
                                  '>=' if forward else '<=')
        else:
            row = self.store.seek(self.path, self.pos[0], '>' if forward else '<', self.pos[1])
        if row:
            self.pos = row[:2]
        return row

    def read(self, key):
        row = self.store.seek(self.path, key, '==')
        if row:
            self.pos, self.pending = row[:2], None
        return row


class FileServer(object):
    """Atende os pedidos do KIXFH de um passo."""

    def __init__(self, store, dds, log, ims=None):
        self.store, self.dds, self.log = store, dds, log
        self.files = {}
        self.sql = None
        self.ims = ims                  # dli.Session da regiao IMS, se houver

    def serve_command(self, payload):
        """EXEC SQL, EXEC DLI ou CALL 'CBLTDLI' (pedido no formato do KIXCMD)."""
        spec, values = unpack_request(payload)
        if spec.startswith('SQL|'):
            if self.sql is None:
                self.sql = db2.Session()
                db2.prepare(self.store.db)
            updates = self.sql.execute(self.store.db, self.store.begin, spec, values)
        elif self.ims is None:
            self.log('KIXCMD: %s fora de uma regiao IMS (EXEC PGM=DFSRRC00)' % spec[:20])
            updates = []
        elif spec == 'DLICALL':
            for p in values:            # sem a spec, os indices comecam em 1
                p.idx -= 1
            updates = self.ims.call_dli(values)[1]
        else:
            updates = self.ims.exec_dli(spec, values)[1]
        return struct.pack('>H', len(updates)) + b''.join(pack_update(p, v) for p, v in updates)

    def serve(self, payload):
        if payload[:2] == b'\x00\x00':
            return self.serve_command(payload[2:])
        op, handle, mode, refkey, namelen = struct.unpack_from('>HQBHH', payload, 0)
        pos = 15
        name = payload[pos:pos + namelen].decode('latin-1').strip().upper()
        pos += namelen
        (nkeys,) = struct.unpack_from('>H', payload, pos)
        keys = [struct.unpack_from('>II', payload, pos + 2 + 8 * i) for i in range(nkeys)]
        pos += 2 + 8 * nkeys
        maxlen, curlen = struct.unpack_from('>II', payload, pos)
        record = payload[pos + 8:pos + 8 + maxlen]
        status, out = self._do(op, handle, name, keys, refkey, record, curlen or maxlen)
        out = out[:maxlen] if out else b''
        return status.encode() + struct.pack('>I', len(out)) + out

    def _do(self, op, handle, name, keys, refkey, record, curlen):
        if op in OPEN_OPS:
            dsn = self.dds.get(os.path.basename(name))
            if dsn is None:
                self.log('KIXFH: DD %s ausente ou nao e um cluster VSAM' % name)
                return '35', None
            try:
                self.files[handle] = OpenFile(self.store, dsn, OPEN_OPS[op])
            except NotFound:
                return '35', None
            return '00', None
        f = self.files.get(handle)
        if f is None:
            return '42' if op in CLOSE_OPS else '47', None
        if op in CLOSE_OPS:
            del self.files[handle]
            return '00', None
        if keys:
            f.use_key(*keys[refkey if refkey < len(keys) else 0])
        key = f.path.key_of(record)

        if op in START_OPS:
            return ('00' if f.start(key, START_OPS[op]) else '23'), None
        if op in READ_NEXT_OPS or op in READ_PREV_OPS:
            row = f.step(op in READ_NEXT_OPS)
            return ('00', row[2]) if row else ('10', None)
        if op in READ_KEY_OPS:
            row = f.read(key)
            return ('00', row[2]) if row else ('23', None)
        if op == OP_WRITE:
            if f.mode == 'INPUT':
                return '48', None
            self.store.begin()
            try:
                self.store.write(f.dsn, record[:curlen])
            except Duplicate:
                return '22', None
            return '00', None
        if op == OP_REWRITE:
            if f.mode != 'I-O':
                return '49', None
            self.store.begin()
            try:
                self.store.write(f.dsn, record[:curlen], replace=True)
            except NotFound:
                return '23', None
            return '00', None
        if op == OP_DELETE:
            if f.mode != 'I-O':
                return '49', None
            self.store.begin()
            try:
                self.store.delete(f.base.name, f.base.key_of(record))
            except NotFound:
                return '23', None
            return '00', None
        return '00', None               # UNLOCK, COMMIT, FLUSH...


def run_program(kixbatch, lib_dir, store, program, parm, env_dds, vsam_dds, stdin, output, log,
                info=None, cwd=None, ims=None):
    """Roda `program`; devolve (codigo de retorno, abendou?).

    env_dds: {ddname: arquivo} dos DDs sequenciais; vsam_dds: {ddname: DSN}
    dos clusters; stdin/output: arquivos abertos (SYSIN e SYSOUT); info:
    variaveis KIX_* com o job, o passo e os DDs (para a TIOT emulada).
    """
    to_child_r, to_child_w = os.pipe()
    from_child_r, from_child_w = os.pipe()
    env = dict(os.environ, KIX_FD_IN=str(to_child_r), KIX_FD_OUT=str(from_child_w),
               COB_LIBRARY_PATH=lib_dir, **(info or {}))
    for dd, path in env_dds.items():
        env['DD_' + dd] = path
    session = None
    if ims:                             # (definicoes, PSB, regiao BMP?)
        defs, psb, bmp = ims
        session = dli.Session(defs, store, env_dds, io_pcb=bmp)
        if session.schedule(psb) != dli.OK:
            log('DFS554A PSB %s nao encontrado' % psb)
            return 12, False
        env['KIX_IMS_PCBS'] = ','.join((['IOPCB'] if bmp else [])
                                       + [p.dbd.name for p in session.pcbs])
    proc = subprocess.Popen([kixbatch, program] + ([parm] if parm else []), env=env,
                            stdin=stdin or subprocess.DEVNULL, stdout=output, stderr=output,
                            cwd=cwd,    # um DD nao alocado nao deve criar arquivo no projeto
                            pass_fds=(to_child_r, from_child_w))
    os.close(to_child_r)
    os.close(from_child_w)
    server = FileServer(store, vsam_dds, log, session)
    try:
        with os.fdopen(from_child_r, 'rb') as rd, os.fdopen(to_child_w, 'wb') as wr:
            while True:
                head = rd.read(4)
                if len(head) < 4:
                    break
                reply = server.serve(rd.read(struct.unpack('>I', head)[0]))
                wr.write(struct.pack('>I', len(reply)) + reply)
                wr.flush()
    except BrokenPipeError:
        pass
    finally:
        code = proc.wait()
        store.commit()                  # VSAM nao recuperavel: o que foi gravado fica
    return code, code < 0 or code in (ABEND_EXIT, 70) or code > 255
