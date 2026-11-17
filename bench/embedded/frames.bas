' expect: K_SINK=22784
Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Volatile Dim sink As LongWord

' UART byte stream: A5, command, value, XOR checksum; bad checksums are rejected.
Const stream(32) As Byte = (0, 165, 1, 42, 142, 165, 2, 99, 196, 165, 1, 7, 0, 85, 165, 3, 12, 170, 165, 2, 18, 181, 165, 9, 77, 225, 165, 1, 0, 164, 165, 0)
Dim regs(4) As Byte
Dim pass, i, value, state, command, payload, checksum As Byte
Dim accepted, rejected As Word
For pass = 0 To 31
    state = 0
    For i = 0 To 31
        value = stream(i)
        Select state
            Case 0
                If value = 165 Then
                    checksum = value
                    state = 1
                End If
            Case 1
                command = value
                checksum = checksum Xor value
                state = 2
            Case 2
                payload = value
                checksum = checksum Xor value
                state = 3
            Case Else
                If checksum = value Then
                    If command >= 1 And command <= 4 Then
                        regs(command - 1) = payload
                        accepted = accepted + 1
                        sink = sink + payload + command
                    Else
                        rejected = rejected + 1
                    End If
                Else
                    rejected = rejected + 1
                End If
                state = 0
        End Select
    Next
    For i = 0 To 3
        sink = sink + regs(i)
    Next
Next
sink = sink + LongWord(accepted) * 100 + rejected
