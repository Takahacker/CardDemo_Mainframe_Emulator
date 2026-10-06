"""Leitor de mapas BMS (macros DFHMSD / DFHMDI / DFHMDF).

Le os .bms originais e produz, para cada mapa, a lista de campos com
posicao, atributos e o deslocamento de cada campo na area simbolica
(o mesmo layout dos copybooks de app/cpy-bms).
"""
import glob
import os

TIOAPFX = 12
COLORS = {'DEFAULT': 0x00, 'BLUE': 0xF1, 'RED': 0xF2, 'PINK': 0xF3,
          'GREEN': 0xF4, 'TURQUOISE': 0xF5, 'YELLOW': 0xF6, 'NEUTRAL': 0xF7}
HILIGHTS = {'OFF': 0x00, 'BLINK': 0xF1, 'REVERSE': 0xF2, 'UNDERLINE': 0xF4}


class Field(object):
    def __init__(self, name, ops):
        self.name = name
        row, col = ops['POS']
        self.row, self.col = int(row), int(col)
        self.length = int(ops.get('LENGTH', 0))
        self.initial = ops.get('INITIAL')
        attrb = ops.get('ATTRB', ['ASKIP'])
        attrb = set(attrb if isinstance(attrb, list) else [attrb])
        self.ic = 'IC' in attrb
        self.numeric = 'NUM' in attrb
        a = 0
        if 'ASKIP' in attrb:
            a |= 0x30
        elif 'PROT' in attrb:
            a |= 0x20
        if self.numeric:
            a |= 0x10
        if 'BRT' in attrb:
            a |= 0x08
        elif 'DRK' in attrb:
            a |= 0x0C
        if 'FSET' in attrb:
            a |= 0x01
        self.attr = a
        self.color = COLORS.get(ops.get('COLOR', 'DEFAULT'), 0)
        self.hilight = HILIGHTS.get(ops.get('HILIGHT', 'OFF'), 0)
        just = ops.get('JUSTIFY')
        just = set(just if isinstance(just, list) else [just]) if just else set()
        self.right = 'RIGHT' in just or (self.numeric and 'LEFT' not in just)
        self.zero = 'ZERO' in just or (self.numeric and 'BLANK' not in just)
        self.offset = None          # inicio do campo (L) na area simbolica

    def address(self, cols=80):
        """Endereco de buffer do byte de atributo."""
        return (self.row - 1) * cols + (self.col - 1)


class Map(object):
    def __init__(self, name, mapset, ops, ext):
        self.name, self.mapset = name, mapset
        size = ops.get('SIZE', ['24', '80'])
        self.rows, self.cols = int(size[0]), int(size[1])
        self.ctrl = ops.get('CTRL')
        self.ext = ext              # bytes de atributo estendido por campo
        self.fields = []
        self.length = TIOAPFX

    def add(self, field):
        if field.name:
            field.offset = self.length
            self.length += 3 + self.ext + field.length
        self.fields.append(field)

    def named(self):
        return [f for f in self.fields if f.name]


def _statements(text):
    """Junta as linhas de continuacao (coluna 72) em instrucoes completas."""
    stmt, in_quote = None, False
    for line in text.splitlines():
        line = line.rstrip('\n')
        if stmt is None:
            if not line.strip() or line.startswith('*'):
                continue
            body, start = line[:71], 0
        else:
            body, start = line[:71], 15
        cont = len(line) > 71 and line[71] != ' '
        piece = body[start:]
        for i, c in enumerate(piece):
            if c == "'":
                in_quote = not in_quote
        if not (cont and in_quote):
            piece = piece.rstrip()
        stmt = piece if stmt is None else stmt + piece
        if not cont:
            yield stmt
            stmt, in_quote = None, False
    if stmt:
        yield stmt


def _split(operands):
    """'A=1,B=(X,Y),C='a,b'' -> dict, com listas para valores em parenteses."""
    parts, depth, quote, cur = [], 0, False, ''
    for c in operands:
        if c == "'":
            quote = not quote
        if not quote:
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
            elif c == ',' and depth == 0:
                parts.append(cur)
                cur = ''
                continue
            elif c == ' ' and depth == 0:
                break               # o resto da linha e comentario
        cur += c
    if cur:
        parts.append(cur)
    ops = {}
    for p in parts:
        key, _, val = p.partition('=')
        if val.startswith("'"):
            val = val[1:-1].replace("''", "'").replace('&&', '&')
        elif val.startswith('('):
            val = [v.strip() for v in val[1:-1].split(',')]
        ops[key.strip()] = val
    return ops


def parse(text):
    """Devolve {nome do mapa: Map} de um fonte BMS."""
    maps, mapset, ext, current = {}, None, 0, None
    for stmt in _statements(text):
        label = '' if stmt[0] == ' ' else stmt.split()[0]
        rest = stmt[len(label):].lstrip()
        opcode, _, operands = rest.partition(' ')
        ops = _split(operands.lstrip())
        if opcode == 'DFHMSD':
            if ops.get('TYPE') == 'FINAL':
                continue
            mapset = label
            ext = 4 if (ops.get('EXTATT') == 'YES' or 'DSATTS' in ops) else 0
        elif opcode == 'DFHMDI':
            map_ext = 4 if 'DSATTS' in ops else ext
            current = maps[label] = Map(label, mapset, ops, map_ext)
        elif opcode == 'DFHMDF':
            current.add(Field(label, ops))
    return maps


def load_all(bms_dir):
    """Le todos os .bms de um diretorio: {(mapset, mapa): Map}."""
    result = {}
    for path in sorted(glob.glob(os.path.join(bms_dir, '*.bms'))):
        with open(path, encoding='latin-1') as f:
            for m in parse(f.read()).values():
                result[(m.mapset, m.name)] = m
    return result
