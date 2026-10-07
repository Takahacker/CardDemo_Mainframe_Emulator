"""Catalogo de datasets: clusters VSAM, sequenciais e GDGs.

Os clusters ficam no SQLite (vsam.Store), com o DSN como nome. Os
sequenciais sao arquivos de registros de tamanho fixo, sem delimitador,
em <dados>/dsn/<DSN>; o catalogo guarda LRECL e RECFM. Uma geracao de GDG
e um sequencial chamado <BASE>.GnnnnV00.
"""
import os
import re

from .vsam import NotFound, Store

_GENERATION = re.compile(r'\.G(\d{4})V00$')
_RELATIVE = re.compile(r'^(.*)\(([+-]?\d+)\)$')
_MEMBER = re.compile(r'^(.*)\(([A-Z0-9@#$]+)\)$')


class Catalog(object):
    def __init__(self, data_dir, store=None):
        self.data_dir = data_dir
        self.dsn_dir = os.path.join(data_dir, 'dsn')
        os.makedirs(self.dsn_dir, exist_ok=True)
        self.store = store or Store(os.path.join(data_dir, 'carddemo.db'))
        db = self.store.db
        db.execute('CREATE TABLE IF NOT EXISTS kix_dsn (dsn TEXT PRIMARY KEY,'
                   ' lrecl INT, recfm TEXT)')
        db.execute('CREATE TABLE IF NOT EXISTS kix_gdg (base TEXT PRIMARY KEY, lim INT)')

    def close(self):
        self.store.close()

    # --- consulta ---------------------------------------------------------
    def is_vsam(self, dsn):
        try:
            self.store.path(dsn)
            return True
        except NotFound:
            return False

    def entry(self, dsn):
        """(lrecl, recfm) de um sequencial catalogado, ou None."""
        return self.store.db.execute('SELECT lrecl, recfm FROM kix_dsn WHERE dsn = ?',
                                     (dsn,)).fetchone()

    def exists(self, dsn):
        return self.is_vsam(dsn) or self.entry(dsn) is not None

    def filename(self, dsn):
        return os.path.join(self.dsn_dir, dsn)

    def lrecl(self, dsn):
        if self.is_vsam(dsn):
            return self.store.path(dsn).reclen
        entry = self.entry(dsn)
        if entry is None:
            raise NotFound(dsn)
        return entry[0]

    # --- sequenciais ------------------------------------------------------
    def catalog(self, dsn, lrecl, recfm='FB'):
        self.store.db.execute('INSERT OR REPLACE INTO kix_dsn VALUES (?,?,?)',
                              (dsn, lrecl, recfm))
        if not os.path.exists(self.filename(dsn)):
            open(self.filename(dsn), 'wb').close()

    def delete(self, dsn):
        """Apaga um sequencial; NotFound se nao estiver catalogado."""
        if self.entry(dsn) is None:
            raise NotFound(dsn)
        self.store.db.execute('DELETE FROM kix_dsn WHERE dsn = ?', (dsn,))
        if os.path.exists(self.filename(dsn)):
            os.remove(self.filename(dsn))

    def read(self, dsn):
        """Registros de um dataset (cluster: na ordem da chave)."""
        if self.is_vsam(dsn):
            return self.store.records(dsn)
        lrecl, recfm = self.entry(dsn) or (None, None)
        if lrecl is None:
            raise NotFound(dsn)
        with open(self.filename(dsn), 'rb') as f:
            data = f.read()
        return [data[i:i + lrecl] for i in range(0, len(data), lrecl)]

    def write(self, dsn, records, lrecl=None, recfm='FB'):
        """Grava um sequencial inteiro e o cataloga."""
        lrecl = lrecl or (len(records[0]) if records else 80)
        with open(self.filename(dsn), 'wb') as f:
            for record in records:
                f.write(bytes(record).ljust(lrecl)[:lrecl])
        self.catalog(dsn, lrecl, recfm)

    # --- GDG --------------------------------------------------------------
    def define_gdg(self, base, limit):
        if self.gdg_limit(base) is not None:
            return False
        self.store.db.execute('INSERT INTO kix_gdg VALUES (?,?)', (base, limit))
        return True

    def gdg_limit(self, base):
        row = self.store.db.execute('SELECT lim FROM kix_gdg WHERE base = ?', (base,)).fetchone()
        return row and row[0]

    def generations(self, base):
        """Numeros absolutos das geracoes catalogadas, em ordem."""
        rows = self.store.db.execute('SELECT dsn FROM kix_dsn WHERE dsn LIKE ?',
                                     (base + '.G____V00',))
        return sorted(int(_GENERATION.search(r[0]).group(1)) for r in rows)

    @staticmethod
    def generation_name(base, number):
        return '%s.G%04dV00' % (base, number)

    def roll_off(self, base):
        """Aplica o LIMIT do GDG, apagando as geracoes mais antigas."""
        limit, gens = self.gdg_limit(base), self.generations(base)
        while limit and len(gens) > limit:
            self.delete(self.generation_name(base, gens.pop(0)))


def split_relative(dsn):
    """'A.B(+1)' -> ('A.B', 1); sem geracao relativa -> (dsn, None)."""
    m = _RELATIVE.match(dsn)
    return (m.group(1), int(m.group(2))) if m else (dsn, None)


def split_member(dsn):
    """'A.B(MEMBRO)' -> ('A.B', 'MEMBRO'); senao (dsn, None)."""
    m = _MEMBER.match(dsn)
    return (m.group(1), m.group(2)) if m else (dsn, None)
