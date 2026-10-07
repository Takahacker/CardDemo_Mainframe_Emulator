      * CMQGMOV - opcoes do MQGET (MQGMO) (layout do IBM MQ; escrito para o mini-CICS)
           10  MQGMO.
               15  MQGMO-STRUCID           PIC X(4)  VALUE 'GMO '.
               15  MQGMO-VERSION           PIC S9(9) BINARY VALUE 1.
               15  MQGMO-OPTIONS           PIC S9(9) BINARY VALUE 0.
               15  MQGMO-WAITINTERVAL      PIC S9(9) BINARY VALUE 0.
               15  MQGMO-SIGNAL1           PIC S9(9) BINARY VALUE 0.
               15  MQGMO-SIGNAL2           PIC S9(9) BINARY VALUE 0.
               15  MQGMO-RESOLVEDQNAME     PIC X(48) VALUE SPACES.
