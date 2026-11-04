Module Spi
Include "pinio"
' Test double for `Spi`: every byte goes to the SSD1680 model in the `Pinio` double next to this file.
Public Function SpiInit(ByVal hz As LongWord, ByVal mode As Byte, ByVal sck As Byte, ByVal sdo As Byte, ByVal sdi As Byte) As Byte
    Result = 1
End Function

Public Sub SpiWrite(ByVal b As Byte)
    Pinio.Send(b)
End Sub
