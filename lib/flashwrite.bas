Module Flashwrite
' Program flash self-write of the 18F27Q10 (DS40002043F, section 12.1). Addresses are PFM *word*
' addresses 0..65535 (Table 12-2: 65536 words); word w is byte address 2*w, which is what NVMADR holds
' [12.5.5]. A sector is 128 words = 256 bytes, so sector s starts at word 128*s (sectors 0..511).
' The last sector, FlashLastSector, is the one a program normally keeps for data: the compiler fills
' flash from address 0 upward, so check the code size (basil --report) before using any other sector.
' Erasing a sector that holds code destroys that code. Vectors and start-up are in sector 0.
'
' Reads use RD and need no unlock [12.1.1.6, NVMCON0.NVMEN note]. Every other operation needs NVMEN and
' the unlock sequence, two bytes into NVMCON2 then the control bit [12.1.2, Table 12-4]:
'   word write 55h AAh WR, sector write DDh 22h SECWR, sector erase CCh 33h SECER, sector read BBh 44h SECRD.
' The sequence must not be interrupted, so each routine disables interrupts (INTCON.GIE, which with
' IPEN = 1 disables all interrupts [15.13.1]) and restores GIE as it found it. The CPU stalls while a
' write or erase runs: about 50 us for a word, 10 ms typical for a sector erase, 6 ms for a sector write
' [Table 39-5 MEM35..MEM37], so interrupts are served late, not lost. Do not call this module from a
' handler and from the main program; it is not reentrant. Interrupts are switched off before NVMADR,
' NVMDAT, TBLPTR and TABLAT are loaded, not just around the unlock sequence, so a handler that reads a
' Const array (a table read moves TBLPTR) cannot disturb them.
'
' Errata (DS80000832G):
'   1.9.1  the first instruction after a self-write instruction may not execute. Workaround: two
'          all-zero NOPs immediately after it [p.7]. Every unlock sequence below ends BSF NVMCON1,x
'          followed by exactly two NOPs inside the same Asm block, so nothing else can be scheduled between.
'   1.6.2  do not write the program flash above 85 degrees C [p.6]. Erase and write are writes.
'   1.6.1  after a Reset during a write NVMERR stays set across later Resets until a write succeeds, so
'          NVMERR is cleared before each operation and read right after it. Writes are also verified.
' Endurance is 10k erase/write cycles per sector (MEM30), so FlashUpdateWord does nothing when the
' word already holds the value. Write protection (the WRTn configuration bits) makes a write fail and
' NVMERR is set [12.1.4].
#if not _has(NVMADRU)
#error "flashwrite: only the PIC18F27/47Q10 NVM registers (NVMADRU, NVMCON0.NVMERR) are supported"
#endif
Dim NvmRd As NVMCON1.0
Dim NvmEn As NVMCON0.7
Dim NvmErr As NVMCON0.4
Dim IntEn As INTCON.7

' Words in a sector, and the number of the last sector.
Public Const FlashSectorWords = 128
Public Const FlashLastSector = 511

' The PFM word address of the first word of sector s.
Public Function FlashSectorAddr(ByVal sector As Word) As Word
    Result = sector << 7
End Function

Sub SetAddr(ByVal addr As Word)
    NVMADRU = Byte(addr >> 15)
    NVMADRH = Byte(addr >> 7)
    NVMADRL = Byte(addr << 1)
End Sub

' The word at PFM word address addr (65535 = FFFFh when erased).
Public Function FlashReadWord(ByVal addr As Word) As Word
    SetAddr(addr)
    NvmRd = 1
    While NvmRd = 1
    Wend
    Result = NVMDAT
End Function

' Erases the sector (every word becomes FFFFh). Returns 1 on success, 0 for a sector above 511 (which
' would wrap onto a lower one) or when NVMERR was set (write-protected sector).
Public Function FlashEraseSector(ByVal sector As Word) As Byte
    Dim ie As Byte
    Result = 0
    If sector <= FlashLastSector Then
        ie = IntEn
        IntEn = 0
        SetAddr(sector << 7)
        NvmErr = 0
        NvmEn = 1
        Asm
            movlw 0xCC
            movwf NVMCON2, c
            movlw 0x33
            movwf NVMCON2, c
            bsf NVMCON1, 6, c   ; SECER
            nop                 ; errata 1.9.1: two all-zero NOPs after the self-write instruction
            nop
        End Asm
        NvmEn = 0
        If ie = 1 Then
            IntEn = 1
        End If
        If NvmErr = 0 Then
            Result = 1
        End If
        NvmErr = 0
    End If
End Function

' Programs one word that is still erased (FFFFh), about 50 us. Returns 1 when the word reads back as
' value, 0 when it does not (the word was not erased, or write protection, or NVMERR).
Public Function FlashWriteWord(ByVal addr As Word, ByVal value As Word) As Byte
    Dim ie As Byte
    ie = IntEn
    IntEn = 0
    SetAddr(addr)
    NVMDAT = value
    NvmErr = 0
    NvmEn = 1
    Asm
        movlw 0x55
        movwf NVMCON2, c
        movlw 0xAA
        movwf NVMCON2, c
        bsf NVMCON1, 4, c   ; WR
        nop                 ; errata 1.9.1: two all-zero NOPs after the self-write instruction
        nop
    End Asm
    NvmEn = 0
    If ie = 1 Then
        IntEn = 1
    End If
    Result = 0
    If NvmErr = 0 Then
        If FlashReadWord(addr) = value Then
            Result = 1
        End If
    End If
    NvmErr = 0
End Function

' Replaces one word and keeps the other 127 of its sector, about 20 ms. Does nothing when the word
' already holds value, and uses the quick word write when it is erased. Otherwise follows Example 12-4:
' sector read into the holding registers, sector erase, the two bytes of the word to the holding
' registers with TBLWT, sector write. The holding registers (RAM bank 13) are not used by the compiler.
' Returns 1 when the word reads back as value, 0 on failure; after a failure in the middle the sector
' may be erased, so a program that needs its data should write it again.
Public Function FlashUpdateWord(ByVal addr As Word, ByVal value As Word) As Byte
    Dim cur As Word
    Dim ie As Byte
    cur = FlashReadWord(addr)
    If cur = value Then
        Result = 1
    ElseIf cur = 65535 Then
        Result = FlashWriteWord(addr, value)
    Else
        Result = 0
        ie = IntEn
        IntEn = 0
        TBLPTRU = 0
        TBLPTRH = 0
        TBLPTRL = Byte(addr << 1)
        SetAddr(addr)
        NvmErr = 0
        NvmEn = 1
        Asm
            movlw 0xBB
            movwf NVMCON2, c
            movlw 0x44
            movwf NVMCON2, c
            bsf NVMCON1, 1, c   ; SECRD
            nop                 ; errata 1.9.1: two all-zero NOPs after the self-write instruction
            nop
        End Asm
        If NvmErr = 0 Then
            Asm
                movlw 0xCC
                movwf NVMCON2, c
                movlw 0x33
                movwf NVMCON2, c
                bsf NVMCON1, 6, c   ; SECER
                nop                 ; errata 1.9.1
                nop
            End Asm
        End If
        If NvmErr = 0 Then
            TABLAT = Byte(value)
            Asm
                tblwt*+
            End Asm
            TABLAT = Byte(value >> 8)
            Asm
                tblwt*+
                movlw 0xDD
                movwf NVMCON2, c
                movlw 0x22
                movwf NVMCON2, c
                bsf NVMCON1, 5, c   ; SECWR
                nop                 ; errata 1.9.1
                nop
            End Asm
        End If
        NvmEn = 0
        If ie = 1 Then
            IntEn = 1
        End If
        If NvmErr = 0 Then
            If FlashReadWord(addr) = value Then
                Result = 1
            End If
        End If
        NvmErr = 0
    End If
End Function
