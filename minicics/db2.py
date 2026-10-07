"""Db2 minimo: executa o EXEC SQL dos programas sobre o SQLite.

O tradutor (translate.emit_sql) manda cada comando como a spec
"SQL|tipo|cursor|assinatura|texto" mais a SQLCA e as variaveis host. As
tabelas ficam no mesmo banco dos arquivos VSAM; o esquema vira prefixo
(CARDDEMO.X -> CARDDEMO_X). So o subconjunto que o CardDemo usa.
"""
import re
import sqlite3
import struct

# Clausulas de armazenamento do Db2, sem equivalente aqui
_SKIP = re.compile(r'^\s*(SET\s+CURRENT|GRANT|REVOKE|COMMIT|CREATE\s+(DATABASE|TABLESPACE|'
                   r'STOGROUP)|DROP\s+(DATABASE|TABLESPACE|STOGROUP)|LABEL|COMMENT)\b', re.I)


def prepare(db):
    """Funcoes e tabelas de sistema que os comandos do CardDemo esperam."""
    db.create_function('REPEAT', 2, lambda text, n: (text or '') * int(n))
    db.create_function('TIMESTAMP_FORMAT', 2, lambda text, fmt: text)
    db.create_function('KIXCHAR', 2, lambda value, n: str(value if value is not None else '')
                       .ljust(int(n))[:int(n)])
    db.execute('PRAGMA foreign_keys = ON')
    db.execute('PRAGMA case_sensitive_like = ON')
    db.execute('CREATE TABLE IF NOT EXISTS SYSIBM_SYSDUMMY1 (IBMREQD TEXT)')
    if not db.execute('SELECT 1 FROM SYSIBM_SYSDUMMY1').fetchone():
        db.execute("INSERT INTO SYSIBM_SYSDUMMY1 VALUES ('Y')")


def _cast_char(sql):
    """CAST(x AS CHAR(n)) completa com brancos no Db2: vira KIXCHAR(x, n)."""
    while True:
        m = re.search(r'\bCAST\s*\(', sql, re.I)
        if not m:
            return sql
        depth, i = 1, m.end()
        while i < len(sql) and depth:
            depth += {'(': 1, ')': -1}.get(sql[i], 0)
            i += 1
        inner = sql[m.end():i - 1]
        t = re.search(r'\s+AS\s+(?:VAR)?CHAR\s*\(\s*(\d+)\s*\)\s*$', inner, re.I)
        if t:
            new = 'KIXCHAR(%s, %s)' % (inner[:t.start()], t.group(1))
        else:
            new = 'KIX_CAST(' + inner + ')'
        sql = sql[:m.start()] + new + sql[i:]
        if not t:
            return sql.replace('KIX_CAST(', 'CAST(')


def dialect(sql):
    """Db2 -> SQLite: esquema como prefixo e funcoes equivalentes."""
    sql = re.sub(r'\b([A-Z][A-Z0-9_]*)\.([A-Z][A-Z0-9_]*)\b', r'\1_\2', sql)
    sql = re.sub(r'(?i)\bCURRENT\s+(DATE|TIME|TIMESTAMP)\b', r'CURRENT_\1', sql)
    sql = re.sub(r'(?i)\bFETCH\s+FIRST\s+(\d+)\s+ROWS?\s+ONLY\b', r'LIMIT \1', sql)
    sql = re.sub(r'(?i)\bFOR\s+(FETCH|READ)\s+ONLY\b|\bWITH\s+(UR|CS|RS|RR)\b', '', sql)
    return _cast_char(sql)


def ddl(sql):
    """Ajusta um comando DDL/DML avulso (DSNTEP2 / DSNTIAD); None = ignorar."""
    if _SKIP.match(sql):
        return None
    sql = dialect(sql)
    if re.match(r'\s*CREATE\s+TABLE\b', sql, re.I):
        sql = re.sub(r'\)\s*IN\s+[\w.]+(\s+CCSID\s+\w+)?\s*$', ')', sql, flags=re.I | re.S)
        sql = re.sub(r'\s+CCSID\s+\w+\s*$', '', sql, flags=re.I)
    elif re.match(r'\s*CREATE\s+(UNIQUE\s+)?INDEX\b', sql, re.I):
        sql = re.sub(r'(?is)^(.*?\([^()]*\)).*$', r'\1', sql)
        sql = re.sub(r'(?i)\bINDEX\s+IF NOT EXISTS\b', 'INDEX', sql)
        sql = re.sub(r'(?i)\bINDEX\b', 'INDEX IF NOT EXISTS', sql, 1)
    return sql


def add_foreign_key(db, sql):
    """ALTER TABLE t FOREIGN KEY ...: o SQLite so aceita a chave no CREATE.

    Recria a tabela (com os dados e os indices) acrescentando a restricao.
    """
    m = re.match(r'\s*ALTER\s+TABLE\s+(\w+)\s+(?:ADD\s+)?(FOREIGN\s+KEY\b.*)$', sql, re.I | re.S)
    table, clause = m.group(1), m.group(2)
    rows = db.execute("SELECT type, sql FROM sqlite_master WHERE tbl_name = ? AND sql NOT NULL",
                      (table,)).fetchall()
    create = next(s for t, s in rows if t == 'table')
    create = create[:create.rindex(')')] + ', ' + clause + ')'
    db.execute('ALTER TABLE %s RENAME TO KIX_OLD' % table)
    for t, s in rows:
        if t == 'index':
            db.execute('DROP INDEX IF EXISTS %s' % re.search(r'INDEX\s+(?:IF NOT EXISTS\s+)?(\w+)',
                                                              s, re.I).group(1))
    db.execute(create)
    db.execute('INSERT INTO %s SELECT * FROM KIX_OLD' % table)
    db.execute('DROP TABLE KIX_OLD')
    for t, s in rows:
        if t == 'index':
            db.execute(s)


def sqlcode_of(error, sql):
    text = str(error)
    if 'UNIQUE constraint' in text or 'PRIMARY KEY' in text:
        return -803
    if 'FOREIGN KEY' in text:
        return -532 if sql.lstrip().upper().startswith('DELETE') else -530
    if 'no such table' in text:
        return -204
    if 'no such column' in text:
        return -206
    if 'syntax error' in text:
        return -104
    if 'locked' in text:
        return -911
    return -901


def sqlca(code, rows=0, message=''):
    message = message.encode('latin-1', 'replace')[:70]
    state = '00000' if code == 0 else '02000' if code == 100 else '58004'
    return (b'SQLCA   ' + struct.pack('>ii', 136, code)
            + struct.pack('>h', len(message)) + message.ljust(70) + b'KIXDB2  '
            + struct.pack('>6i', 0, 0, rows, 0, 0, 0) + b' ' * 11 + state.encode())


class Session(object):
    """Cursores abertos por uma tarefa (ou por um passo batch)."""

    def __init__(self):
        self.cursors = {}

    def execute(self, db, begin, spec, params):
        """Executa um comando; devolve [(parametro, valor a gravar)].

        params[0] e a SQLCA; os demais seguem a assinatura (entradas e
        depois saidas). `begin` abre a unidade de trabalho antes de gravar.
        """
        _, kind, cursor, sig, sql = spec.split('|', 4)
        hosts = params[1:]
        inputs = [self._input(p, s) for p, s in zip(hosts, sig) if s in 'iI']
        outputs = [(p, s) for p, s in zip(hosts, sig) if s in 'oO']
        code, rows, row, message = 0, 0, None, ''
        try:
            if kind == 'OPEN':
                self.cursors[cursor] = iter(db.execute(dialect(sql), inputs).fetchall())
            elif kind == 'CLOSE':
                code = 0 if self.cursors.pop(cursor, None) is not None else -501
            elif kind == 'FETCH':
                if cursor not in self.cursors:
                    code = -501
                else:
                    row = next(self.cursors[cursor], None)
                    code = 0 if row else 100
            elif sql.lstrip().upper().startswith('SELECT'):
                found = db.execute(dialect(sql), inputs).fetchmany(2)
                row = found[0] if found else None
                code = 100 if not found else -811 if len(found) > 1 else 0
            else:
                begin()
                rows = db.execute(dialect(sql), inputs).rowcount
                code = 100 if rows == 0 and not sql.lstrip().upper().startswith('INSERT') else 0
        except sqlite3.Error as e:
            code, message = sqlcode_of(e, sql), str(e)
        updates = [(params[0], sqlca(code, rows, message))]
        if row is not None and code == 0:
            for (param, s), value in zip(outputs, row):
                updates.append((param, self._output(param, s, value)))
        return updates

    @staticmethod
    def _input(param, s):
        if s == 'I':                    # VARCHAR: tamanho (2 bytes) + texto
            (length,) = struct.unpack_from('>h', param.data, 0)
            return param.data[2:2 + max(length, 0)].decode('latin-1')
        if param.numeric:
            return param.value / 10.0 ** param.scale if param.scale else param.value
        return param.data.decode('latin-1').rstrip(' \x00')

    @staticmethod
    def _output(param, s, value):
        if s == 'O':
            text = str(value if value is not None else '').encode('latin-1', 'replace')
            text = text[:len(param.data) - 2]
            return struct.pack('>h', len(text)) + text.ljust(len(param.data) - 2)
        if param.numeric:
            return int(round(float(value or 0) * 10 ** param.scale))
        return str(value if value is not None else '')


def run_script(db, text, log):
    """Roda os comandos (separados por ';') de um membro de controle."""
    lines = [re.sub(r'--.*$', '', l[:72]) for l in text]
    script = re.sub(r'/\*.*?\*/', ' ', '\n'.join(lines), flags=re.S)
    worst = 0
    for statement in script.split(';'):
        # (os membros de carga do CardDemo trazem o COMMIT sem ';' antes)
        statement = re.sub(r'(?i)\s+COMMIT$', '', ' '.join(statement.split()))
        if not statement:
            continue
        sql = ddl(statement)
        if sql is None:
            continue
        try:
            if re.match(r'\s*ALTER\s+TABLE\s+\w+\s+(ADD\s+)?FOREIGN\s+KEY', sql, re.I):
                add_foreign_key(db, sql)
                rows = 0
            else:
                rows = max(db.execute(sql).rowcount, 0)
            log(' %s' % statement[:100])
            log('DSNT400I SQLCODE = 000, %d linha(s)' % rows)
        except sqlite3.Error as e:
            code = sqlcode_of(e, sql)
            if 'already exists' in str(e):
                code = -601
            log(' %s' % statement[:100])
            log('DSNT408I SQLCODE = %d, %s' % (code, e))
            worst = max(worst, 4 if code == -601 else 8)
    return worst
