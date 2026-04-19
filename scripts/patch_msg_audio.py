"""Patch a Fallout 2 .msg file to add audio fields from a voice mod DAT.

Usage: patch_msg_audio.py <voice_dat> <input_msg> <output_msg>

Scans the voice DAT for .acm files, extracts message IDs from filenames
(e.g. cas0103.acm -> msg 103, audio name "cas0103"), and patches the
corresponding .msg lines to include the audio field.
"""
import struct
import sys
import re

def get_audio_map(dat_path):
    """Returns {msg_id: audio_basename} from ACM files in a voice DAT."""
    audio_map = {}
    with open(dat_path, 'rb') as f:
        f.seek(-8, 2)
        tree_size = struct.unpack('<I', f.read(4))[0]
        file_size = struct.unpack('<I', f.read(4))[0]
        f.seek(file_size - tree_size - 8)
        file_count = struct.unpack('<I', f.read(4))[0]
        for _ in range(file_count):
            name_len = struct.unpack('<I', f.read(4))[0]
            name = f.read(name_len).decode('ascii', errors='replace')
            f.read(13)
            if name.lower().endswith('.acm'):
                basename = name.rsplit('\\', 1)[-1]
                basename = basename[:basename.rfind('.')]
                digits = basename.lstrip('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ')
                if digits.isdigit():
                    audio_map[int(digits)] = basename
    return audio_map

def patch_msg(input_path, output_path, audio_map):
    """Patch .msg file: fill empty audio fields where voice files exist."""
    line_re = re.compile(r'^\{(\d+)\}\{([^}]*)\}\{(.*)\}$')
    patched = 0
    with open(input_path, 'r', errors='replace') as fin, \
         open(output_path, 'w', newline='\r\n') as fout:
        for line in fin:
            stripped = line.rstrip('\r\n')
            m = line_re.match(stripped)
            if m:
                msg_id = int(m.group(1))
                audio = m.group(2)
                text = m.group(3)
                if not audio and msg_id in audio_map:
                    audio = audio_map[msg_id]
                    patched += 1
                fout.write(f'{{{msg_id}}}{{{audio}}}{{{text}}}\n')
            else:
                fout.write(stripped + '\n')
    return patched

if __name__ == '__main__':
    dat_path = sys.argv[1]
    input_msg = sys.argv[2]
    output_msg = sys.argv[3]
    audio_map = get_audio_map(dat_path)
    print(f"Found {len(audio_map)} audio files in DAT")
    patched = patch_msg(input_msg, output_msg, audio_map)
    print(f"Patched {patched} message lines with audio names -> {output_msg}")
