"""Lossless archive transport: reuse old ZIP streams or recompress unchanged entries.

Only a byte-identical result with the recorded SHA-256 is accepted. No extraction
to the filesystem and no archive paths are used as local paths.
"""
import hashlib
import json
import os
import pathlib
import struct
import sys
import zipfile
import zlib

MAGIC = b"ABDZIP1\n"


def pinned_deflate(data, level):
    """Use a pinned Linux x86-64 libz when Python embeds another zlib version."""
    import ctypes as C
    class Stream(C.Structure):
        _fields_ = [("next_in", C.c_void_p), ("avail_in", C.c_uint), ("total_in", C.c_ulong),
                    ("next_out", C.c_void_p), ("avail_out", C.c_uint), ("total_out", C.c_ulong),
                    ("msg", C.c_char_p), ("state", C.c_void_p), ("zalloc", C.c_void_p),
                    ("zfree", C.c_void_p), ("opaque", C.c_void_p), ("data_type", C.c_int),
                    ("adler", C.c_ulong), ("reserved", C.c_ulong)]
    lib = C.CDLL(os.environ["ABADDON_ZLIB_PATH"])
    lib.zlibVersion.restype = C.c_char_p
    lib.deflateInit2_.argtypes = [C.POINTER(Stream), C.c_int, C.c_int, C.c_int, C.c_int, C.c_int, C.c_char_p, C.c_int]
    lib.deflateBound.argtypes = [C.POINTER(Stream), C.c_ulong]
    lib.deflateBound.restype = C.c_ulong
    lib.deflate.argtypes = [C.POINTER(Stream), C.c_int]
    lib.deflateEnd.argtypes = [C.POINTER(Stream)]
    stream = Stream()
    code = lib.deflateInit2_(C.byref(stream), level, 8, -15, 8, 0, lib.zlibVersion(), C.sizeof(Stream))
    if code:
        raise ValueError("pinned libz initialization failed: %d" % code)
    try:
        source = C.create_string_buffer(data)
        destination = C.create_string_buffer(lib.deflateBound(C.byref(stream), len(data)))
        stream.next_in, stream.avail_in = C.addressof(source), len(data)
        stream.next_out, stream.avail_out = C.addressof(destination), len(destination)
        code = lib.deflate(C.byref(stream), 4)  # Z_FINISH
        if code != 1:
            raise ValueError("pinned libz failed to finish: %d" % code)
        return destination.raw[:stream.total_out]
    finally:
        lib.deflateEnd(C.byref(stream))


def digest(data):
    return hashlib.sha256(data).hexdigest()


def raw_block(data, info):
    name_len, extra_len = struct.unpack_from("<HH", data, info.header_offset + 26)
    offset = info.header_offset + 30 + name_len + extra_len
    return offset, data[offset:offset + info.compress_size]


def deflate(data, level):
    if os.environ.get("ABADDON_ZLIB_PATH"):
        return pinned_deflate(data, level)
    stream = zlib.compressobj(level, zlib.DEFLATED, -15)
    return stream.compress(data) + stream.flush()


def create(old_path, new_path, delta_path):
    old, new = old_path.read_bytes(), new_path.read_bytes()
    ops, literals = [], bytearray()

    def literal(data):
        if data:
            if ops and ops[-1][0] == "L":
                ops[-1][1] += len(data)
            else:
                ops.append(["L", len(data)])
            literals.extend(data)

    with zipfile.ZipFile(old_path) as oz, zipfile.ZipFile(new_path) as nz:
        old_raw, old_plain = {}, {}
        for info in oz.infolist():
            offset, data = raw_block(old, info)
            old_raw[(digest(data), len(data))] = offset
            old_plain.setdefault((info.CRC, info.file_size), []).append(info)
        cursor = 0
        counts = {"raw": 0, "deflate": 0, "literal": 0}
        for info in sorted(nz.infolist(), key=lambda item: item.header_offset):
            offset, data = raw_block(new, info)
            literal(new[cursor:offset])
            key = digest(data), len(data)
            if key in old_raw:
                ops.append(["C", old_raw[key], len(data)])
                counts["raw"] += len(data)
            else:
                candidate = None
                if info.compress_type == zipfile.ZIP_DEFLATED:
                    for prior in old_plain.get((info.CRC, info.file_size), []):
                        plain = oz.read(prior)
                        if plain != nz.read(info):
                            continue
                        for level in (6, 9):
                            if deflate(plain, level) == data:
                                candidate = ["D", prior.filename, level, key[0], len(data)]
                                break
                        if candidate:
                            break
                if candidate:
                    ops.append(candidate)
                    counts["deflate"] += len(data)
                else:
                    literal(data)
                    counts["literal"] += len(data)
            cursor = offset + len(data)
        literal(new[cursor:])
    metadata = {"schema": 1, "base_sha256": digest(old), "result_sha256": digest(new),
                "result_size": len(new), "zlib_version": zlib.ZLIB_VERSION, "operations": ops}
    header = zlib.compress(json.dumps(metadata, separators=(",", ":")).encode(), 9)
    delta = MAGIC + struct.pack(">Q", len(header)) + header + bytes(literals)
    delta_path.write_bytes(delta)
    print(json.dumps({"patch": str(delta_path), "size": len(delta), "sha256": digest(delta), "reused": counts,
                      "literal_total": len(literals), "header_size": len(header), "operations": len(ops)}), flush=True)


def apply(old_path, delta_path, destination):
    old, delta = old_path.read_bytes(), delta_path.read_bytes()
    if not delta.startswith(MAGIC):
        raise ValueError("Invalid delta header")
    header_length = struct.unpack_from(">Q", delta, len(MAGIC))[0]
    offset = len(MAGIC) + 8
    meta = json.loads(zlib.decompress(delta[offset:offset + header_length]))
    offset += header_length
    if meta["schema"] != 1 or digest(old) != meta["base_sha256"]:
        raise ValueError("Wrong base archive or delta schema")
    result = bytearray()
    with zipfile.ZipFile(old_path) as oz:
        for op in meta["operations"]:
            if op[0] == "L":
                block = delta[offset:offset + op[1]]
                if len(block) != op[1]:
                    raise ValueError("Truncated literal")
                offset += op[1]
            elif op[0] == "C":
                block = old[op[1]:op[1] + op[2]]
                if len(block) != op[2]:
                    raise ValueError("Invalid copy range")
            elif op[0] == "D":
                block = deflate(oz.read(op[1]), op[2])
                if len(block) != op[4] or digest(block) != op[3]:
                    raise ValueError("DEFLATE output differs for %r; producer zlib=%s, current=%s" %
                                     (op[1], meta["zlib_version"], zlib.ZLIB_VERSION))
            else:
                raise ValueError("Unknown operation")
            result.extend(block)
    if offset != len(delta) or len(result) != meta["result_size"] or digest(result) != meta["result_sha256"]:
        raise ValueError("Reconstructed archive does not match the recorded bytes")
    destination.write_bytes(result)
    print(json.dumps({"reconstructed": str(destination), "size": len(result), "sha256": digest(result),
                      "byte_identical_by_sha256": True}), flush=True)


if __name__ == "__main__":
    mode, old, other, dest = sys.argv[1:]
    function = {"create": create, "apply": apply}[mode]
    function(pathlib.Path(old), pathlib.Path(other), pathlib.Path(dest))
