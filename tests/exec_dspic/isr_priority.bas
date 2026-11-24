' expect: ISRP_PT=2 ISRP_PI=6 ISRP_PC=4 ISRP_NEST=1 ISRP_HI=1 ISRP_LO=1 ISRP_ORDER=21
' Handlers with priorities: `Interrupt T1(ipLow)` is written to IPC0.T1IP (2) and `Interrupt INT0(ipHigh)` to IPC0.INT0IP (6) at
' start-up; the handler without a priority keeps the reset priority (4). The low handler raises the INT0 flag while it
' runs, so the higher-priority one must run inside it (nest = 1) and finish first (order is built as 2, 1: the
' high handler's digit first). Several handlers are enabled at once.
Program Isrp
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW

Dim pt As Byte
Dim pi As Byte
Dim pc As Byte
Dim nest As Byte
Dim hi As Byte
Dim lo As Byte
Dim order As Byte
Dim inlow As Byte

Interrupt INT0(ipHigh)
    IFS0.INT0IF = 0
    hi = hi + 1
    If inlow = 1 Then
        Inc(nest)
    End If
    order = order * 10 + 2
End Interrupt

Interrupt T1(ipLow)
    IFS0.T1IF = 0
    lo = lo + 1
    inlow = 1
    IFS0.INT0IF = 1
    inlow = 1
    order = order * 10 + 1
    inlow = 0
End Interrupt

Interrupt CNA()
    IFS0.CNAIF = 0
End Interrupt

pt = IPC0.T1IP
pi = IPC0.INT0IP
pc = IPC0.CNAIP
IEC0.INT0IE = 1
IEC0.T1IE = 1
IEC0.CNAIE = 1
Enable(INT0)
Enable(T1)
Enable(CNA)
IFS0.T1IF = 1
While lo = 0 Or hi = 0
Wend
Terminate
