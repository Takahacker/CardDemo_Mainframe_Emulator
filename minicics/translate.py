"""Tradutor de comandos: troca cada EXEC CICS ... END-EXEC por CALL "KIXCMD".

Faz o papel do tradutor CICS da IBM. O fonte original nao e alterado; o
resultado vai para build/src. Cada comando vira

    CALL "KIXCMD" USING BY CONTENT "<spec>" <um parametro por opcao>

onde <spec> e "VERBO|OPCAO=|FLAG|...": "=" marca as opcoes que consomem
um parametro, na ordem.
"""
import re

RESP = {
    'NORMAL': 0, 'ERROR': 1, 'RDATT': 2, 'WRBRK': 3, 'EOF': 4, 'EODS': 5,
    'EOC': 6, 'INBFMH': 7, 'ENDINPT': 8, 'NONVAL': 9, 'NOSTART': 10,
    'TERMIDERR': 11, 'FILENOTFOUND': 12, 'DSIDERR': 12, 'NOTFND': 13,
    'DUPREC': 14, 'DUPKEY': 15, 'INVREQ': 16, 'IOERR': 17, 'NOSPACE': 18,
    'NOTOPEN': 19, 'ENDFILE': 20, 'ILLOGIC': 21, 'LENGERR': 22, 'QZERO': 23,
    'SIGNAL': 24, 'QBUSY': 25, 'ITEMERR': 26, 'PGMIDERR': 27,
    'TRANSIDERR': 28, 'ENDDATA': 29, 'EXPIRED': 31, 'MAPFAIL': 36,
    'INVMPSZ': 38, 'OVERFLOW': 40, 'QIDERR': 44, 'SYSIDERR': 53,
    'ENQBUSY': 55, 'NOTAUTH': 70, 'DISABLED': 84, 'LOCKED': 100,
    'RECORDBUSY': 101,
}

# Opcoes cujo argumento e um nome de paragrafo, nao um dado: nao viram
# parametro. O paragrafo entra na spec como "OPCAO:<indice>", e o desvio e
# feito pelo GO TO ... DEPENDING ON RETURN-CODE emitido apos cada comando.
LABEL_VERBS = {'HANDLE', 'IGNORE'}
_GOTO_MARK = '      *KIXGOTO'

_OPTION = re.compile(r"\s*([A-Z0-9][A-Z0-9-]*)\s*", re.I)
_DFHRESP = re.compile(r"DFHRESP\s*\(\s*([A-Z0-9]+)\s*\)", re.I)


class TranslateError(Exception):
    pass


def parse_options(body):
    """'SEND MAP('A') ERASE' -> [('SEND', None), ('MAP', "'A'"), ('ERASE', None)]"""
    opts, i = [], 0
    while i < len(body):
        m = _OPTION.match(body, i)
        if not m:
            if not body[i:].strip():
                break
            raise TranslateError('opcao invalida em: %r' % body[i:i + 30])
        name, i = m.group(1).upper(), m.end()
        arg = None
        if i < len(body) and body[i] == '(':
            depth, quote, j = 0, None, i
            while j < len(body):
                c = body[j]
                if quote:
                    if c == quote:
                        quote = None
                elif c in "'\"":
                    quote = c
                elif c == '(':
                    depth += 1
                elif c == ')':
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            if depth:
                raise TranslateError('parenteses nao fechados: %r' % body)
            arg = ' '.join(body[i + 1:j].split())
            i = j + 1
        opts.append((name, arg))
    return opts


def _is_content(arg):
    """Literais e LENGTH OF vao BY CONTENT; itens de dados, BY REFERENCE."""
    return (arg[0] in "'\"" or re.match(r"[+-]?\d", arg) is not None
            or arg.upper().startswith('LENGTH OF'))


def _wrap(prefix, text, indent, width=72):
    """Quebra 'prefix text' em linhas de formato fixo, sem cortar literais."""
    words = re.findall(r"'[^']*'|\"[^\"]*\"|\S+", text)
    lines, cur = [], ' ' * indent + prefix
    for w in words:
        if len(cur) + 1 + len(w) > width and cur.strip() != prefix.strip():
            lines.append(cur)
            cur = ' ' * (indent + 4) + w
        else:
            cur += ' ' + w
    lines.append(cur)
    return lines


def emit_call(opts, labels):
    """Linhas do CALL de um comando; `labels` acumula os paragrafos de HANDLE."""
    verb = opts[0][0]
    rest = list(opts[1:])
    names = [n for n, _ in rest]

    # Area simbolica implicita: MAP('X') sem FROM/INTO usa XO / XI.
    if 'MAP' in names:
        maparg = dict(rest)['MAP']
        implied = {'SEND': ('FROM', 'O'), 'RECEIVE': ('INTO', 'I')}.get(verb)
        if implied and implied[0] not in names and 'MAPONLY' not in names:
            if not (maparg and maparg[0] in "'\""):
                raise TranslateError('MAP variavel sem %s' % implied[0])
            rest.append((implied[0], maparg.strip("'\"") + implied[1]))

    spec, params = [verb], []
    for name, arg in rest:
        if arg is None:
            spec.append(name)
        elif verb in LABEL_VERBS:
            if name == 'PROGRAM':       # HANDLE ABEND PROGRAM: nao suportado
                spec.append(name)
                continue
            label = arg.upper()
            if label not in labels:
                labels.append(label)
            spec.append('%s:%d' % (name, labels.index(label) + 1))
        else:
            spec.append(name + '=')
            params.append(arg)

    out = _call('|'.join(spec), params) + [_GOTO_MARK]
    if verb == 'RETURN':
        # Num programa chamado por LINK o RETURN devolve o controle ao
        # chamador; no programa principal o processo termina antes daqui.
        out.append('           GOBACK')
    return out


def _call(text, params):
    """CALL "KIXCMD" com a spec `text` (quebrada em literais) e os parametros."""
    chunks = [text[i:i + 40] for i in range(0, len(text), 40)]
    out = ['           CALL "KIXCMD" USING']
    for n, chunk in enumerate(chunks):
        lead = '               BY CONTENT ' if n == 0 else '                        & '
        out.append('%s"%s"' % (lead, chunk))
    for arg in params:
        how = 'BY CONTENT' if _is_content(arg) else 'BY REFERENCE'
        out.extend(_wrap(how, arg, 15))
    out.append('           END-CALL')
    return out


# --- EXEC DLI --------------------------------------------------------------
_DLI_OPS = {'=': 'EQ', '>': 'GT', '<': 'LT', '>=': 'GE', '=>': 'GE', '<=': 'LE', '=<': 'LE',
            '^=': 'NE', '<>': 'NE', '!=': 'NE'}


def emit_dli(body):
    """Linhas COBOL de um EXEC DLI.

    Vira CALL "KIXCMD" com a spec "DLI|funcao|DIB=|PCB=|SEGMENT:nome|
    WHERE:campo:op=|INTO=|...": "=" marca o que consome um parametro, ":"
    separa um valor literal. O primeiro parametro e o bloco DLZDIB.
    """
    opts = parse_options(body)
    spec, params = ['DLI', opts[0][0], 'DIB='], ['DLZDIB']
    for name, arg in opts[1:]:
        if arg is None:
            continue                    # USING, NODHABEND...
        if name in ('SEGMENT', 'PSB') and not arg.startswith('('):
            spec.append('%s:%s' % (name, arg.strip("'").upper()))
        elif name == 'WHERE':
            m = re.match(r'([A-Z0-9#@$]+)\s*(>=|<=|=>|=<|<>|\^=|!=|=|>|<|[A-Z]{2})\s*(.+)$',
                         arg, re.I)
            if not m:
                raise TranslateError('WHERE nao suportado: %s' % arg)
            op = _DLI_OPS.get(m.group(2), m.group(2).upper())
            spec.append('WHERE:%s:%s=' % (m.group(1).upper(), op))
            params.append(m.group(3))
        else:
            spec.append(name + '=')
            params.append(arg.strip('()') if name in ('SEGMENT', 'PSB') else arg)
    return _call('|'.join(spec), params)


# --- EXEC SQL --------------------------------------------------------------
_HOSTVAR = re.compile(r':\s*([A-Za-z][A-Za-z0-9-]*)')
_VARCHAR = re.compile(r'^.{6} +\d+\s+([A-Z0-9-]+)\s*\.\s*\n(?:.{6}\*.*\n)*.{6} +49\s', re.M | re.I)


def varchar_groups(text):
    """Nomes dos grupos VARCHAR (os que tem filhos de nivel 49, como no DCLGEN)."""
    return set(name.upper() for name in _VARCHAR.findall(text))


def emit_sql(body, cursors, varchars):
    """Linhas COBOL de um EXEC SQL.

    Vira CALL "KIXCMD" com a spec "SQL|tipo|cursor|assinatura|texto": o
    texto leva "?" no lugar das variaveis host de entrada, e a assinatura
    tem uma letra por variavel (i entrada, o saida; maiuscula = VARCHAR).
    """
    words = body.split()
    head = words[0].upper()
    if head == 'INCLUDE':
        return ['       COPY %s.' % words[1].upper()]
    if head == 'DECLARE':
        m = re.match(r'DECLARE\s+(\S+)\s+CURSOR\b.*?\bFOR\s+(.*)$', body, re.I | re.S)
        if m:
            cursors[m.group(1).upper()] = m.group(2)
        return []
    if head in ('WHENEVER', 'BEGIN', 'END'):
        return []
    kind, cursor, sql, outputs = 'EXEC', '', body, []
    if head in ('OPEN', 'CLOSE'):
        kind, cursor = head, words[1].upper()
        if cursor not in cursors:
            raise TranslateError('cursor %s nao declarado' % cursor)
        sql = cursors[cursor] if head == 'OPEN' else ''
    elif head == 'FETCH':
        m = re.match(r'FETCH\s+(\S+)\s+INTO\s+(.*)$', body, re.I | re.S)
        kind, cursor, sql = 'FETCH', m.group(1).upper(), ''
        outputs = _HOSTVAR.findall(m.group(2))
    elif head == 'SELECT':
        m = re.search(r'\bINTO\s+((?::\s*[A-Za-z0-9-]+\s*,?\s*)+)', sql, re.I)
        if m:
            outputs = _HOSTVAR.findall(m.group(1))
            sql = sql[:m.start()] + sql[m.end():]
    inputs = _HOSTVAR.findall(sql)
    sql = _HOSTVAR.sub('?', sql)

    def sig(names, letter):
        return ''.join(letter.upper() if n.upper() in varchars else letter for n in names)
    spec = 'SQL|%s|%s|%s|%s' % (kind, cursor, sig(inputs, 'i') + sig(outputs, 'o'),
                                ' '.join(sql.split()))
    return _call(spec, ['SQLCA'] + inputs + outputs)


def translate(source, cics=True, include=None):
    """Devolve o fonte traduzido (str) de um programa COBOL CICS e/ou SQL.

    cics=False (programa batch) nao mexe na LINKAGE nem na PROCEDURE
    DIVISION. `include(nome)` devolve o texto de um membro de EXEC SQL
    INCLUDE, que e expandido no lugar como faz o pre-compilador do Db2
    (None: vira COPY).
    """
    out, labels, cursors, varchars = [], [], {}, set()
    state = {'pending': None, 'kind': None, 'linkage': False, 'commarea': False}

    def finish(kind, body, tail):
        try:
            if kind == 'CICS':
                call = emit_call(parse_options(body), labels)
            elif kind == 'DLI':
                call = emit_dli(body)
            else:
                if body.split()[0].upper() == 'INCLUDE':
                    member = include(body.split()[1].upper()) if include else None
                    if member is not None:
                        varchars.update(varchar_groups(member))
                        for raw in member.splitlines():
                            feed(raw)
                        return
                    tail = ''           # o COPY ja leva o ponto
                call = emit_sql(body, cursors, varchars)
        except TranslateError as e:
            raise TranslateError('%s (linha: %s)' % (e, body[:60]))
        out.append('      *KIX  EXEC %s %s' % (kind, body[:50]))
        out.extend(call)
        if tail and call:               # declaracao (nada emitido): o ponto sobra
            out.append('           ' + tail)

    def feed(raw):
        line = raw.rstrip('\n')
        code = line[6:72] if len(line) > 6 else ''
        indicator = code[:1]
        text = code[1:]
        upper = text.upper()

        if indicator in '*/':
            out.append(line[:72])
            return

        if state['pending'] is not None:
            end = upper.find('END-EXEC')
            if end < 0:
                state['pending'].append(text)
                return
            body = ' '.join(' '.join(state['pending'] + [text[:end]]).split())
            state['pending'] = None
            finish(state['kind'], body, text[end + len('END-EXEC'):].strip())
            return

        m = re.search(r'EXEC\s+(CICS|SQL|DLI)\b', upper)
        if m:
            state['kind'] = m.group(1)
            rest = text[m.end():]
            end = rest.upper().find('END-EXEC')
            if end >= 0:              # comando inteiro em uma linha
                finish(m.group(1), ' '.join(rest[:end].split()),
                       rest[end + len('END-EXEC'):].strip())
            else:
                state['pending'] = [rest]
            return

        line = line[:72]
        if _DFHRESP.search(line):
            def repl(m):
                key = m.group(1).upper()
                if key not in RESP:
                    raise TranslateError('DFHRESP(%s) desconhecido' % key)
                return str(RESP[key])
            line = _DFHRESP.sub(repl, line)

        if has_dli and re.match(r'\s*WORKING-STORAGE\s+SECTION\s*\.', upper):
            out.append(line)
            out.append('       COPY DFHDIB.')
            return
        if not cics:
            out.append(line)
            return
        if re.match(r'\s*LINKAGE\s+SECTION\s*\.', upper):
            state['linkage'] = True
            out.append(line)
            out.append('       COPY DFHEIBLK.')
            return
        if re.match(r'\s*01\s+DFHCOMMAREA\b', upper):
            state['commarea'] = True
        if re.match(r'\s*PROCEDURE\s+DIVISION\s*\.', upper):
            if not state['linkage']:
                out.append('       LINKAGE SECTION.')
                out.append('       COPY DFHEIBLK.')
            if not state['commarea']:
                out.append('       01  DFHCOMMAREA PIC X(1).')
            out.append('       PROCEDURE DIVISION USING DFHEIBLK DFHCOMMAREA.')
            return
        out.append(line)

    varchars.update(varchar_groups(source))
    has_dli = re.search(r'EXEC\s+DLI\b', source, re.I) is not None
    for raw in source.splitlines():
        feed(raw)

    if state['pending'] is not None:
        raise TranslateError('EXEC %s sem END-EXEC' % state['kind'])
    # KIXCMD devolve em RETURN-CODE o indice do paragrafo de HANDLE a
    # assumir (0 = segue em frente; GO TO DEPENDING ignora fora da faixa).
    # O CONTINUE e necessario: o cobc 3.2 trata todo GO TO como desvio
    # incondicional e, se ele for o ultimo comando de um ramo de IF ou
    # EVALUATE, deixa a execucao cair no ramo seguinte.
    goto = _wrap('GO TO', ' '.join(labels) + ' DEPENDING ON RETURN-CODE', 11)
    goto.append('           CONTINUE')
    lines, out = out, []
    for line in lines:
        if line != _GOTO_MARK:
            out.append(line)
        elif labels:
            out.extend(goto)
    return '\n'.join(out) + '\n'
