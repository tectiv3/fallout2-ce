"""Extract a file from a Fallout 2 DAT2 archive."""
import struct
import sys
import zlib

def extract(dat_path, file_path, output_path=None):
    with open(dat_path, 'rb') as f:
        f.seek(-8, 2)
        tree_size = struct.unpack('<I', f.read(4))[0]
        file_size = struct.unpack('<I', f.read(4))[0]
        f.seek(file_size - tree_size - 8)
        file_count = struct.unpack('<I', f.read(4))[0]
        for i in range(file_count):
            name_len = struct.unpack('<I', f.read(4))[0]
            name = f.read(name_len).decode('ascii', errors='replace')
            compressed, decomp_sz, packed_sz, offset = struct.unpack('<BIII', f.read(13))
            if name.lower() == file_path.lower():
                f.seek(offset)
                data = f.read(packed_sz)
                if compressed:
                    data = zlib.decompress(data)
                if output_path:
                    with open(output_path, 'wb') as out:
                        out.write(data)
                    print(f"Extracted {name} -> {output_path} ({len(data)} bytes)")
                else:
                    sys.stdout.buffer.write(data)
                return True
    print(f"File not found: {file_path}", file=sys.stderr)
    return False

if __name__ == "__main__":
    dat_path = sys.argv[1]
    file_path = sys.argv[2]
    output_path = sys.argv[3] if len(sys.argv) > 3 else None
    extract(dat_path, file_path, output_path)
