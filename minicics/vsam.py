"""Catalogo e arquivos VSAM (KSDS e indices alternativos) sobre SQLite.

Cada cluster e uma tabela (k = chave primaria, r = registro). Um caminho
(path) de indice alternativo e so outra forma de ordenar a mesma tabela.
"""
import sqlite3


class NotFound(Exception):
    pass


class Duplicate(Exception):
    pass


class Path(object):
    def __init__(self, name, base, reclen, keyoff, keylen, primary):
        self.name, self.base, self.reclen = name, base, reclen
        self.keyoff, self.keylen, self.primary = keyoff, keylen, primary
        self.table = '"%s"' % base
        self.expr = 'k' if primary else 'substr(r, %d, %d)' % (keyoff + 1, keylen)

    def key_of(self, record):
        return bytes(record[self.keyoff:self.keyoff + self.keylen])


class Store(object):
    def __init__(self, filename):
        self.db = sqlite3.connect(filename, isolation_level=None, timeout=30)
        self.db.execute('CREATE TABLE IF NOT EXISTS kix_catalog (name TEXT PRIMARY KEY,'
                        ' base TEXT, reclen INT, keyoff INT, keylen INT, prim INT)')
        self._paths = {}

    def close(self):
        self.db.close()

    # --- catalogo (o que o IDCAMS DEFINE faria) ---------------------------
    def define_cluster(self, name, reclen, keyoff, keylen):
        self.db.execute('DROP TABLE IF EXISTS "%s"' % name)
        self.db.execute('CREATE TABLE "%s" (k BLOB PRIMARY KEY, r BLOB) WITHOUT ROWID' % name)
        self.db.execute('DELETE FROM kix_catalog WHERE base = ?', (name,))
        self.db.execute('INSERT INTO kix_catalog VALUES (?,?,?,?,?,1)',
                        (name, name, reclen, keyoff, keylen))
        self._paths.clear()

    def define_path(self, name, base, keyoff, keylen):
        reclen = self.path(base).reclen
        self.db.execute('INSERT OR REPLACE INTO kix_catalog VALUES (?,?,?,?,?,0)',
                        (name, base, reclen, keyoff, keylen))
        self.db.execute('CREATE INDEX IF NOT EXISTS "%s_ix" ON "%s" (substr(r, %d, %d))'
                        % (name, base, keyoff + 1, keylen))
        self._paths.clear()

    def path(self, name):
        if name not in self._paths:
            row = self.db.execute('SELECT name, base, reclen, keyoff, keylen, prim '
                                  'FROM kix_catalog WHERE name = ?', (name,)).fetchone()
            if not row:
                raise NotFound(name)
            self._paths[name] = Path(*row)
        return self._paths[name]

    def names(self):
        return [r[0] for r in self.db.execute('SELECT name FROM kix_catalog ORDER BY name')]

    def count(self, name):
        return self.db.execute('SELECT count(*) FROM %s' % self.path(name).table).fetchone()[0]

    # --- acesso ----------------------------------------------------------
    def seek(self, name, key, op, pk=None):
        """Primeiro registro cuja chave satisfaz `op` (==, >=, >, <=, <).

        Devolve (chave no caminho, chave primaria, registro) ou None. `pk`
        desempata chaves alternativas duplicadas ao continuar um browse.
        """
        p = self.path(name)
        desc = op in ('<', '<=')
        order = '%s %s, k %s' % (p.expr, 'DESC' if desc else 'ASC', 'DESC' if desc else 'ASC')
        if pk is not None and op != '==':
            where, args = '(%s, k) %s (?, ?)' % (p.expr, op), (key, pk)
        else:
            where, args = '%s %s ?' % (p.expr, op), (key,)
        row = self.db.execute('SELECT %s, k, r FROM %s WHERE %s ORDER BY %s LIMIT 1'
                              % (p.expr, p.table, where, order), args).fetchone()
        return row and tuple(bytes(x) for x in row)

    def write(self, name, record, replace=False):
        base = self.path(self.path(name).base)
        record = bytes(record).ljust(base.reclen, b'\x00')[:base.reclen]
        key = base.key_of(record)
        if replace:
            cur = self.db.execute('UPDATE %s SET r = ? WHERE k = ?' % base.table, (record, key))
            if cur.rowcount == 0:
                raise NotFound(key)
            return
        try:
            self.db.execute('INSERT INTO %s VALUES (?, ?)' % base.table, (key, record))
        except sqlite3.IntegrityError:
            raise Duplicate(key)

    def delete(self, name, pk):
        cur = self.db.execute('DELETE FROM %s WHERE k = ?' % self.path(name).table, (pk,))
        if cur.rowcount == 0:
            raise NotFound(pk)
