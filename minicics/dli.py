"""IMS DB minimo: bancos hierarquicos (DL/I) no mesmo SQLite.

Le as definicoes (DBD e PSB) dos fontes de macro em <modulo>/ims e atende
as chamadas dos programas: EXEC DLI (online e BMP) e CALL 'CBLTDLI'
(batch). Cada segmento e uma linha de kix_ims cuja chave e a chave
concatenada do caminho (pai + filho...), de modo que a ordem da chave e a
ordem hierarquica. So ha suporte a um tipo de segmento por nivel, que e o
que o CardDemo usa, e aos PCBs de GSAM (arquivos sequenciais).
"""
import glob
import os
import re
import struct

from . import bms

OK, NOT_FOUND, END_OF_DB, DUPLICATE = '  ', 'GE', 'GB', 'II'
NO_PARENT, NO_POSITION, KEY_CHANGED = 'GP', 'DJ', 'DA'
_OPS = {'EQ': lambda a, b: a == b, 'NE': lambda a, b: a != b,
        'GT': lambda a, b: a > b, 'GE': lambda a, b: a >= b,
        'LT': lambda a, b: a < b, 'LE': lambda a, b: a <= b}
_OPS.update({'=': _OPS['EQ'], ' =': _OPS['EQ'], '= ': _OPS['EQ'], '>': _OPS['GT'],
             '<': _OPS['LT'], '>=': _OPS['GE'], '=>': _OPS['GE'], '<=': _OPS['LE'],
             '=<': _OPS['LE'], '^=': _OPS['NE'], '<>': _OPS['NE']})
_NAME = re.compile(r'[A-Z0-9#@$]+')


# --- definicoes --------------------------------------------------------------
class Segment(object):
    def __init__(self, name, parent, size):
        self.name, self.parent, self.size = name, parent, size
        self.fields = {}                # campo -> (inicio a partir de 0, tamanho)
        self.key = None
        self.level, self.prefix = 1, 0  # nivel e tamanho da chave concatenada do pai

    def key_of(self, data):
        start, length = self.key
        return bytes(data[start:start + length]).ljust(length, b'\x00')


class Dbd(object):
    def __init__(self, name, access):
        self.name, self.access = name, access
        self.segments = {}
        self.dd_in = self.dd_out = None     # GSAM
        self.record = 0

    @property
    def gsam(self):
        return 'GSAM' in self.access


class Definitions(object):
    """DBDs e PSBs de todos os modulos."""

    def __init__(self, dirs):
        self.dbds, self.psbs = {}, {}
        for d in dirs:
            for path in sorted(glob.glob(os.path.join(d, '*'))):
                with open(path, encoding='latin-1') as f:
                    self._parse(f.read())

    def _parse(self, text):
        dbd, segment, pcbs = None, None, []
        for stmt in bms._statements(text):
            label = '' if stmt[0] == ' ' else stmt.split()[0]
            opcode, _, operands = stmt[len(label):].lstrip().partition(' ')
            ops = bms._split(operands.lstrip())

            def names(key):
                value = ops.get(key, '')
                return _NAME.findall(','.join(value) if isinstance(value, list) else value)
            if opcode == 'DBD':
                dbd = self.dbds[names('NAME')[0]] = Dbd(names('NAME')[0], names('ACCESS'))
            elif opcode == 'DATASET' and dbd is not None:
                dbd.dd_in = (names('DD1') or [None])[0]
                dbd.dd_out = (names('DD2') or [dbd.dd_in])[0]
                dbd.record = int((names('RECORD') or ['0'])[0])
            elif opcode == 'SEGM' and dbd is not None:
                parent = (names('PARENT') or ['0'])[0]
                segment = Segment(names('NAME')[0], None if parent == '0' else parent,
                                  int(names('BYTES')[0]))
                if segment.parent:
                    up = dbd.segments[segment.parent]
                    segment.level, segment.prefix = up.level + 1, up.prefix + up.key[1]
                dbd.segments[segment.name] = segment
            elif opcode == 'FIELD' and segment is not None:
                field = names('NAME')
                where = (int(names('START')[0]) - 1, int(names('BYTES')[0]))
                segment.fields[field[0]] = where
                if 'SEQ' in field[1:]:
                    segment.key = where
            elif opcode == 'PCB':
                pcbs.append(((names('DBDNAME') or names('NAME') or ['?'])[0], names('TYPE')))
            elif opcode == 'PSBGEN':
                self.psbs[names('PSBNAME')[0]] = [n for n, t in pcbs if 'TP' not in t]
                pcbs = []


def prepare(db):
    db.execute('CREATE TABLE IF NOT EXISTS kix_ims (dbd TEXT, ckey BLOB, seg TEXT, data BLOB,'
               ' PRIMARY KEY (dbd, ckey)) WITHOUT ROWID')


# --- posicao em um PCB -------------------------------------------------------
class Pcb(object):
    def __init__(self, dbd):
        self.dbd = dbd
        self.pos = None                 # chave concatenada do segmento corrente
        self.parent = None              # pai estabelecido para o GNP
        self.reader = None              # arquivo de entrada (GSAM)

    # ssas: [(segmento, None | (campo, operador, valor))]
    def _matches(self, db, ckey, seg, data, ssas):
        if not ssas:
            return True
        name, qual = ssas[-1]
        if name != seg or not self._qualifies(self.dbd.segments[seg], data, qual):
            return False
        for name, qual in ssas[:-1]:    # os SSAs anteriores qualificam os ancestrais
            up = self.dbd.segments[name]
            row = db.execute('SELECT data FROM kix_ims WHERE dbd = ? AND ckey = ?',
                             (self.dbd.name, ckey[:up.prefix + up.key[1]])).fetchone()
            if not row or not self._qualifies(up, bytes(row[0]), qual):
                return False
        return True

    @staticmethod
    def _qualifies(segment, data, qual):
        if qual is None:
            return True
        field, op, value = qual
        start, length = segment.fields[field]
        return _OPS[op](bytes(data[start:start + length]), bytes(value[:length]).ljust(length))

    def _scan(self, db, after, ssas, within=None):
        sql = 'SELECT ckey, seg, data FROM kix_ims WHERE dbd = ? AND ckey > ? ORDER BY ckey'
        for ckey, seg, data in db.execute(sql, (self.dbd.name, after or b'')):
            ckey, data = bytes(ckey), bytes(data)
            if within is not None and not ckey.startswith(within):
                return None
            if self._matches(db, ckey, seg, data, ssas):
                return ckey, seg, data
        return None

    def call(self, db, begin, func, ssas, data):
        """Uma chamada DL/I: devolve (status, segmento, dados lidos ou None)."""
        func = func.strip().upper()
        if func.startswith('GH'):       # GHU / GHN / GHNP: aqui igual ao sem hold
            func = 'G' + func[2:]
        if func in ('GU', 'GN', 'GNP'):
            if func == 'GNP' and self.parent is None:
                return NO_PARENT, '', None
            row = self._scan(db, None if func == 'GU' else self.pos, ssas,
                             self.parent if func == 'GNP' else None)
            if row is None:
                return (END_OF_DB if func == 'GN' else NOT_FOUND), '', None
            self.pos = row[0]
            if func != 'GNP':
                self.parent = row[0]
            return OK, row[1], row[2]
        if func == 'ISRT':
            name = ssas[-1][0]
            segment = self.dbd.segments[name]
            if segment.parent is None:
                above = b''
            elif len(ssas) > 1:
                row = self._scan(db, None, ssas[:-1])
                if row is None:
                    return NOT_FOUND, '', None
                above = row[0]
            elif self.pos is None or len(self.pos) < segment.prefix:
                return NOT_FOUND, '', None
            else:
                above = self.pos[:segment.prefix]
            ckey = above + segment.key_of(data)
            record = bytes(data[:segment.size]).ljust(segment.size, b'\x00')
            begin()
            if db.execute('SELECT 1 FROM kix_ims WHERE dbd = ? AND ckey = ?',
                          (self.dbd.name, ckey)).fetchone():
                return DUPLICATE, name, None
            db.execute('INSERT INTO kix_ims VALUES (?,?,?,?)', (self.dbd.name, ckey, name, record))
            self.pos = ckey
            return OK, name, None
        if func in ('REPL', 'DLET'):
            # O alvo e o segmento nomeado no caminho corrente: o ultimo lido
            # ou um ancestral dele (o CBPAUP0C apaga a raiz depois de ter
            # lido e apagado os filhos).
            if self.pos and ssas and ssas[-1][0] in self.dbd.segments:
                named = self.dbd.segments[ssas[-1][0]]
                if len(self.pos) >= named.prefix + named.key[1]:
                    self.pos = self.pos[:named.prefix + named.key[1]]
            row = self.pos and db.execute('SELECT seg FROM kix_ims WHERE dbd = ? AND ckey = ?',
                                          (self.dbd.name, self.pos)).fetchone()
            if not row:
                return NO_POSITION, '', None
            segment = self.dbd.segments[row[0]]
            begin()
            if func == 'DLET':          # o segmento e todos os seus dependentes
                db.execute('DELETE FROM kix_ims WHERE dbd = ? AND substr(ckey, 1, ?) = ?',
                           (self.dbd.name, len(self.pos), self.pos))
                return OK, row[0], None
            if segment.key_of(data) != self.pos[segment.prefix:]:
                return KEY_CHANGED, row[0], None
            db.execute('UPDATE kix_ims SET data = ? WHERE dbd = ? AND ckey = ?',
                       (bytes(data[:segment.size]).ljust(segment.size, b'\x00'),
                        self.dbd.name, self.pos))
            return OK, row[0], None
        return 'AD', '', None           # funcao invalida

    def level(self, name):
        return self.dbd.segments[name].level if name in self.dbd.segments else 0


# --- sessao ------------------------------------------------------------------
class Session(object):
    """PSB agendado por uma tarefa (ou por um passo batch) e seus PCBs."""

    def __init__(self, defs, store, files=None, io_pcb=False):
        self.defs, self.store = defs, store
        self.files = files or {}        # {ddname: arquivo}, para os PCBs de GSAM
        self.io_pcb = io_pcb            # o primeiro PCB do programa e o de E/S (BMP)
        self.psb, self.pcbs = None, []
        prepare(store.db)

    def schedule(self, name):
        if self.psb:
            return 'TC'
        if name not in self.defs.psbs:
            return 'TE'
        self.psb = name
        self.pcbs = [Pcb(self.defs.dbds[d]) for d in self.defs.psbs[name]
                     if d in self.defs.dbds]
        return OK

    def terminate(self):
        self.psb, self.pcbs = None, []

    def pcb(self, number=None, name=None):
        """PCB pelo numero (EXEC DLI) ou pelo nome do DBD na mascara (CBLTDLI)."""
        if name is not None:
            for pcb in self.pcbs:
                if pcb.dbd.name == name:
                    return pcb
        index = (number or 1) - 1 - (1 if self.io_pcb else 0)
        candidates = [p for p in self.pcbs if not p.dbd.gsam] or self.pcbs
        if not candidates:
            return None
        return self.pcbs[index] if 0 <= index < len(self.pcbs) else candidates[0]

    def _gsam(self, pcb, func, data):
        dbd = pcb.dbd
        if func.strip() == 'ISRT':
            path = self.files.get(dbd.dd_out)
            if path is None:
                return 'AI', None
            with open(path, 'ab') as f:
                f.write(bytes(data[:dbd.record]).ljust(dbd.record))
            return OK, None
        if func.strip() in ('GN', 'GU'):
            if pcb.reader is None or func.strip() == 'GU':
                path = self.files.get(dbd.dd_in)
                if path is None:
                    return 'AI', None
                pcb.reader = open(path, 'rb')
            record = pcb.reader.read(dbd.record)
            return (OK, record) if record else (END_OF_DB, None)
        return 'AD', None

    # --- EXEC DLI ---------------------------------------------------------
    def exec_dli(self, spec, values):
        """Spec "DLI|funcao|DIB=|PCB=|SEGMENT:x|WHERE:campo:op=|INTO=|...".

        Devolve [(parametro, valor a gravar)]; o primeiro e o DIB.
        """
        items = spec.split('|')
        func, values = items[1], list(values)
        dib, number, ssas, area, into, psb = None, None, [], None, False, None
        for item in items[2:]:
            name, eq, _ = item.partition('=')
            param = values.pop(0) if eq else None
            name, _, literal = name.partition(':')
            if name == 'DIB':
                dib = param
            elif name == 'PCB':
                number = param.number()
            elif name == 'SEGMENT':
                ssas.append((literal, None))
            elif name == 'WHERE':
                field, _, op = literal.partition(':')
                ssas[-1] = (ssas[-1][0], (field, op, param.data))
            elif name in ('INTO', 'FROM'):
                area, into = param, name == 'INTO'
            elif name == 'PSB':
                psb = param.text() if param is not None else literal
        status, segment, data, pcb = OK, '', None, None
        if func in ('SCHD', 'SCHEDULE'):
            status = self.schedule((psb or '').strip().upper())
        elif func in ('TERM', 'TERMINATE'):
            self.terminate()
            self.store.commit()
        elif func in ('CHKP', 'SYMCHKP', 'CHECKPOINT'):
            self.store.commit()
        else:
            pcb = self.pcb(number)
            if pcb is None:
                status = 'TG' if not self.psb else NO_POSITION
            else:
                status, segment, data = pcb.call(self.store.db, self.store.begin, func, ssas,
                                                 area.data if area is not None else b'')
        level = pcb.level(segment) if pcb else 0
        block = ('ZZ' + status + segment.ljust(8) + '  ' + ('%02d' % level)).encode()
        block += struct.pack('>h', len(pcb.pos) if pcb and pcb.pos else 0)
        block += (pcb.dbd.name if pcb else '').ljust(8).encode() + b'HIDAM   ' + b' ' * 6
        updates = [(dib, block)] if dib is not None else []
        if data is not None and into and area is not None:
            updates.append((area, data[:len(area.data)].ljust(len(area.data), b'\x00')))
        return status, updates

    # --- CALL 'CBLTDLI' ---------------------------------------------------
    def call_dli(self, values):
        """Parametros: funcao, mascara do PCB, area de E/S e os SSAs.

        (Um contador de parametros na frente, se houver, e ignorado.)
        """
        values = list(values)
        if values and values[0].numeric and len(values[0].data) <= 4:
            values.pop(0)
        func, mask = values[0].text().upper(), values[1]
        area = values[2] if len(values) > 2 else None
        ssas = []
        for param in values[3:]:
            text = param.data
            name = text[:8].decode('latin-1').strip()
            if text[8:9] == b'(':
                ssas.append((name, (text[9:17].decode('latin-1').strip(),
                                    text[17:19].decode('latin-1'), text[19:len(text) - 1])))
            else:
                ssas.append((name, None))
        pcb = self.pcb(name=mask.data[:8].decode('latin-1').strip())
        if pcb is None:
            status, segment, data = 'TG', '', None
        elif pcb.dbd.gsam:
            status, data = self._gsam(pcb, func, area.data if area else b'')
            segment = ''
        else:
            status, segment, data = pcb.call(self.store.db, self.store.begin, func, ssas,
                                             area.data if area else b'')
        new = bytearray(mask.data)
        keyfb = (pcb.pos or b'') if pcb and not pcb.dbd.gsam else b''
        new[8:12] = ('%02d' % (pcb.level(segment) if pcb else 0) + status).encode()
        if len(new) >= 36:
            new[20:28] = segment.ljust(8).encode()
            new[28:32] = struct.pack('>i', len(keyfb))
            new[36:36 + len(keyfb)] = keyfb[:len(new) - 36]
        updates = [(mask, bytes(new))]
        if data is not None and area is not None:
            updates.append((area, data[:len(area.data)].ljust(len(area.data), b'\x00')))
        return status, updates
