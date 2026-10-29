#!/usr/bin/env python3
"""Convert a Scrap Mechanic survival save into a save for this custom game.

The input save is never modified. The output is a byte-for-byte copy of the
SQLite database with two fields changed:

* ``Game.flags`` gets the custom-game bit (``flags | 1``).
* ``Game.mods`` contains one mod record for this custom game.

A mod record is 24 bytes: four zero bytes, a big-endian 32-bit Workshop file
id, and the mod's 16-byte local UUID. The first four bytes of the blob hold the
big-endian record count.

This tool does not publish a Workshop item. Use file-id 0 for a local mod and
put the same mod in the game's user Mods folder.
"""

from __future__ import annotations

import argparse
import shutil
import sqlite3
import struct
import sys
import uuid
from pathlib import Path

CUSTOM_GAME_FLAG = 1
MOD_RECORD_SIZE = 24


def read_game_row(connection: sqlite3.Connection) -> tuple[int, int, bytes]:
    rows = connection.execute(
        "SELECT savegameversion, flags, mods FROM Game"
    ).fetchall()
    if len(rows) != 1:
        raise ValueError(f"expected exactly one Game row, found {len(rows)}")
    savegameversion, flags, mods = rows[0]
    if not isinstance(savegameversion, int) or not isinstance(flags, int):
        raise ValueError("Game.savegameversion and Game.flags must be integers")
    return savegameversion, flags, bytes(mods or b"")


def make_mods_blob(file_id: int, local_id: uuid.UUID) -> bytes:
    if not 0 <= file_id <= 0xFFFFFFFF:
        raise ValueError("file_id must fit in an unsigned 32-bit integer")
    return b"".join(
        (
            struct.pack(">I", 1),
            b"\x00\x00\x00\x00",
            struct.pack(">I", file_id),
            local_id.bytes,
        )
    )


def patch_save(input_path: Path, output_path: Path, file_id: int, local_id: uuid.UUID) -> None:
    if input_path.resolve() == output_path.resolve():
        raise ValueError("input and output must be different files")
    if not input_path.is_file():
        raise FileNotFoundError(input_path)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(input_path, output_path)

    connection = sqlite3.connect(output_path)
    try:
        savegameversion, flags, _old_mods = read_game_row(connection)
        mods_blob = make_mods_blob(file_id, local_id)
        connection.execute(
            "UPDATE Game SET flags = ?, mods = ?",
            (flags | CUSTOM_GAME_FLAG, mods_blob),
        )
        connection.commit()
        if connection.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise ValueError("output save failed SQLite integrity_check")
        print(
            f"wrote {output_path} "
            f"(savegameversion={savegameversion}, flags={flags | CUSTOM_GAME_FLAG}, "
            f"mods=1, file_id={file_id}, local_id={local_id})"
        )
    finally:
        connection.close()


def parse_uuid(value: str) -> uuid.UUID:
    try:
        return uuid.UUID(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="source survival .db")
    parser.add_argument("output", type=Path, help="destination custom-game .db")
    parser.add_argument(
        "--local-id",
        required=True,
        type=parse_uuid,
        help="localId UUID from description.json",
    )
    parser.add_argument(
        "--file-id",
        type=int,
        default=0,
        help="published Workshop file id, or 0 for a local mod",
    )
    args = parser.parse_args()
    try:
        patch_save(args.input, args.output, args.file_id, args.local_id)
    except (OSError, ValueError, sqlite3.Error) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
