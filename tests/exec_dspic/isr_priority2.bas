' expect: ISRP2_PT=6 ISRP2_PI=3 ISRP2_PC=4 ISRP2_NEST=0 ISRP2_ORDER=12
' The same two handlers with the priorities the other way round (T1 is 6, INT0 is 3 given as a number): the raised INT0 flag
' waits until the T1 handler is done, so nothing nests and the order is 1, then 2.
Program Isrp2
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

Interrupt INT0(3)
    IFS0.INT0IF = 0
    hi = hi + 1
    If inlow = 1 Then
        Inc(nest)
    End If
    order = order * 10 + 2
End Interrupt

Interrupt T1(ipHigh)
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
