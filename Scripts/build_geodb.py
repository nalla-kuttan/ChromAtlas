#!/usr/bin/env python3
"""Build ChromAtlas/Resources/geo.sqlite from GeoNames cities15000.

Run this on your Mac (it is the only step that touches the network; the app never does):

    curl -O https://download.geonames.org/export/dump/cities15000.zip
    curl -O https://download.geonames.org/export/dump/admin1CodesASCII.txt
    unzip cities15000.zip
    python3 Scripts/build_geodb.py cities15000.txt admin1CodesASCII.txt ChromAtlas/Resources/geo.sqlite

Then re-run `xcodegen generate`. When `geo.sqlite` is in the bundle, GeoDatabase uses it
instead of the ~420-city `cities_seed.csv` fallback. Schema matches GeoDatabase.swift.
"""
import sqlite3
import sys


def main(cities_path, admin1_path, out_path):
    admin1 = {}
    with open(admin1_path, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2:
                admin1[parts[0]] = parts[1]

    db = sqlite3.connect(out_path)
    db.executescript("""
        DROP TABLE IF EXISTS cities;
        DROP TABLE IF EXISTS city_rtree;
        CREATE TABLE cities (
            id INTEGER PRIMARY KEY, name TEXT NOT NULL, country_code TEXT NOT NULL,
            admin1 TEXT, latitude REAL NOT NULL, longitude REAL NOT NULL, population INTEGER);
        CREATE VIRTUAL TABLE city_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);
    """)
    rows = 0
    with open(cities_path, encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) < 15:
                continue
            rows += 1
            lat, lon = float(p[4]), float(p[5])
            cc, a1 = p[8], admin1.get(f"{p[8]}.{p[10]}", "")
            db.execute("INSERT INTO cities VALUES (?,?,?,?,?,?,?)", (rows, p[1], cc, a1, lat, lon, int(p[14] or 0)))
            db.execute("INSERT INTO city_rtree VALUES (?,?,?,?,?)", (rows, lat, lat, lon, lon))
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"wrote {rows} cities to {out_path}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
