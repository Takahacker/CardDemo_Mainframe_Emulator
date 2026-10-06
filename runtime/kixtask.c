/*
 * kixtask - processo de uma tarefa do mini-CICS.
 *
 * O servidor (minicics/server.py) cria um kixtask por transacao. Os
 * programas COBOL traduzidos fazem CALL "KIXCMD" para cada EXEC CICS;
 * aqui o comando e seus parametros sao enviados ao servidor, que
 * implementa a semantica e devolve o que deve ser gravado de volta.
 *
 * Pedido  : u32 tam | spec\0 | u16 n | n * (u8 tipo, i64 valor, u32 tam, bytes)
 * Resposta: u32 tam | u8 acao | EIB | u16 n | n * (u16 idx, u8 tipo, dado)
 *           acao 2 (XCTL) acrescenta: programa[8] | u32 calen | commarea
 */
#include <libcob.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define EIB_LEN 85
#define COMMAREA_MAX 32768

enum { ACT_CONTINUE = 0, ACT_EXIT = 1, ACT_XCTL = 2 };

static int fd_in, fd_out;
static unsigned char eib[EIB_LEN];
static unsigned char commarea[COMMAREA_MAX];

static unsigned char *out;
static size_t out_len, out_cap;

static void die(const char *msg)
{
    fprintf(stderr, "kixtask: %s\n", msg);
    exit(70);
}

static void put(const void *p, size_t n)
{
    if (out_len + n > out_cap) {
        out_cap = (out_len + n) * 2;
        out = realloc(out, out_cap);
        if (!out) die("sem memoria");
    }
    memcpy(out + out_len, p, n);
    out_len += n;
}

static void put_int(uint64_t v, int bytes)
{
    unsigned char b[8];
    for (int i = 0; i < bytes; i++)
        b[i] = (unsigned char)(v >> (8 * (bytes - 1 - i)));
    put(b, bytes);
}

static uint64_t get_int(const unsigned char **p, int bytes)
{
    uint64_t v = 0;
    for (int i = 0; i < bytes; i++)
        v = (v << 8) | *(*p)++;
    return v;
}

static void read_all(void *buf, size_t n)
{
    unsigned char *p = buf;
    while (n > 0) {
        ssize_t r = read(fd_in, p, n);
        if (r <= 0) die("servidor fechou a conexao");
        p += r;
        n -= r;
    }
}

static void write_all(const void *buf, size_t n)
{
    const unsigned char *p = buf;
    while (n > 0) {
        ssize_t r = write(fd_out, p, n);
        if (r <= 0) die("falha ao escrever para o servidor");
        p += r;
        n -= r;
    }
}

static void run_program(const char *name, const unsigned char *data, size_t calen);

/* Envia o pedido montado em `out` e aplica a resposta. */
static void exchange(int nparams)
{
    unsigned char hdr[4];
    hdr[0] = out_len >> 24; hdr[1] = out_len >> 16;
    hdr[2] = out_len >> 8;  hdr[3] = out_len;
    write_all(hdr, 4);
    write_all(out, out_len);

    read_all(hdr, 4);
    size_t len = ((size_t)hdr[0] << 24) | (hdr[1] << 16) | (hdr[2] << 8) | hdr[3];
    unsigned char *reply = malloc(len ? len : 1);
    if (!reply) die("sem memoria");
    read_all(reply, len);

    const unsigned char *p = reply;
    int action = *p++;
    memcpy(eib, p, EIB_LEN);
    p += EIB_LEN;

    int nupd = (int)get_int(&p, 2);
    for (int i = 0; i < nupd; i++) {
        int idx = (int)get_int(&p, 2);
        int kind = *p++;
        if (kind == 'N') {
            int64_t v = (int64_t)get_int(&p, 8);
            if (idx <= nparams) cob_put_s64_param(idx, v);
        } else {
            size_t n = get_int(&p, 4);
            if (idx <= nparams) {
                size_t size = cob_get_param_size(idx);
                memcpy(cob_get_param_data(idx), p, n < size ? n : size);
            }
            p += n;
        }
    }

    if (action == ACT_EXIT)
        cob_stop_run(0);
    if (action == ACT_XCTL) {
        char name[9];
        memcpy(name, p, 8);
        name[8] = 0;
        p += 8;
        size_t calen = get_int(&p, 4);
        run_program(name, p, calen);   /* nao retorna */
    }
    free(reply);
}

static void simple_request(const char *spec)
{
    out_len = 0;
    put(spec, strlen(spec) + 1);
    put_int(0, 2);
    exchange(0);
}

static void run_program(const char *name, const unsigned char *data, size_t calen)
{
    char prog[9];
    int n = 0;
    while (n < 8 && name[n] && name[n] != ' ') { prog[n] = name[n]; n++; }
    prog[n] = 0;

    if (calen > COMMAREA_MAX) calen = COMMAREA_MAX;
    memset(commarea, 0, COMMAREA_MAX);
    if (calen) memmove(commarea, data, calen);

    void *argv[2] = { eib, commarea };
    cob_call(prog, 2, argv);
    /* O programa terminou com GOBACK: equivale a EXEC CICS RETURN. */
    simple_request("RETURN");
    cob_stop_run(0);
}

/* Ponto de entrada chamado pelo COBOL traduzido. */
int KIXCMD(void)
{
    int n = cob_get_num_params();
    if (n < 1) die("KIXCMD sem parametros");

    out_len = 0;
    put(cob_get_param_data(1), cob_get_param_size(1));
    put("", 1);
    put_int(n - 1, 2);
    for (int i = 2; i <= n; i++) {
        int type = cob_get_param_type(i);
        int numeric = (type & COB_TYPE_NUMERIC) && type != COB_TYPE_NUMERIC_FLOAT
                      && type != COB_TYPE_NUMERIC_DOUBLE;
        size_t size = cob_get_param_size(i);
        put(numeric ? "N" : "X", 1);
        put_int(numeric ? (uint64_t)cob_get_s64_param(i) : 0, 8);
        put_int(size, 4);
        put(cob_get_param_data(i), size);
    }
    exchange(n);
    return 0;
}

/*
 * CEEDAYS do Language Environment: converte uma data em dia Lilian
 * (dia 1 = 15/10/1582). Chamado pelo CSUTLDTC do CardDemo.
 * Parametros: data e mascara (u16 tam + texto), i32 resultado e o
 * feedback code de 12 bytes (zeros = ok; senao severidade 3 e a mensagem).
 * Mascaras aceitas: YYYY, MM, DD e separadores literais.
 */
static int cee_fail(unsigned char *fc, int msg)
{
    static const unsigned char tail[4] = { 0x59, 0xC3, 0xC5, 0xC5 };  /* "CEE" */
    fc[0] = 0; fc[1] = 3;
    fc[2] = (unsigned char)(msg >> 8); fc[3] = (unsigned char)msg;
    memcpy(fc + 4, tail, 4);
    return 0;
}

int CEEDAYS(unsigned char *date, unsigned char *pic, unsigned char *lilian,
            unsigned char *fc)
{
    static const int mdays[] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    const unsigned char *d = date + 2, *p = pic + 2;
    int dlen = (date[0] << 8) | date[1], plen = (pic[0] << 8) | pic[1];
    int part[3] = { -1, -1, -1 };          /* ano, mes, dia */

    memset(fc, 0, 12);
    memset(lilian, 0, 4);
    while (plen > 0 && p[plen - 1] == ' ') plen--;
    while (dlen > 0 && d[dlen - 1] == ' ') dlen--;
    if (plen == 0) return cee_fail(fc, 2518);
    if (dlen < plen) return cee_fail(fc, 2507);

    for (int i = 0; i < plen; ) {
        int which, width;
        if (plen - i >= 4 && !memcmp(p + i, "YYYY", 4)) { which = 0; width = 4; }
        else if (plen - i >= 2 && !memcmp(p + i, "MM", 2)) { which = 1; width = 2; }
        else if (plen - i >= 2 && !memcmp(p + i, "DD", 2)) { which = 2; width = 2; }
        else if (p[i] == 'Y' || p[i] == 'M' || p[i] == 'D') return cee_fail(fc, 2518);
        else {
            if (d[i] != p[i]) return cee_fail(fc, 2508);
            i++;
            continue;
        }
        int v = 0;
        for (int k = 0; k < width; k++) {
            if (d[i + k] < '0' || d[i + k] > '9') return cee_fail(fc, 2520);
            v = v * 10 + (d[i + k] - '0');
        }
        part[which] = v;
        i += width;
    }
    int y = part[0], m = part[1], day = part[2];
    if (y < 0 || m < 0 || day < 0) return cee_fail(fc, 2518);
    if (m < 1 || m > 12) return cee_fail(fc, 2517);
    int leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    if (day < 1 || day > mdays[m - 1] + (m == 2 && leap)) return cee_fail(fc, 2508);
    if (y < 1582 || (y == 1582 && (m < 10 || (m == 10 && day < 15))))
        return cee_fail(fc, 2513);

    /* dia juliano (Fliegel-Van Flandern) menos o de 14/10/1582 */
    long a = (14 - m) / 12, yy = y + 4800 - a, mm = m + 12 * a - 3;
    long jdn = day + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045;
    long n = jdn - 2299160;
    lilian[0] = (unsigned char)(n >> 24); lilian[1] = (unsigned char)(n >> 16);
    lilian[2] = (unsigned char)(n >> 8);  lilian[3] = (unsigned char)n;
    return 0;
}

int main(int argc, char **argv)
{
    const char *in = getenv("KIX_FD_IN"), *outfd = getenv("KIX_FD_OUT");
    if (!in || !outfd) die("deve ser iniciado pelo servidor do mini-CICS");
    fd_in = atoi(in);
    fd_out = atoi(outfd);
    cob_init(argc, argv);
    simple_request("INIT");   /* a resposta e um XCTL para o programa inicial */
    die("servidor nao indicou o programa inicial");
    return 0;
}
