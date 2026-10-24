Module Eeprom
' Data EEPROM (the data Flash memory, DFM) of the 18F27Q10: 1024 bytes at addresses 0..1023
' (DS40002043F, section 12.3; the NVM address of the array is 0x310000, NVMADRU = 0x31).
' Reads are byte reads [12.3.1]. A write erases and programs one byte in one operation [12.3.2] and
' needs NVMEN and the unlock sequence 0x55, 0xAA, WR = 1. The module sets NVMEN only around that
' sequence and disables interrupts for it, then restores the global interrupt enable as it found it.
' The CPU keeps running during the programming time, but the next write waits for the previous one.
' RD is polled until clear, as its description requires [12.5.2]. An address above 1023 is not valid: a read returns 255 and a write does nothing [12.3.4].
'
' Errata (DS80000832G): 1.6.1, after a Reset during a write NVMERR stays set across later Resets
' until one write succeeds, so NVMERR is not a reliable error flag. EepromWrite therefore reports
' success by reading the byte back and clears NVMERR itself. 1.6.2 concerns program flash only.
' The module is not reentrant: do not call it from a handler and from the main program.
Dim NvmWr As NVMCON1.4
Dim NvmRd As NVMCON1.0
Dim NvmEn As NVMCON0.7
Dim NvmErr As NVMCON0.4
Dim IntEn As INTCON.7
Dim NvmDone As PIR7.5

' Number of bytes of data EEPROM.
Public Const EepromSize = 1024

Sub SetAddr(ByVal addr As Word)
    NVMADRU = 49
    NVMADRH = Byte(addr >> 8)
    NVMADRL = Byte(addr)
End Sub

' One byte, 0..255; 255 for an address outside 0..1023.
Public Function EepromRead(ByVal addr As Word) As Byte
    Result = 255
    If addr < EepromSize Then
        SetAddr(addr)
        NvmRd = 1
        While NvmRd = 1
        Wend
        Result = NVMDATL
    End If
End Function

' Writes `value` unless the byte already holds it (saves an erase/write cycle). Returns 1 when the
' byte reads back as `value`, 0 for an invalid address or a failed write.
Public Function EepromWrite(ByVal addr As Word, ByVal value As Byte) As Byte
    Dim ie As Byte
    Result = 0
    If addr < EepromSize Then
        If EepromRead(addr) <> value Then
            NVMDATL = value
            ie = IntEn
            IntEn = 0
            NvmEn = 1
            NVMCON2 = 85
            NVMCON2 = 170
            NvmWr = 1
            If ie = 1 Then
                IntEn = 1
            End If
            While NvmWr = 1
            Wend
            NvmEn = 0
            NvmDone = 0
        End If
        If EepromRead(addr) = value Then
            Result = 1
        End If
        NvmErr = 0
    End If
End Function

' Little-endian 16-bit value at addr, addr + 1.
Public Function EepromReadWord(ByVal addr As Word) As Word
    Result = EepromRead(addr) + EepromRead(addr + 1) * 256
End Function

' Returns 1 when both bytes were stored.
Public Function EepromWriteWord(ByVal addr As Word, ByVal value As Word) As Byte
    Result = EepromWrite(addr, Byte(value)) And EepromWrite(addr + 1, Byte(value >> 8))
End Function
