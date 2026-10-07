"""MQ minimo: filas de mensagens no mesmo SQLite, para as chamadas MQI.

Os programas fazem CALL 'MQOPEN' / 'MQGET' / 'MQPUT' / 'MQPUT1' /
'MQCLOSE' (runtime/kixtask.c), que chegam aqui como a spec "MQ|<funcao>"
com os parametros da chamada. Uma fila e criada ao primeiro uso. Nao ha
gerente de filas remoto, prioridade nem expiracao; MQGET nao espera
(WAIT com intervalo devolve logo MQRC-NO-MSG-AVAILABLE).
"""
import datetime
import os
import struct

CC_OK, CC_WARNING, CC_FAILED = 0, 1, 2
RC_NONE, RC_HOBJ_ERROR, RC_NO_MSG = 0, 2019, 2033
RC_NOT_INPUT, RC_NOT_OUTPUT, RC_TRUNCATED = 2037, 2039, 2079
OO_INPUT, OO_OUTPUT, OO_BROWSE = 1 | 2 | 4, 16, 8
GMO_BROWSE = 16 | 32
PMO_NEW_MSG_ID, PMO_NEW_CORREL_ID = 64, 128
NONE24 = b'\x00' * 24

# Deslocamentos nas estruturas (cpy/CMQ*.cpy)
OD_NAME = 12
MD_LEN, MD_MSGID, MD_CORRELID, MD_REPLYTOQ, MD_PUTDATE = 324, 48, 72, 100, 304
GMO_OPTIONS, PMO_OPTIONS = 8, 8
TM_LEN = 684


def prepare(db):
    db.execute('CREATE TABLE IF NOT EXISTS kix_mq (id INTEGER PRIMARY KEY AUTOINCREMENT,'
               ' queue TEXT, md BLOB, data BLOB)')


def _name(data):
    return bytes(data[:48]).decode('latin-1').rstrip(' \x00')


def new_md(reply_to=''):
    md = bytearray(b'MD  ' + struct.pack('>7i', 1, 0, 8, -1, 0, 785, 0) + b' ' * 8
                   + struct.pack('>2i', -1, 2) + NONE24 * 2 + struct.pack('>i', 0)
                   + b' ' * 108 + b'\x00' * 32 + b' ' * 32 + struct.pack('>i', 0) + b' ' * 48)
    md[MD_REPLYTOQ:MD_REPLYTOQ + 48] = reply_to.ljust(48).encode('latin-1')
    return md


def put(db, queue, md, data, options=0):
    """Grava uma mensagem; devolve o MQMD como ficou (MsgId, data e hora)."""
    md = bytearray(bytes(md).ljust(MD_LEN, b'\x00')[:MD_LEN])
    if md[MD_MSGID:MD_MSGID + 24] == NONE24 or options & PMO_NEW_MSG_ID:
        md[MD_MSGID:MD_MSGID + 24] = b'KIX ' + os.urandom(20)
    if options & PMO_NEW_CORREL_ID:
        md[MD_CORRELID:MD_CORRELID + 24] = b'KIX ' + os.urandom(20)
    now = datetime.datetime.now()
    md[MD_PUTDATE:MD_PUTDATE + 16] = now.strftime('%Y%m%d%H%M%S%f')[:16].encode()
    db.execute('INSERT INTO kix_mq (queue, md, data) VALUES (?,?,?)',
               (queue, bytes(md), bytes(data)))
    return bytes(md)


def get(db, queue, msgid=NONE24, correlid=NONE24, browse_after=None):
    """Proxima mensagem (id, md, dados) que casa MsgId / CorrelId, ou None.

    Sem `browse_after` a leitura e destrutiva.
    """
    rows = db.execute('SELECT id, md, data FROM kix_mq WHERE queue = ? AND id > ? ORDER BY id',
                      (queue, browse_after or 0))
    for row in rows.fetchall():
        md = bytes(row[1])
        if msgid != NONE24 and md[MD_MSGID:MD_MSGID + 24] != msgid:
            continue
        if correlid != NONE24 and md[MD_CORRELID:MD_CORRELID + 24] != correlid:
            continue
        if browse_after is None:
            db.execute('DELETE FROM kix_mq WHERE id = ?', (row[0],))
        return row[0], md, bytes(row[2])
    return None


def depths(db):
    """{fila: (mensagens, id da mais recente)}."""
    return dict((q, (n, last)) for q, n, last in db.execute(
        'SELECT queue, count(*), max(id) FROM kix_mq GROUP BY queue'))


def trigger_message(queue, transid):
    """MQTM entregue ao programa disparado (EXEC CICS RETRIEVE)."""
    return (b'TM  ' + struct.pack('>i', 1) + queue.ljust(48).encode('latin-1') + b' ' * 48
            + b' ' * 64 + struct.pack('>i', 1) + transid.ljust(256).encode() + b' ' * 256)


class Session(object):
    """Filas abertas por uma tarefa."""

    def __init__(self):
        self.handles, self.last = {}, 0

    def call(self, db, begin, func, p):
        """Executa uma chamada MQI; devolve [(parametro, valor a gravar)].

        O codigo de conclusao e o de razao sao sempre os dois ultimos
        parametros.
        """
        cc, rc, out = CC_OK, RC_NONE, []
        if func == 'OPEN':              # hconn, od, opcoes, hobj, cc, rc
            self.last += 1
            self.handles[self.last] = [_name(p[1].data[OD_NAME:]), p[2].number(), 0]
            out.append((p[3], self.last))
        elif func == 'CLOSE':           # hconn, hobj, opcoes, cc, rc
            if self.handles.pop(p[1].number(), None) is None:
                cc, rc = CC_FAILED, RC_HOBJ_ERROR
        elif func in ('PUT', 'PUT1'):   # hconn, hobj | od, md, pmo, tam, buffer, cc, rc
            if func == 'PUT':
                handle = self.handles.get(p[1].number())
                queue = handle and handle[0]
                if handle is None:
                    cc, rc = CC_FAILED, RC_HOBJ_ERROR
                elif not handle[1] & OO_OUTPUT:
                    cc, rc = CC_FAILED, RC_NOT_OUTPUT
            else:
                queue = _name(p[1].data[OD_NAME:])
            if cc == CC_OK:
                begin()
                options = struct.unpack_from('>i', p[3].data, PMO_OPTIONS)[0]
                md = put(db, queue, p[2].data, p[5].data[:max(p[4].number(), 0)], options)
                out.append((p[2], md))
        elif func == 'GET':             # hconn, hobj, md, gmo, tam, buffer, tam dados, cc, rc
            handle = self.handles.get(p[1].number())
            options = struct.unpack_from('>i', p[3].data, GMO_OPTIONS)[0]
            browse = bool(options & GMO_BROWSE)
            if handle is None:
                cc, rc = CC_FAILED, RC_HOBJ_ERROR
            elif not handle[1] & (OO_BROWSE if browse else OO_INPUT):
                cc, rc = CC_FAILED, RC_NOT_INPUT
            else:
                if not browse:
                    begin()
                if options & 16:        # BROWSE-FIRST
                    handle[2] = 0
                md = p[2].data
                found = get(db, handle[0], md[MD_MSGID:MD_MSGID + 24],
                            md[MD_CORRELID:MD_CORRELID + 24], handle[2] if browse else None)
                if found is None:
                    cc, rc = CC_FAILED, RC_NO_MSG
                else:
                    if browse:
                        handle[2] = found[0]
                    room = min(max(p[4].number(), 0), len(p[5].data))
                    data = found[2]
                    if len(data) > room:
                        cc, rc = CC_WARNING, RC_TRUNCATED
                    out += [(p[2], found[1]), (p[5], data[:room].ljust(len(p[5].data))),
                            (p[6], len(data))]
        else:
            cc, rc = CC_FAILED, 2012    # MQRC-ENVIRONMENT-ERROR
        return out + [(p[-2], cc), (p[-1], rc)]


def main(data_dir, action, queue, text='', reply_to='', wait=0):
    """Cliente de linha de comando: faz o papel da aplicacao do outro lado da fila."""
    import time
    from . import config
    from .vsam import Store
    store = Store(os.path.join(data_dir or config.DATA_DIR, 'carddemo.db'))
    prepare(store.db)
    if action == 'depth':
        for name, (count, _) in sorted(depths(store.db).items()):
            print('%-48s %d' % (name, count))
    elif not queue:
        raise SystemExit('informe a fila')
    elif action == 'put':
        md = put(store.db, queue, new_md(reply_to), text.encode('latin-1'))
        print('MsgId %s' % md[MD_MSGID:MD_MSGID + 24].hex())
    else:
        deadline = time.time() + wait
        while True:
            found = get(store.db, queue)
            if found or time.time() >= deadline:
                break
            time.sleep(0.1)
        if not found:
            raise SystemExit('MQRC 2033: nenhuma mensagem em %s' % queue)
        print(found[2].decode('latin-1').rstrip())
    store.close()
