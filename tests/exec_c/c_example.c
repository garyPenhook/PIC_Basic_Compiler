/* Helpers called from c_example.bas. The file is an ordinary C file: it has no main(). */

static unsigned char total;            /* C data, cleared by the XC8 start-up code */

/* CRC-8, polynomial 0x07, one byte at a time. */
unsigned char crc8(unsigned char crc, unsigned char data)
{
    unsigned char i;
    crc ^= data;
    for (i = 0; i < 8; i++)
        crc = (crc & 0x80) ? (unsigned char)((crc << 1) ^ 0x07) : (unsigned char)(crc << 1);
    return crc;
}

void total_add(unsigned char v)
{
    total += v;
}

unsigned int total_get(void)
{
    return total;
}

long scale(int v, unsigned char mul)
{
    return (long)v * mul;
}
