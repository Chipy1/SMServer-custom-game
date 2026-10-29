from __future__ import annotations

import sqlite3
import struct
import tempfile
import unittest
import uuid
from pathlib import Path

from tools.port_save import make_mods_blob, patch_save


class PortSaveTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.source = self.root / "survival.db"
        connection = sqlite3.connect(self.source)
        connection.execute(
            "CREATE TABLE Game (savegameversion INTEGER, flags INTEGER, mods BLOB)"
        )
        connection.execute("INSERT INTO Game VALUES (29, 14, ?)", (b"\x00\x00\x00\x00",))
        connection.commit()
        connection.close()

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def test_make_mods_blob(self) -> None:
        local_id = uuid.UUID("703ab739-902f-4838-b76b-9682f6a5c86a")
        blob = make_mods_blob(3440826317, local_id)
        self.assertEqual(len(blob), 28)
        self.assertEqual(struct.unpack(">I", blob[:4])[0], 1)
        self.assertEqual(blob[4:8], b"\x00\x00\x00\x00")
        self.assertEqual(struct.unpack(">I", blob[8:12])[0], 3440826317)
        self.assertEqual(uuid.UUID(bytes=blob[12:28]), local_id)

    def test_patch_save_preserves_source(self) -> None:
        local_id = uuid.UUID("703ab739-902f-4838-b76b-9682f6a5c86a")
        destination = self.root / "custom.db"
        patch_save(self.source, destination, 0, local_id)

        source = sqlite3.connect(self.source)
        self.assertEqual(
            source.execute("SELECT flags, mods FROM Game").fetchone(),
            (14, b"\x00\x00\x00\x00"),
        )
        source.close()

        custom = sqlite3.connect(destination)
        flags, mods = custom.execute("SELECT flags, mods FROM Game").fetchone()
        self.assertEqual(flags, 15)
        self.assertEqual(struct.unpack(">I", mods[:4])[0], 1)
        self.assertEqual(uuid.UUID(bytes=mods[12:28]), local_id)
        custom.close()

    def test_rejects_same_path(self) -> None:
        with self.assertRaises(ValueError):
            patch_save(
                self.source,
                self.source,
                0,
                uuid.UUID("703ab739-902f-4838-b76b-9682f6a5c86a"),
            )


if __name__ == "__main__":
    unittest.main()
