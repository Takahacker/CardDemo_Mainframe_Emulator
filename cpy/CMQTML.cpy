      * CMQTML - mensagem de gatilho (MQTM) (layout do IBM MQ; escrito para o mini-CICS)
           10  MQTM.
               15  MQTM-STRUCID            PIC X(4).
               15  MQTM-VERSION            PIC S9(9) BINARY.
               15  MQTM-QNAME              PIC X(48).
               15  MQTM-PROCESSNAME        PIC X(48).
               15  MQTM-TRIGGERDATA        PIC X(64).
               15  MQTM-APPLTYPE           PIC S9(9) BINARY.
               15  MQTM-APPLID             PIC X(256).
               15  MQTM-ENVDATA            PIC X(128).
               15  MQTM-USERDATA           PIC X(128).
