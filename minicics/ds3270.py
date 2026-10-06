"""Fluxo de dados 3270: monta telas (saida) e interpreta a leitura (entrada)."""

# Comandos e ordens
CMD_WRITE, CMD_ERASE_WRITE = 0xF1, 0xF5
SF, SFE, SBA, IC = 0x1D, 0x29, 0x11, 0x13
XA_3270, XA_HILIGHT, XA_COLOR = 0xC0, 0x41, 0x42
WCC_RESTORE, WCC_ALARM = 0x02, 0x04

AID_ENTER, AID_CLEAR = 0x7D, 0x6D
SHORT_READ_AIDS = (0x6D, 0x6C, 0x6E, 0x6B)      # CLEAR, PA1, PA2, PA3

# Tabela que transforma 6 bits em um caractere EBCDIC "grafico"
CODE = bytes([0x40] + list(range(0xC1, 0xCA)) + list(range(0x4A, 0x50))
             + [0x50] + list(range(0xD1, 0xDA)) + list(range(0x5A, 0x60))
             + [0x60, 0x61] + list(range(0xE2, 0xEA)) + list(range(0x6A, 0x70))
             + list(range(0xF0, 0xFA)) + list(range(0x7A, 0x80)))

# O COBOL roda em ASCII; o terminal fala EBCDIC (cp037, com os colchetes
# na posicao da code page "bracket", padrao do x3270).
_A2E = bytearray(bytes(range(256)).decode('latin-1').encode('cp037', 'replace'))
_A2E[ord('[')], _A2E[ord(']')] = 0xAD, 0xBD
for _c in range(256):
    if _A2E[_c] < 0x40:
        _A2E[_c] = 0x00 if _c == 0 else 0x40
_A2E = bytes(_A2E)
_E2A = bytearray(bytes(range(256)).decode('cp037').encode('latin-1', 'replace'))
_E2A[0xAD], _E2A[0xBD] = ord('['), ord(']')
_E2A = bytes(_E2A)


def to_ebcdic(data):
    return bytes(data).translate(_A2E)


def to_ascii(data):
    return bytes(data).translate(_E2A)


def addr(pos):
    return bytes([CODE[(pos >> 6) & 0x3F], CODE[pos & 0x3F]])


def _decode_addr(b1, b2):
    if b1 & 0xC0 == 0:
        return ((b1 & 0x3F) << 8) | b2
    return ((b1 & 0x3F) << 6) | (b2 & 0x3F)


def start_field(pos, attr, color=0, hilight=0):
    out = bytes([SBA]) + addr(pos)
    if not color and not hilight:
        return out + bytes([SF, CODE[attr & 0x3F]])
    pairs = [XA_3270, CODE[attr & 0x3F]]
    if color:
        pairs += [XA_COLOR, color]
    if hilight:
        pairs += [XA_HILIGHT, hilight]
    return out + bytes([SFE, len(pairs) // 2] + pairs)


def write(body, erase, restore=True, alarm=False):
    wcc = (WCC_RESTORE if restore else 0) | (WCC_ALARM if alarm else 0)
    return bytes([CMD_ERASE_WRITE if erase else CMD_WRITE, CODE[wcc]]) + body


def text_screen(text, erase=True, alarm=False):
    """Tela nao formatada (SEND TEXT e mensagens do proprio mini-CICS)."""
    body = bytes([SBA]) + addr(0) + to_ebcdic(text) + bytes([SBA]) + addr(0) + bytes([IC])
    return write(body, erase, True, alarm)


class Inbound(object):
    """Resultado de uma leitura: tecla, cursor e campos modificados."""

    def __init__(self, record):
        self.aid = record[0] if record else AID_ENTER
        self.cursor = 0
        self.fields = {}            # endereco do 1o byte de dados -> bytes ASCII
        self.text = b''             # dados de tela nao formatada
        if len(record) < 3 or self.aid in SHORT_READ_AIDS:
            return
        self.cursor = _decode_addr(record[1], record[2])
        i, n = 3, len(record)
        if i < n and record[i] != SBA:
            j = record.find(bytes([SBA]), i)
            j = n if j < 0 else j
            self.text = to_ascii(record[i:j]).replace(b'\x00', b'')
            i = j
        while i + 2 < n and record[i] == SBA:
            pos = _decode_addr(record[i + 1], record[i + 2])
            j = record.find(bytes([SBA]), i + 3)
            j = n if j < 0 else j
            self.fields[pos] = to_ascii(record[i + 3:j]).replace(b'\x00', b'')
            i = j
        if not self.text and self.fields:
            self.text = self.fields[min(self.fields)]
