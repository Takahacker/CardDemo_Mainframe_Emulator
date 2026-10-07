"""Leitor e executor de JCL: o lado batch do mini-CICS.

Faz o papel do JES + iniciador: le um job, expande os procedimentos,
aloca os datasets de cada passo (catalogo em datasets.py), executa o
programa (utilitario em utilities.py ou COBOL via batch.py) e aplica as
disposicoes. A saida (SYSOUT) de cada job vai para <dados>/jobs.
"""
import glob
import os
import re
import tempfile

from . import batch, config, dli, utilities
from .datasets import Catalog, split_member, split_relative
from .vsam import NotFound

_SYMBOL = re.compile(r'&([A-Z0-9@#$]+)\.?')
# Parametros do EXEC que nao sao simbolos passados ao procedimento
_EXEC_KEYWORDS = {'PGM', 'PROC', 'PARM', 'COND', 'REGION', 'TIME', 'ACCT'}
# Bibliotecas (PDS) -> diretorio do CardDemo com os membros
_LIBRARIES = {'PROC': 'proc', 'CNTL': 'ctl', 'JCL': 'jcl'}


# DDs de bibliotecas de programas e de arquivos internos do IMS: nao ha o
# que alocar (os programas vem de build/batch; o banco esta no SQLite)
_LIBRARY_DDS = {'STEPLIB', 'JOBLIB', 'DBRMLIB', 'IMS', 'DFSRESLB', 'PROCLIB', 'DFSVSAMP',
                'IEFRDER', 'IMSLOGR', 'IMSMON', 'DFSSEL', 'DFSCTL', 'RECON1', 'RECON2', 'RECON3',
                'DDPAUTP0', 'DDPAUTX0'}


class JclError(Exception):
    pass


class Statement(object):
    def __init__(self, name, op, params, data=None):
        self.name, self.op, self.params, self.data = name, op, params, data

    def copy(self):
        return Statement(self.name, self.op, dict(self.params),
                         None if self.data is None else list(self.data))


class Step(object):
    def __init__(self, name, exec_params):
        self.name, self.params = name, exec_params
        self.dds = []                   # [(nome, [Statement, ...])], com concatenacoes


# --- leitura ---------------------------------------------------------------
def split_params(text):
    """'A=1,B=(X,Y),C' -> ['A=1', 'B=(X,Y)', 'C'] (virgulas do nivel externo)."""
    parts, depth, quote, cur = [], 0, False, ''
    for c in text:
        if c == "'":
            quote = not quote
        elif not quote:
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
            elif c == ',' and depth == 0:
                parts.append(cur)
                cur = ''
                continue
        cur += c
    if cur:
        parts.append(cur)
    return parts


def unparen(value):
    """'(A,B)' -> ['A', 'B']; 'A' -> ['A']."""
    if value.startswith('(') and value.endswith(')'):
        return split_params(value[1:-1])
    return [value]


def _params(text):
    """Campo de parametros -> dict; posicionais ficam em '_' (lista)."""
    out = {'_': []}
    for part in split_params(text):
        m = re.match(r"([A-Z0-9@#$.]+)=(.*)$", part, re.S)
        if m and not part.startswith("'"):
            value = m.group(2)
            if len(value) > 1 and value[0] == value[-1] == "'":
                value = value[1:-1].replace("''", "'")
            out[m.group(1)] = value
        else:
            out['_'].append(part)
    return out


def _field(text):
    """Corta o campo de parametros no primeiro branco fora de aspas."""
    quote = False
    for i, c in enumerate(text):
        if c == "'":
            quote = not quote
        elif c == ' ' and not quote:
            return text[:i]
    return text


def parse(text):
    """Texto de um job ou procedimento -> lista de Statement."""
    lines = [l.rstrip('\r') for l in text.split('\n')]
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        i += 1
        if not line.startswith('//') or line.startswith('//*'):
            continue
        body = line[2:72]
        if not body.strip():
            break                       # instrucao nula: fim do job
        m = re.match(r'(\S*)\s+(\S+)\s*(.*)$', body)
        if not m:
            continue
        name, op, rest = m.group(1), m.group(2), _field(m.group(3))
        while rest.endswith(',') and i < len(lines):
            nxt = lines[i]
            if nxt.startswith('//*'):
                i += 1
                continue
            if not nxt.startswith('// '):
                break                   # virgula sobrando antes de outra instrucao
            rest += _field(nxt[2:72].lstrip())
            i += 1
        stmt = Statement(name, op, _params(rest.rstrip(',')))
        if op == 'DD' and stmt.params['_'][:1] in (['*'], ['DATA']):
            stmt.data = []
            while i < len(lines):
                if lines[i].startswith('/*'):
                    i += 1
                    break
                if lines[i].startswith('//') and stmt.params['_'][0] == '*':
                    break
                stmt.data.append(lines[i][:80])
                i += 1
        out.append(stmt)
    return out


def _substitute(stmt, symbols):
    def repl(m):
        if m.group(1) not in symbols:
            return m.group(0)
        return symbols[m.group(1)]
    stmt = stmt.copy()
    for key, value in stmt.params.items():
        if key == '_':
            stmt.params[key] = [_SYMBOL.sub(repl, v) for v in value]
        else:
            stmt.params[key] = _SYMBOL.sub(repl, value)
    return stmt


def expand(statements, symbols, find_proc):
    """Resolve simbolos e procedimentos: Statement[] -> (nome do job, Step[])."""
    symbols, jobname, steps, procs = dict(symbols), None, [], {}
    i = 0
    while i < len(statements):
        raw = statements[i]
        i += 1
        if raw.op == 'PROC':
            body = []                   # procedimento em linha, ate o PEND
            while i < len(statements) and statements[i].op != 'PEND':
                body.append(statements[i])
                i += 1
            procs[raw.name] = [raw] + body
            i += 1
            continue
        stmt = _substitute(raw, symbols)
        if stmt.op == 'JOB':
            jobname = stmt.name
        elif stmt.op == 'SET':
            symbols.update((k, v) for k, v in stmt.params.items() if k != '_')
        elif stmt.op == 'EXEC':
            dds, overrides = [], []
            while i < len(statements) and statements[i].op == 'DD':
                dd = _substitute(statements[i], symbols)
                i += 1
                if '.' in dd.name:
                    overrides.append(dd)
                elif not dd.name and overrides and not dds:
                    overrides.append(dd)
                else:
                    dds.append(dd)
            proc = stmt.params.get('PROC') or (stmt.params['_'] or [None])[0]
            if 'PGM' in stmt.params:
                step = Step(stmt.name, stmt.params)
                for dd in dds:
                    _add_dd(step, dd)
                steps.append(step)
                continue
            body = procs.get(proc) or find_proc(proc)
            if body is None:
                raise JclError('procedimento %s nao encontrado' % proc)
            inner = dict(symbols)
            inner.update((k, v) for k, v in body[0].params.items()
                         if k != '_' and body[0].op == 'PROC')
            inner.update((k, v) for k, v in stmt.params.items()
                         if k != '_' and k not in _EXEC_KEYWORDS)
            _, proc_steps = expand(body[1:] if body[0].op == 'PROC' else body, inner, find_proc)
            last = None
            for dd in overrides:
                if dd.name:
                    stepname, ddname = dd.name.split('.', 1)
                    target = next((s for s in proc_steps if s.name == stepname), None)
                    if target is None:
                        raise JclError('passo %s nao existe no procedimento %s'
                                       % (stepname, proc))
                    dd.name = ddname
                    _override_dd(target, dd)
                    last = target
                elif last is not None:
                    _add_dd(last, dd)
            steps.extend(proc_steps)
    return jobname, steps


def _add_dd(step, dd):
    if not dd.name and step.dds:
        step.dds[-1][1].append(dd)      # concatenacao
    else:
        step.dds.append((dd.name, [dd]))


def _override_dd(step, dd):
    for n, (name, parts) in enumerate(step.dds):
        if name == dd.name:
            if dd.data is None and parts[0].data is None:
                merged = parts[0].copy()
                merged.params.update((k, v) for k, v in dd.params.items() if k != '_')
                dd = merged
            step.dds[n] = (name, [dd])
            return
    step.dds.append((dd.name, [dd]))


# --- alocacao --------------------------------------------------------------
class Alloc(object):
    """Um dataset alocado a um DD: instream, sysout, dummy, vsam ou seq."""

    def __init__(self, kind, dsn=None, lines=None, lrecl=None, recfm='FB',
                 disp=('SHR', 'KEEP', 'KEEP'), new=False, gdg=None):
        self.kind, self.dsn, self.lines = kind, dsn, lines
        self.lrecl, self.recfm, self.disp, self.new, self.gdg = lrecl, recfm, disp, new, gdg


class StepContext(object):
    """O que um passo enxerga: seus DDs, o catalogo e o log do job."""

    def __init__(self, job, step, allocs):
        self.job, self.step, self.allocs = job, step, allocs
        self.catalog = job.catalog
        self.parm = step.params.get('PARM', '')

    def log(self, text):
        self.job.log(text)

    def has(self, dd):
        return dd in self.allocs

    def alloc(self, dd):
        return self.allocs[dd][0]

    def text(self, dd):
        """Linhas de um DD de controle (instream ou membro de biblioteca)."""
        lines = []
        for a in self.allocs.get(dd, []):
            if a.kind == 'instream':
                lines.extend(a.lines)
            elif a.kind in ('seq', 'vsam'):
                lines.extend(r.decode('latin-1') for r in self.catalog.read(a.dsn))
        return lines

    def read(self, dd):
        """Registros de um DD, com as concatenacoes."""
        records = []
        for a in self.allocs.get(dd, []):
            if a.kind == 'instream':
                records.extend(l.ljust(80).encode('latin-1') for l in a.lines)
            elif a.kind in ('seq', 'vsam'):
                records.extend(self.catalog.read(a.dsn))
        return records

    def write(self, dd, records, lrecl=None):
        a = self.alloc(dd)
        if a.kind == 'sysout':
            for r in records:
                self.log(bytes(r).decode('latin-1').rstrip())
        elif a.kind == 'seq':
            a.lrecl = a.lrecl or lrecl
            self.catalog.write(a.dsn, records, a.lrecl, a.recfm)


class Job(object):
    def __init__(self, text, catalog, app, name=None):
        self.catalog, self.app = catalog, app
        statements = parse(text)
        self.scan_only = any(s.op == 'JOB' and s.params.get('TYPRUN') == 'SCAN'
                             for s in statements)
        self.name, self.steps = expand(statements, {'SYSUID': 'KIXUSER'}, self._find_proc)
        self.name = self.name or name or 'JOB'
        self.results = []               # [(passo, programa, 'RC=0000' / 'FLUSH' / ...)]
        self.maxcc, self.abended = 0, False
        self._gdg = {}                  # base -> ultima geracao no inicio do job
        self._log = None
        self.log_path = None

    # --- bibliotecas -------------------------------------------------------
    def _member(self, library, member):
        folder = _LIBRARIES.get(library.rsplit('.', 1)[-1])
        for d in config.module_dirs(self.app, folder) if folder else []:
            for path in sorted(glob.glob(os.path.join(d, '*'))):
                if os.path.splitext(os.path.basename(path))[0].upper() == member.upper():
                    with open(path, encoding='latin-1') as f:
                        return f.read()
        return None

    def _find_proc(self, name):
        text = self._member('PROC', name)
        return None if text is None else parse(text)

    # --- log ---------------------------------------------------------------
    def log(self, text):
        self._log.write(text + '\n')
        self._log.flush()

    # --- execucao ----------------------------------------------------------
    def run(self):
        jobs_dir = os.path.join(self.catalog.data_dir, 'jobs')
        os.makedirs(jobs_dir, exist_ok=True)
        number = len(os.listdir(jobs_dir)) + 1
        self.log_path = os.path.join(jobs_dir, 'J%05d.%s.log' % (number, self.name))
        with open(self.log_path, 'w', encoding='latin-1') as self._log:
            self.log('JOB %s' % self.name)
            if self.scan_only:
                self.log('TYPRUN=SCAN no cartao JOB ignorado: o job sera executado')
            for step in self.steps:
                program = step.params.get('PGM', '?')
                if self.abended or self._bypass(step):
                    self.results.append((step.name, program, 'FLUSH'))
                    self.log('--- %s %s: nao executado' % (step.name, program))
                    continue
                self.log('--- %s EXEC PGM=%s' % (step.name, program))
                try:
                    rc, abend = self._run_step(step, program)
                except JclError as e:
                    self.log('JCL ERROR: %s' % e)
                    self.results.append((step.name, program, 'JCL ERROR'))
                    self.abended, self.maxcc = True, max(self.maxcc, 16)
                    continue
                if abend:
                    self.abended = True
                    self.results.append((step.name, program, 'ABEND %s' % abend))
                    self.log('--- %s ABEND %s' % (step.name, abend))
                else:
                    self.maxcc = max(self.maxcc, rc)
                    self.results.append((step.name, program, 'RC=%04d' % rc))
                    self.log('--- %s RC=%04d' % (step.name, rc))
            self.log('JOB %s %s' % (self.name, self.status()))
        return self

    def status(self):
        if any(r[2] == 'JCL ERROR' for r in self.results):
            return 'JCL ERROR'
        return 'ABEND' if self.abended else 'MAXCC=%04d' % self.maxcc

    def ok(self):
        return not self.abended and self.maxcc <= 4

    def _bypass(self, step):
        """COND=(codigo,operador): pula o passo se o teste vale para algum anterior."""
        cond = step.params.get('COND')
        if not cond:
            return False
        tests = [unparen(t) for t in unparen(cond)] if cond.startswith('((') else [unparen(cond)]
        ops = {'GT': int.__gt__, 'GE': int.__ge__, 'EQ': int.__eq__,
               'NE': int.__ne__, 'LT': int.__lt__, 'LE': int.__le__}
        codes = [int(r[2][3:]) for r in self.results if r[2].startswith('RC=')]
        return any(len(t) >= 2 and ops[t[1]](int(t[0]), rc) for t in tests for rc in codes)

    def _resolve(self, dsn):
        """Nome catalogado de um DSN, resolvendo a geracao relativa de GDG."""
        base, relative = split_relative(dsn)
        if relative is None:
            return dsn, None
        if self.catalog.gdg_limit(base) is None:
            raise JclError('GDG %s nao definido' % base)
        if base not in self._gdg:
            self._gdg[base] = (self.catalog.generations(base) or [0])[-1]
        number = self._gdg[base] + relative
        if number < 1:
            raise JclError('geracao %s nao existe' % dsn)
        return self.catalog.generation_name(base, number), base

    def _allocate(self, step):
        allocs = {}
        for name, parts in step.dds:
            if name in _LIBRARY_DDS or (name == '' and not allocs):
                continue
            allocs[name] = [self._alloc(dd, allocs) for dd in parts]
        return allocs

    def _alloc(self, dd, allocs):
        p = dd.params
        if dd.data is not None:
            return Alloc('instream', lines=dd.data)
        if 'SYSOUT' in p:
            return Alloc('sysout')
        dsn = p.get('DSN') or p.get('DSNAME')
        if 'DUMMY' in p['_'] or dsn == 'NULLFILE' or not dsn:
            return Alloc('dummy')
        library, member = split_member(dsn)
        if member and split_relative(dsn)[1] is None:
            text = self._member(library, member)
            if text is None:
                raise JclError('membro %s nao encontrado' % dsn)
            return Alloc('instream', dsn=dsn, lines=[l[:80] for l in text.splitlines()])
        dsn, gdg = self._resolve(dsn)
        disp = (unparen(p.get('DISP', 'NEW')) + ['', ''])[:3]
        disp[0] = disp[0] or 'NEW'
        disp[1] = disp[1] or ('DELETE' if disp[0] == 'NEW' else 'KEEP')
        disp[2] = disp[2] or disp[1]
        dcb = dict(x.split('=', 1) for x in unparen(p.get('DCB', '')) if '=' in x)
        lrecl = int(p.get('LRECL') or dcb.get('LRECL') or 0) or None
        recfm = p.get('RECFM') or dcb.get('RECFM') or 'FB'
        back = re.match(r'\(?\*\.(\w+)\)?$', p.get('DCB', ''))
        if back and back.group(1) in allocs:     # DCB=(*.SORTIN)
            lrecl = allocs[back.group(1)][0].lrecl
        if self.catalog.is_vsam(dsn):
            return Alloc('vsam', dsn, lrecl=self.catalog.lrecl(dsn), disp=tuple(disp))
        exists = self.catalog.entry(dsn) is not None
        if disp[0] in ('NEW', 'MOD') and (disp[0] == 'NEW' or not exists):
            self.catalog.write(dsn, [], lrecl or 80, recfm)
            return Alloc('seq', dsn, lrecl=lrecl, recfm=recfm, disp=tuple(disp), new=True, gdg=gdg)
        if not exists:
            raise JclError('DATA SET NOT FOUND: %s' % dsn)
        entry = self.catalog.entry(dsn)
        return Alloc('seq', dsn, lrecl=entry[0], recfm=entry[1], disp=tuple(disp), gdg=gdg)

    def _dispose(self, allocs, abend):
        for parts in allocs.values():
            for a in parts:
                if a.kind != 'seq':
                    continue
                action = a.disp[2] if abend else a.disp[1]
                if action == 'DELETE':
                    try:
                        self.catalog.delete(a.dsn)
                    except NotFound:
                        pass
                elif a.new:
                    if a.lrecl:
                        self.catalog.catalog(a.dsn, a.lrecl, a.recfm)
                    if a.gdg:
                        self.catalog.roll_off(a.gdg)

    def _run_step(self, step, program):
        allocs = self._allocate(step)
        ctx = StepContext(self, step, allocs)
        try:
            if program in utilities.PROGRAMS:
                rc, abend = utilities.PROGRAMS[program](ctx), None
            elif os.path.exists(os.path.join(config.BATCH_DIR, program + config.MODULE_EXT)):
                rc, abend = self._run_cobol(ctx, program)
            else:
                self.log('IEW4000I programa %s nao encontrado' % program)
                rc, abend = 0, 'S806'
        except Exception:
            self._dispose(allocs, True)
            raise
        self._dispose(allocs, abend)
        return rc, abend

    def _run_cobol(self, ctx, program, ims=None):
        """Roda um programa COBOL; ims=(PSB, regiao BMP?) numa regiao IMS."""
        env, vsam, temps, stdin = {}, {}, [], None
        if ims:
            ims = (dli.Definitions(config.module_dirs(self.app, 'ims')),) + tuple(ims)
        try:
            for name, parts in ctx.allocs.items():
                a = parts[0]
                if a.kind == 'vsam' and len(parts) == 1:
                    vsam[name] = a.dsn
                    continue
                if a.kind == 'seq' and len(parts) == 1:
                    env[name] = self.catalog.filename(a.dsn)
                elif a.kind == 'dummy':
                    env[name] = os.devnull
                elif a.kind == 'sysout':
                    continue            # DISPLAY vai para o log do job
                else:                   # instream, concatenacao ou cluster lido em sequencia
                    fd, path = tempfile.mkstemp(prefix='kix_%s_' % name)
                    with os.fdopen(fd, 'wb') as f:
                        f.write(b''.join(ctx.read(name)))
                    temps.append(path)
                    env[name] = path
            if ctx.has('SYSIN'):        # ACCEPT ... FROM SYSIN
                fd, path = tempfile.mkstemp(prefix='kix_SYSIN_')
                with os.fdopen(fd, 'w', encoding='latin-1') as f:
                    f.write('\n'.join(ctx.text('SYSIN')) + '\n')
                temps.append(path)
                stdin = open(path, 'rb')
            code, abend = batch.run_program(
                config.KIXBATCH, config.BATCH_DIR, self.catalog.store, program, ctx.parm,
                env, vsam, stdin, self._log, self.log,
                {'KIX_JOBNAME': self.name, 'KIX_STEPNAME': ctx.step.name,
                 'KIX_DDNAMES': ','.join(ctx.allocs)},
                os.path.dirname(self.log_path), ims)
        finally:
            if stdin:
                stdin.close()
            for path in temps:
                os.remove(path)
        if abend:
            return 0, 'U0999' if code == batch.ABEND_EXIT else 'S0C4 (saida %d)' % code
        return code, None


# --- interface -------------------------------------------------------------
def find_job(app, name):
    """Caminho de um JCL: arquivo indicado ou membro de app/jcl."""
    if os.path.exists(name):
        return name
    for d in config.module_dirs(app, 'jcl'):
        for path in sorted(glob.glob(os.path.join(d, '*'))):
            if os.path.splitext(os.path.basename(path))[0].upper() == name.upper():
                return path
    raise SystemExit('JCL %s nao encontrado' % name)


def submit(text, data_dir, app, name=None, catalog=None):
    """Executa um job; devolve o Job (results, maxcc, log_path)."""
    own = catalog is None
    catalog = catalog or Catalog(data_dir)
    try:
        return Job(text, catalog, app, name).run()
    finally:
        if own:
            catalog.close()


def main(carddemo=None, data_dir=None, jobs=()):
    app = config.carddemo_app(carddemo)
    data_dir = data_dir or config.DATA_DIR
    failed = 0
    for name in jobs:
        path = find_job(app, name)
        with open(path, encoding='latin-1') as f:
            job = submit(f.read(), data_dir, app, os.path.splitext(os.path.basename(path))[0])
        print('%-8s %s' % (job.name, job.status()))
        for step, program, result in job.results:
            print('  %-8s %-8s %s' % (step, program, result))
        print('  log: %s' % job.log_path)
        failed += not job.ok()
    if failed:
        raise SystemExit('%d job(s) com erro' % failed)
