Module I2c
' Test double for `I2c`: the same routines, wired to a model of the MCP794xx register file instead of a bus
' (RTCC and SRAM at control byte 0xDE/0xDF, EEPROM and protected EEPROM at 0xAE/0xAF). The model follows the
' data sheet where the driver depends on it: OSCRUN follows ST / EXTOSC at once, a write to RTCWKDAY clears
' PWRFAIL and keeps OSCRUN, a write to ALMxWKDAY clears ALMxIF, the RTCC block address wraps 0x1F -> 0x00, the
' protected EEPROM writes only after 0x55, 0xAA to EEUNLOCK (0x09) and locks again, the EEPROM does not
' acknowledge its control byte while a write cycle runs, and addresses past the blocks are not acknowledged.
Dim regs(96) As Byte
Dim ee(128) As Byte
Dim idm(8) As Byte
Dim state As Byte
Dim dev As Byte
Dim rd As Boolean
Dim ptr As Byte
Dim unl As Byte
Dim busy As Byte
Dim last As Byte
Dim starts As Word

Public Function I2cInit(ByVal hz As LongWord, ByVal scl As Byte, ByVal sda As Byte) As Byte
    state = 0
    busy = 0
    unl = 0
    last = 0
    Result = 0
End Function

Public Function I2cStatus() As Byte
    Result = last
End Function

Public Function I2cStart() As Byte
    state = 1
    Inc(starts)
    last = 0
    Result = 0
End Function

Public Function I2cRestart() As Byte
    state = 1
    last = 0
    Result = 0
End Function

Public Function I2cStop() As Byte
    If dev = 1 And state = 3 And busy = 0 And ptr <> 255 Then
        busy = 3
    End If
    state = 0
    last = 0
    Result = 0
End Function

Sub Advance()
    Inc(ptr)
    If dev = 0 Then
        If ptr = 32 Then
            ptr = 0
        ElseIf ptr = 96 Then
            ptr = 32
        End If
    End If
End Sub

Sub StoreRtc(ByVal v As Byte)
    Dim a As Byte
    a = ptr
    If a = 3 Then
        regs(3) = (v And 15) Or (regs(3) And 32)
    ElseIf a = 13 Or a = 20 Then
        regs(a) = v And 247
    ElseIf a = 9 Then
        If v = 85 And unl = 0 Then
            unl = 1
        ElseIf v = 170 And unl = 1 Then
            unl = 2
        Else
            unl = 0
        End If
    Else
        regs(a) = v
    End If
    If a = 0 Or a = 7 Then
        If (regs(0) And 128) <> 0 Or (regs(7) And 8) <> 0 Then
            regs(3) = regs(3) Or 32
        Else
            regs(3) = regs(3) And 223
        End If
    End If
End Sub

Public Function I2cSend(ByVal b As Byte) As Byte
    Result = 0
    last = 0
    If state = 1 Then
        If b = 222 Or b = 223 Then
            dev = 0
            rd = b = 223
            If rd Then
                state = 4
            Else
                state = 2
            End If
        ElseIf b = 174 Or b = 175 Then
            dev = 1
            If busy > 0 Then
                Dec(busy)
                last = 3
                Result = 3
                state = 0
                Exit
            End If
            rd = b = 175
            If rd Then
                state = 4
            Else
                state = 2
            End If
        Else
            last = 3
            Result = 3
            state = 0
        End If
    ElseIf state = 2 Then
        If dev = 0 And b > 95 Then
            last = 3
            Result = 3
            state = 0
        Else
            ptr = b
            state = 3
        End If
    ElseIf state = 3 Then
        If dev = 0 Then
            If ptr > 95 Then
                last = 3
                Result = 3
            Else
                StoreRtc(b)
                Advance()
            End If
        Else
            If ptr < 128 Then
                ee(ptr) = b
            ElseIf ptr >= 240 And ptr < 248 Then
                If unl = 2 Then
                    idm(ptr - 240) = b
                End If
                unl = 0
            End If
            Inc(ptr)
        End If
    Else
        last = 3
        Result = 3
    End If
End Function

Public Function I2cReceive(ByVal ack As Boolean) As Byte
    Result = 0
    last = 0
    If state <> 4 Then
        last = 3
        Exit
    End If
    If dev = 0 Then
        Result = regs(ptr)
        Advance()
    Else
        If ptr < 128 Then
            Result = ee(ptr)
        ElseIf ptr >= 240 And ptr < 248 Then
            Result = idm(ptr - 240)
        End If
        Inc(ptr)
    End If
End Function

' Model access for the test: register / byte `i` of RTCC+SRAM (0..95), and the EEPROM and protected EEPROM.
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
