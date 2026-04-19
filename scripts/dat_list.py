"""List contents of a Fallout 2 DAT2 file."""
import struct
import sys

def list_dat(path, filter_str=None):
    with open(path, 'rb') as f:
        f.seek(-8, 2)
        tree_size = struct.unpack('<I', f.read(4))[0]
        file_size = struct.unpack('<I', f.read(4))[0]
        f.seek(file_size - tree_size - 8)
        file_count = struct.unpack('<I', f.read(4))[0]
        print(f"DAT: {path}")
        print(f"Files: {file_count}")
        for i in range(file_count):
            name_len = struct.unpack('<I', f.read(4))[0]
            name = f.read(name_len).decode('ascii', errors='replace')
            compressed, decomp_sz, packed_sz, offset = struct.unpack('<BIII', f.read(13))
            if filter_str is None or filter_str.lower() in name.lower():
                comp_str = "zlib" if compressed else "raw"
                print(f"  {name}  ({comp_str}, {decomp_sz} bytes)")

if __name__ == "__main__":
    path = sys.argv[1]
    filt = sys.argv[2] if len(sys.argv) > 2 else None
    list_dat(path, filt)
