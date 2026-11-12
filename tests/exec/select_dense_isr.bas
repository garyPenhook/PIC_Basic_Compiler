' expect: SDI_OK=1 SDI_HITS=300
' devices: 18F27Q10 18F16Q41
' engine: mdb
' A handler and the main program both dispatch through dense Selects (a computed jump through PCL on the PIC18, which
' reads PCL to set PCLATH and PCLATU first). Timer0 interrupts land at many places of the main loop, so some fall
' between the read of PCL and the `addwf PCL`; the handler's own jump must not leave PCLATH/PCLATU changed for the
' main program. basil-sim does not model PCLATH, so this runs in MDB. The main loop adds the arm number of each value it dispatches; every pass must see its own value.
Program SDI
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
#if _has(PIR3.TMR0IF)
Dim T0If As PIR3.7
Dim T0Ie As PIE3.7
#else
Dim T0If As PIR0.5
Dim T0Ie As PIE0.5
#endif
Dim hits As Word
Dim hv As Byte
Dim ok As Byte
Dim i As Byte
Dim sum As Word
Dim want As Word

Function Pick(ByVal s As Byte) As Byte
    Select s
        Case 0
            Result = 3
        Case 1
            Result = 5
        Case 2
            Result = 7
        Case 3
            Result = 11
        Case 4
            Result = 13
        Case 5
            Result = 17
        Case 6
            Result = 19
        Case 7
            Result = 23
        Case Else
            Result = 0
    End Select
End Function

Interrupt Tick()
    T0If = 0
    Inc(hits)
    hv = hits And 7
    Select hv
        Case 0
            hv = 1
        Case 1
            hv = 2
        Case 2
            hv = 3
        Case 3
            hv = 4
        Case 4
            hv = 5
        Case 5
            hv = 6
        Case 6
            hv = 7
        Case Else
            hv = 8
    End Select
    If hits < 300 Then
        TMR0H = 240 + Byte(hits And 7)
    Else
        T0CON0 = 0
    End If
End Interrupt

T0Ie = 1
Enable(Tick)
T0CON1 = 65
T0CON0 = 128
ok = 1
While hits < 300
    For i = 0 To 8
        sum = 0
        sum = sum + Pick(i)
        Select i
            Case 0
                sum = sum + 100
            Case 1
                sum = sum + 200
            Case 2
                sum = sum + 300
            Case 3
                sum = sum + 400
            Case 4
                sum = sum + 500
            Case 5
                sum = sum + 600
            Case 6
                sum = sum + 700
            Case 7
                sum = sum + 800
            Case Else
                sum = sum + 900
        End Select
        want = 0
        Select i
            Case 0
                want = 103
            Case 1
                want = 205
            Case 2
                want = 307
            Case 3
                want = 411
            Case 4
                want = 513
            Case 5
                want = 617
            Case 6
                want = 719
            Case 7
                want = 823
            Case Else
                want = 900
        End Select
        If sum <> want Then
            ok = 0
        End If
    Next
Wend
Disable(Tick)
