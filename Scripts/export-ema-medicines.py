#!/usr/bin/env python3
"""Extract a German medicine index from the EMA Article 57 workbook.

Download the workbook from the source page, then pass its path as the sole argument.
The extract contains only product names, active substances, and routes.
"""

import re
import sys
from pathlib import Path
from xml.etree import ElementTree
from zipfile import ZipFile


SOURCE = (
    "https://www.ema.europa.eu/en/human-regulatory-overview/post-authorisation/"
    "data-medicines-iso-idmp-standards-post-authorisation/public-data-article-57-database"
)
REUSE_NOTICE = "https://www.ema.europa.eu/en/about-us/about-website/legal-notice"
OUTPUT = (
    Path(__file__).resolve().parents[1]
    / "FreakLog/Assets/Assets.xcassets/GermanMedicines.dataset/Medicines.tsv"
)


def extract(workbook):
    with ZipFile(workbook) as archive:
        strings = [
            "".join(part.text or "" for part in item.findall(".//{*}t"))
            for item in ElementTree.fromstring(archive.read("xl/sharedStrings.xml"))
        ]
        medicines = set()
        metadata = {}
        found_columns = False

        with archive.open("xl/worksheets/sheet1.xml") as sheet:
            rows = ElementTree.iterparse(sheet, events=("end",))
            for _, row in rows:
                if not row.tag.endswith("}row"):
                    continue
                values = {}
                for cell in row.findall("{*}c"):
                    value = cell.findtext("{*}v")
                    if cell.get("t") == "s" and value is not None:
                        column = cell.get("r", "").rstrip("0123456789")
                        values[column] = " ".join(strings[int(value)].split())
                row.clear()

                label = values.get("A", "")
                if not found_columns:
                    if label.startswith("EMA/"):
                        metadata["revision"] = label
                    if label.startswith("Data as present"):
                        metadata["date"] = label.rsplit(" ", maxsplit=1)[-1]
                    found_columns = (
                        label.startswith("Product name")
                        and values.get("B", "").startswith("Active substance")
                        and values.get("C") == "Route of administration"
                        and values.get("D") == "Product authorisation country"
                    )
                    continue

                if values.get("D") == "Germany" and label and values.get("B"):
                    medicines.add((label, values["B"], values.get("C", "")))

    revision = metadata.get("revision", "")
    date = metadata.get("date", "")
    if not found_columns or not re.fullmatch(r"\d{2}/\d{2}/\d{4}", date) or not revision or not medicines:
        raise ValueError("The workbook's columns or source metadata have changed.")

    lines = [
        "Source: European Medicines Agency, Article 57 product data",
        SOURCE,
        REUSE_NOTICE,
        revision,
        date,
        *("\t".join(item) for item in sorted(medicines, key=lambda row: (row[0].casefold(), row))),
    ]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 Scripts/export-ema-medicines.py WORKBOOK.xlsx")
    OUTPUT.write_text(extract(sys.argv[1]), encoding="utf-8")
