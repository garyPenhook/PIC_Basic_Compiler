Module Aht30
Include "i2c"
' Aosong AHT30 temperature and humidity sensor on I2C (AHT30 data sheet, Aosong/ASAIR, Sep 2023;
' section numbers below are from it). The WeAct AHT30 board carries the same part. The bus is set
' up by the caller first with the `I2c` module (at most 400 kHz [Table 8]; keep it at 400 kHz or
' less and sample no more than once a second, or the self-heating passes 0.1 C [2.4]). The bus needs
' external pull-ups (2.0..4.7 kOhm [3.2]); the sensor takes 2.2..5.5 V [Table 2]. The module owns no pins.
'
' The sensor is a client at 7-bit address 0x38 (write byte 0x70, read byte 0x71) [5.1]. A reading takes
' two steps [5.2]:
'   Aht30Start()   sends 0xAC 0x33 0x00, which starts one measurement;
'   Aht30Fetch()   at least 80 ms later, reads 7 bytes: status, 20 bits of humidity, 20 bits of
'                  temperature, and a CRC8 over the first six [Table 9, 5.2].
' Aht30Measure() does both, with the 80 ms wait in between (it blocks for that time). Between the two
' calls the program is free to do other work. After a measurement the sensor goes to sleep until the
' next communication [5.2].
'
' Results are whole hundredths, rounded to the nearest, from RH = S_RH / 2^20 * 100 and
' T = S_T / 2^20 * 200 - 50 [5.2]:
'   temperature  Integer, 1/100 degree C   (2512 = 25.12 C, -1250 = -12.50 C)
'   humidity     Word,    1/100 %RH        (4560 = 45.60 %RH)
' The outputs are written only when the routine returns 0.
'
' Status codes (the first four are those of the `I2c` module):
'   0 ok, 1 timeout (a bus line held low or no pull-up), 2 bus collision, 3 no acknowledge (sensor
'   absent or wrong address), 4 I2c not initialised, 5 busy (status bit 7 still set: Fetch was called
'   before the measurement finished, so the bytes are those of the previous one), 6 CRC mismatch.
' The status byte's calibration bit (bit 3) and CRC_flag (bit 4) are not checked.
' The module is not reentrant, and uses the `I2c` module: do not call it from a handler and from
' the main program.
Dim frame(7) As Byte

' CRC8 of frame(0..5): initial value 0xFF, polynomial x^8 + x^5 + x^4 + 1 (0x31) [5.2].
Function Crc8() As Byte
    Dim i As Byte
    Dim k As Byte
    Dim c As Byte
    c = 255
    i = 0
    While i < 6
        c = c Xor frame(i)
        k = 0
        While k < 8
            If (c And 128) <> 0 Then
                c = (c << 1) Xor 49
            Else
                c = c << 1
            End If
            Inc(k)
        Wend
        Inc(i)
    Wend
    Result = c
End Function

' Waits out the power-up time of the sensor: 5 ms after VDD before the first command [5.2, 2.5].
Public Sub Aht30Init()
    DelayMs(5)
End Sub

' Starts one measurement (Start, 0x70, 0xAC, 0x33, 0x00, Stop). Returns the status code; the Stop is
' always attempted. Call Aht30Fetch no sooner than 80 ms later.
Public Function Aht30Start() As Byte
    Dim s As Byte
    Result = I2c.I2cStart()
    If Result = 0 Then
        Result = I2c.I2cSend(112)
    End If
    If Result = 0 Then
        Result = I2c.I2cSend(172)
    End If
    If Result = 0 Then
        Result = I2c.I2cSend(51)
    End If
    If Result = 0 Then
        Result = I2c.I2cSend(0)
    End If
    s = I2c.I2cStop()
    If Result = 0 Then
        Result = s
    End If
End Function

' Reads the result of the last Aht30Start (Start, 0x71, 7 bytes, Stop), checks it, and converts it to
' `temp` (1/100 degree C) and `rh` (1/100 %RH). Returns the status code (see the header).
Public Function Aht30Fetch(ByRef temp As Integer, ByRef rh As Word) As Byte
    Dim s As Byte
    Dim i As Byte
    Dim raw As LongWord
    Result = I2c.I2cStart()
    If Result = 0 Then
        Result = I2c.I2cSend(113)
    End If
    i = 0
    While Result = 0 And i < 7
        frame(i) = I2c.I2cReceive(i < 6)
        Result = I2c.I2cStatus()
        Inc(i)
    Wend
    s = I2c.I2cStop()
    If Result = 0 Then
        Result = s
    End If
    If Result = 0 Then
        If (frame(0) And 128) <> 0 Then
            Result = 5
        ElseIf Crc8() <> frame(6) Then
            Result = 6
        End If
    End If
    If Result = 0 Then
        ' RH x 100 = S_RH * 10000 / 2^20 = S_RH * 625 / 2^16 (rounded; S_RH * 625 fits 32 bits).
        raw = (LongWord(frame(1)) << 12) Or (LongWord(frame(2)) << 4) Or LongWord(frame(3) >> 4)
        rh = Word((raw * 625 + 32768) >> 16)
        ' T x 100 = S_T * 20000 / 2^20 - 5000 = S_T * 1250 / 2^16 - 5000.
        raw = (LongWord(frame(3) And 15) << 16) Or (LongWord(frame(4)) << 8) Or LongWord(frame(5))
        temp = Integer((raw * 1250 + 32768) >> 16) - 5000
    End If
End Function

' Start, the 80 ms wait of the data sheet [5.2], Fetch. Returns the status code.
Public Function Aht30Measure(ByRef temp As Integer, ByRef rh As Word) As Byte
    Result = Aht30Start()
    If Result = 0 Then
        DelayMs(80)
        Result = Aht30Fetch(temp, rh)
    End If
End Function
