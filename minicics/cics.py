"""Uma tarefa CICS: executa o programa e atende seus comandos EXEC CICS.

O programa COBOL roda no processo kixtask (runtime/kixtask.c); cada
comando chega aqui pelo pipe, e a resposta diz o que gravar de volta nos
parametros, o novo conteudo do EIB e se o programa continua.
"""
import datetime
import os
import struct
import subprocess

from . import db2, dli, ds3270, mq
from .translate import RESP
from .vsam import Duplicate, NotFound, Store

ACT_CONTINUE, ACT_EXIT, ACT_XCTL, ACT_BRANCH, ACT_LINK = 0, 1, 2, 3, 4
EPOCH_1900 = datetime.datetime(1900, 1, 1)
INTERNAL_READER = 'JOBS'                # fila TD ligada ao leitor interno do JES


class Condition(Exception):
    """Condicao excepcional de um comando (vira EIBRESP / RESP)."""

    def __init__(self, name, resp2=0):
        Exception.__init__(self, name)
        self.name, self.resp, self.resp2 = name, RESP[name], resp2


class Abend(Exception):
    def __init__(self, code, detail=''):
        Exception.__init__(self, code)
        self.code, self.detail = code, detail


class Param(object):
    def __init__(self, idx, numeric, value, data, scale=0):
        self.idx, self.numeric, self.value, self.data = idx, numeric, value, data
        self.scale = scale              # casas decimais (value vem sem a virgula)

    def text(self):
        return self.data.decode('latin-1').rstrip(' \x00')

    def number(self):
        return self.value if self.numeric else int(self.text() or 0)


def _packed(value, size=4):
    digits = '%0*d' % (size * 2 - 1, abs(value))
    return bytes.fromhex(digits + ('D' if value < 0 else 'C'))


def unpack_request(payload):
    """Pedido do KIXCMD -> (spec, [Param])."""
    end = payload.index(b'\x00')
    spec = payload[:end].decode('latin-1')
    (count,), pos = struct.unpack_from('>H', payload, end + 1), end + 3
    values = []
    for i in range(count):
        kind, value, size = struct.unpack_from('>cqI', payload, pos)
        pos += 13
        scale = kind[0] - 0x10 if 0x10 < kind[0] < 0x30 else 0
        values.append(Param(i + 2, kind == b'N' or scale > 0, value, payload[pos:pos + size],
                            scale))
        pos += size
    return spec, values


def pack_update(param, value):
    """Gravacao de `value` (int, str ou bytes) em um parametro do COBOL."""
    if isinstance(value, int):
        if param.numeric:
            return struct.pack('>HcQ', param.idx, b'N', value & (2 ** 64 - 1))
        value = str(value).encode()
    if isinstance(value, str):
        value = value.encode('latin-1')
    if not param.numeric:
        value = value.ljust(len(param.data))
    return struct.pack('>HcI', param.idx, b'X', len(value)) + value


class Task(object):
    def __init__(self, region, term, transid, program, commarea, inbound, start_data=None):
        self.region, self.term = region, term
        self.start_data = start_data    # dados do START / gatilho (EXEC CICS RETRIEVE)
        self.links = []                 # niveis de LINK: estado do chamador
        self.mq = None                  # sessao MQ (filas abertas)
        self.dli = None                 # sessao IMS (PSB agendado)
        self.transid, self.program = transid, program
        self.commarea, self.inbound = commarea, inbound
        self.number = region.next_task_number()
        self.started = datetime.datetime.now()
        self.resp = self.resp2 = 0
        self.next_transid = None
        self.next_commarea = b''
        self.sent = False               # a tarefa escreveu algo no terminal?
        self.browses = {}
        self.locked = {}                # cluster -> chave do ultimo READ UPDATE
        self.updates = []
        self.handlers = {}              # condicao -> indice do paragrafo (HANDLE CONDITION)
        self.ignored = set()            # condicoes de IGNORE CONDITION
        self.abend_label = 0            # indice do paragrafo de HANDLE ABEND
        self.sql = None                 # sessao Db2 (cursores abertos)
        self.job = []                   # cartoes gravados na fila do leitor interno
        self._store = None

    # --- infraestrutura ---------------------------------------------------
    @property
    def store(self):
        if self._store is None:
            self._store = Store(self.region.store_path)
        return self._store

    def eib(self, calen=None):
        t = self.started
        date = (t.year - 1900) * 1000 + t.timetuple().tm_yday
        time = t.hour * 10000 + t.minute * 100 + t.second
        calen = len(self.commarea) if calen is None else calen
        return b''.join([
            _packed(time), _packed(date), self.transid.ljust(4).encode(),
            _packed(self.number), self.term.termid.ljust(4).encode(),
            struct.pack('>hhh', 0, self.inbound.cursor, calen),
            bytes([self.inbound.aid]), b'\x00' * 2, b'\x00' * 6, b' ' * 24,
            b'\x00' * 11, b' ' * 4, b'\x00' * 2,
            struct.pack('>ii', self.resp, self.resp2), b'\x00'])

    def set(self, param, value):
        """Agenda a gravacao de `value` (int ou bytes) no parametro do COBOL."""
        if param is None or param is True:
            return
        self.updates.append(pack_update(param, value))

    def run(self):
        to_child_r, to_child_w = os.pipe()
        from_child_r, from_child_w = os.pipe()
        env = dict(os.environ, KIX_FD_IN=str(to_child_r), KIX_FD_OUT=str(from_child_w),
                   COB_LIBRARY_PATH=self.region.lib_dir)
        log = open(self.region.log_path, 'ab')
        log_start = log.tell()
        proc = subprocess.Popen([self.region.kixtask], env=env, stdin=subprocess.DEVNULL,
                                stdout=log, stderr=log,
                                pass_fds=(to_child_r, from_child_w))
        os.close(to_child_r)
        os.close(from_child_w)
        abend = None
        try:
            with os.fdopen(from_child_r, 'rb') as rd, os.fdopen(to_child_w, 'wb') as wr:
                while True:
                    head = rd.read(4)
                    if len(head) < 4:
                        break
                    payload = rd.read(struct.unpack('>I', head)[0])
                    try:
                        reply = self._serve(payload)
                    except Abend as a:
                        abend = a
                        break
                    wr.write(struct.pack('>I', len(reply)) + reply)
                    wr.flush()
        except BrokenPipeError:
            pass
        finally:
            if abend:
                proc.kill()
            code = proc.wait()
            log.close()
            if abend is None and code != 0:
                with open(self.region.log_path, 'rb') as f:
                    f.seek(log_start)
                    detail = f.read().decode('latin-1').strip().splitlines()
                abend = Abend('ASRA', detail[-1] if detail else 'codigo de saida %d' % code)
            if self._store:             # fim da tarefa: syncpoint implicito
                if abend:
                    self._store.rollback()
                else:
                    self._store.commit()
                self._store.close()
        if abend:
            self.next_transid = None
            self.region.log('tarefa %d %s: ABEND %s %s' % (self.number, self.transid,
                                                         abend.code, abend.detail))
            self.term.send(ds3270.message_screen(
                'DFHAC2206 Transaction %s failed with abend %s. %s'
                % (self.transid, abend.code, abend.detail)))
            self.sent = True

    def _serve(self, payload):
        spec, values = unpack_request(payload)
        if spec.startswith('SQL|'):
            return self._sql(spec, values)
        if spec.startswith('MQ|'):
            return self._mq(spec, values)
        if spec.startswith('DLI|'):
            return self._dli(spec, values)
        spec = spec.split('|')
        verb, opts = spec[0], {}
        for item in spec[1:]:
            if item.endswith('='):
                opts[item[:-1]] = values.pop(0)
            else:
                opts[item] = True

        self.updates, self.resp, self.resp2 = [], 0, 0
        action, extra = ACT_CONTINUE, b''
        handler = getattr(self, 'cmd_' + verb.lower().replace('-', '_'), None)
        if handler is None:
            raise Abend('AEY9', 'comando EXEC CICS %s nao implementado' % verb)
        self.region.trace('%s %s' % (verb, ' '.join(
            k if v is True else '%s(%s)' % (k, v.text()[:20]) for k, v in opts.items())))
        try:
            try:
                result = handler(opts)
                if result:
                    action, extra = result
            except Condition as c:
                self.resp, self.resp2 = c.resp, c.resp2
                self.region.trace('  -> %s' % c.name)
                if 'RESP' in opts or 'NOHANDLE' in opts or c.name in self.ignored:
                    pass
                elif c.name in self.handlers or 'ERROR' in self.handlers:
                    action = ACT_BRANCH
                    extra = struct.pack('>H', self.handlers.get(c.name) or self.handlers['ERROR'])
                else:
                    raise Abend('AEI' + c.name[:1],
                                'condicao %s em %s nao tratada' % (c.name, verb))
        except Abend as a:
            # HANDLE ABEND: desvia para a rotina do programa, que fica
            # desativada enquanto roda (um novo abend encerra a tarefa).
            if not self.abend_label or 'CANCEL' in opts:
                raise
            self.region.trace('  -> abend %s, desvia para a rotina de HANDLE ABEND' % a.code)
            action, extra = ACT_BRANCH, struct.pack('>H', self.abend_label)
            self.abend_label = 0
        self.set(opts.get('RESP'), self.resp)
        self.set(opts.get('RESP2'), self.resp2)
        calen = None
        if action == ACT_XCTL:
            calen = struct.unpack_from('>I', extra, 8)[0]
        return (bytes([action]) + self.eib(calen) + struct.pack('>H', len(self.updates))
                + b''.join(self.updates) + extra)

    def _sql(self, spec, values):
        self.region.trace('EXEC ' + ' '.join(spec.split('|', 4)[1::3])[:110])
        if self.sql is None:
            self.sql = db2.Session()
            db2.prepare(self.store.db)
        updates = self.sql.execute(self.store.db, self.store.begin, spec, values)
        code = struct.unpack_from('>i', updates[0][1], 12)[0]
        if code:
            self.region.trace('  -> SQLCODE %d' % code)
        return (bytes([ACT_CONTINUE]) + self.eib() + struct.pack('>H', len(updates))
                + b''.join(pack_update(p, v) for p, v in updates))

    def _dli(self, spec, values):
        if self.dli is None:
            self.dli = dli.Session(self.region.ims, self.store)
        status, updates = self.dli.exec_dli(spec, values)
        self.region.trace('EXEC DLI %s%s' % (' '.join(spec.split('|')[1:])[:80],
                                             ' -> %s' % status if status.strip() else ''))
        return (bytes([ACT_CONTINUE]) + self.eib() + struct.pack('>H', len(updates))
                + b''.join(pack_update(p, v) for p, v in updates))

    def _mq(self, spec, values):
        func = spec.split('|')[1]
        for p in values:                # sem a spec, os indices comecam em 1
            p.idx -= 1
        if self.mq is None:
            self.mq = mq.Session()
            mq.prepare(self.store.db)
        updates = self.mq.call(self.store.db, self.store.begin, func, values)
        cc, rc = updates[-2][1], updates[-1][1]
        self.region.trace('MQ%s%s' % (func, ' -> CC %d RC %d' % (cc, rc) if cc else ''))
        return (bytes([ACT_CONTINUE]) + self.eib() + struct.pack('>H', len(updates))
                + b''.join(pack_update(p, v) for p, v in updates))

    @staticmethod
    def _commarea(opts):
        if 'COMMAREA' not in opts:
            return b''
        data = opts['COMMAREA'].data
        if 'LENGTH' in opts:
            data = data[:opts['LENGTH'].number()]
        return data

    def _xctl(self, program, commarea):
        program = program.strip().upper()
        if program not in self.region.programs:
            raise Condition('PGMIDERR', 1)
        self.program, self.commarea = program, commarea
        self.handlers, self.ignored, self.abend_label = {}, set(), 0
        return ACT_XCTL, program.ljust(8).encode() + struct.pack('>I', len(commarea)) + commarea

    # --- controle de programa ---------------------------------------------
    def cmd_init(self, opts):
        return self._xctl(self.program, self.commarea)

    def cmd_xctl(self, opts):
        return self._xctl(opts['PROGRAM'].text(), self._commarea(opts))

    def cmd_link(self, opts):
        program = opts['PROGRAM'].text().strip().upper()
        if program not in self.region.programs:
            raise Condition('PGMIDERR', 1)
        self.links.append((self.program, self.commarea, self.handlers, self.ignored,
                           self.abend_label))
        self.program, self.commarea = program, self._commarea(opts)
        self.handlers, self.ignored, self.abend_label = {}, set(), 0
        area = opts.get('COMMAREA')
        return ACT_LINK, program.ljust(8).encode() + struct.pack('>H', area.idx if area else 0)

    def cmd_linkend(self, opts):
        (self.program, self.commarea, self.handlers, self.ignored,
         self.abend_label) = self.links.pop()

    def cmd_retrieve(self, opts):
        if self.start_data is None:
            raise Condition('ENDDATA')
        data, self.start_data = self.start_data, None
        self.set(opts.get('INTO'), data)
        self.set(opts.get('LENGTH'), len(data))

    def cmd_return(self, opts):
        if self.links:                  # programa chamado por LINK: o GOBACK
            return None                 # emitido pelo tradutor devolve o controle
        if 'TRANSID' in opts:
            self.next_transid = opts['TRANSID'].text().upper()
            self.next_commarea = self._commarea(opts)
        return ACT_EXIT, b''

    def cmd_abend(self, opts):
        raise Abend(opts['ABCODE'].text() if 'ABCODE' in opts else '????', 'EXEC CICS ABEND')

    @staticmethod
    def _labels(opts):
        """Opcoes de HANDLE / IGNORE: [(nome, indice do paragrafo ou 0)]."""
        out = []
        for item in opts:
            name, _, index = item.partition(':')
            if name not in ('CONDITION', 'ABEND', 'AID', 'RESP', 'RESP2', 'NOHANDLE'):
                out.append((name, int(index or 0)))
        return out

    def cmd_handle(self, opts):
        if 'ABEND' in opts:             # LABEL(paragrafo), CANCEL ou RESET
            self.abend_label = dict(self._labels(opts)).get('LABEL', 0)
        elif 'CONDITION' in opts:
            for name, index in self._labels(opts):
                self.ignored.discard(name)
                if index:
                    self.handlers[name] = index
                else:                   # sem paragrafo: volta a acao padrao
                    self.handlers.pop(name, None)

    def cmd_ignore(self, opts):
        for name, _ in self._labels(opts):
            self.handlers.pop(name, None)
            self.ignored.add(name)

    def cmd_syncpoint(self, opts):
        if 'ROLLBACK' in opts:
            self.store.rollback()
        else:
            self.store.commit()
        self.locked.clear()

    def cmd_inquire(self, opts):
        if 'PROGRAM' in opts and opts['PROGRAM'].text().upper() not in self.region.programs:
            raise Condition('PGMIDERR', 1)

    def cmd_assign(self, opts):
        known = {'APPLID': self.region.applid, 'SYSID': self.region.sysid,
                 'USERID': 'CICSUSER', 'OPID': '   ', 'NETNAME': self.term.termid,
                 'FACILITY': self.term.termid, 'PROGRAM': self.program,
                 'TCTUALENG': 0, 'TWALENG': 0, 'CWALENG': 0, 'SCRNHT': 24, 'SCRNWD': 80}
        for name, param in opts.items():
            if param is not True and name in known:
                self.set(param, known[name])

    # --- data e hora ------------------------------------------------------
    def cmd_asktime(self, opts):
        now = datetime.datetime.now()
        self.set(opts.get('ABSTIME'), int((now - EPOCH_1900).total_seconds() * 1000))

    def cmd_formattime(self, opts):
        t = self.started
        if 'ABSTIME' in opts:
            t = EPOCH_1900 + datetime.timedelta(milliseconds=opts['ABSTIME'].number())
        dsep = ''
        if 'DATESEP' in opts:
            dsep = '/' if opts['DATESEP'] is True else opts['DATESEP'].text() or '/'
        tsep = ''
        if 'TIMESEP' in opts:
            tsep = ':' if opts['TIMESEP'] is True else opts['TIMESEP'].text() or ':'
        yy, yyyy, mm, dd = t.strftime('%y'), t.strftime('%Y'), t.strftime('%m'), t.strftime('%d')
        ddd = t.strftime('%j')
        formats = {
            'YYMMDD': dsep.join([yy, mm, dd]), 'YYYYMMDD': dsep.join([yyyy, mm, dd]),
            'MMDDYY': dsep.join([mm, dd, yy]), 'MMDDYYYY': dsep.join([mm, dd, yyyy]),
            'DDMMYY': dsep.join([dd, mm, yy]), 'DDMMYYYY': dsep.join([dd, mm, yyyy]),
            'YYDDD': dsep.join([yy, ddd]), 'YYYYDDD': dsep.join([yyyy, ddd]),
            'DATE': dsep.join([mm, dd, yy]), 'TIME': t.strftime(tsep.join(['%H', '%M', '%S'])),
            'YEAR': t.year, 'MONTHOFYEAR': t.month, 'DAYOFMONTH': t.day,
            'DAYOFWEEK': (t.weekday() + 1) % 7, 'DAYCOUNT': (t - EPOCH_1900).days,
            'MILLISECONDS': t.microsecond // 1000,
        }
        for name, value in formats.items():
            if name in opts and opts[name] is not True:
                self.set(opts[name], value)

    # --- terminal ---------------------------------------------------------
    def _map(self, opts):
        name = opts['MAP'].text().upper()
        mapset = opts['MAPSET'].text().upper() if 'MAPSET' in opts else name
        try:
            return self.region.maps[(mapset, name)]
        except KeyError:
            raise Abend('APCT', 'mapa %s do mapset %s nao encontrado' % (name, mapset))

    def cmd_send(self, opts):
        erase = 'ERASE' in opts
        if 'MAP' not in opts:           # SEND TEXT
            data = opts['FROM'].data
            if 'LENGTH' in opts:
                data = data[:opts['LENGTH'].number()]
            self.term.send(ds3270.text_screen(data, erase, 'ALARM' in opts))
            self.sent = True
            return
        m = self._map(opts)
        data = None if 'MAPONLY' in opts else opts['FROM'].data.ljust(m.length, b'\x00')
        dataonly = 'DATAONLY' in opts
        cursor = opts.get('CURSOR')
        symbolic = cursor is True
        ctrl = m.ctrl or []
        ctrl = ctrl if isinstance(ctrl, list) else [ctrl]

        fields, ic = [], None
        for f in m.fields:
            attr, color, hilight, text = f.attr, f.color, f.hilight, f.initial
            if f.name and data is not None:
                o = f.offset
                length = struct.unpack_from('>h', data, o)[0]
                # X'80' e a flag "campo apagado" deixada pelo RECEIVE MAP na
                # mesma posicao: nao e um atributo pedido pelo programa.
                if data[o + 2] not in (0x00, 0x80):
                    attr = data[o + 2] & 0x3F
                if m.ext:
                    color = data[o + 3] or color
                    hilight = data[o + 5] or hilight
                value = data[o + 3 + m.ext:o + 3 + m.ext + f.length]
                if value[:1] != b'\x00' and f.length:
                    text = value
                elif dataonly:
                    text = None
                if symbolic and length == -1 and ic is None:
                    ic = f
            elif dataonly:
                continue
            fields.append((f, attr, color, hilight, text))
        if ic is None and not isinstance(cursor, Param):
            ic = next((f for f in m.fields if f.ic), None)

        body = b''
        for f, attr, color, hilight, text in fields:
            body += ds3270.start_field(f.address(m.cols), attr, color, hilight)
            if f is ic:
                body += bytes([ds3270.IC])
            if text:
                body += ds3270.to_ebcdic(text[:f.length] if f.length else b'')
        if isinstance(cursor, Param):
            body += bytes([ds3270.SBA]) + ds3270.addr(cursor.number()) + bytes([ds3270.IC])
        restore = 'FREEKB' in opts or 'FREEKB' in ctrl
        alarm = 'ALARM' in opts or ('ALARM' in ctrl and self.region.alarm)
        self.term.send(ds3270.write(body, erase, restore, alarm))
        self.sent = self.sent or restore

    def cmd_receive(self, opts):
        if 'MAP' not in opts:
            data = self.inbound.text
            self.set(opts.get('INTO'), data)
            self.set(opts.get('LENGTH'), len(data))
            return
        m = self._map(opts)
        area = bytearray(m.length)
        if self.inbound.aid in ds3270.SHORT_READ_AIDS or not self.inbound.fields:
            self.set(opts['INTO'], bytes(area))
            raise Condition('MAPFAIL')
        for f in m.named():
            value = self.inbound.fields.get((f.address(m.cols) + 1) % (m.rows * m.cols))
            if value is None:
                continue
            value = value[:f.length]
            o = f.offset
            if not value:
                area[o + 2] = 0x80      # campo modificado e apagado
                continue
            struct.pack_into('>h', area, o, len(value))
            pad = b'0' if f.zero else b' '
            value = value.rjust(f.length, pad) if f.right else value.ljust(f.length, b' ')
            area[o + 3 + m.ext:o + 3 + m.ext + f.length] = value
        self.set(opts['INTO'], bytes(area))

    # --- arquivos ---------------------------------------------------------
    def _file(self, opts):
        name = (opts.get('DATASET') or opts['FILE']).text().upper()
        name = self.region.files.get(name, name)    # DSN definido no CSD
        try:
            return name, self.store.path(name)
        except NotFound:
            raise Condition('FILENOTFOUND', 1)

    @staticmethod
    def _key(opts, path):
        key = opts['RIDFLD'].data
        if 'KEYLENGTH' in opts:
            key = key[:opts['KEYLENGTH'].number()]
        return key[:path.keylen]

    def _deliver(self, opts, path, row):
        akey, pk, record = row
        self.set(opts.get('INTO'), record)
        self.set(opts.get('LENGTH'), len(record))
        return akey, pk

    def cmd_read(self, opts):
        name, path = self._file(opts)
        key = self._key(opts, path)
        if 'UPDATE' in opts:            # o registro fica bloqueado ate o syncpoint
            self.store.begin()
        if 'GENERIC' in opts or 'GTEQ' in opts:
            row = self.store.seek(name, key, '>=')
            if row and 'GTEQ' not in opts and not row[0].startswith(key):
                row = None
        else:
            row = self.store.seek(name, key.ljust(path.keylen), '==')
        if not row:
            raise Condition('NOTFND', 1)
        self._deliver(opts, path, row)
        if 'UPDATE' in opts:
            self.locked[path.base] = row[1]
        if 'GENERIC' in opts or 'GTEQ' in opts:
            self.set(opts['RIDFLD'], row[0])

    def cmd_write(self, opts):
        name, path = self._file(opts)
        self.store.begin()
        try:
            self.store.write(name, opts['FROM'].data)
        except Duplicate:
            raise Condition('DUPREC')

    def cmd_rewrite(self, opts):
        name, path = self._file(opts)
        self.store.begin()
        try:
            self.store.write(name, opts['FROM'].data, replace=True)
            self.locked.pop(path.base, None)
        except NotFound:
            raise Condition('INVREQ', 30)

    def cmd_delete(self, opts):
        name, path = self._file(opts)
        self.store.begin()
        if 'RIDFLD' not in opts:        # apaga o registro do ultimo READ UPDATE
            pk = self.locked.pop(path.base, None)
            if pk is None:
                raise Condition('INVREQ', 47)
        else:
            row = self.store.seek(name, self._key(opts, path).ljust(path.keylen), '==')
            if not row:
                raise Condition('NOTFND', 1)
            pk = row[1]
        try:
            self.store.delete(path.base, pk)
        except NotFound:
            raise Condition('NOTFND', 1)

    def cmd_unlock(self, opts):
        name, path = self._file(opts)
        self.locked.pop(path.base, None)

    def cmd_startbr(self, opts):
        name, path = self._file(opts)
        key = self._key(opts, path)
        full = key.ljust(path.keylen, b'\x00')
        if 'EQUAL' in opts:
            found = self.store.seek(name, full, '==')
        elif key == b'\xff' * len(key):
            found = True                # posiciona no fim do arquivo
        else:
            found = self.store.seek(name, full, '>=')
        if not found:
            raise Condition('NOTFND', 1)
        # pos: (chave, chave primaria) do ultimo registro lido; None = recem-posicionado
        self.browses[name] = {'start': full, 'pos': None, 'dir': None}

    def _browse(self, opts, forward):
        name, path = self._file(opts)
        b = self.browses.get(name)
        if b is None:
            raise Condition('INVREQ', 34)
        if b['pos'] is None:
            row = self.store.seek(name, b['start'], '>=' if forward else '<=')
        else:
            same = b['dir'] != forward      # ao inverter o sentido, repete o registro
            op = ('>=' if same else '>') if forward else ('<=' if same else '<')
            row = self.store.seek(name, b['pos'][0], op, b['pos'][1])
        if not row:
            raise Condition('ENDFILE')
        b['pos'], b['dir'] = self._deliver(opts, path, row), forward
        self.set(opts['RIDFLD'], row[0])

    def cmd_readnext(self, opts):
        self._browse(opts, True)

    def cmd_readprev(self, opts):
        self._browse(opts, False)

    def cmd_endbr(self, opts):
        name, path = self._file(opts)
        self.browses.pop(name, None)

    # --- filas ------------------------------------------------------------
    def cmd_writeq(self, opts):
        queue = opts['QUEUE'].text()
        data = opts['FROM'].data
        if 'LENGTH' in opts:
            data = data[:opts['LENGTH'].number()]
        with open(os.path.join(self.region.data_dir, 'tdq_%s.txt' % queue), 'ab') as f:
            f.write(data.rstrip() + b'\n')
        if queue.upper() == INTERNAL_READER:
            line = data.decode('latin-1').rstrip()
            if line.startswith('/*EOF'):
                self.region.submit(self.job)
                self.job = []
            else:
                self.job.append(line)
