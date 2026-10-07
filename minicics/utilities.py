"""Utilitarios de JCL: IDCAMS, SORT, IEBGENER, IEFBR14 e SDSF.

Cada um recebe o contexto do passo (jcl.StepContext) e devolve o codigo
de retorno. So esta implementado o subconjunto que os jobs do CardDemo
usam.
"""
import re

from . import db2
from .vsam import Duplicate, NotFound

_COMPARE = {'EQ': lambda a, b: a == b, 'NE': lambda a, b: a != b,
            'GT': lambda a, b: a > b, 'GE': lambda a, b: a >= b,
            'LT': lambda a, b: a < b, 'LE': lambda a, b: a <= b}
_COMPARE['='] = _COMPARE['EQ']


# --- IDCAMS ----------------------------------------------------------------
def _idcams_commands(lines):
    """Junta as continuacoes ('-' no fim) e tira os comentarios /* */."""
    text, cur = [], ''
    for line in lines:
        line = re.sub(r'/\*.*?\*/', ' ', line[:72]).rstrip()
        if line.endswith('-'):
            cur += line[:-1] + ' '
            continue
        cur += line
        if cur.strip():
            text.append(' '.join(cur.split()))
        cur = ''
    if cur.strip():
        text.append(' '.join(cur.split()))
    return text


def _arg(command, keyword):
    """Valores de KEYWORD(a b) em um comando: ['a', 'b'] ou None."""
    m = re.search(r'\b(?:%s)\s*\(\s*([^()]*?)\s*\)' % keyword, command)
    return re.split(r'[\s,]+', m.group(1)) if m else None


class Idcams(object):
    def __init__(self, ctx):
        self.ctx, self.catalog, self.store = ctx, ctx.catalog, ctx.catalog.store
        self.lastcc = self.maxcc = 0

    def run(self):
        for command in _idcams_commands(self.ctx.text('SYSIN')):
            self.execute(command)
        return self.maxcc

    def execute(self, command):
        m = re.match(r'IF\s+(LASTCC|MAXCC)\s*(=|[A-Z]{2})\s*(\d+)\s+THEN\s+(.*)$', command)
        if m:
            value = self.lastcc if m.group(1) == 'LASTCC' else self.maxcc
            if _COMPARE[m.group(2)](value, int(m.group(3))):
                self.execute(m.group(4))
            return
        m = re.match(r'SET\s+(LASTCC|MAXCC)\s*=\s*(\d+)', command)
        if m:
            if m.group(1) == 'MAXCC':
                self.maxcc = int(m.group(2))
            self.lastcc = int(m.group(2))
            return
        self.ctx.log(' ' + command)
        verb = command.split()[0]
        handler = getattr(self, 'do_' + verb.lower(), None)
        if handler is None:
            self.ctx.log('IDC3200I comando %s nao suportado' % verb)
            cc = 16
        else:
            cc = handler(command)
        self.lastcc, self.maxcc = cc, max(self.maxcc, cc)
        self.ctx.log('IDC0001I LASTCC=%d' % cc)

    def do_delete(self, command):
        name = command.split()[1].strip('()')
        try:
            if self.catalog.is_vsam(name):
                if self.store.path(name).primary:
                    self.store.delete_cluster(name)
                else:
                    self.store.delete_path(name)
            else:
                self.catalog.delete(name)
        except NotFound:
            self.ctx.log('IDC3012I ENTRY %s NOT FOUND' % name)
            return 8
        return 0

    def do_define(self, command):
        kind = command.split()[1].upper()
        name = _arg(command, 'NAME')[0]
        if kind in ('GENERATIONDATAGROUP', 'GDG'):
            limit = int((_arg(command, 'LIMIT') or ['255'])[0])
            return 0 if self.catalog.define_gdg(name, limit) else 12
        if self.catalog.exists(name):
            self.ctx.log('IDC3013I DUPLICATE DATA SET NAME %s' % name)
            return 12
        try:
            if kind in ('CLUSTER', 'CL'):
                if re.search(r'\b(NONINDEXED|NUMBERED|LINEAR)\b', command):
                    self.ctx.log('IDC3200I so clusters KSDS sao suportados')
                    return 12
                keylen, keyoff = (int(x) for x in _arg(command, 'KEYS'))
                reclen = int(_arg(command, 'RECORDSIZE|RECSZ')[1])
                self.store.define_cluster(name, reclen, keyoff, keylen)
            elif kind in ('ALTERNATEINDEX', 'AIX'):
                keylen, keyoff = (int(x) for x in _arg(command, 'KEYS'))
                self.store.define_path(name, _arg(command, 'RELATE|REL')[0], keyoff, keylen)
            elif kind == 'PATH':
                aix = self.store.path(_arg(command, 'PATHENTRY|PENT')[0])
                self.store.define_path(name, aix.base, aix.keyoff, aix.keylen)
            else:
                self.ctx.log('IDC3200I DEFINE %s nao suportado' % kind)
                return 16
        except NotFound as e:
            self.ctx.log('IDC3012I ENTRY %s NOT FOUND' % e)
            return 12
        return 0

    def do_bldindex(self, command):
        # o indice alternativo e um indice do SQLite: ja nasce construido
        for keyword in ('INDATASET|IDS', 'OUTDATASET|ODS'):
            name = _arg(command, keyword)
            if name and not self.catalog.is_vsam(name[0]):
                self.ctx.log('IDC3012I ENTRY %s NOT FOUND' % name[0])
                return 12
        return 0

    def _dataset(self, command, dd_keyword, dsn_keyword):
        dd = _arg(command, dd_keyword)
        if dd:
            if not self.ctx.has(dd[0]):
                raise NotFound('DD ' + dd[0])
            return self.ctx.alloc(dd[0])
        dsn = _arg(command, dsn_keyword)[0]
        if not self.catalog.exists(dsn):
            raise NotFound(dsn)
        from .jcl import Alloc
        return Alloc('vsam' if self.catalog.is_vsam(dsn) else 'seq', dsn,
                     lrecl=self.catalog.lrecl(dsn))

    def do_repro(self, command):
        try:
            source = self._dataset(command, 'INFILE|IFILE', 'INDATASET|IDS')
            target = self._dataset(command, 'OUTFILE|OFILE', 'OUTDATASET|ODS')
        except NotFound as e:
            self.ctx.log('IDC3300I %s nao encontrado' % e)
            return 12
        if source.kind == 'instream':
            records = [l.ljust(80).encode('latin-1') for l in source.lines]
        elif source.kind == 'dummy':
            records = []
        else:
            records = self.catalog.read(source.dsn)
        cc = 0
        if target.kind == 'vsam':
            self.store.begin()
            written = 0
            for record in records:
                try:
                    self.store.write(target.dsn, record)
                    written += 1
                except Duplicate:
                    cc = 8
            self.store.commit()
            if cc:
                self.ctx.log('IDC3308I %d registros com chave duplicada rejeitados'
                             % (len(records) - written))
        elif target.kind == 'seq':
            target.lrecl = target.lrecl or source.lrecl
            self.catalog.write(target.dsn, records, target.lrecl, target.recfm)
            written = len(records)
        else:
            written = 0
        self.ctx.log('IDC0005I NUMBER OF RECORDS PROCESSED WAS %d' % written)
        return cc

    def do_listcat(self, command):
        for name in self.store.names():
            self.ctx.log(' CLUSTER/PATH ' + name)
        return 0

    def do_verify(self, command):
        return 0


def idcams(ctx):
    return Idcams(ctx).run()


# --- SORT ------------------------------------------------------------------
_FORMATS = ('CH', 'ZD', 'BI', 'PD', 'AC', 'FS', 'UFF', 'SFF')


def zoned(data):
    """Decimal zonado (sinal sobreposto no ultimo byte, estilo EBCDIC em ASCII)."""
    text = bytes(data).decode('latin-1').strip()
    if not text:
        return 0
    last, sign = text[-1], 1
    if last in '{ABCDEFGHI':
        text = text[:-1] + str('{ABCDEFGHI'.index(last))
    elif last in '}JKLMNOPQR':
        text, sign = text[:-1] + str('}JKLMNOPQR'.index(last)), -1
    if text[:1] in '+-':
        sign, text = (-1 if text[0] == '-' else 1) * sign, text[1:]
    digits = re.sub(r'\D', '', text)
    return sign * int(digits or 0)


def _packed(data):
    digits = ''.join('%02x' % b for b in data)
    return (-1 if digits[-1:] in 'bd' else 1) * int(digits[:-1] or 0)


def _value(record, pos, length, fmt):
    data = record[pos - 1:pos - 1 + length]
    if fmt in ('ZD', 'FS', 'UFF', 'SFF'):
        return zoned(data)
    if fmt == 'PD':
        return _packed(data)
    return data


def _tokens(text):
    """Operandos de um cartao do SORT, sem os parenteses de agrupamento."""
    out, cur, quote, depth = [], '', False, 0
    for c in text:
        if c == "'":
            quote = not quote
        if not quote:
            if c == '(' and not cur.endswith('='):
                continue
            if c == '(':
                depth += 1
            elif c == ')':
                if not depth:
                    continue
                depth -= 1
            elif c in ', ' and not depth:
                if cur:
                    out.append(cur)
                cur = ''
                continue
        cur += c
    if cur:
        out.append(cur)
    return out


def _sort_cards(lines):
    """Cartoes SYSIN do SORT: {'SORT': 'FIELDS=(...)', 'INCLUDE': ..., ...}."""
    cards, cur = {}, ''
    for line in lines:
        line = line[:71].strip()
        if not line or line.startswith('*'):
            continue
        cur += line
        if cur.endswith(','):
            continue
        verb, _, rest = cur.partition(' ')
        cards[verb.upper()] = rest.strip()
        cur = ''
    return cards


class Sort(object):
    def __init__(self, ctx):
        self.ctx = ctx
        self.symbols = {}
        for line in ctx.text('SYMNAMES'):
            line = line.strip()
            if not line or line.startswith('*'):
                continue
            name, _, rest = line.partition(',')
            m = re.match(r"([CX]'[^']*'|\S+)", rest)
            self.symbols[name.strip()] = _tokens(m.group(1)) if m else []

    def expand(self, text):
        out = []
        for token in _tokens(text):
            m = re.match(r'(\d+:)(.+)$', token)
            prefix, name = (m.group(1), m.group(2)) if m else ('', token)
            if name in self.symbols:
                values = list(self.symbols[name])
                values[0] = prefix + values[0]
                out.extend(values)
            else:
                out.append(token)
        return out

    def run(self):
        cards = _sort_cards(self.ctx.text('SYSIN'))
        records = self.ctx.read('SORTIN')
        for verb, keep in (('INCLUDE', True), ('OMIT', False)):
            if verb in cards:
                test = self.condition(cards[verb].split('=', 1)[1])
                records = [r for r in records if test(r) == keep]
        fields = cards.get('SORT', cards.get('MERGE', 'FIELDS=COPY')).split('=', 1)[1]
        if fields.strip('()').upper() != 'COPY':
            records = self.sort(records, self.expand(fields))
        for verb in ('OUTREC', 'BUILD'):
            if verb in cards:
                build = self.outrec(self.expand(cards[verb].split('=', 1)[1]))
                records = [build(r) for r in records]
        self.ctx.write('SORTOUT', records, len(records[0]) if records else None)
        self.ctx.log('ICE054I RECORDS - IN: %d, OUT: %d' % (len(self.ctx.read('SORTIN')),
                                                          len(records)))
        return 0

    @staticmethod
    def sort(records, tokens):
        keys, i = [], 0
        while i + 1 < len(tokens):
            pos, length = int(tokens[i]), int(tokens[i + 1])
            i += 2
            fmt = 'CH'
            if i < len(tokens) and tokens[i] in _FORMATS:
                fmt, i = tokens[i], i + 1
            order = tokens[i] if i < len(tokens) else 'A'
            i += 1
            keys.append((pos, length, fmt, order))
        for pos, length, fmt, order in reversed(keys):      # ordenacao estavel, da
            records = sorted(records,                       # ultima chave para a primeira
                             key=lambda r: _value(r, pos, length, fmt), reverse=order == 'D')
        return records

    def _operand(self, tokens, i):
        """Um operando de COND: campo (pos, tam, fmt) ou constante."""
        token = tokens[i]
        if re.match(r"C'", token):
            return ('const', token[2:-1].encode('latin-1')), i + 1
        if i + 2 < len(tokens) and tokens[i + 2] in _FORMATS:
            return ('field', int(token), int(tokens[i + 1]), tokens[i + 2]), i + 3
        return ('const', int(token)), i + 1

    def condition(self, text):
        tokens, i, groups = self.expand(text), 0, [[]]
        while i < len(tokens):
            left, i = self._operand(tokens, i)
            op = tokens[i]
            right, i = self._operand(tokens, i + 1)
            groups[-1].append((left, op, right))
            if i < len(tokens):
                if tokens[i] in ('OR', '|'):
                    groups.append([])
                i += 1

        def get(operand, record, like):
            if operand[0] == 'field':
                return _value(record, *operand[1:])
            value = operand[1]
            if isinstance(value, bytes) and like[0] == 'field' and like[3] == 'CH':
                value = value.ljust(like[2])
            return value

        def test(record):
            return any(all(_COMPARE[op](get(a, record, b), get(b, record, a))
                           for a, op, b in group) for group in groups)
        return test

    @staticmethod
    def outrec(tokens):
        items, i = [], 0                # (coluna ou None, funcao do registro)
        while i < len(tokens):
            token, column = tokens[i], None
            m = re.match(r'(\d+):(.+)$', token)
            if m:
                column, token = int(m.group(1)), m.group(2)
            i += 1
            m = re.match(r'(\d*)([XZ])$', token)
            if m:
                fill = (b' ' if m.group(2) == 'X' else b'\x00') * int(m.group(1) or 1)
                items.append((column, lambda r, fill=fill: fill))
            elif token.startswith("C'"):
                items.append((column, lambda r, lit=token[2:-1].encode('latin-1'): lit))
            else:
                pos, length, fmt, mask = int(token), int(tokens[i]), 'CH', None
                i += 1
                if i < len(tokens) and tokens[i] in _FORMATS:
                    fmt, i = tokens[i], i + 1
                if i < len(tokens) and tokens[i].startswith('EDIT='):
                    mask, i = tokens[i][5:].strip('()'), i + 1
                items.append((column, lambda r, a=(pos, length, fmt), mask=mask:
                              _edit(_value(r, *a), mask) if mask else r[a[0] - 1:a[0] - 1 + a[1]]))

        def build(record):
            out = b''
            for column, get in items:
                if column:
                    out = out.ljust(column - 1)
                out += get(record)
            return out
        return build


def _edit(value, mask):
    """EDIT=(mascara): T = digito, I = digito com supressao de zero."""
    places = sum(c in 'TI' for c in mask)
    digits = iter('%0*d' % (places, abs(int(value))))
    out, significant = '', False
    for c in mask:
        if c in 'TI':
            d = next(digits)
            significant = significant or c == 'T' or d != '0'
            out += d if significant else ' '
        else:
            out += c if significant else ' '
    return out.encode('latin-1')


def sort(ctx):
    return Sort(ctx).run()


# --- os demais ---------------------------------------------------------------
def iebgener(ctx):
    records = ctx.read('SYSUT1')
    ctx.write('SYSUT2', records, len(records[0]) if records else None)
    ctx.log('IEB1035I %d registros copiados' % len(records))
    return 0


def iefbr14(ctx):
    return 0                            # so as disposicoes dos DDs importam


def sdsf(ctx):
    # CEMT SET FILE OPEN/CLOSED: a regiao online compartilha o mesmo banco,
    # nao ha arquivo para fechar.
    for line in ctx.text('ISFIN'):
        ctx.log(' ' + line.rstrip())
    return 0


# --- IKJEFT01 (TSO em batch): processador de comandos DSN do Db2 -------------
def ikjeft01(ctx):
    """Atende 'RUN PROGRAM(x)': DSNTEP2/DSNTEP4/DSNTIAD, DSNTIAUL ou um programa."""
    commands = ' '.join(l[:72].rstrip().rstrip('-') for l in ctx.text('SYSTSIN'))
    programs = re.findall(r'RUN\s+PROGRAM\s*\(\s*(\w+)\s*\)', commands, re.I)
    db = ctx.catalog.store.db
    db2.prepare(db)
    rc = 0
    for program in programs:
        program = program.upper()
        ctx.log(' DSN RUN PROGRAM(%s)' % program)
        if program in ('DSNTEP2', 'DSNTEP4', 'DSNTIAD'):
            rc = max(rc, db2.run_script(db, ctx.text('SYSIN'), ctx.log))
        elif program == 'DSNTIAUL':
            script = ' '.join(l[:72] for l in ctx.text('SYSIN'))
            for n, statement in enumerate(s for s in script.split(';') if s.strip()):
                rows = db.execute(db2.dialect(' '.join(statement.split()))).fetchall()
                records = [''.join(str(v) for v in row).encode('latin-1', 'replace')
                           for row in rows]
                ctx.write('SYSREC%02d' % n, records, max(map(len, records)) if records else None)
                ctx.log('DSNT495I %d linhas descarregadas em SYSREC%02d' % (len(records), n))
        else:
            code, abend = ctx.job._run_cobol(ctx, program)
            if abend:
                ctx.log('programa %s: ABEND %s' % (program, abend))
                return 12
            rc = max(rc, code)
    if not programs:
        ctx.log(' ' + commands.strip()[:100])   # FREE / BIND: nada a fazer aqui
    return rc


# --- DFSRRC00: controlador de regiao do IMS ----------------------------------
def dfsrrc00(ctx):
    """PARM='BMP|DLI|DBB,programa,PSB': roda o programa com os PCBs do PSB."""
    parm = [p.strip() for p in ctx.parm.strip('()').split(',')]
    if len(parm) < 3 or parm[0] not in ('BMP', 'DLI', 'DBB'):
        ctx.log('DFS0000I regiao %s nao suportada (so BMP, DLI e DBB)' % ctx.parm)
        return 12
    code, abend = ctx.job._run_cobol(ctx, parm[1], (parm[2], parm[0] == 'BMP'))
    if abend:
        ctx.log('DFS0000I programa %s: ABEND %s' % (parm[1], abend))
        return 12
    return code


PROGRAMS = {'DFSRRC00': dfsrrc00,'IKJEFT01': ikjeft01, 'IKJEFT1A': ikjeft01, 'IKJEFT1B': ikjeft01,'IDCAMS': idcams, 'SORT': sort, 'DFSORT': sort, 'ICEMAN': sort,
            'IEBGENER': iebgener, 'ICEGENER': iebgener, 'IEFBR14': iefbr14, 'SDSF': sdsf}
