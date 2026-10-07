/*
 * kixbatch - processo de um passo batch (EXEC PGM=<programa COBOL>).
 *
 * O executor de JCL (minicics/jcl.py) cria um kixbatch por passo. Os
 * programas batch sao compilados com -fcallfh=KIXFH: toda E/S de arquivo
 * passa por KIXFH. Arquivos indexados (os clusters VSAM) sao atendidos
 * pelo lado Python, sobre o mesmo SQLite da regiao online; os demais vao
 * para o libcob, que resolve o DD pelo ambiente (DD_<nome>).
 *
 * O EXEC SQL dos programas batch chega por KIXCMD, como no online: o
 * pedido leva opcode 0 e, depois, o mesmo formato do kixtask.
 *
 * Pedido  : u32 tam | u16 opcode | u64 arquivo | u8 modo | u16 chave ref
 *           | u16 tam nome | nome | u16 n chaves | n * (u32 pos, u32 tam)
 *           | u32 tam maximo | u32 tam atual | registro
 * Resposta: u32 tam | status[2] | u32 tam do registro | registro
 */
#include <libcob.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int fd_in, fd_out;
static unsigned char *out;
static size_t out_len, out_cap;

static void die(const char *msg)
{
    fprintf(stderr, "kixbatch: %s\n", msg);
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

static void read_all(void *buf, size_t n)
{
    unsigned char *p = buf;
    while (n > 0) {
        ssize_t r = read(fd_in, p, n);
        if (r <= 0) die("executor fechou a conexao");
        p += r;
        n -= r;
    }
}

static void write_all(const void *buf, size_t n)
{
    const unsigned char *p = buf;
    while (n > 0) {
        ssize_t r = write(fd_out, p, n);
        if (r <= 0) die("falha ao escrever para o executor");
        p += r;
        n -= r;
    }
}

/* Manipulador de arquivos (EXTFH) de todos os programas batch. */
int KIXFH(unsigned char *opcode, FCD3 *fcd)
{
    if (fcd->fileOrg != ORG_INDEXED)
        return EXTFH(opcode, fcd);

    size_t maxlen = LDCOMPX4(fcd->maxRecLen);
    int nkeys = fcd->kdbPtr ? LDCOMPX2(fcd->kdbPtr->nkeys) : 0;

    out_len = 0;
    put(opcode, 2);
    put_int((uint64_t)(uintptr_t)fcd, 8);
    put_int(fcd->openMode, 1);
    put_int(LDCOMPX2(fcd->refKey), 2);
    put_int(LDCOMPX2(fcd->fnameLen), 2);
    put(fcd->fnamePtr, LDCOMPX2(fcd->fnameLen));
    put_int(nkeys, 2);
    for (int i = 0; i < nkeys; i++) {
        KDB_KEY *k = &fcd->kdbPtr->key[i];
        EXTKEY *part = (EXTKEY *)((char *)fcd->kdbPtr + LDCOMPX2(k->offset));
        put_int(LDCOMPX4(part->pos), 4);
        put_int(LDCOMPX4(part->len), 4);
    }
    put_int(maxlen, 4);
    put_int(LDCOMPX4(fcd->curRecLen), 4);
    put(fcd->recPtr, maxlen);

    unsigned char hdr[4];
    STCOMPX4(out_len, hdr);
    write_all(hdr, 4);
    write_all(out, out_len);

    read_all(hdr, 4);
    size_t len = LDCOMPX4(hdr);
    unsigned char *reply = malloc(len ? len : 1);
    if (!reply) die("sem memoria");
    read_all(reply, len);
    memcpy(fcd->fileStatus, reply, 2);
    size_t reclen = LDCOMPX4(reply + 2);
    if (reclen) {
        if (reclen > maxlen) reclen = maxlen;
        memcpy(fcd->recPtr, reply + 6, reclen);
        STCOMPX4(reclen, fcd->curRecLen);
    }
    free(reply);

    int op = (opcode[0] << 8) | opcode[1];
    if (fcd->fileStatus[0] != '0') {
        /* O libcob 3.2 nao registra o arquivo do erro neste caminho, e o
         * tratador padrao gerado pelo cobc o consulta (para saber se ha
         * FILE STATUS). Todo arquivo do CardDemo tem. */
        static cob_file with_status;
        with_status.flag_select_features = COB_SELECT_FILE_STATUS;
        cob_get_global_ptr()->cob_error_file = &with_status;
    }
    if (fcd->fileStatus[0] == '0') {
        /* idem: a excecao de uma operacao anterior (fim de arquivo em
         * outro arquivo) ficaria valendo e o READ ... INTO nao moveria */
        cob_get_global_ptr()->cob_exception_code = 0;
        if (op >= OP_OPEN_INPUT && op <= OP_OPEN_INPUT_REVERSED)
            fcd->openMode = (unsigned char)(op & 0x03);
        else if (op >= OP_CLOSE && op <= OP_CLOSE_NOREWIND)
            fcd->openMode = OPEN_NOT_OPEN;
    }
    return 0;
}

/* Envia um comando com os parametros da chamada COBOL, a partir de `first`. */
static int command(const char *spec, size_t spec_len, int first)
{
    int n = cob_get_num_params();

    out_len = 0;
    put_int(0, 2);
    put(spec, spec_len);
    put("", 1);
    put_int(n - first + 1, 2);
    for (int i = first; i <= n; i++) {
        int type = cob_get_param_type(i);
        int numeric = (type & COB_TYPE_NUMERIC) && type != COB_TYPE_NUMERIC_FLOAT
                      && type != COB_TYPE_NUMERIC_DOUBLE;
        size_t size = cob_get_param_size(i);
        /* tipo: X, N (inteiro) ou 0x10 + casas decimais */
        int scale = numeric ? cob_get_param_scale(i) : 0;
        unsigned char kind = !numeric ? 'X' : scale > 0 && scale < 32 ? 0x10 + scale : 'N';
        put(&kind, 1);
        put_int(numeric ? (uint64_t)cob_get_s64_param(i) : 0, 8);
        put_int(size, 4);
        put(cob_get_param_data(i), size);
    }
    unsigned char hdr[4];
    STCOMPX4(out_len, hdr);
    write_all(hdr, 4);
    write_all(out, out_len);

    read_all(hdr, 4);
    size_t len = LDCOMPX4(hdr);
    unsigned char *reply = malloc(len ? len : 1);
    if (!reply) die("sem memoria");
    read_all(reply, len);
    const unsigned char *p = reply;
    int nupd = (p[0] << 8) | p[1];
    p += 2;
    for (int i = 0; i < nupd; i++) {
        int idx = (p[0] << 8) | p[1];
        int kind = p[2];
        p += 3;
        if (kind == 'N') {
            int64_t v = 0;
            for (int k = 0; k < 8; k++) v = (v << 8) | *p++;
            if (idx <= n && !cob_get_param_constant(idx)) cob_put_s64_param(idx, v);
        } else {
            size_t size = LDCOMPX4(p);
            p += 4;
            if (idx <= n) {
                size_t room = cob_get_param_size(idx);
                memcpy(cob_get_param_data(idx), p, size < room ? size : room);
            }
            p += size;
        }
    }
    free(reply);
    return 0;
}

/* Ponto de entrada do EXEC SQL / EXEC DLI traduzido (ver runtime/kixtask.c). */
int KIXCMD(void)
{
    if (cob_get_num_params() < 1) die("KIXCMD sem parametros");
    return command((const char *)cob_get_param_data(1), cob_get_param_size(1), 2);
}

/* Interface de chamada do DL/I: atendida em minicics/dli.py. */
int CBLTDLI(void) { return command("DLICALL", 7, 1); }
int AIBTDLI(void) { return command("DLICALL", 7, 1); }

/* CEE3ABD do Language Environment: encerra o passo com abend de usuario. */
int CEE3ABD(unsigned char *abcode, unsigned char *timing)
{
    int code = 0;
    if (cob_get_num_params() >= 1)
        code = (abcode[0] << 24) | (abcode[1] << 16) | (abcode[2] << 8) | abcode[3];
    fflush(stdout);
    fprintf(stderr, "CEE3ABD: abend de usuario U%04d\n", code);
    cob_stop_run(134);
    return 0;
}

/*
 * COBDATFT (app/asm/COBDATFT.asm): converte datas entre AAAAMMDD e
 * AAAA-MM-DD. Area: tipo de entrada, data[20], tipo de saida, data[20].
 */
int COBDATFT(unsigned char *rec)
{
    unsigned char *in = rec + 1, *dst = rec + 22;
    if (rec[0] == '1' && in[4] != '-' && rec[21] != '2') {
        memcpy(dst, in, 4);
        dst[4] = '-';
        memcpy(dst + 5, in + 4, 2);
        dst[7] = '-';
        memcpy(dst + 8, in + 6, 2);
    } else if (rec[0] == '2' && rec[21] != '1') {
        memcpy(dst, in, 4);
        memcpy(dst + 4, in + 5, 2);
        memcpy(dst + 6, in + 8, 2);
    } else {
        memcpy(dst, "INVALID INPUT", 13);
    }
    return 0;
}

/*
 * KIXPSA: blocos de controle do z/OS que o CBSTM03A percorre para listar
 * os DDs do passo (PSA -> TCB -> TIOT). No host a PSA fica no endereco 0;
 * aqui o build troca esse acesso por CALL 'KIXPSA', que devolve uma PSA
 * de mentira com o layout que o programa declara (ponteiros nativos).
 */
int KIXPSA(unsigned char **psaptr)
{
    static unsigned char psa[536 + sizeof(void *)], tcb[12 + sizeof(void *)];
    static unsigned char tiot[24 + 20 * 65 + 4];
    const char *job = getenv("KIX_JOBNAME"), *step = getenv("KIX_STEPNAME");
    const char *dds = getenv("KIX_DDNAMES");
    unsigned char *p = tiot, *entry = tiot + 24;
    void *ptr;

    memset(tiot, 0, sizeof tiot);
    memset(p, ' ', 24);
    if (job) memcpy(p, job, strlen(job) > 8 ? 8 : strlen(job));
    if (step) memcpy(p + 8, step, strlen(step) > 8 ? 8 : strlen(step));
    for (int n = 0; dds && *dds && n < 64; n++, entry += 20) {
        size_t len = strcspn(dds, ",");
        entry[0] = 20;                          /* TIOELNGH */
        memset(entry + 4, ' ', 8);
        memcpy(entry + 4, dds, len > 8 ? 8 : len);
        entry[17] = 0x00; entry[18] = 0xF0; entry[19] = 0x00;   /* UCB */
        dds += len + (dds[len] == ',');
    }
    ptr = tiot; memcpy(tcb + 12, &ptr, sizeof ptr);
    ptr = tcb;  memcpy(psa + 536, &ptr, sizeof ptr);
    *psaptr = psa;
    return 0;
}

/* MVSWAIT (app/asm/MVSWAIT.asm): espera em centesimos de segundo. */
int MVSWAIT(unsigned char *centis)
{
    unsigned int n = (centis[0] << 24) | (centis[1] << 16) | (centis[2] << 8) | centis[3];
    usleep(n * 10000u);
    return 0;
}

int main(int argc, char **argv)
{
    const char *in = getenv("KIX_FD_IN"), *outfd = getenv("KIX_FD_OUT");
    static unsigned char parm[2 + 100];
    if (!in || !outfd || argc < 2) die("deve ser iniciado pelo executor de JCL");
    fd_in = atoi(in);
    fd_out = atoi(outfd);

    /* PARM= do EXEC: meia palavra com o tamanho, depois o texto */
    size_t n = argc > 2 ? strlen(argv[2]) : 0;
    if (n > 100) n = 100;
    parm[0] = (unsigned char)(n >> 8);
    parm[1] = (unsigned char)n;
    memset(parm + 2, ' ', 100);
    if (n) memcpy(parm + 2, argv[2], n);

    cob_init(0, NULL);

    /* Regiao IMS (EXEC PGM=DFSRRC00): o programa recebe as mascaras dos PCBs
     * do PSB, com o nome do DBD preenchido. KIX_IMS_PCBS traz a lista; se o
     * programa tem a entrada DLITCBL, e por ela que o IMS entra. */
    const char *pcbs = getenv("KIX_IMS_PCBS");
    if (pcbs) {
        static unsigned char masks[16][36 + 255];
        void *args[16];
        int count = 0;
        while (*pcbs && count < 16) {
            size_t len = strcspn(pcbs, ",");
            memset(masks[count], ' ', 20);
            memcpy(masks[count], pcbs, len > 8 ? 8 : len);
            args[count] = masks[count];
            count++;
            pcbs += len + (pcbs[len] == ',');
        }
        const char *entry = argv[1];
        if (cob_resolve(argv[1]) && cob_resolve("DLITCBL")) {
            entry = "DLITCBL";
            if (count > 1 && !memcmp(masks[0], "IOPCB", 5)) {   /* so os PCBs de banco */
                memmove(args, args + 1, sizeof(void *) * (size_t)(count - 1));
                count--;
            }
        }
        cob_stop_run(cob_call(entry, count, args));
    }

    void *args[1] = { parm };
    int rc = cob_call(argv[1], 1, args);
    cob_stop_run(rc);
    return 0;
}
