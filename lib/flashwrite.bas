Module Flashwrite
' Program flash self-write of the 18F27Q10 (DS40002043F, section 12.1) and of the PIC18F0x/1xQ41 (DS40002214G,
' section 10.3; the paragraph after the Q10 notes below). Addresses are PFM *word*
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
'
' PIC18F0x/1xQ41 (chosen with `#if _has(NVMLOCK)`): the same word and sector (page) addressing, the sector being
' 128 words [10.3.1] and the flash 8, 16 or 32 K words, so FlashLastSector is 63, 127 or 255. NVMADR holds the
' byte address, as above. Operations are NVMCMD in NVMCON1 (read 000, word write 011, page read 010, page write
' 101, page erase 110 [Table 10-1]) then the unlock sequence NVMLOCK = 55h, AAh and GO [10.2]; GO clears when the
' operation ends, and WRERR (NVMCON1 bit 7) reports a write-protected or invalid target [10.3.1]. A word write
' needs an erased word [10.3.5]. FlashUpdateWord follows the Word Modify procedure [10.3.6, Example 10-7]: page
' read into the buffer RAM (the last RAM bank, the one after the GPR banks [Table 10-2]; TBLWT writes it with the
' low byte of TBLPTR as the offset [10.3.10.5]), page erase, change the two bytes, page write. The data sheet gives
' no pause after the GO instruction and the silicon errata (DS80000901H, DS80000911H) none for the NVM, so none is added.
' NVMCMD is put back to 000 at the end [10.3.5 step 9]. Interrupts are off from before NVMADR is loaded.
'
' PIC16F17126/46 (DS40002343F, section 15.1; chosen with `Not _has(PRODL)`): word addresses 0..16383 of 14-bit words (values are masked to 14 bits, an
' erased word is 3FFFh) and a "sector" is the 32-word row [15.1.2.3, 15.1.2.4]. NVMADR holds the word address. A row erase is FREE, WREN and the unlock
' (55h, AAh to NVMCON2, then WR); a write loads the write latches one word at a time (LWLO = 1) and then writes all of them to the row (LWLO = 0).
' The latches are reset to 3FFFh at the end of every write (an erase leaves them alone) [15.1.2.4, 15.1.2.3], and a latch not loaded is left blank, so
' a single-word write leaves the other words of the row as they are. The latch array is shared by all rows (NVMADRL[4:0] picks the latch), so a
' latch left loaded by a write that failed (WRERR, a write-protected row) could be written into another row by the next write: after a failed
' write do not write again before a Reset. A written word must be erased. The CPU stalls until each operation ends (about 2 ms for a row write), so there is no wait on WR.
' FlashUpdateWord keeps the row in a 64-byte RAM image (Example 15-4) because there is no sector buffer. The errata (DS80001009E) show nothing for
' the NVM. Interrupts are off from before the address is loaded to the end of the operation.
'
' PIC16F183xx (DS40001799F, DS40001800E, DS40001795K, DS40001839E, section 11.4; the same branch, `Not _has(PRODL)`): the same row of 32 words and 32 write latches [Table 11-1],
' the same NVMCON1 bits and the same flow [Figure 11-5: load the latches with LWLO = 1 and the unlock, then write them with LWLO = 0 and the unlock; a row erase is FREE, WREN
' and the unlock] and no NOPs after the WR bit [11.4.2 note]. NVMADRH bit 7 is unimplemented and reads 1 [Register 11-4], so NVMADRH reads back 80h above the row address bits.
' Errata (DS80000666H item 4.2, DS80000667E 1.2.2, DS80000668L 4.2): WRERR may be set again by a Reset after an interrupted write; FlashWriteWord clears NVMCON1 and reports
' success only by the read-back. The LF parts may fail to write below 2.2 V at -40 C (item 4.1) and may not use NVM below 2.0 V at 25 C or less (item 5.3).
#if _has(NVMLOCK)
Dim NvmGo As NVMCON0.0
Dim NvmErr As NVMCON1.7
Dim IntEn As INTCON0.7
#elseif _has(NVMADRU)
Dim NvmRd As NVMCON1.0
Dim NvmEn As NVMCON0.7
Dim NvmErr As NVMCON0.4
Dim IntEn As INTCON.7
#elseif Not _has(PRODL)
Dim NvmWr As NVMCON1.1
Dim NvmRd As NVMCON1.0
Dim NvmErr As NVMCON1.3
Dim IntEn As INTCON.7
#else
#error "flashwrite: only the NVM registers of the PIC18F27/47Q10 (NVMADRU, NVMCON0.NVMERR), the PIC18-Q41 (NVMLOCK, NVMCON1.WRERR) and the PIC16F171xx (NVMCON1.WRERR) are supported"
#endif

#if _has(PRODL)
' Words in a sector, and the number of the last sector (the program flash in bytes / 256, less one).
Public Const FlashSectorWords = 128
Public Const FlashLastSector As Word = _FlashBytes / 256 - 1

' The PFM word address of the first word of sector s.
Public Function FlashSectorAddr(ByVal sector As Word) As Word
    Result = sector << 7
End Function

Sub SetAddr(ByVal addr As Word)
    NVMADRU = Byte(addr >> 15)
    NVMADRH = Byte(addr >> 7)
    NVMADRL = Byte(addr << 1)
End Sub
#else
' Words in a sector (a row of the program flash), and the number of the last sector (the flash in words / 32,
' less one: the device description gives the size of this core in words).
Public Const FlashSectorWords = 32
Public Const FlashLastSector As Word = _FlashBytes / 32 - 1

' The PFM word address of the first word of sector s.
Public Function FlashSectorAddr(ByVal sector As Word) As Word
    Result = sector << 5
End Function

' NVMADR holds the word address itself on this core.
Sub SetAddr(ByVal addr As Word)
    NVMADRH = Byte(addr >> 8)
    NVMADRL = Byte(addr)
End Sub

' One operation that needs the unlock sequence (NVMCON1 is set up by the caller): 55h, AAh, WR [15.1.2.2]. The
' three steps follow each other with no bank change in between. The CPU stalls until the operation is done and
' resumes with the next instruction, so there is no wait for WR to clear.
Sub Unlock()
    NVMCON2 = 85
    NVMCON2 = 170
    NvmWr = 1
End Sub
#endif

' The word at PFM word address addr (65535 = FFFFh when erased).
Public Function FlashReadWord(ByVal addr As Word) As Word
    SetAddr(addr)
#if _has(NVMLOCK)
    NVMCON1 = 0
    NvmGo = 1
    While NvmGo = 1
    Wend
#elseif Not _has(PRODL)
    NVMCON1 = 0
    NvmRd = 1
    While NvmRd = 1
    Wend
#else
    NvmRd = 1
    While NvmRd = 1
    Wend
#endif
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
#if _has(PRODL)
        SetAddr(sector << 7)
#else
        SetAddr(sector << 5)
#endif
#if _has(NVMLOCK)
        NVMCON1 = 6
        NVMLOCK = 85
        NVMLOCK = 170
        NvmGo = 1
        While NvmGo = 1
        Wend
        If NvmErr = 0 Then
            Result = 1
        End If
        NVMCON1 = 0
        If ie = 1 Then
            IntEn = 1
        End If
#elseif Not _has(PRODL)
        NVMCON1 = 20
        Unlock()
        If NvmErr = 0 Then
            Result = 1
        End If
        NVMCON1 = 0
        If ie = 1 Then
            IntEn = 1
        End If
#else
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
#endif
    End If
End Function

' Programs one word that is still erased (FFFFh), about 50 us. Returns 1 when the word reads back as
' value, 0 when it does not (the word was not erased, or write protection, or NVMERR).
Public Function FlashWriteWord(ByVal addr As Word, ByVal value As Word) As Byte
    Dim ie As Byte
#if Not _has(PRODL)
    Result = 0
    If addr >= _FlashBytes Then
        Exit
    End If
#endif
    ie = IntEn
    IntEn = 0
    SetAddr(addr)
    NVMDAT = value
#if _has(NVMLOCK)
    NVMCON1 = 3
    NVMLOCK = 85
    NVMLOCK = 170
    NvmGo = 1
    While NvmGo = 1
    Wend
    Result = 0
    If NvmErr = 0 Then
        NVMCON1 = 0
        If FlashReadWord(addr) = value Then
            Result = 1
        End If
    End If
    NVMCON1 = 0
    If ie = 1 Then
        IntEn = 1
    End If
#elseif Not _has(PRODL)
    ' Load this word's write latch (LWLO = 1), then write the latches to the row (LWLO = 0): the other
    ' latches hold 3FFFh, which leaves the other words of the row as they are.
    NVMCON1 = 36
    Unlock()
    NVMCON1 = 4
    Unlock()
    Result = 0
    If NvmErr = 0 Then
        NVMCON1 = 0
        If FlashReadWord(addr) = (value And 16383) Then
            Result = 1
        End If
    End If
    NVMCON1 = 0
    If ie = 1 Then
        IntEn = 1
    End If
#else
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
#endif
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
#if _has(NVMLOCK) Or Not _has(PRODL)
    Dim failed As Byte
#endif
#if Not _has(PRODL)
    Dim img(32) As Word
    Dim base As Word
    Dim i As Byte
    Result = 0
    If addr >= _FlashBytes Then
        Exit
    End If
    value = value And 16383
    cur = FlashReadWord(addr)
    If cur = value Then
        Result = 1
    ElseIf cur = 16383 Then
#else
    cur = FlashReadWord(addr)
    If cur = value Then
        Result = 1
    ElseIf cur = 65535 Then
#endif
        Result = FlashWriteWord(addr, value)
    Else
        Result = 0
        ie = IntEn
        IntEn = 0
#if Not _has(PRODL)
        ' Example 15-4 (DS40002343F p.164): row read into a RAM image, row erase, 32 write latches loaded
        ' (LWLO = 1, the last one with LWLO = 0 so it starts the write). The row is the 32 words that
        ' share the upper bits of the address.
        base = addr And 65504
        NVMCON1 = 0
        For i = 0 To 31
            SetAddr(base + i)
            NvmRd = 1
            While NvmRd = 1
            Wend
            img(i) = NVMDAT
        Next
        img(Byte(addr And 31)) = value
        SetAddr(base)
        NVMCON1 = 20
        Unlock()
        If NvmErr = 0 Then
            ' All 32 latches are loaded with LWLO = 1; the write is then a separate operation with LWLO = 0 (the data sheet is
            ' not consistent about whether NVMDAT is read by that last operation, Example 15-4 against Table 15-3; this form
            ' works either way, the latch of word 31 being loaded already).
            NVMCON1 = 36
            For i = 0 To 31
                SetAddr(base + i)
                NVMDAT = img(i)
                Unlock()
            Next
            NVMCON1 = 4
            Unlock()
        End If
        failed = NvmErr
        NVMCON1 = 0
        If ie = 1 Then
            IntEn = 1
        End If
        If failed = 0 Then
            If FlashReadWord(addr) = value Then
                Result = 1
            End If
        End If
#elseif _has(NVMLOCK)
        SetAddr(addr)
        NVMCON1 = 2
        NvmGo = 1
        While NvmGo = 1
        Wend
        NVMCON1 = 6
        NVMLOCK = 85
        NVMLOCK = 170
        NvmGo = 1
        While NvmGo = 1
        Wend
        failed = NvmErr
        If failed = 0 Then
            TBLPTRU = 0
            TBLPTRH = 0
            TBLPTRL = Byte(addr << 1)
            TABLAT = Byte(value)
            Asm
                tblwt*+
            End Asm
            TABLAT = Byte(value >> 8)
            Asm
                tblwt*+
            End Asm
            NVMCON1 = 5
            NVMLOCK = 85
            NVMLOCK = 170
            NvmGo = 1
            While NvmGo = 1
            Wend
            failed = NvmErr
        End If
        NVMCON1 = 0
        If ie = 1 Then
            IntEn = 1
        End If
        If failed = 0 Then
            If FlashReadWord(addr) = value Then
                Result = 1
            End If
        End If
#else
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
#endif
    End If
End Function
