' expect: E-PP-ERROR E-UNDECLARED
' `aht30` sends one byte at a time, which the I2C1 peripheral cannot do: the module refuses the hardware option at build time.
Program T
Device = 18F16Q41
Clock = 64
#option I2c = Hardware
Include "aht30"
