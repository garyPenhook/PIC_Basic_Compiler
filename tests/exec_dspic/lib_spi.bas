' expect: S_OK=1 S_BAD=0 S_CON=33056 S_BRG=199 S_RP=1286 S_SDI=34 S_DONE=1
' Library spi on the dsPIC33CK: SPI1 as host in mode 0 at 10 kHz (Clock = 8, so BRG = 199) with SCK on RB4, SDO on RB5 and SDI on RB2 (pins 20, 21, 18). Checked: SPI1CON1L = 8120h (SPIEN, MSTEN, CKE), the PPS codes (SCK1 = 6 in the low byte of RPOR2
' for RP36, SDO1 = 5 in its high byte for RP37), RPINR20 low byte = RP34, and that a pin the part cannot route (RA1 = 1), the same pin twice and a mode above 3 are refused. **A transfer is not checked:** MPLAB X's simulator has no SPI model (SPI1BUFL
' reads back what was written and SPIRBF never sets), so SpiTransfer, SpiRead and SpiWrite only have to run to their time-out here.
Program S
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW
Include "spi"
Dim OK As Byte
Dim BAD As Byte
Dim R1 As Byte
Dim ST1 As Byte
Dim R2 As Byte
Dim CON As Word
Dim BRG As Word
Dim RP As Word
Dim SDI As Word
Dim DONE As Byte
BAD = Spi.SpiInit(10000, 0, 1, 21, 18)
BAD = BAD + Spi.SpiInit(10000, 0, 20, 20, 18)
BAD = BAD + Spi.SpiInit(10000, 4, 20, 21, 18)
OK = Spi.SpiInit(10000, 0, 20, 21, 18)
R1 = Spi.SpiTransfer($5A)
ST1 = Spi.SpiStatus()
R2 = Spi.SpiRead()
Spi.SpiWrite(1)
CON = SPI1CON1L
BRG = SPI1BRGL
RP = RPOR2
SDI = RPINR20 And $FF
DONE = 1
