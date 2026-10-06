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
# parametro. HANDLE ABEND/CONDITION sao registrados como no-op por ora.
LABEL_VERBS = {'HANDLE', 'IGNORE'}

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


def emit_call(opts):
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
        if arg is None or verb in LABEL_VERBS:
            spec.append(name)
        else:
            spec.append(name + '=')
            params.append(arg)

    text = '|'.join(spec)
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


def translate(source):
    """Devolve o fonte traduzido (str) de um programa COBOL CICS."""
    out, pending = [], None
    has_linkage = has_commarea = False
    lines = source.splitlines()

    for raw in lines:
        line = raw.rstrip('\n')
        code = line[6:72] if len(line) > 6 else ''
        indicator = code[:1]
        text = code[1:]
        upper = text.upper()

        if indicator in '*/':
            out.append(line[:72])
            continue

        if pending is not None:
            end = upper.find('END-EXEC')
            if end < 0:
                pending.append(text)
                continue
            pending.append(text[:end])
            tail = text[end + len('END-EXEC'):].strip()
            body = ' '.join(' '.join(pending).split())
            try:
                call = emit_call(parse_options(body))
            except TranslateError as e:
                raise TranslateError('%s (linha: %s)' % (e, body[:60]))
            out.append('      *KIX  EXEC CICS %s' % body[:50])
            out.extend(call)
            if tail:
                out.append('           ' + tail)
            pending = None
            continue

        m = re.search(r'EXEC\s+CICS\b', upper)
        if m:
            pending = []
            rest = text[m.end():]
            end = rest.upper().find('END-EXEC')
            if end >= 0:              # comando inteiro em uma linha
                lines_tail = rest[end + len('END-EXEC'):].strip()
                body = ' '.join(rest[:end].split())
                out.append('      *KIX  EXEC CICS %s' % body[:50])
                out.extend(emit_call(parse_options(body)))
                if lines_tail:
                    out.append('           ' + lines_tail)
                pending = None
            else:
                pending.append(rest)
            continue

        line = line[:72]
        if _DFHRESP.search(line):
            def repl(m):
                key = m.group(1).upper()
                if key not in RESP:
                    raise TranslateError('DFHRESP(%s) desconhecido' % key)
                return str(RESP[key])
            line = _DFHRESP.sub(repl, line)

        if re.match(r'\s*LINKAGE\s+SECTION\s*\.', upper):
            has_linkage = True
            out.append(line)
            out.append('       COPY DFHEIBLK.')
            continue
        if re.match(r'\s*01\s+DFHCOMMAREA\b', upper):
            has_commarea = True
        if re.match(r'\s*PROCEDURE\s+DIVISION\s*\.', upper):
            if not has_linkage:
                out.append('       LINKAGE SECTION.')
                out.append('       COPY DFHEIBLK.')
            if not has_commarea:
                out.append('       01  DFHCOMMAREA PIC X(1).')
            out.append('       PROCEDURE DIVISION USING DFHEIBLK DFHCOMMAREA.')
            continue
        out.append(line)

    if pending is not None:
        raise TranslateError('EXEC CICS sem END-EXEC')
    return '\n'.join(out) + '\n'
