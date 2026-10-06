"""Linha de comando: python3 -m minicics {build,load,run}."""
import argparse

from . import build, load, server


def main():
    parser = argparse.ArgumentParser(prog='minicics', description=__import__('minicics').__doc__)
    parser.add_argument('--carddemo', help='raiz do repositorio do CardDemo '
                        '(padrao: $CARDDEMO_HOME ou ../aws-mainframe-modernization-carddemo)')
    sub = parser.add_subparsers(dest='command', required=True)

    p = sub.add_parser('build', help='compila o kixtask e os programas online')
    p.add_argument('programs', nargs='*', help='programas (padrao: todos os CO*.cbl)')

    p = sub.add_parser('load', help='define os arquivos VSAM e carrega os dados')
    p.add_argument('--data', help='diretorio de dados (padrao: data/)')

    p = sub.add_parser('run', help='sobe a regiao e atende terminais TN3270')
    p.add_argument('--host', default='127.0.0.1')
    p.add_argument('--port', type=int, default=3270)
    p.add_argument('--data', help='diretorio de dados (padrao: data/)')
    p.add_argument('--start', metavar='TRANSID', type=str.upper,
                   help='transacao iniciada ao conectar (ex.: CC00)')
    p.add_argument('--trace', action='store_true', help='registra cada comando EXEC CICS')

    args = parser.parse_args()
    if args.command == 'build':
        build.main(args.carddemo, args.programs)
    elif args.command == 'load':
        load.main(args.carddemo, args.data)
    else:
        server.main(args.host, args.port, carddemo=args.carddemo, data_dir=args.data,
                    start=args.start, trace=args.trace)


if __name__ == '__main__':
    main()
