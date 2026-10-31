Module Spi
Include "pinio"
' Test double for `Spi`: the bytes of each chip select cycle go to a model of the MCP795xx (the instruction set
' of DS20002300E Table 4-1). The model follows the data sheet where the driver depends on it: OSCRUN follows
' ST / EXTOSC at once, a write to RTCWKDAY clears PWRFAIL and keeps OSCRUN, a write to ALMxWKDAY clears ALMxIF,
' the RTCC block address wraps 0x1F -> 0x00, EEPROM and STATUS writes need the write enable latch (EEWREN) which
' a write clears, the protected EEPROM also needs UNLOCK 0x55 then UNLOCK 0xAA, and a write cycle shows WIP in
' STATUS for three reads.
Dim regs(96) As Byte
Dim ee(256) As Byte
Dim idm(16) As Byte
Dim st As Byte
Dim ins As Byte
Dim ptr As Byte
Dim wel As Boolean
Dim unl As Byte
Dim busy As Byte
Dim bp As Byte
Dim wdtClears As Byte

Public Function SpiInit(ByVal hz As LongWord, ByVal mode As Byte, ByVal sck As Byte, ByVal sdo As Byte, ByVal sdi As Byte) As Byte
    Result = 1
End Function

Public Sub SpiOff(ByVal sck As Byte, ByVal sdo As Byte)
End Sub

Public Function SpiStatus() As Byte
    Result = 0
End Function

Sub Advance()
    Inc(ptr)
    If ins = 19 Or ins = 18 Then
        If ptr = 32 Then
            ptr = 0
        ElseIf ptr = 96 Then
            ptr = 32
        End If
    ElseIf ins = 51 Or ins = 50 Then
        ptr = ptr And 15
    End If
End Sub

Sub StoreRtc(ByVal v As Byte)
    Dim a As Byte
    a = ptr
    If a = 4 Then
        regs(4) = (v And 15) Or (regs(4) And 32)
    ElseIf a = 15 Or a = 22 Then
        regs(a) = v And 247
    Else
        regs(a) = v
    End If
    If a = 1 Or a = 8 Then
        If (regs(1) And 128) <> 0 Or (regs(8) And 8) <> 0 Then
            regs(4) = regs(4) Or 32
        Else
            regs(4) = regs(4) And 223
        End If
    End If
End Sub

Sub Finish(ByVal d As Byte)
    ' The single data byte of SRWRITE, UNLOCK and CLRRAM.
    Dim i As Byte
    If ins = 1 Then
        If wel Then
            bp = (d >> 2) And 3
            wel = False
            busy = 3
        End If
    ElseIf ins = 20 Then
        If wel And d = 85 And unl = 0 Then
            unl = 1
        ElseIf wel And d = 170 And unl = 1 Then
            unl = 2
        Else
            unl = 0
            wel = False
        End If
    ElseIf ins = 84 Then
        For i = 32 To 95
            regs(i) = 0
        Next
    End If
End Sub

Public Function SpiTransfer(ByVal b As Byte) As Byte
    Result = 0
    If Pinio.TakeFall() Then
        st = 0
    End If
    If st = 0 Then
        ins = b
        If b = 19 Or b = 18 Or b = 3 Or b = 2 Or b = 51 Or b = 50 Then
            st = 1
        ElseIf b = 5 Then
            st = 4
        ElseIf b = 1 Or b = 20 Or b = 84 Then
            st = 2
        ElseIf b = 6 Then
            wel = True
            st = 5
        ElseIf b = 68 Then
            Inc(wdtClears)
            st = 5
        Else
            st = 5
        End If
    ElseIf st = 1 Then
        ptr = b
        st = 3
    ElseIf st = 2 Then
        Finish(b)
        st = 5
    ElseIf st = 4 Then
        Result = (bp << 2) Or 0
        If wel Then
            Result = Result Or 2
        End If
        If busy > 0 Then
            Result = Result Or 1
            Dec(busy)
        End If
    ElseIf st = 3 Then
        If ins = 19 Then
            If ptr < 96 Then
                Result = regs(ptr)
            End If
            Advance()
        ElseIf ins = 18 Then
            If ptr < 96 Then
                StoreRtc(b)
            End If
            Advance()
        ElseIf ins = 3 Then
            Result = ee(ptr)
            Inc(ptr)
        ElseIf ins = 2 Then
            If wel Then
                ee(ptr) = b
                wel = False
                busy = 3
            End If
            Inc(ptr)
        ElseIf ins = 51 Then
            If ptr < 16 Then
                Result = idm(ptr)
            End If
            Advance()
        ElseIf ins = 50 Then
            If wel And unl = 2 And ptr < 16 Then
                idm(ptr) = b
                busy = 3
            End If
            wel = False
            unl = 0
            Advance()
        End If
    End If
End Function

Public Sub SpiWrite(ByVal b As Byte)
    Dim r As Byte
    r = SpiTransfer(b)
End Sub

Public Function SpiRead() As Byte
    Result = SpiTransfer(255)
End Function

Public Function ModelReg(ByVal i As Byte) As Byte
    Result = regs(i)
End Function

Public Sub ModelPoke(ByVal i As Byte, ByVal v As Byte)
    regs(i) = v
End Sub

Public Function ModelEe(ByVal i As Byte) As Byte
    Result = ee(i)
End Function

Public Function ModelId(ByVal i As Byte) As Byte
    Result = idm(i)
End Function

Public Function ModelBp() As Byte
    Result = bp
End Function

Public Function ModelWdtClears() As Byte
    Result = wdtClears
End Function
