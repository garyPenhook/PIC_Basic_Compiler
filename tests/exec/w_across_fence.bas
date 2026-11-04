' expect: WF_WF_R=165 WF_WF_S=65
' A call that is inlined (called once) with a Byte argument and locals that start at zero: the argument is carried in WREG across the
' statement ends of the body, and the load of it must not be taken for dead (the st79 glcd test is the one that failed without the fix).
Program Wf
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim wf_k As Byte
Dim wf_ch As Byte
Dim wf_r As Word
Dim wf_s As Word
Sub Glyph(ByVal ch As Byte)
    Dim i As Byte
    Dim p As Word
    Dim q As Word
    Dim base As Word
    base = Word(ch - 32) * 5
    i = 0
    wf_r = base
    wf_s = Word(i) + Word(ch)
End Sub
wf_ch = 65
wf_k = 3
If wf_k = 1 Then
    wf_r = 7
ElseIf wf_k = 3 Then
    Glyph(wf_ch)
End If
