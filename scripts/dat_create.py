"""Create a Fallout 2 DAT2 archive from a list of (archive_path, local_path) pairs.

Usage: dat_create.py <output.dat> <archive_path1>=<local_path1> [...]
"""
import struct
import sys
import zlib

def create_dat(output_path, file_entries):
    """file_entries: list of (archive_path, local_path)"""
    # Read all files
    files = []
    for archive_path, local_path in file_entries:
        with open(local_path, 'rb') as f:
            data = f.read()
        compressed = zlib.compress(data)
        # Use compressed if smaller
        if len(compressed) < len(data):
            files.append((archive_path, data, compressed, 1))
        else:
            files.append((archive_path, data, data, 0))

    with open(output_path, 'wb') as out:
        # Write file data, track offsets
        entries = []
        for archive_path, raw_data, stored_data, is_compressed in files:
            offset = out.tell()
            out.write(stored_data)
            entries.append((archive_path, is_compressed, len(raw_data), len(stored_data), offset))

        # Write directory tree
        tree_start = out.tell()
        out.write(struct.pack('<I', len(entries)))
        for archive_path, compressed, decomp_sz, packed_sz, offset in entries:
            name_bytes = archive_path.encode('ascii')
            out.write(struct.pack('<I', len(name_bytes)))
            out.write(name_bytes)
            out.write(struct.pack('<BIII', compressed, decomp_sz, packed_sz, offset))

        tree_size = out.tell() - tree_start
        file_size = out.tell() + 8
        out.write(struct.pack('<I', tree_size))
        out.write(struct.pack('<I', file_size))

    print(f"Created {output_path} with {len(entries)} files")

if __name__ == '__main__':
    output = sys.argv[1]
    pairs = []
    for arg in sys.argv[2:]:
        archive_path, local_path = arg.split('=', 1)
        pairs.append((archive_path, local_path))
    create_dat(output, pairs)
