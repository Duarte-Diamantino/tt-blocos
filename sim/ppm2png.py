"""Converte o frame.ppm (P3) gravado pelo testbench num PNG, só com a biblioteca padrão."""
import struct
import sys
import zlib


def main(src: str, dst: str) -> None:
    tokens = open(src).read().split()
    assert tokens[0] == "P3", "esperava um PPM P3"
    w, h, maxv = int(tokens[1]), int(tokens[2]), int(tokens[3])
    vals = [int(t) * 255 // maxv for t in tokens[4:]]
    assert len(vals) == w * h * 3, f"imagem incompleta: {len(vals)} de {w * h * 3} valores"

    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw.extend(vals[y * w * 3:(y + 1) * w * 3])

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    with open(dst, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
